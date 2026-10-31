# English Documentation Index

Welcome to the English documentation hub for the `devops-skill` ecosystem. Each guide follows the Diátaxis documentation framework to provide conceptual foundations, hands-on tutorials, operational reference commands, and standards mappings.

For the Spanish version of this documentation, visit [Documentación en Español](../es/README.md).

---

## 📖 Module Guides

### [1. Containers & Runtimes Architecture](./01-containers-and-runtimes.md)

Deep dive into OCI runtimes, base image selection (Distroless vs. Debian Slim vs. Alpine vs. Scratch), musl vs. glibc considerations, preventing Copy-on-Write duplicate layers, BuildKit caching mounts, multi-stage language blueprints (Go, Rust, Node.js, Next.js standalone, Python, Java 21), and container layer efficiency auditing with `dive`.

### [2. Kubernetes Orchestration, Service Mesh & Autoscaling](./02-kubernetes-and-orchestration.md)

Production standards for Kubernetes clusters: Pod Security Standards (Restricted profile), Quality of Service (QoS) eviction mechanics, default-deny NetworkPolicies, Gateway API HTTPRoutes vs. Ingress, Cilium eBPF L7 filtering, Istio Ambient sidecarless mesh with mTLS, event-driven autoscaling via KEDA, and Vertical Pod Autoscaler (VPA) recommendation mode coexistence.

### [3. Infrastructure as Code, Configuration as Code & DBDevOps](./03-infrastructure-as-code-and-cac.md)

Multicloud IaC engineering using Terraform and OpenTofu: remote state locking (AWS S3/DynamoDB, Google Cloud Storage CMEK, Azure Blob Leases), OpenTofu 1.8+ native client-side AES-GCM state encryption, immutable Golden AMIs with HashiCorp Packer and Ansible CIS Level 2 hardening, and zero-downtime database migrations (Expand/Contract pattern) with Atlas and Flyway.

### [4. CI/CD Pipelines, GitOps Progressive Delivery & IDP](./04-cicd-gitops-and-delivery.md)

Enterprise software delivery: passwordless cloud authentication using OpenID Connect (OIDC), multi-CI pipelines (GitHub Actions, GitLab CI DAG, Jenkins dynamic K8s Pod agents), ArgoCD and Flux v2 pull-based GitOps, progressive canary releases with Argo Rollouts and Prometheus metrics analysis, Spotify Backstage Internal Developer Platforms, Composable Infrastructure via Crossplane XRDs, and Harbor Enterprise HA artifact governance.

### [5. DevSecOps 360°, Zero Trust Architecture & Runtime Defense](./05-devsecops-zero-trust-and-runtime.md)

Full-lifecycle security engineering across the Cloud Native Application Protection Platform (CNAPP) spectrum: STRIDE threat modeling, Semgrep AST-based SAST, Spectral OpenAPI 3.1 contract linting, Nuclei DAST, NIST SP 800-207 Zero Trust with SPIFFE/SPIRE workload identities, HashiCorp Vault HA Raft storage, Policy as Code with OPA Gatekeeper and Kyverno, Falco eBPF kernel syscall monitoring, and Prowler CSPM.

### [6. SRE, Observability, FinOps & Specialized X-Ops](./06-sre-observability-finops-and-xops.md)

Advanced reliability and runtime operations: OpenTelemetry Collector pipelines, W3C TraceContext distributed correlation, mathematical formulation of SLAs/SLOs/SLIs with Google SRE Multi-Window Multi-Burn-Rate alerting, Chaos Mesh fault injection, Kubernetes FinOps with OpenCost and PromQL right-sizing formulas, Karpenter Spot instance consolidation, and specialized X-Ops (MLOps/LLMOps vLLM GPU serving, DataOps dbt Slim CI, NetOps Containerlab, and NoOps Knative scale-to-zero).
