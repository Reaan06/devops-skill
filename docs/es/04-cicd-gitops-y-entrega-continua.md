# CI/CD, GitOps y Arquitectura de Entrega Progresiva

## 1. Explicación: Conceptos y Arquitectura

La Integración Continua (CI), la Entrega Continua (CD) y GitOps articulan el ciclo de vida del software desde la autoría del código hasta su ejecución fiable en producción. Las plataformas modernas de entrega reemplazan los despliegues imperativos basados en inserción directa (*push*) por **federación de identidad sin contraseñas (OIDC keyless)**, **reconciliación declarativa GitOps (pull)**, **modelado progresivo del tráfico (Canary)** y **plataformas de autoservicio para desarrolladores (IDP)**.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Git Push del Desarrollador (Trunk)                │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Integración Continua (GitHub Actions / GitLab CI / Jenkins K8s)        │
 │  • Intercambio de Token OIDC efímero con Cloud STS (Cero Secretos)     │
 │  • Compilación aislada en contenedores con Kaniko / BuildKit           │
 │  • Generación de SBOM (Syft) y Firma Keyless (Cosign / Sigstore)       │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ OCI Push
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Registro Empresarial Harbor en Alta Disponibilidad (HA)                │
 │  • Puerta de seguridad con Trivy (Bloqueo si CVSS >= 7.0)              │
 │  • Imposibilidad de sobreescritura de tags y verificación de firmas    │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Git Tag / Commit al Repositorio de Configuración
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Controladores GitOps In-Cluster (ArgoCD / FluxCD v2)                   │
 │  • Reconciliación continua pull y autocorrección de desvíos (Self-Heal)│
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Entrega Progresiva Canary (Argo Rollouts)                              │
 │  • Paso 1: Enrutamiento del 10% de tráfico al Canary                   │
 │  • Paso 2: Análisis con Prometheus (Latencia P99 y Error Budget)       │
 │  • Paso 3: Promoción automática al 100% o reversión instantánea       │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Cero Credenciales Estáticas mediante OpenID Connect (OIDC)

Los pipelines de CI/CD tradicionales solían almacenar credenciales estáticas de larga duración (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, claves JSON de cuentas de servicio) en las variables secretas del repositorio. Este patrón presenta graves riesgos de seguridad:
- Exfiltración accidental a través de scripts de compilación mal configurados o dependencias comprometidas.
- Falta habitual de rotación periódica de credenciales, persistiendo activas durante meses o años.
- Las credenciales robadas permiten acceso irrestricto a la API cloud fuera de los horarios y flujos legítimos de CI.

#### El Flujo de Federación de Identidad OIDC

1. **Disparo del Flujo**: El agente de ejecución de CI solicita un JSON Web Token (JWT) firmado a su proveedor de identidad OIDC nativo (por ejemplo, `token.actions.githubusercontent.com`).
2. **Presentación del Token**: El runner presenta el JWT al servicio STS del proveedor cloud (AWS STS, GCP STS, Azure AD).
3. **Validación Criptográfica**: El proveedor de nube valida la firma contra las claves públicas del emisor OIDC registradas en `/.well-known/openid-configuration`.
4. **Evaluación de Claims**: El proveedor de nube comprueba los claims del token, validando que el campo `sub` (subject) coincida exactamente con la organización, repositorio y rama autorizados.
5. **Emisión de Credenciales Temporales**: El proveedor cloud emite credenciales efímeras con validez acotada (de 15 a 60 minutos), restringidas estrictamente al rol IAM asumido.

### 1.2 Comparativa Arquitectónica: CI Push frente a GitOps Pull

| Dimensión | CI/CD Push (Despliegues Directos) | GitOps Pull (ArgoCD / FluxCD) |
| :--- | :--- | :--- |
| **Vector de Ejecución** | El runner de CI externo ejecuta comandos `kubectl apply` o `helm upgrade`. | Un controlador interno en el clúster reconcilia continuamente el estado deseado desde Git. |
| **Privilegios de Acceso** | Las credenciales de administración del clúster (`kubeconfig`) deben residir en runners externos. | Ninguna credencial del clúster abandona el perímetro del clúster. El controlador se ejecuta localmente. |
| **Desvío de Configuración** | Intervenciones manuales o parches de emergencia en el clúster quedan sin detectar hasta sobreescribirse. | El controlador detecta cambios manuales en segundos y restablece el estado del clúster al declarado en Git. |
| **Auditabilidad y Rollback** | El historial de despliegues queda disperso en logs heterogéneos de pipelines. | El historial de commits de Git constituye el registro de auditoría inmutable. El rollback es un simple `git revert`. |

### 1.3 Estrategias de Entrega Progresiva

La entrega progresiva desacopla el despliegue técnico del código de su liberación operativa hacia los usuarios finales:

- **Rolling Update**: Sustituye pods secuencialmente uno a uno. Resulta inadecuado ante cambios de esquema o APIs incompatibles, ya que versiones antiguas y nuevas conviven atendiendo tráfico simultáneamente sin segmentación.
- **Blue/Green**: Despliega un entorno idéntico duplicado (Green) junto a la versión en producción activa (Blue). Desvía el 100% del tráfico instantáneamente mediante el balanceador de carga tras superar las pruebas de humo.
- **Canary (Argo Rollouts)**: Dirige un porcentaje progresivo del tráfico productivo real (por ejemplo: 5% -> 20% -> 50% -> 100%) hacia la versión candidata mientras monitoriza métricas en tiempo real (tasa de errores HTTP 5xx, latencia P99) mediante plantillas de análisis PromQL.
- **Shadow / Dark Launch (Tráfico Espejo)**: Clona peticiones HTTP entrantes reales y las reenvía asíncronamente a la versión candidata sin retornar sus respuestas a los clientes. Permite verificar rendimiento de consultas y estabilidad bajo carga real con radio de impacto nulo para los usuarios.

### 1.4 Ingeniería de Plataformas y Plataformas Internas de Desarrollo (IDP)

Los equipos de plataforma mitigan la sobrecarga cognitiva de los desarrolladores estableciendo **Rutas Pavimentadas (Golden Paths)**:
- **Portales para Desarrolladores (Backstage / Port)**: Proveen catálogo unificado de servicios, documentación como código (TechDocs) y plantillas de inicialización que generan repositorios con CI/CD, escáneres de seguridad y manifiestos de GitOps preconfigurados.
- **Infraestructura Declarativa con Crossplane**: Convierte a Kubernetes en un plano de control universal. Los desarrolladores consumen infraestructura cloud mediante recursos personalizados (`PostgreSQLInstance`), mientras los ingenieros de plataforma definen *Composite Resource Definitions* (XRDs) que encapsulan recursos subyacentes de AWS, GCP o Azure según las políticas corporativas.

### 1.5 Gestión de Artefactos Empresariales con Harbor en Alta Disponibilidad

Los registros OCI constituyen el punto de enlace crítico entre la automatización de construcción y la ejecución en el clúster:
- **Arquitectura de Alta Disponibilidad**: Desacopla los controladores sin estado del motor de almacenamiento persistente (S3, PostgreSQL administrado, Redis Sentinel).
- **Control de Vulnerabilidades (Vulnerability Gating)**: Escanea automáticamente las capas del contenedor con Trivy al publicarse. Si se detectan vulnerabilidades críticas que superen el umbral corporativo (CVSS $\ge 7.0$), se bloquea su descarga en los nodos del clúster.
- **Inmutabilidad de Tags y Atestación Criptográfica**: Prohíbe sobreescribir etiquetas de imágenes publicadas (`v1.2.0`) y exige firmas criptográficas válidas de Sigstore Cosign antes de permitir su ejecución en producción.

---

## 2. Guías Prácticas: Blueprints y Manifiestos de Producción

### 2.1 Flujo de Trabajo en GitHub Actions con Autenticación OIDC y Puertas de Seguridad

```yaml
name: Continuous Integration & Container Release

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

permissions:
  id-token: write # Requerido para la emisión del token JWT OIDC
  contents: read
  security-events: write

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Autenticación en AWS mediante OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111122223333:role/github-actions-production-deployer
          aws-region: us-east-1
          audience: sts.amazonaws.com

      - name: Configurar Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Inicio de sesión en Registro Harbor Empresarial
        uses: docker/login-action@v3
        with:
          registry: harbor.corp.internal
          username: ${{ secrets.HARBOR_ROBOT_USER }}
          password: ${{ secrets.HARBOR_ROBOT_TOKEN }}

      - name: Extracción de Metadatos OCI
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: harbor.corp.internal/production/backend-api
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=sha-,format=short

      - name: Construir y Publicar Imagen de Contenedor
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Escaneo de Vulnerabilidades con Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: harbor.corp.internal/production/backend-api:${{ steps.meta.outputs.version || 'latest' }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          ignore-unfixed: true

      - name: Cargar Resultados SARIF a GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
```

### 2.2 Pipeline Empresarial en GitLab CI con Grafo DAG (`needs:`) y Kaniko

```yaml
stages:
  - test
  - security
  - build

variables:
  HARBOR_REGISTRY: "harbor.corp.internal"
  IMAGE_NAME: "harbor.corp.internal/production/order-service"

unit_tests:
  stage: test
  image: golang:1.24-bookworm
  script:
    - go test -v -race -coverprofile=coverage.out ./...

gitleaks_scan:
  stage: security
  image: zricethezav/gitleaks:latest
  needs: [] # Se ejecuta inmediatamente vía DAG sin esperar a unit_tests
  script:
    - gitleaks detect --verbose --redact --exit-code 1

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.0-debug
    entrypoint: [""]
  needs:
    - unit_tests
    - gitleaks_scan
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"https://${HARBOR_REGISTRY}\":{\"auth\":\"$(printf "%s:%s" "${HARBOR_USER}" "${HARBOR_PASSWORD}" | base64 | tr -d '\n')\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor
      --context "${CI_PROJECT_DIR}"
      --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
      --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"
      --cache=true
      --cache-repo="${IMAGE_NAME}/cache"
```

### 2.3 Pipeline Declarativo de Jenkins con Agentes de Pod Efímeros en Kubernetes

```groovy
pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    role: jenkins-agent
spec:
  containers:
    - name: golang
      image: golang:1.24-bookworm
      command: ['cat']
      tty: true
    - name: kaniko
      image: gcr.io/kaniko-project/executor:debug
      command: ['cat']
      tty: true
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
  volumes:
    - name: docker-config
      secret:
        secretName: harbor-credentials
'''
    }
  }
  stages {
    stage('Test') {
      steps {
        container('golang') {
          sh 'go test -v ./...'
        }
      }
    }
    stage('Build & Push') {
      steps {
        container('kaniko') {
          sh '/kaniko/executor --context=`pwd` --destination=harbor.corp.internal/production/service:${BUILD_NUMBER}'
        }
      }
    }
  }
}
```

### 2.4 Manifiesto de Aplicación en ArgoCD con Autocorrección de Desvíos

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-system-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/my-org/gitops-manifests.git'
    targetRevision: main
    path: environments/production/payment-system
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: production-apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 2.5 Despliegue Progresivo Canary con Argo Rollouts y Análisis de PromQL

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: order-service-rollout
  namespace: production-apps
spec:
  replicas: 10
  strategy:
    canary:
      analysis:
        templates:
          - templateName: success-rate-analysis
        args:
          - name: service-name
            value: order-service
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - setWeight: 25
        - pause: { duration: 10m }
        - setWeight: 50
        - pause: { duration: 10m }
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
        - name: app
          image: harbor.corp.internal/production/order-service:v2.5.0
          ports:
            - containerPort: 8080
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-analysis
  namespace: production-apps
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result[0] >= 0.999
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus-k8s.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{app="order-service",status!~"5.*"}[2m]))
            /
            sum(rate(http_requests_total{app="order-service"}[2m]))
```

---

## 3. Referencia Operativa: Comandos y Flujos de Trabajo

### 3.1 Administración Operativa con la CLI de ArgoCD

```bash
# Iniciar sesión en el servidor de ArgoCD
argocd login argocd.corp.internal --grpc-web

# Listar aplicaciones y estado de sincronización
argocd app list

# Inspeccionar diferencias en tiempo real entre Git y el clúster
argocd app diff payment-system-production

# Disparar sincronización manual con purga de recursos eliminados
argocd app sync payment-system-production --prune

# Revertir a un commit de Git anterior
argocd app rollback payment-system-production
```

### 3.2 Gestión de Lanzamientos con la CLI de Argo Rollouts

```bash
# Monitorear en tiempo real el progreso del rollout y los pesos de tráfico canary
kubectl argo rollouts get rollout order-service-rollout -n production-apps --watch

# Promocionar manualmente una etapa pausada
kubectl argo rollouts promote order-service-rollout -n production-apps

# Abortar inmediatamente el release candidato y devolver el tráfico a la versión estable
kubectl argo rollouts abort order-service-rollout -n production-apps

# Reintentar un rollout abortado o fallido
kubectl argo rollouts retry order-service-rollout -n production-apps
```

### 3.3 Firma y Verificación Criptográfica de Artefactos con Cosign

```bash
# Firmar imagen de contenedor en modo keyless mediante Sigstore OIDC
cosign sign --yes harbor.corp.internal/production/backend-api:v2.4.1

# Adjuntar SBOM en formato CycloneDX a la imagen en el registro
cosign attach sbom --sbom sbom.cyclonedx.json harbor.corp.internal/production/backend-api:v2.4.1

# Verificar la firma criptográfica contra la identidad OIDC de confianza antes del despliegue
cosign verify \
  --certificate-identity "https://github.com/my-org/my-repo/.github/workflows/ci.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  harbor.corp.internal/production/backend-api:v2.4.1
```

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Referencia de Plantillas del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| Autenticación OIDC GitHub Actions | `templates/github-actions/oidc-aws-auth.yml` | Flujo de autenticación keyless con AWS STS |
| Compilación, Escaneo y Push CI | `templates/github-actions/ci-docker-build-push.yml` | Compilación multi-arquitectura con compuerta Trivy |
| Pipeline Empresarial GitLab CI | `templates/gitlab/.gitlab-ci-enterprise.yml` | Ejecución DAG con compilador Kaniko en contenedor |
| Pipeline Jenkins en K8s | `templates/jenkins/Jenkinsfile.declarative` | Agentes de pod dinámicos y efímeros en Kubernetes |
| Aplicación ArgoCD | `templates/gitops/argocd-application.yaml` | Definición de autosincronización y autorreparación |
| Kustomization FluxCD | `templates/gitops/fluxcd-kustomization.yaml` | Reconciliación continua y seguimiento de orígenes |
| Rollout Canary Argo | `templates/gitops/argo-rollouts-canary.yaml` | División progresiva de tráfico con análisis de métricas |
| Plantilla de Servicio Backstage | `templates/platform/backstage-software-template.yaml` | Inicialización de microservicios según Golden Path |
| XRD Crossplane (Postgres) | `templates/platform/crossplane-xrd-postgres.yaml` | Composición declarativa de base de datos cloud |
| Valores Harbor HA | `templates/artifacts/harbor-values-ha.yaml` | Configuración de Harbor en HA con S3, Postgres y Redis |

### 4.2 Estándares y Marcos de Cumplimiento

- **SLSA (Supply-chain Levels for Software Artifacts) Nivel 3**:
  - Entornos de compilación efímeros y aislados (runners alojados, Kaniko o pods efímeros).
  - Procedencia de compilación atestada criptográficamente con in-toto y Cosign.
- **Seguridad en la Cadena de Suministro CIS**:
  - Supresión total de credenciales estáticas en todas las fases de construcción.
  - Verificación obligatoria de firmas de artefactos antes de su admisión en el clúster.
