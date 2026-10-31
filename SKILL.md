---
name: devops-skill
description: "Trigger: devops, docker, dockerfile, compose, kubernetes, k8s, helm, terraform, opentofu, iac, pipeline, github actions, ci/cd, gitops, argocd, devsecops, otel, opentelemetry, sre, deploy, despliegue, contenedor, infraestructura, trivy, cosign. Full-lifecycle 2025/2026 DevOps and DevSecOps engineering across containers, Kubernetes, IaC, CI/CD pipelines, GitOps, and observability."
license: MIT
metadata:
  author: "Reaan"
  version: "2.0.0"
---

# DevOps & DevSecOps Engineering

Full-lifecycle 2025/2026 cloud-native DevOps and DevSecOps engineering across hardened containers, Kubernetes orchestration, Infrastructure as Code (Terraform / OpenTofu), GitOps delivery, automated CI/CD pipelines, OpenTelemetry observability, and software supply chain security.

## Activation Contract

Trigger this skill when:

- Containerizing applications or optimizing container builds (Go, Node.js, Python, Rust, Java).
- Hardening container runtimes, fixing layer bloat, or auditing with `dive`.
- Designing or auditing Kubernetes manifests for production (Pod Security Standards Restricted, NetworkPolicies, QoS, HPA v2, PDB).
- Authoring or refactoring Infrastructure as Code using Terraform or OpenTofu with remote state locking, encryption, and modular architecture.
- Building CI/CD pipelines with GitHub Actions using keyless OIDC authentication for AWS/GCP (eliminating static credentials).
- Implementing GitOps delivery workflows using ArgoCD or Flux with drift detection and automated rollback.
- Signing container images keylessly with Cosign, generating SBOMs with Syft, and enforcing supply chain gates (SLSA Level 3).
- Setting up observability architectures using OpenTelemetry Collectors, structured JSON logging with W3C trace context, and Prometheus golden signals.
- Hardening repositories against secret leaks with Gitleaks and scanning vulnerabilities with Trivy.

Antipatterns to avoid:

- Running containers as `root` (UID 0) or leaving out explicit non-root declarations.
- Running `COPY` followed by `RUN chown -R` in Dockerfiles (triggers Copy-on-Write duplicate layers).
- Committing static cloud credentials (`AWS_ACCESS_KEY_ID`, service account JSON keys) to CI secrets instead of using short-lived OIDC tokens.
- Deploying Kubernetes workloads without CPU/memory requests and limits or omitting `readOnlyRootFilesystem: true`.
- Storing unencrypted Terraform state files locally or without state locking mechanisms (DynamoDB / native S3 locking).
- Permitting arbitrary cross-namespace or pod-to-pod network traffic by omitting `NetworkPolicy` default-deny rules.
- Silently swallowing build or security scan failures in CI (`exit 0` masks or `--continue-on-error`).

## Hard Rules

1. **Non-Root Execution Everywhere**: Container runtimes MUST execute as non-root users (`USER nonroot:nonroot` or UID `>= 1000`). In Kubernetes, enforce `runAsNonRoot: true` and specify explicit `runAsUser` and `runAsGroup`.
2. **Zero COW Chown Bloat**: Never run `COPY` followed by a standalone `RUN chown -R`. Always enforce ownership at transfer time with `COPY --chown=user:group`.
3. **Restricted Pod Security Standard**: Production Kubernetes workloads MUST satisfy the Pod Security Standard `restricted` profile: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: { drop: ["ALL"] }`, and `seccompProfile: { type: RuntimeDefault }`.
4. **Guaranteed QoS or Calibrated Burstable**: Production workloads with sensitive tail latencies MUST declare matching CPU/memory requests and limits (`Guaranteed` QoS). Dynamic workloads MUST define calibrated requests with reasonable limit ceilings to prevent OOM cascade kills.
5. **Default-Deny Ingress and Egress**: Every Kubernetes namespace hosting workloads MUST define a baseline `NetworkPolicy` denying all incoming and outgoing traffic by default, whitelisting only essential service-to-service flows, DNS (UDP/TCP port 53), and monitoring scrapers.
6. **Keyless Cloud Authentication (OIDC)**: CI/CD pipelines MUST authenticate to AWS, GCP, or Azure using OpenID Connect (OIDC). Long-lived static access keys and credentials in CI secrets are strictly prohibited.
7. **Immutable, Signed Artifacts**: Production container images MUST be pinned by digest (`sha256:...`), signed with keyless Cosign via Sigstore Fulcio/Rekor, and accompanied by a CycloneDX or SPDX Software Bill of Materials (SBOM).
8. **Encrypted Remote State with Locking**: Terraform/OpenTofu state files MUST reside in remote object storage with AES-256 or KMS customer-managed encryption, versioning enabled, public access blocked, and state locking enforced via DynamoDB or native state locking.
9. **W3C Trace Context Propagation**: Structured application logs MUST format output in single-line JSON and inject distributed tracing context (`trace_id`, `span_id`, `trace_flags`) compatible with the W3C TraceContext specification.

## Decision Gates

### Base Image Selection Matrix

| Base Image | Best For | Pros | Cons / Gotchas |
| --- | --- | --- | --- |
| **Distroless** (`gcr.io/distroless/static-debian12`, `distroless/cc-debian12`) | Go, Rust, static C/C++ binaries | Zero package manager, zero shell, minimal attack surface, non-root user built-in | Ephemeral debug containers needed for live troubleshooting |
| **Debian Slim** (`node:22-bookworm-slim`, `python:3.12-slim`) | Node.js, Python, Ruby, dynamic runtimes | Full `glibc` compatibility, standard Debian packages via `apt`, reliable DNS and C-extensions | Larger footprint (~50–120 MB); requires explicit cleanup in single `RUN` layer |
| **Alpine Linux** (`alpine:3.21`) | Lightweight utilities, simple shell workers | Ultra small footprint (~7 MB base), rapid pull | Uses `musl libc`; binary incompatibility or performance degradation with Python wheels and Go CGO |
| **Scratch** (`FROM scratch`) | 100% statically linked Go or Rust binaries | Absolute zero base overhead | No CA certificates, no `/etc/passwd`, no zoneinfo unless copied from builder stage |

### Orchestration & Delivery Matrix

| Dimension | Pattern A (Standard Cloud-Native) | Pattern B (High-Assurance / Regulated) |
| --- | --- | --- |
| **Cluster Ingress** | NGINX Ingress Controller / Traefik with cert-manager | Envoy Gateway / Istio Ambient Mesh with mTLS and SPIFFE/SPIRE |
| **GitOps Engine** | ArgoCD with declarative Application CRDs | ArgoCD with ApplicationSet, automated sync windows, and Kyverno policy guardrails |
| **Secret Management** | External Secrets Operator (ESO) syncing from AWS Secrets Manager / Vault | HashiCorp Vault Agent Injector with dynamic credentials and HSM encryption |
| **Scaling Strategy** | HPA v2 using CPU/Memory metrics | HPA v2 + KEDA driven by Prometheus PromQL queries or message queue lag |

### Observability & Telemetry Matrix

| Layer | Recommended Standard | Implementation Notes |
| --- | --- | --- |
| **Tracing & Metrics** | OpenTelemetry SDK + OTel Collector | Export traces via OTLP/gRPC to Tempo/Jaeger; metrics to Prometheus/Mimir |
| **Logging** | JSON structured logging stdout | Collector fluentforward/filelog receiver -> Loki/Elasticsearch with trace-log correlation |
| **Dashboarding & Alerts** | Grafana + Prometheus Alertmanager | Alert on 4 Golden Signals (Latency, Traffic, Errors, Saturation) with Multi-Window Multi-Burn-Rate alerts |

## Execution Steps

### 1. Discover & Baseline

1. Identify application runtime (language, version, dependency manager, build steps).
2. Scan existing repository for exposed secrets and credentials using `scripts/scan-secrets.sh`.
3. Inventory existing deployment artifacts (Dockerfiles, Compose files, Helm charts, Kubernetes manifests, Terraform code).
4. Identify compliance requirements (SOC2, PCI-DSS, ISO27001, SLSA target tier).

### 2. Containerize & Harden Runtime

1. Create or audit `.dockerignore` using `templates/containers/.dockerignore`.
2. Author multi-stage `Dockerfile` choosing between Distroless (`templates/containers/Dockerfile.distroless.go`) and Debian Slim (`templates/containers/Dockerfile.slim.node`, `templates/containers/Dockerfile.slim.python`).
3. Leverage BuildKit cache mounts (`--mount=type=cache,target=...`) for package managers (`go build`, `npm/pnpm`, `pip`).
4. Prevent Copy-on-Write duplicate layers by applying `--chown=user:group` directly inside `COPY` instructions.
5. Audit image layer efficiency and wasted space with `scripts/audit-image.sh` (target efficiency `>= 98%`).
6. Configure local or staging multi-service topologies with `templates/containers/compose.hardened.yaml` enforcing read-only root filesystems, drop capabilities, and CPU/memory caps.

### 3. Orchestrate & Policy Enforcement

1. Scaffold production Kubernetes manifests:
   - Hardened Deployment with `restricted` security context (`templates/kubernetes/deployment-hardened.yaml`).
   - ClusterIP Service and TLS-terminated Ingress (`templates/kubernetes/service-ingress.yaml`).
   - Strict `NetworkPolicy` default-deny for ingress and egress (`templates/kubernetes/network-policy-default-deny.yaml`).
   - HorizontalPodAutoscaler v2 targeting CPU and custom metrics (`templates/kubernetes/hpa-v2.yaml`).
   - PodDisruptionBudget ensuring high availability during node drains (`templates/kubernetes/pdb.yaml`).
2. Validate manifests syntax and schema using `scripts/k8s-dry-run-validate.sh`.
3. Verify readiness, liveness, and startup probes to protect against traffic blackholes during rolling updates.

### 4. Infrastructure as Code & State

1. Configure remote state backend with encryption, locking, and public access blocks (`templates/terraform/backend-s3-dynamodb.tf`).
2. Structure Terraform / OpenTofu root module and variables (`templates/terraform/main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`).
3. Run static security and syntax validation:

   ```bash
   terraform fmt -check
   tflint --init && tflint
   trivy config .
   ```

4. Enforce principle of least privilege in IAM policies and cloud network topologies.

### 5. Secure CI/CD & GitOps Delivery

1. Author GitHub Actions workflows:
   - Container build, multi-platform compilation, and push to registry (`templates/github-actions/ci-docker-build-push.yml`).
   - Passwordless cloud authentication using OpenID Connect (`templates/github-actions/oidc-aws-auth.yml`).
   - Security scanning gate with Gitleaks and Trivy (`templates/github-actions/gitleaks-trivy-scan.yml`).
2. Implement keyless image signing with Cosign and Sigstore in the release job.
3. Generate and attest CycloneDX/SPDX SBOM with Syft.
4. Configure GitOps reconciliation via ArgoCD Application manifest (`templates/gitops/argocd-application.yaml`).

### 6. Observability, SRE & SLOs

1. Deploy and configure the OpenTelemetry Collector (`templates/observability/otel-collector-config.yaml`) with pipelines for traces, metrics, and logs.
2. Standardize application logging schema using `templates/observability/structured-log-spec.json` ensuring correlation with `trace_id` and `span_id`.
3. Define Service Level Objectives (SLOs) and Error Budgets for the service based on latency percentiles (P95, P99) and availability ratios.
4. Configure Prometheus alerting rules for burn rates (1h, 6h, 3d windows).

### 7. Continuous DevSecOps Audit

1. Execute periodic and PR-triggered container vulnerability scans with Trivy (`severity: HIGH,CRITICAL`, `exit-code: 1`).
2. Execute secret scans across Git commit history with Gitleaks.
3. Validate supply chain integrity against SLSA Level 3 requirements.

## Output Contract

When completing a DevOps or DevSecOps implementation or review, return:

1. **Architecture & Topology Summary**: Clear explanation of components deployed (containers, Kubernetes resources, IaC modules, CI/CD pipelines).
2. **Security & Hardening Posture**: Specific controls activated (non-root UID, read-only rootfs, dropped capabilities, NetworkPolicies, OIDC, Cosign signature).
3. **Verification Evidence**:
   - `audit-image.sh` efficiency score and layer findings.
   - `k8s-dry-run-validate.sh` validation status.
   - `scan-secrets.sh` leak inspection results.
   - IaC linting and static analysis results.
4. **Artifact Manifest**: List of newly authored or modified templates, configurations, and scripts with relative repository paths.

## Reference Architecture & Deep Dives

For exhaustive implementation standards and architectural blueprints, consult the references:

| Topic | Reference Document | Key Focus Areas |
| --- | --- | --- |
| **Containers & Runtime** | `references/01-containers-runtime.md` | Distroless, rootless UID, BuildKit cache mounts, COW chown bloat, dive audit |
| **Kubernetes Cloud-Native** | `references/02-kubernetes-cloudnative.md` | PSS Restricted, NetworkPolicies default-deny, Guaranteed QoS, HPA v2, PDB |
| **IaC & Terraform/OpenTofu** | `references/03-iac-terraform-opentofu.md` | Remote S3/DynamoDB state locking, KMS, clean module structure, TFLint/Trivy |
| **CI/CD & GitOps** | `references/04-cicd-gitops.md` | Keyless OIDC (AWS/GCP), Cosign signing, SLSA provenance, ArgoCD sync |
| **Observability & SRE** | `references/05-observability-sre.md` | OpenTelemetry v1.30+ collector, Prometheus 4 golden signals, JSON traceparent |
| **DevSecOps Supply Chain** | `references/06-devsecops-supply-chain.md` | Syft SBOM, Trivy vulnerability gating, Gitleaks commit scanning, SLSA L3 |
| **OSS Governance & Standards** | `references/07-oss-governance-standards.md` | Diátaxis docs, PR etiquette, automated quality gates, semantic versioning |
