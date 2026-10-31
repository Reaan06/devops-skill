---
name: devops-skill
description: "Trigger: devops, docker, dockerfile, compose, kubernetes, k8s, helm, terraform, opentofu, iac, pipeline, github actions, ci/cd, gitops, argocd, flux, devsecops, otel, opentelemetry, sre, deploy, despliegue, contenedor, infraestructura, trivy, cosign, cac, ansible, packer, dbdevops, atlas, flyway, keda, cilium, istio, backstage, crossplane, harbor, sast, semgrep, dast, nuclei, falco, spiffe, spire, vault, chaos, finops, opencost, karpenter, mlops, vllm, dataops, dbt, netops, containerlab, noops, knative. Full-lifecycle 2025/2026 DevOps, DevSecOps, SRE, Platform Engineering, FinOps, and X-Ops."
license: MIT
metadata:
  author: "Reaan"
  version: "2.0.0"
---

# DevOps, DevSecOps & Enterprise Cloud-Native Engineering

Full-lifecycle 2025/2026 cloud-native DevOps, DevSecOps, SRE, Platform Engineering, FinOps, and specialized X-Ops engineering across hardened containers, Kubernetes orchestration, Infrastructure as Code, GitOps progressive delivery, zero-trust security, and runtime telemetry.

## Activation Contract

Trigger this skill when:

- Containerizing applications or optimizing container builds (Go, Node.js, Python, Rust, Java).
- Hardening container runtimes, fixing layer bloat, or auditing with `dive`.
- Designing or auditing Kubernetes manifests for production (Pod Security Standards Restricted, NetworkPolicies, QoS, HPA v2, PDB).
- Authoring or refactoring Infrastructure as Code using Terraform or OpenTofu with remote state locking, encryption, and modular architecture.
- Automating Configuration as Code (CaC) and immutable Golden Images using HashiCorp Packer and Ansible.
- Managing database migrations with zero downtime (Expand/Contract pattern) using Atlas, Liquibase, or Flyway.
- Building CI/CD pipelines with GitHub Actions, GitLab CI, or Jenkins using keyless OIDC authentication for AWS/GCP/Azure.
- Implementing GitOps delivery workflows using ArgoCD or Flux v2 with drift detection, sync windows, and automated rollback.
- Implementing progressive delivery (Canary, Blue/Green, Shadow) with Argo Rollouts and OpenFeature flags.
- Scaling Kubernetes workloads with KEDA event-driven triggers and calibrating resources with Vertical Pod Autoscaler (VPA).
- Designing Cloud-Native networking with Gateway API, Cilium eBPF L7 policies, or Istio Ambient Mesh with strict mTLS.
- Building Internal Developer Platforms (IDP) with Backstage and composable infrastructure via Crossplane XRDs.
- Deploying enterprise artifact management with Harbor HA, automated Trivy security gates, and immutable signed tags.
- Implementing Threat Modeling (STRIDE), deep SAST with Semgrep, dynamic testing (DAST) with Nuclei/ZAP, and Fuzzing (AFL++/Jazzer).
- Enforcing Spec-Driven API security (OpenAPI 3.1, GraphQL Armor, gRPC/Buf) using Spectral rulesets.
- Enforcing Policy as Code with OPA Gatekeeper / Kyverno, Cloud Workload Protection (CWPP) with Falco eBPF, and CSPM with Prowler.
- Architecting Zero Trust Architecture (ZTA) using SPIFFE/SPIRE workload identities and HashiCorp Vault HA.
- Formulating SRE contracts (SLAs, SLOs, SLIs), multi-window multi-burn-rate alerting, error budget freeze policies, and Chaos Engineering.
- Managing Kubernetes runtime FinOps with OpenCost / Kubecost and spot instance resilience with Karpenter.
- Engineering specialized X-Ops domains: MLOps/LLMOps (vLLM, GPU slicing, DVC, NeMo), DataOps (dbt Slim CI, Airflow), NetOps (gNMI, Containerlab), and NoOps (Knative scale-to-zero, CloudEvents).

Antipatterns to avoid:

- Running containers as `root` (UID 0) or leaving out explicit non-root declarations.
- Running `COPY` followed by `RUN chown -R` in Dockerfiles (triggers Copy-on-Write duplicate layers).
- Committing static cloud credentials (`AWS_ACCESS_KEY_ID`, service account JSON keys) to CI secrets instead of using short-lived OIDC tokens.
- Deploying Kubernetes workloads without CPU/memory requests and limits or omitting `readOnlyRootFilesystem: true`.
- Storing unencrypted Terraform state files locally or without state locking mechanisms (DynamoDB / native S3 locking).
- Permitting arbitrary cross-namespace or pod-to-pod network traffic by omitting `NetworkPolicy` default-deny rules.
- Performing destructive database migrations in a single release without an Expand/Contract transition phase.
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
10. **Zero-Downtime Expand/Contract Migrations**: Database schema modifications MUST decouple column/table creation from destructive drops across separate release cycles with backwards compatibility.

## Decision Gates

### Base Image Selection Matrix

| Base Image | Best For | Pros | Cons / Gotchas |
| --- | --- | --- | --- |
| **Distroless** (`gcr.io/distroless/static-debian12`, `distroless/cc-debian12`) | Go, Rust, static C/C++ binaries | Zero package manager, zero shell, minimal attack surface, non-root user built-in | Ephemeral debug containers needed for live troubleshooting |
| **Debian Slim** (`node:22-bookworm-slim`, `python:3.12-slim`) | Node.js, Python, Ruby, dynamic runtimes | Full `glibc` compatibility, standard Debian packages via `apt`, reliable DNS and C-extensions | Larger footprint (~50–120 MB); requires explicit cleanup in single `RUN` layer |
| **Alpine Linux** (`alpine:3.21`) | Lightweight utilities, simple shell workers | Ultra small footprint (~7 MB base), rapid pull | Uses `musl libc`; binary incompatibility or performance degradation with Python wheels and Go CGO |
| **Scratch** (`FROM scratch`) | 100% statically linked Go or Rust binaries | Absolute zero base overhead | No CA certificates, no `/etc/passwd`, no zoneinfo unless copied from builder stage |

### Progressive Delivery & Release Matrix

| Strategy | Traffic Shift Mechanism | Rollback Trigger | Best For | Reference |
| --- | --- | --- | --- | --- |
| **Rolling Update** | Pod-by-pod replacement via Deployment spec | Readiness probe failures | Standard stateless apps with backwards-compatible APIs | `02-kubernetes-cloudnative.md` |
| **Canary (Argo Rollouts)** | Percentage-based traffic splitting (10% -> 20% -> 50% -> 100%) | Prometheus PromQL error budget / P95 latency burn rate | High-traffic services, mission-critical APIs | `09-multici-progressive-releases.md` |
| **Blue/Green** | 100% instant cutover via Service selector switch | Pre-promotion smoke test failure | Services requiring strict atomic cutover or state synchronicity | `09-multici-progressive-releases.md` |
| **Shadow / Dark Launch** | Asynchronous traffic mirroring (0% user impact) | Error diff against live responses | High-risk refactors, machine learning model validation | `09-multici-progressive-releases.md` |

### Security Engines & Testing Matrix

| Security Layer | Tooling Standard | Gate Enforcement | Output & Integration | Reference |
| --- | --- | --- | --- | --- |
| **Threat Modeling** | OWASP Threat Dragon / STRIDE | Pre-implementation architectural gate | Architecture Data Flow Diagram (DFD) | `14-devsecops-advanced-testing.md` |
| **Secret Detection** | Gitleaks / Pre-commit | Block commit & PR merge (`exit 1`) | Pre-commit hook & CI pipeline check | `06-devsecops-supply-chain.md` |
| **SAST** | Semgrep / SonarQube | Fail on High/Critical CWEs | SARIF export to GitHub/GitLab Security tab | `14-devsecops-advanced-testing.md` |
| **SCA** | Trivy / Syft SBOM | Fail on fixable CVEs with CVSS >= 7.0 | CycloneDX SBOM + SARIF vulnerability report | `06-devsecops-supply-chain.md` |
| **DAST** | Nuclei / OWASP ZAP | Automated scan on ephemeral staging | Dynamic vulnerability report | `14-devsecops-advanced-testing.md` |
| **API Contract** | Spectral / GraphQL Armor | Lint OpenAPI 3.1 & GraphQL schemas in CI | Fail on missing auth or BOLA risks | `15-spec-driven-api-security.md` |
| **Policy as Code** | Kyverno / OPA Gatekeeper | Block admission of non-compliant pods | In-cluster validating admission webhook | `16-pac-cwpp-cnapp-runtime.md` |
| **CWPP (Runtime)** | Falco / Tetragon eBPF | Kernel syscall anomaly detection | Prometheus alerts & SOAR pod quarantine | `16-pac-cwpp-cnapp-runtime.md` |
| **CSPM / CNAPP** | Prowler | Daily CIS Cloud Benchmark scan | Compliance posture dashboard | `16-pac-cwpp-cnapp-runtime.md` |

### X-Ops Specializations Routing Matrix

| Domain | Core Challenges | Recommended Stack | Production Blueprint |
| --- | --- | --- | --- |
| **MLOps / LLMOps** | GPU underutilization, model drift, prompt injection | NVIDIA GPU Operator, vLLM, DVC, MLflow, NeMo | `references/20-mlops-llmops-engineering.md` |
| **DataOps** | Silent schema drift, data pipeline test coverage | dbt Slim CI, Great Expectations, Airflow, Dagster | `references/21-dataops-pipeline-engineering.md` |
| **NetOps** | Manual switch drift, unvalidated BGP updates | NetBox SSoT, gNMI telemetry, Containerlab in CI | `references/22-netops-network-automation.md` |
| **NoOps / Serverless** | Cold starts, vendor lock-in, event orchestration | Knative Serving, AWS Lambda, CloudEvents | `references/23-noops-serverless-event-driven.md` |

## Execution Steps

### 1. Discover & Baseline

1. Identify application runtime (language, version, dependency manager, build steps).
2. Scan existing repository for exposed secrets and credentials using `scripts/scan-secrets.sh`.
3. Inventory existing deployment artifacts (Dockerfiles, Compose files, Helm charts, Kubernetes manifests, Terraform code).
4. Identify compliance requirements (SOC2, PCI-DSS, ISO27001, SLSA target tier).

### 2. Containerize & Harden Runtime

1. Create or audit `.dockerignore` using `templates/containers/.dockerignore`.
2. Author multi-stage `Dockerfile` choosing between Distroless (`templates/containers/Dockerfile.distroless.go`, `Dockerfile.distroless.rust`) and Debian Slim (`templates/containers/Dockerfile.slim.node`, `templates/containers/Dockerfile.slim.python`, `Dockerfile.temurin.java21`).
3. Leverage BuildKit cache mounts (`--mount=type=cache,target=...`) for package managers (`go build`, `cargo`, `npm/pnpm`, `pip`, `maven`).
4. Prevent Copy-on-Write duplicate layers by applying `--chown=user:group` directly inside `COPY` instructions.
5. Audit image layer efficiency and wasted space with `scripts/audit-image.sh` (target efficiency `>= 98%`).
6. Configure local or staging multi-service topologies with `templates/containers/compose.hardened.yaml` enforcing read-only root filesystems, drop capabilities, and CPU/memory caps.

### 3. Orchestrate & Policy Enforcement

1. Scaffold production Kubernetes manifests:
   - Hardened Deployment with `restricted` security context (`templates/kubernetes/deployment-hardened.yaml`).
   - ClusterIP Service and TLS-terminated Ingress or Gateway API (`templates/kubernetes/service-ingress.yaml`, `gateway-api-httproute.yaml`).
   - Strict `NetworkPolicy` default-deny for ingress and egress or Cilium L7 policy (`templates/kubernetes/network-policy-default-deny.yaml`, `cilium-networkpolicy-l7.yaml`).
   - Autoscaling via HPA v2 and KEDA event-driven triggers (`templates/kubernetes/hpa-v2.yaml`, `keda-scaledobject-prometheus.yaml`).
   - PodDisruptionBudget ensuring high availability during node drains (`templates/kubernetes/pdb.yaml`).
2. Validate manifests syntax and schema using `scripts/k8s-dry-run-validate.sh` and `kubeconform`.
3. Verify readiness, liveness, and startup probes to protect against traffic blackholes during rolling updates.

### 4. Infrastructure as Code, CaC & State

1. Configure remote state backend with encryption, locking, and public access blocks (`templates/terraform/backend-s3-dynamodb.tf`, `backend-gcs.tf`, `backend-azurerm.tf`).
2. Apply OpenTofu 1.8+ native state encryption block for local and remote protection (`templates/terraform/backend-encryption.tf`).
3. Build immutable Golden Images with Packer and Ansible CIS hardening (`templates/cac/packer-golden-ami.pkr.hcl`, `templates/cac/ansible-baseline-hardening.yml`).
4. Run static security and syntax validation:

   ```bash
   terraform fmt -check
   checkov -d .
   infracost breakdown --path .
   ```

5. Enforce principle of least privilege in IAM policies and cloud network topologies.

### 5. Secure CI/CD, GitOps & Delivery

1. Author CI/CD workflows:
   - GitHub Actions container build, multi-platform compilation, and push (`templates/github-actions/ci-docker-build-push.yml`).
   - GitLab CI enterprise pipeline with DAG and Kaniko (`templates/gitlab/.gitlab-ci-enterprise.yml`).
   - Jenkins declarative pipeline on dynamic K8s Pod agents (`templates/jenkins/Jenkinsfile.declarative`).
   - Keyless cloud authentication using OpenID Connect (`templates/github-actions/oidc-aws-auth.yml`).
   - Security scanning gate with Gitleaks, Trivy, and Semgrep (`templates/github-actions/gitleaks-trivy-scan.yml`, `semgrep-sast.yml`).
2. Implement keyless image signing with Cosign and Sigstore in the release job.
3. Generate and attest CycloneDX/SPDX SBOM with Syft.
4. Configure GitOps reconciliation via ArgoCD Application (`templates/gitops/argocd-application.yaml`) or Flux v2 Kustomization (`templates/gitops/fluxcd-kustomization.yaml`).
5. Configure progressive canary releases with Argo Rollouts and Prometheus metrics analysis (`templates/gitops/argo-rollouts-canary.yaml`).

### 6. Observability, SRE, Chaos & FinOps

1. Deploy and configure the OpenTelemetry Collector (`templates/observability/otel-collector-config.yaml`) with pipelines for traces, metrics, and logs.
2. Standardize application logging schema using `templates/observability/structured-log-spec.json` ensuring correlation with `trace_id` and `span_id`.
3. Define Service Level Objectives (SLOs) and Error Budget Policies (`templates/sre/error-budget-policy.md`) with multi-window multi-burn-rate alerting (`templates/kubernetes/prometheus-rule-slo-alerts.yaml`).
4. Execute hypothesis-driven Chaos Engineering using Chaos Mesh (`templates/sre/chaos-mesh-network-delay.yaml`).
5. Track and allocate runtime Kubernetes compute costs using OpenCost (`templates/finops/opencost-k8s-values.yaml`).
6. Optimize cloud compute spending using Karpenter spot instance diversification and consolidation (`templates/finops/karpenter-spot-nodepool.yaml`).

### 7. Continuous DevSecOps Audit & Runtime Defense

1. Execute continuous SAST (Semgrep), DAST (Nuclei), and CSPM (Prowler) scans in CI.
2. Monitor runtime kernel syscalls with Falco eBPF (`templates/security/falco-rules-k8s.yaml`) to detect privilege escalation and interactive shells.
3. Manage secrets dynamically with External Secrets Operator or HashiCorp Vault HA Raft (`templates/security/vault-cluster-raft-values.yaml`).
4. Issue cryptographic workload identities with SPIFFE/SPIRE (`templates/security/spire-agent-server-k8s.yaml`).

## Output Contract

When completing a DevOps or DevSecOps implementation or review, return:

1. **Architecture & Topology Summary**: Clear explanation of components deployed (containers, Kubernetes resources, IaC modules, CI/CD pipelines, IDP, Mesh).
2. **Security & Hardening Posture**: Specific controls activated (non-root UID, read-only rootfs, dropped capabilities, NetworkPolicies, OIDC, Cosign signature, Falco rules, SPIFFE identities).
3. **Verification Evidence**:
   - `scripts/validate-all.sh` 8/8 validation suite status.
   - Container layer audit efficiency score.
   - Secret scan results (Gitleaks).
   - Schema and policy validation results (Kubeconform, Checkov, Yamllint).
4. **Artifact Manifest**: List of newly authored or modified templates, configurations, and scripts with relative repository paths.

## Reference Architecture & Deep Dives

For exhaustive implementation standards and architectural blueprints, consult the references:

| Topic | Reference Document | Key Focus Areas |
| --- | --- | --- |
| **Containers & Runtime** | `references/01-containers-runtime.md` | Distroless, rootless UID, BuildKit cache mounts, COW chown bloat, dive audit |
| **Kubernetes Cloud-Native** | `references/02-kubernetes-cloudnative.md` | PSS Restricted, NetworkPolicies default-deny, Guaranteed QoS, HPA v2, PDB |
| **IaC & Terraform/OpenTofu** | `references/03-iac-terraform-opentofu.md` | Remote S3/DynamoDB/GCS/Azure state locking, KMS, clean module structure, TFLint/Trivy |
| **CI/CD & GitOps** | `references/04-cicd-gitops.md` | Keyless OIDC (AWS/GCP), Cosign signing, SLSA provenance, ArgoCD sync |
| **Observability & SRE** | `references/05-observability-sre.md` | OpenTelemetry v1.30+ collector, Prometheus 4 golden signals, JSON traceparent |
| **DevSecOps Supply Chain** | `references/06-devsecops-supply-chain.md` | Syft SBOM, Trivy vulnerability gating, Gitleaks commit scanning, SLSA L3 |
| **OSS Governance & Standards** | `references/07-oss-governance-standards.md` | Diátaxis docs, PR etiquette, automated quality gates, semantic versioning |
| **SCM & Config as Code** | `references/08-scm-branching-cac.md` | Trunk-Based Development, Monorepo DAG, Packer & Ansible CIS Golden Images |
| **Multi-CI & Progressive Releases** | `references/09-multici-progressive-releases.md` | GitLab CI, Jenkins, Argo Rollouts canary, Shadow deploys, OpenFeature flags |
| **Zero-Downtime DBDevOps** | `references/10-dbdevops-zero-downtime.md` | Atlas, Liquibase, Flyway, 3-phase Expand/Contract migrations, K8s PreSync jobs |
| **Service Mesh & KEDA** | `references/11-servicemesh-keda-autoscaling.md` | KEDA event-driven autoscaling, VPA coexistence, Cilium eBPF, Istio Ambient mTLS |
| **Platform Engineering & IDP** | `references/12-platform-engineering-idp.md` | Backstage, Port, Golden Paths, Crossplane XRDs & declarative compositions |
| **Enterprise Artifacts (Harbor)** | `references/13-artifact-management-harbor.md` | Harbor HA with S3/Postgres, Trivy vulnerability gates, Cosign signature enforcement |
| **Advanced DevSecOps Testing** | `references/14-devsecops-advanced-testing.md` | Threat Modeling (STRIDE), Semgrep SAST, Nuclei/ZAP DAST, AFL++/Jazzer fuzzing |
| **Spec-Driven API Security** | `references/15-spec-driven-api-security.md` | OpenAPI 3.1 & GraphQL contract linting with Spectral, OWASP API Top 10 mitigation |
| **PaC, CWPP & CNAPP** | `references/16-pac-cwpp-cnapp-runtime.md` | OPA Gatekeeper vs Kyverno, Falco eBPF syscall tracing, Prowler CSPM, SOAR quarantine |
| **Zero Trust, SPIFFE & Vault** | `references/17-zero-trust-spiffe-vault.md` | NIST SP 800-207 Zero Trust, SPIFFE/SPIRE workload SVIDs, Vault HA Raft storage |
| **SRE & Chaos Engineering** | `references/18-sre-chaos-engineering.md` | Mathematical SLA/SLO/SLI, Multi-Window Multi-Burn-Rate alerting, Chaos Mesh |
| **Runtime FinOps & Spot** | `references/19-finops-runtime-cost-optimization.md` | OpenCost pod cost allocation, PromQL right-sizing formulas, Karpenter Spot resilience |
| **MLOps & LLMOps** | `references/20-mlops-llmops-engineering.md` | ML lifecycle (DVC/MLflow), GPU slicing (MIG), vLLM PagedAttention, NeMo guardrails |
| **DataOps Pipelines** | `references/21-dataops-pipeline-engineering.md` | DataOps agile lifecycle, dbt Slim CI, Airflow K8sExecutor, Great Expectations |
| **NetOps & Network as Code** | `references/22-netops-network-automation.md` | NetBox SSoT, NETCONF/RESTCONF, gNMI telemetry, Containerlab virtual topologies |
| **NoOps & Serverless** | `references/23-noops-serverless-event-driven.md` | Autonomous operations, FaaS architectures, CloudEvents, Knative scale-to-zero |
