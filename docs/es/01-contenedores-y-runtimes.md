# Contenedores Hardened e Ingeniería de Runtimes OCI

## 1. Explicación: Conceptos y Arquitectura

La contenedorización nativa de la nube en entornos empresariales exige tres propiedades fundamentales: **superficie de ataque mínima**, **caché de capas determinista** y **ejecución sin privilegios** (unprivileged). La práctica histórica de incluir gestores de paquetes (`apt`, `apk`), shells interactivas (`bash`, `sh`) y cadenas de compilación en imágenes de producción ejecutadas como `root` (UID 0) viola el principio de defensa en profundidad y expone la infraestructura a ataques de escalada de privilegios y escape de contenedores.

### 1.1 Arquitectura del Stack de Runtimes OCI

La Open Container Initiative (OCI) define estándares universales para los formatos de imagen y runtimes de contenedores. En hosts Linux modernos, la ejecución de contenedores sigue una arquitectura por capas desacoplada:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Orquestador de Contenedores                 │
│              (Kubernetes Kubelet / Docker CLI)              │
└──────────────────────────────┬──────────────────────────────┘
                               │ CRI / gRPC
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  Runtime de Alto Nivel                      │
│                  (containerd / CRI-O)                       │
│   • Descarga y descompresión de imágenes                    │
│   • Gestión de snapshots y almacenamiento (overlay2)        │
│   • Orquestación del ciclo de vida del contenedor           │
└──────────────────────────────┬──────────────────────────────┘
                               │ OCI Runtime Spec
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  Runtime de Bajo Nivel                      │
│                      (runc / crun)                          │
│   • Namespaces del kernel Linux (pid, net, ipc, mnt, uts)   │
│   • Grupos de control unificados (cgroups v2)               │
│   • Filtros Seccomp y LSM (AppArmor / SELinux)              │
└─────────────────────────────────────────────────────────────┘
```

La imagen de contenedor es una secuencia inmutable de archivos tarball de solo lectura apilados mediante el sistema de archivos de unión `overlay2`. Cuando un contenedor se inicializa, `containerd` desempaqueta las capas de la imagen como componentes `lowerdir` de solo lectura y monta una capa efímera de lectura/escritura (`upperdir`), fusionándolas en la vista de trabajo (`merged`).

### 1.2 Matriz de Selección y Arquitectura de Imágenes Base

La elección de la imagen base determina la densidad de vulnerabilidades (CVEs), el rendimiento de memoria dinámica, la latencia de resolución DNS y la compatibilidad binaria:

| Imagen Base | Tamaño Descomprimido | Conteo Típico de CVEs | Biblioteca C | Shell Interactiva | Gestor de Paquetes | Cargas de Trabajo Principales |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Distroless Static** (`gcr.io/distroless/static-debian12:nonroot`) | ~2–4 MB | 0 | Ninguna (estático puro) | No | No | Go, Rust (enlazado estático) |
| **Distroless CC** (`gcr.io/distroless/cc-debian12:nonroot`) | ~25–35 MB | 0–1 | `glibc` | No | No | Go con CGO, C++, Rust dinámico |
| **Debian Slim** (`debian:bookworm-slim`, `node:22-bookworm-slim`) | ~60–120 MB | 1–5 | `glibc` | Sí (`bash`, `dash`) | Sí (`apt`) | Python (con wheels nativos en C), Node.js, Ruby |
| **Alpine Linux** (`alpine:3.21`) | ~7 MB | 0–2 | `musl libc` | Sí (`ash`) | Sí (`apk`) | Utilidades ligeras de shell, scripts de red |
| **Scratch** (`FROM scratch`) | 0 MB | 0 | Ninguna | No | No | Binarios ultra minimalistas de Go/Rust |

### 1.3 Análisis Profundo: Distroless frente a Alpine en Producción Empresarial

Aunque Alpine Linux ha sido históricamente popular por su reducido tamaño (~3.2 MB comprimido, ~7 MB descomprimido), el uso de `musl libc` introduce serias advertencias operativas en entornos de alta concurrencia:

1. **Rendimiento del Asignador de Memoria**: Bajo cargas altamente concurrentes y multihilo, el asignador de memoria de `musl` presenta mayor fragmentación y menor tasa de procesamiento en comparación con la implementación `ptmalloc3` de `glibc`.
2. **Semántica de Resolución DNS**: El resolver DNS de `musl` envía consultas paralelas A y AAAA sobre un único socket UDP. Esto provoca caídas de paquetes o picos de latencia en firewalls con NAT con estado o clústeres de Kubernetes con CoreDNS que carezcan de soporte EDNS0.
3. **Incompatibilidad con el Ecosistema Python**: El repositorio oficial PyPI distribuye binarios precompilados bajo el estándar `manylinux`, optimizado exclusivamente para `glibc`. En Alpine, `pip` no puede utilizar wheels `manylinux` y se ve forzado a compilar paquetes desde el código fuente C, incrementando drásticamente los tiempos de compilación e introduciendo compiladores en la imagen de despliegue.
4. **Ventajas de Distroless**: Las imágenes `distroless` de Google Container Tools se construyen a partir de paquetes upstream de Debian enlazados contra `glibc`. Esto garantiza compatibilidad binaria total con bibliotecas empresariales mientras elimina de raíz gestores de paquetes, compiladores y shells.

### 1.4 Mecánica del Desperdicio de Capas por Copy-on-Write (COW)

Los motores OCI que utilizan el controlador `overlay2` procesan las instrucciones de forma acumulativa:

```text
Capa de Imagen 2 (chown tardío): [ Archivos /app duplicados (50 MB) con UID 10001 ]  ◄── Desperdicio COW
Capa de Imagen 1 (copy como root): [ Archivos /app originales (50 MB) con UID 0    ]
Capa Base del Sistema Operativo:   [ Archivos Base Distroless / Debian              ]
```

Cuando una instrucción genera archivos en la capa $N$ con propietario `root`, ejecutar `RUN chown -R appuser:appgroup /app` en la capa $N+1$ obliga al sistema de archivos de unión a copiar cada archivo desde la capa inferior hacia la capa superior para modificar sus metadatos de inodo. Esto duplica el tamaño real de la imagen en el registro.

De igual forma, instalar paquetes en una capa y limpiar la caché en una capa posterior preserva permanentemente los archivos descargados en el historial subyacente:

```dockerfile
# ANTIPATRÓN: Preserva listas de apt en la historia de capas
RUN apt-get update && apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*

# PATRÓN DE ORO: Transacción atómica en una única capa
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
```

---

## 2. Guías Prácticas: Blueprints Multi-Etapa de Producción

### 2.1 Blueprint Multi-Etapa para Go con Distroless

El siguiente blueprint incorpora montajes de caché de BuildKit para compilaciones ultrarrápidas, elimina símbolos de depuración, purga rutas de compilación y apunta a `distroless/static-debian12:nonroot`:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM golang:1.24-bookworm AS builder

WORKDIR /src

# Caché de dependencias
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download -x

# Copia del árbol de código fuente
COPY . .

# Compilación de binario estático sin símbolos de depuración
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /bin/server ./cmd/server

# Etapa final de runtime: distroless estático sin privilegios
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# Asignación de permisos en la frontera de copia (cero transferencia COW)
COPY --chown=nonroot:nonroot --from=builder /bin/server /app/server

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/server"]
```

### 2.2 Blueprint para Node.js y Next.js en Modo Standalone

Las aplicaciones Next.js deben utilizar la salida `standalone`, la cual analiza el AST de la aplicación para aislar únicamente las dependencias estrictamente necesarias de `node_modules`:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:22-bookworm-slim AS base
WORKDIR /app
ENV NODE_ENV=production

FROM base AS dependencies
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --prod=false

FROM base AS builder
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY --from=dependencies /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

FROM base AS runner
RUN groupadd --system --gid 1001 nodejs && \
    useradd --system --uid 1001 nextjs

# Copia de artefactos standalone y activos estáticos
COPY --chown=nextjs:nodejs --from=builder /app/public ./public
COPY --chown=nextjs:nodejs --from=builder /app/.next/standalone ./
COPY --chown=nextjs:nodejs --from=builder /app/.next/static ./.next/static

USER nextjs:nodejs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

ENTRYPOINT ["node", "server.js"]
```

### 2.3 Blueprint para Python con Debian Slim y Entorno Virtual

Los entornos de ejecución de Python deben aislarse de los paquetes del sistema operativo eliminando las herramientas de compilación de la imagen final:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
 && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-compile -r requirements.txt

# Etapa final de runtime
FROM python:3.12-slim-bookworm AS runner

WORKDIR /app

# Creación de usuario sin privilegios
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -d /app appuser

COPY --chown=appuser:appgroup --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appgroup . /app

ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

USER appuser:appgroup
EXPOSE 8000

ENTRYPOINT ["gunicorn", "-b", "0.0.0.0:8000", "wsgi:app"]
```

### 2.4 Hardening de Entornos Locales con Docker Compose

Para desarrollo local y pruebas de integración continua, Docker Compose debe replicar las restricciones de seguridad de producción:

```yaml
services:
  api:
    image: myorg/api:1.0.0
    build:
      context: .
      dockerfile: Dockerfile
    user: "10001:10001"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
    restart: unless-stopped
```

---

## 3. Referencia Operativa: Comandos y Diagnósticos

### 3.1 Flujos de Trabajo CLI con BuildKit

Active las capacidades avanzadas del motor BuildKit antes de invocar comandos de construcción:

```bash
# Habilitar BuildKit para comandos docker build nativos
export DOCKER_BUILDKIT=1

# Compilar con visualización de progreso y caché en línea
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --tag myorg/service:v1.0.0 \
  --file Dockerfile .

# Compilación multiplataforma y multiarquitectura con buildx
docker buildx create --name enterprise-builder --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag myorg/service:v1.0.0 \
  --push .
```

### 3.2 Auditoría de Eficiencia de Capas con Dive

Analice la composición de capas y detecte espacio desperdiciado en imágenes OCI:

```bash
# Ejecutar dive en modo puerta de enlace automatizada en CI
CI=true dive myorg/service:v1.0.0 \
  --highestUserWastedPercent 0.05 \
  --lowestEfficiency 0.98

# Análisis interactivo por terminal de las capas de la imagen
dive myorg/service:v1.0.0
```

Métricas clave evaluadas por Dive:
- **Puntuación de Eficiencia (Image Efficiency Score)**: Debe ser $\ge 98\%$.
- **Espacio Desperdiciado (Wasted Space Ratio)**: La suma acumulada de archivos sobreescritos o duplicados entre capas no debe superar el $2\%$.

### 3.3 Triage Diagnóstico: Depuración de Contenedores Distroless sin Shell

Cuando un contenedor basado en `distroless` presenta fallos de red o errores internos, los comandos tradicionales (`docker exec -it <contenedor> /bin/sh`) fallan porque no existe ningún binario de shell en la imagen.

#### Enfoque Diagnóstico 1: Contenedores Efímeros en Kubernetes

```bash
# Conectar un contenedor de depuración efímero compartiendo los namespaces del pod
kubectl debug -it pod/backend-api-7b89f-2k9lm \
  --image=nicolaka/netshoot \
  --target=application \
  -- /bin/bash
```

#### Enfoque Diagnóstico 2: Docker Debug CLI

```bash
# Utilizar el comando debug de Docker Engine 25+
docker debug <container_id>
```

#### Enfoque Diagnóstico 3: Acceso Directo por nsenter y crictl en el Host Linux

```bash
# Obtener el PID del proceso en el nodo host mediante crictl
PID=$(crictl inspect --output go-template --template '{{.info.pid}}' <container_id>)

# Ingresar a los namespaces de red e IPC del contenedor desde el host
sudo nsenter -t $PID -n -i ip addr
```

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Plantillas y Scripts del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| Go Distroless Dockerfile | `templates/containers/Dockerfile.distroless.go` | Nonroot, caché BuildKit, compilación estática |
| Rust Distroless Dockerfile | `templates/containers/Dockerfile.distroless.rust` | Caché de Cargo, runtime Distroless CC |
| Node.js Slim Dockerfile | `templates/containers/Dockerfile.slim.node` | Caché del almacén pnpm, configuración de usuario nonroot |
| Next.js Standalone Dockerfile | `templates/containers/Dockerfile.standalone.nextjs` | Optimización standalone trace, salida menor a 100MB |
| Python Slim Dockerfile | `templates/containers/Dockerfile.slim.python` | Constructor con virtualenv, sin compiladores en runtime |
| Java 21 Temurin Dockerfile | `templates/containers/Dockerfile.temurin21.java` | Multi-etapa Eclipse Temurin con caché CDS |
| Compose Hardened | `templates/containers/compose.hardened.yaml` | Sistema de solo lectura, tmpfs, eliminación de capabilities |
| `.dockerignore` Universal | `templates/containers/.dockerignore` | Poda del contexto de compilación |
| Script de Auditoría de Imágenes | `scripts/audit-image.sh` | Wrapper automatizado para inspección con `dive` |

### 4.2 Mapeo de Controles de Seguridad

- **CIS Docker Benchmark v1.6.0**:
  - Control 4.1: Asegurar que se haya creado un usuario sin privilegios (`USER nonroot`).
  - Control 4.6: Asegurar que se incorporen instrucciones `HEALTHCHECK` en las imágenes.
  - Control 5.12: Asegurar que el sistema de archivos raíz sea montado en solo lectura (`read_only: true`).
- **NIST SP 800-190 (Application Container Security Guide)**:
  - Sección 3.1: Mitigación de vulnerabilidades de imagen y minimización de capas.
  - Sección 3.4: Contexto de ejecución con privilegios mínimos en tiempo de ejecución.
