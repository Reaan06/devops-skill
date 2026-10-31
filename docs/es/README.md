# Índice de Documentación en Español

Bienvenido al centro de documentación técnica en español para el ecosistema `devops-skill`. Cada guía sigue el marco de documentación Diátaxis para proporcionar fundamentos conceptuales, guías paso a paso, comandos de referencia operativa y mapeo exhaustivo de estándares de producción.

Para consultar la versión en inglés de esta documentación, visita [English Documentation](../en/README.md).

---

## 📖 Guías de Módulos

### [1. Arquitectura de Contenedores y Runtimes](./01-contenedores-y-runtimes.md)

Análisis profundo de runtimes OCI, selección de imágenes base (Distroless vs. Debian Slim vs. Alpine vs. Scratch), consideraciones técnicas de musl vs. glibc, prevención de capas duplicadas por Copy-on-Write (bloat de chown), montajes de caché con BuildKit, blueprints multi-etapa (Go, Rust, Node.js, Next.js standalone, Python, Java 21) y auditorías de eficiencia con `dive`.

### [2. Orquestación con Kubernetes, Service Mesh y Autoescalado](./02-kubernetes-y-orquestacion.md)

Estándares de producción para clústeres Kubernetes: perfil Restricted de Pod Security Standards (PSS), mecánica de desalojo por Calidad de Servicio (QoS), NetworkPolicies con política de aislamiento default-deny, Gateway API HTTPRoute vs. Ingress, filtrado L7 con Cilium eBPF, Istio Ambient mesh con mTLS estricto sin sidecars, autoescalado orientado a eventos con KEDA y coexistencia con Vertical Pod Autoscaler (VPA) en modo recomendación.

### [3. Infraestructura como Código, Configuración como Código y DBDevOps](./03-infraestructura-como-codigo-y-cac.md)

Ingeniería multicloud de IaC con Terraform y OpenTofu: bloqueo de estado remoto (AWS S3/DynamoDB, Google Cloud Storage CMEK, Azure Blob Leases), cifrado nativo del lado del cliente con AES-GCM en OpenTofu 1.8+, creación de Golden AMIs inmutables con HashiCorp Packer y hardening CIS Level 2 con Ansible, y migraciones de base de datos sin downtime (patrón Expand/Contract) con Atlas y Flyway.

### [4. Pipelines CI/CD, Entrega Progresiva con GitOps e IDP](./04-cicd-gitops-y-entrega-continua.md)

Entrega continua empresarial: autenticación sin credenciales estáticas mediante OpenID Connect (OIDC), pipelines multi-CI (GitHub Actions, GitLab CI DAG, agentes dinámicos en Pods de K8s para Jenkins), GitOps pull-based con ArgoCD y Flux v2, despliegues canarios progresivos con Argo Rollouts y análisis de métricas en Prometheus, Plataformas Internas de Desarrollador (IDP) con Backstage, infraestructura componible con Crossplane XRDs y gobernanza de artefactos con Harbor HA.

### [5. DevSecOps 360°, Arquitectura Zero Trust y Seguridad en Runtime](./05-devsecops-zero-trust-y-seguridad-en-runtime.md)

Ingeniería de seguridad a lo largo de todo el ciclo de vida CNAPP: modelado de amenazas STRIDE, análisis SAST basado en AST con Semgrep, gobernanza de APIs OpenAPI 3.1 con Spectral, DAST dinámico con Nuclei, arquitectura Zero Trust (NIST SP 800-207) con identidades criptográficas SPIFFE/SPIRE, almacenamiento Raft en HashiCorp Vault HA, Policy as Code con OPA Gatekeeper y Kyverno, monitoreo de llamadas al sistema con Falco eBPF y auditoría CSPM con Prowler.

### [6. SRE, Observabilidad, FinOps y Especializaciones X-Ops](./06-sre-observabilidad-finops-y-xops.md)

Confiabilidad y operaciones avanzadas en runtime: canalizaciones del colector OpenTelemetry con correlación distribuida W3C TraceContext, formulación matemática de SLAs/SLOs/SLIs con alertas Multi-Window Multi-Burn-Rate (Google SRE), inyección de fallas con Chaos Mesh, FinOps en Kubernetes con OpenCost y fórmulas de right-sizing en PromQL, consolidación de instancias Spot con Karpenter, y especializaciones X-Ops (MLOps con inferencia vLLM en GPU, DataOps con dbt Slim CI, NetOps con Containerlab y NoOps con Knative scale-to-zero).
