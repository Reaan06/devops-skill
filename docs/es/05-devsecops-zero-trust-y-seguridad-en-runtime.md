# DevSecOps, Arquitectura Zero Trust y Protección en Runtime

## 1. Explicación: Conceptos y Arquitectura

La ingeniería de seguridad moderna descarta las defensas reactivas perimetrales clásicas (el modelo de "castillo y foso") en favor de una plataforma unificada de protección de aplicaciones nativas de la nube (**Cloud-Native Application Protection Platform - CNAPP**). En infraestructuras cloud-native, los controles de seguridad deben desplazarse a la izquierda (*shift-left*) en los pipelines de CI, imponer identidades criptográficas de carga de trabajo sin credenciales estáticas, validar la admisión en los orquestadores mediante Política como Código e interceptar llamadas al sistema (*syscalls*) anómalas en el kernel durante el runtime.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 1. Compuertas Shift-Left en Pipelines (Pre-Commit y CI)                │
 │  • Detección de Secretos: Gitleaks (Historial de commits en Git)       │
 │  • SAST y Análisis Semántico: Semgrep (Coincidencia semántica con AST) │
 │  • SCA y SBOM: Trivy y Syft (Inventarios CycloneDX / SPDX)             │
 │  • Seguridad de APIs: Spectral (Gobernanza de OpenAPI 3.1 y GraphQL)   │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Imagen OCI Firmada (Cosign)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 2. Compuertas de Admisión en el Clúster (Política como Código)         │
 │  • Webhooks de Admisión con OPA Gatekeeper y Kyverno                   │
 │  • Exigencia de non-root, PSS Restricted, firmas e imágenes aprobadas  │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Pod Programado en el Nodo
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 3. Identidad Criptográfica Zero Trust (SPIFFE / SPIRE)                 │
 │  • Atestación de Nodo mediante TPM / AWS IID / K8s SAT                 │
 │  • Atestación de Carga de Trabajo vía API SPIFFE (Socket UNIX local)   │
 │  • Emisión de SVID X.509 a la aplicación para mTLS sin secretos        │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Ejecución del Contenedor
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 4. Protección y Auditoría en Runtime (CWPP y CSPM)                     │
 │  • Falco / Tetragon: Detección de anomalías en syscalls vía eBPF       │
 │  • Prowler: Escaneo continuo de cumplimiento de CIS Cloud Benchmark    │
 │  • Cuarentena SOAR: Aislamiento automático de red del pod ante alertas │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Modelado de Amenazas con STRIDE y OWASP Threat Dragon

El modelado de amenazas es una disciplina arquitectónica que se efectúa de forma previa a la implementación para identificar vectores de ataque y aplicar mitigaciones sistemáticas en las fronteras de confianza:

| Amenaza STRIDE | Invariante Violado | Primitiva Objetivo | Arquitectura de Mitigación |
| :--- | :--- | :--- | :--- |
| **S**poofing (Suplantación) | Autenticidad | APIs de ingreso, tráfico entre servicios | SVIDs X.509 de SPIFFE/SPIRE, mTLS estricto, tokens OIDC efímeros |
| **T**ampering (Manipulación) | Integridad | Almacenamiento, datos en tránsito, registros BD | Firmas Cosign, cifrado de estado OpenTofu, firmas HMAC |
| **R**epudiation (Repudio) | Irrepudiabilidad | Logs de auditoría, transacciones financieras | Almacenamiento WORM inmutable, logs OTel centralizados append-only |
| **I**nformation Disclosure | Confidencialidad | Secretos, heaps de memoria, variables de entorno | Secretos dinámicos en HashiCorp Vault, External Secrets Operator, TLS 1.3 |
| **D**enial of Service (DoS) | Disponibilidad | Cómputo del nodo, gateways de API | Autoescalado KEDA, limitadores de tasa, cuotas CPU/memoria, circuit breakers |
| **E**levation of Privilege | Autorización | Cuentas de servicio, runtimes de contenedores | PSS Restricted, descarte de capabilities (`ALL`), UIDs non-root |

### 1.2 Gobernanza de Seguridad de APIs Guiada por Especificaciones

Las APIs constituyen la principal superficie de ataque en aplicaciones modernas. El informe OWASP API Security Top 10 destaca vulnerabilidades críticas como la autorización rota a nivel de objeto (BOLA), consumo irrestricto de recursos y autenticación defectuosa.

La seguridad guiada por especificaciones impone gobernanza directamente sobre los contratos de API (OpenAPI 3.1, esquemas GraphQL, protobufs gRPC) mediante **Spectral**:
- **Tipado Estricto de Esquemas**: Rechaza uniones `anyOf` polimórficas sin discriminador explícito, mitigando ataques de contrabando de payloads (*payload smuggling*).
- **Esquemas de Autenticación Obligatorios**: Exige alcances explícitos de OAuth2 u OIDC en cada endpoint publicado.
- **Límites de Profundidad y Coste en GraphQL**: Restringe el anidamiento recursivo de consultas (previniendo ataques DoS por grafos circulares) y desactiva la introspección en entornos productivos.

### 1.3 Arquitectura Zero Trust: SPIFFE/SPIRE y HashiCorp Vault

El estándar NIST SP 800-207 establece que la ubicación física o topológica de red (direcciones IP o subredes VPC) nunca debe presuponer confianza. Cada comunicación exige verificación criptográfica explícita:

- **SPIFFE (Secure Production Identity Framework for Everyone)**: Estandariza la identidad criptográfica agnóstica de la plataforma.
  - **SPIFFE ID**: URI que representa unívocamente la carga de trabajo (`spiffe://acme.internal/ns/production/sa/payment-service`).
  - **SVID (SPIFFE Verifiable Identity Document)**: Certificados X.509 o tokens JWT de corta duración emitidos para la carga de trabajo.
- **SPIRE (SPIFFE Runtime Environment)**: Implementación de referencia de SPIFFE compuesta por:
  - **SPIRE Server**: Autoridad de certificación del clúster que registra cargas de trabajo y firma SVIDs.
  - **SPIRE Agent**: DaemonSet en cada nodo que atesta cargas de trabajo locales mediante metadatos del kernel (UID, PID, cgroups) y expone certificados mediante un socket de dominio UNIX local sin necesidad de tokens estáticos.
- **HashiCorp Vault**: Proporciona gestión centralizada de secretos dinámicos y efímeros (por ejemplo, contraseñas de PostgreSQL de corta duración rotadas automáticamente cada 60 minutos) en lugar de cadenas de credenciales estáticas permanentes.

### 1.4 Política como Código: OPA Gatekeeper frente a Kyverno

La Política como Código (*Policy as Code*) intercepta solicitudes a la API de Kubernetes mediante controladores de admisión `ValidatingAdmissionWebhook` y `MutatingAdmissionWebhook`:

- **OPA Gatekeeper**: Utiliza el lenguaje declarativo **Rego**. Desacopla la lógica de validación en `ConstraintTemplate` y el enlace de recursos en `Constraint`. Resulta óptimo en entornos empresariales multiclúster heterogéneos con tooling consolidado de OPA.
- **Kyverno**: Motor de políticas nativo de Kubernetes configurable en sintaxis YAML estándar sin requerir el aprendizaje de Rego. Sobresale en mutación nativa de recursos, generación automática de manifiestos y verificación de firmas OCI mediante Cosign.

### 1.5 Protección de Cargas de Trabajo Cloud (CWPP) con Falco eBPF

El análisis estático y los controladores de admisión protegen la infraestructura antes de la ejecución del contenedor. Sin embargo, una vez en marcha, posibles vulnerabilidades de día cero (*zero-day*) en las dependencias de la aplicación pueden explotarse para ejecutar comandos no autorizados.

**Falco** supervisa las llamadas al sistema (*syscalls*) en tiempo real a nivel del kernel mediante controladores eBPF. Intercepta operaciones como `execve`, `openat`, `socket` y `setuid`, comparándolas con perfiles de comportamiento declarados para detectar:
- Lanzamiento de shells interactivas (`/bin/sh`, `/bin/bash`) dentro de pods en producción.
- Ejecución de binarios fuera de rutas aprobadas (como scripts en `/tmp` o `/dev/shm`).
- Manipulación de archivos del sistema operativo o binarios ejecutables (`/etc/passwd`, `/etc/shadow`).
- Intentos de escape de namespaces o montajes no autorizados del almacenamiento del host.

---

## 2. Guías Prácticas: Blueprints de Seguridad de Producción

### 2.1 Reglas Personalizadas de SAST con Semgrep (`semgrep-sast.yml`)

Detección de ejecuciones peligrosas de subprocesos y concatenación directa de sentencias SQL:

```yaml
rules:
  - id: prevent-shell-injection
    languages:
      - python
    message: "Potencial inyección de shell: subproceso invocado con shell=True y argumentos dinámicos."
    severity: ERROR
    metadata:
      cwe: "CWE-78: Improper Neutralization of Special Elements used in an OS Command"
      owasp: "A03:2021 - Injection"
    patterns:
      - pattern-either:
          - pattern: subprocess.Popen(..., shell=True, ...)
          - pattern: subprocess.call(..., shell=True, ...)
          - pattern: subprocess.run(..., shell=True, ...)
      - pattern-not: subprocess.Popen("...", shell=True, ...)

  - id: detect-raw-sql-concatenation
    languages:
      - go
    message: "Concatenación directa de cadenas SQL detectada. Utilice consultas parametrizadas para evitar inyección SQL."
    severity: ERROR
    metadata:
      cwe: "CWE-89: SQL Injection"
    pattern: $DB.Query(fmt.Sprintf(...))
```

### 2.2 Conjunto de Reglas de Gobernanza para OpenAPI 3.1 con Spectral

Guarde la siguiente configuración como `.spectral.yaml` para asegurar contratos de API en pipelines de CI:

```yaml
extends: ["spectral:oas"]

rules:
  openapi-enforce-https:
    description: "Todos los endpoints deben exigir transporte seguro mediante HTTPS."
    severity: error
    given: "$.servers[*].url"
    then:
      function: pattern
      functionOptions:
        match: "^https://"

  openapi-mandatory-security:
    description: "Cada operación de la API debe declarar un esquema de seguridad explícito."
    severity: error
    given: "$.paths[*][get,post,put,delete,patch]"
    then:
      field: security
      function: defined

  openapi-no-empty-descriptions:
    description: "Las operaciones de la API deben incluir descripciones detalladas para documentación."
    severity: warn
    given: "$.paths[*][get,post,put,delete,patch].description"
    then:
      function: length
      functionOptions:
        min: 15
```

### 2.3 ConstraintTemplate y Constraint con OPA Gatekeeper

Exigencia de que todos los contenedores en ejecución descarten todas las capacidades del kernel Linux:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirecontainerdropall
spec:
  crd:
    spec:
      names:
        kind: K8sRequireContainerDropAll
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequirecontainerdropall

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not has_drop_all(container)
          msg := sprintf("El contenedor '%v' debe descartar explícitamente ALL en securityContext.capabilities.drop", [container.name])
        }

        has_drop_all(container) {
          drop := container.securityContext.capabilities.drop
          drop[_] == "ALL"
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireContainerDropAll
metadata:
  name: require-drop-all-production
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - "production-apps"
```

### 2.4 Reglas de Detección en Tiempo de Ejecución con Falco eBPF

```yaml
- rule: Terminal Shell Spawned in Container
  desc: Detecta el lanzamiento de shells interactivas en un contenedor de producción
  condition: >
    container.id != host and
    spawned_process and
    proc.name in (bash, sh, zsh, ksh, dash) and
    not k8s.ns.name in (kube-system, build-system)
  output: >
    ALERT: Shell interactiva iniciada en contenedor (user=%user.name pod=%k8s.pod.name
    ns=%k8s.ns.name container=%container.name cmdline=%proc.cmdline parent=%proc.pname)
  priority: CRITICAL
  tags: [mitre_execution, runtime, container]

- rule: Write below root or usr directory in container
  desc: Detecta modificaciones sobre directorios inmutables del sistema en un contenedor
  condition: >
    container.id != host and
    open_write and
    fd.name glob "/bin/*" or fd.name glob "/sbin/*" or fd.name glob "/usr/bin/*"
  output: >
    CRITICAL: Intento de escritura en directorio de binarios del sistema (user=%user.name pod=%k8s.pod.name
    file=%fd.name cmdline=%proc.cmdline)
  priority: EMERGENCY
  tags: [mitre_persistence, integrity]
```

### 2.5 Línea Base de Configuración para Agente y Servidor SPIRE

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-agent-config
  namespace: spire
data:
  agent.conf: |
    agent {
      data_dir = "/run/spire"
      log_level = "INFO"
      server_address = "spire-server.spire.svc.cluster.local"
      server_port = "8081"
      socket_path = "/run/spire/sockets/agent.sock"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "enterprise.corp.internal"
    }
    plugins {
      NodeAttestor "k8s_psat" {
        plugin_data {
          cluster = "production-cluster-01"
        }
      }
      KeyManager "memory" {
        plugin_data {}
      }
      WorkloadAttestor "k8s" {
        plugin_data {
          skip_kubelet_verification = false
        }
      }
    }
```

---

## 3. Referencia Operativa: Comandos de Seguridad y Triage de Incidentes

### 3.1 Detección de Secretos en Pre-Commit y CI con Gitleaks

```bash
# Escanear el árbol de trabajo local y cambios no confirmados
gitleaks detect --source . --verbose --redact

# Escanear un rango de commits específico en pipelines de CI
gitleaks detect \
  --log-opts="${CI_COMMIT_BEFORE_SHA}..${CI_COMMIT_SHA}" \
  --redact \
  --exit-code 1
```

### 3.2 Flujos Operativos de SAST y DAST

```bash
# Ejecutar análisis estático con Semgrep generando salida en formato SARIF
semgrep scan \
  --config p/ci \
  --config p/owasp-top-ten \
  --sarif \
  --output semgrep-report.sarif \
  --error

# Ejecutar pruebas dinámicas de seguridad en aplicaciones con Nuclei
nuclei \
  -target https://staging-api.bank.corp \
  -tags cve,owasp-top-10,misconfiguration \
  -severity critical,high \
  -validate \
  -json-export nuclei-findings.json
```

### 3.3 Auditoría de Postura Cloud (CSPM) con Prowler

```bash
# Ejecutar auditoría de cumplimiento contra CIS Amazon Web Services Benchmark
prowler aws \
  --compliance cis_3.0_aws \
  --severity critical high \
  --output-modes json,csv,html \
  --output-directory prowler-reports
```

### 3.4 Respuesta ante Incidentes en Runtime: Contención de Cargas Comprometidas

Cuando Falco alerte sobre una shell interactiva no autorizada o un intento de exfiltración de credenciales:

```bash
# 1. Inspeccionar los procesos activos del contenedor desde el nodo host
PID=$(kubectl get pod compromised-pod-8b9f-lk2 -n production-apps \
  -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's/containerd:\/\///')
crictl inspect --output go-template --template '{{.info.pid}}' $PID

# 2. Aplicar NetworkPolicy de emergencia para aislar por completo el pod de ingress y egress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-isolate-pod
  namespace: production-apps
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: compromised-service
  policyTypes:
    - Ingress
    - Egress
EOF

# 3. Capturar volcado de memoria para análisis forense digital antes de finalizar el proceso
gdb --pid=$PID --batch -ex "gcore /tmp/forensics-pod-dump.core"
```

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Referencia de Plantillas del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| Reglas Falco eBPF | `templates/security/falco-rules-k8s.yaml` | Detección de anomalías en syscalls del kernel en runtime |
| Constraint OPA Gatekeeper | `templates/security/opa-gatekeeper-constraint.yaml` | Políticas de control de admisión con webhook |
| Ruleset Spectral API | `templates/security/spectral-openapi-ruleset.yaml` | Gobernanza contractual de OpenAPI 3.1 y GraphQL |
| Agente y Servidor SPIRE | `templates/security/spire-agent-server-k8s.yaml` | Identidad criptográfica de cargas de trabajo con SPIFFE |
| Clúster Vault HA Raft | `templates/security/vault-cluster-raft-values.yaml` | Gestión de secretos dinámicos en alta disponibilidad |
| Pipeline Semgrep SAST | `templates/github-actions/semgrep-sast.yml` | Análisis estático de seguridad en GitHub Actions |
| Pipeline Nuclei DAST | `templates/github-actions/nuclei-dast-scan.yml` | Pruebas dinámicas en entornos de preproducción |
| Auditoría Prowler CSPM | `templates/github-actions/prowler-cspm-audit.yml` | Auditoría continua de configuración cloud contra CIS |

### 4.2 Estándares y Marcos de Cumplimiento

- **NIST SP 800-207**: Marco de Implementación de Arquitectura Zero Trust.
- **NIST SP 800-190**: Guía de Seguridad para Contenedores de Aplicación.
- **CIS Kubernetes Benchmark**: Controles 5.2.1 a 5.2.13 (Endurecimiento del runtime de contenedores).
- **OWASP API Security Top 10 (2023)**:
  - API1: Autorización Rota a Nivel de Objeto (BOLA).
  - API2: Autenticación Rota.
  - API4: Consumo Irrestricto de Recursos.
