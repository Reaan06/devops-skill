# DevOps & DevSecOps Engineering Skill

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/gentleman-programming/devops-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/gentleman-programming/devops-skill/actions/workflows/ci.yml)
[![Security Scan](https://github.com/gentleman-programming/devops-skill/actions/workflows/security-scan.yml/badge.svg)](https://github.com/gentleman-programming/devops-skill/actions/workflows/security-scan.yml)
[![DevSecOps Trivy](https://img.shields.io/badge/Security-Trivy%20Gated-brightgreen.svg)](https://trivy.dev/)
[![Supply Chain SLSA 3](https://img.shields.io/badge/Supply%20Chain-SLSA%20L3%20Ready-blueviolet.svg)](https://slsa.dev/)
[![OpenTelemetry Ready](https://img.shields.io/badge/Observability-OpenTelemetry%20v1.30%2B-orange.svg)](https://opentelemetry.io/)

Production-grade 2025/2026 DevOps and DevSecOps engineering skill for cloud-native systems. Covers container runtime hardening, production Kubernetes manifests with zero-trust network policies, immutable Infrastructure as Code with OpenTofu/Terraform, keyless OIDC CI/CD pipelines, GitOps reconciliation with ArgoCD, OpenTelemetry collector architectures, and end-to-end supply chain security.

---

## Capabilities & Architecture Matrix

| Module | Core Standards & Technologies | Key Capabilities & Enforcements |
| --- | --- | --- |
| **Hardened Containers** | Distroless, Debian Slim, Docker BuildKit, Dive | Rootless execution (UID 10001/65532), zero COW chown bloat, BuildKit cache mounts, image efficiency score $\ge$ 98%. |
| **Kubernetes Cloud-Native** | Kubernetes 1.28+, PSS Restricted, NetworkPolicies | Pod Security Standard Restricted, default-deny ingress/egress, Guaranteed/Burstable QoS, HPA v2 custom metrics, PDBs. |
| **Infrastructure as Code** | OpenTofu 1.8+, Terraform 1.9+, AWS S3/DynamoDB | Clean modular hierarchy, remote encrypted S3 state with KMS, distributed state locking, TFLint and Trivy IaC static gates. |
| **CI/CD Automation** | GitHub Actions, OpenID Connect (OIDC) | Zero static credentials, short-lived AWS/GCP STS tokens, multi-platform container compilation (`linux/amd64`, `linux/arm64`). |
| **GitOps Delivery** | ArgoCD v2.10+, Helm, Kustomize | Declarative Application CRDs, automated drift detection, self-healing reconciliation, automated health checking and rollback. |
| **Observability & SRE** | OpenTelemetry v1.30+, Prometheus, W3C TraceContext | Unified OTel Collector pipeline, 4 Golden Signals (Latency, Traffic, Errors, Saturation), single-line JSON logs with injected `trace_id`. |
| **Supply Chain & DevSecOps** | Sigstore Cosign, Syft, Trivy, Gitleaks, SLSA Level 3 | Keyless cryptographic container signing, automated CycloneDX/SPDX SBOM generation and attestation, high/critical CVE build gating. |

---

## Directory Structure

```text
devops-skill/
├── SKILL.md                          # Main skill specification & agent execution contract
├── README.md                         # Project documentation and onboarding
├── LICENSE                           # Apache-2.0 open-source license
├── SECURITY.md                       # Vulnerability disclosure and security policy
├── CONTRIBUTING.md                   # Engineering standards, linting, and PR workflow
├── CODE_OF_CONDUCT.md                # Community covenant code of conduct
├── references/                       # In-depth architectural references & deep dives
│   ├── 01-containers-runtime.md      # Container hardening, distroless, dive efficiency
│   ├── 02-kubernetes-cloudnative.md  # K8s PSS Restricted, NetworkPolicies, QoS, HPA, PDB
│   ├── 03-iac-terraform-opentofu.md  # Clean IaC architecture, remote state locking, KMS
│   ├── 04-cicd-gitops.md             # Keyless OIDC, Cosign signing, SLSA, ArgoCD GitOps
│   ├── 05-observability-sre.md       # OpenTelemetry collector, 4 golden signals, JSON logs
│   ├── 06-devsecops-supply-chain.md  # Syft SBOMs, Trivy CVE gating, Gitleaks, SLSA L3
│   └── 07-oss-governance-standards.md# Diátaxis docs, PR etiquette, quality gates
├── templates/                        # Battle-tested production templates
│   ├── containers/                   # Hardened Dockerfiles, compose, and .dockerignore
│   ├── kubernetes/                   # Production manifests (Deployment, Ingress, NetPol, HPA, PDB)
│   ├── terraform/                    # Root module, variables, outputs, and backend config
│   ├── github-actions/               # OIDC authentication, container build/push, Trivy/Gitleaks
│   ├── gitops/                       # ArgoCD declarative application definitions
│   └── observability/                # OpenTelemetry collector configuration and JSON log spec
└── scripts/                          # Reusable verification and auditing scripts
    ├── audit-image.sh                # Container image efficiency and layer analysis via dive
    ├── scan-secrets.sh               # Git repository secret leak scanning via gitleaks
    └── k8s-dry-run-validate.sh       # Client-side Kubernetes manifest syntax & schema validator
```

---

## Quick Start

### 1. Using Within Pi Agent

To load and activate this skill inside the Pi harness:

```bash
# Verify the skill is indexed in your Pi environment
pi --list-skills | grep devops-skill
```

When interacting with Pi, trigger this skill naturally:

- *"Containerize this Go backend with a Distroless base image and audit image efficiency."*
- *"Author a hardened Kubernetes Deployment meeting the Pod Security Standard Restricted profile with an HPA v2 and default-deny NetworkPolicy."*
- *"Configure Terraform remote state on AWS S3 with KMS encryption and DynamoDB distributed locking."*
- *"Set up a GitHub Actions workflow with AWS OIDC authentication and Cosign keyless image signing."*
- *"Design an OpenTelemetry Collector configuration that exports traces to Tempo and metrics to Prometheus."*

### 2. Standalone CLI Usage

The bundled scripts and templates can be utilized directly in any CI/CD pipeline or local developer workstation:

#### Audit Container Image Efficiency

```bash
# Audit any local Docker image for efficiency and layer duplication
chmod +x scripts/audit-image.sh
./scripts/audit-image.sh my-app:latest 98
```

#### Scan Repository for Leaked Secrets

```bash
# Run Gitleaks across the git commit history
chmod +x scripts/scan-secrets.sh
./scripts/scan-secrets.sh
```

#### Validate Kubernetes Manifests

```bash
# Validate syntax and schema using client-side dry run
chmod +x scripts/k8s-dry-run-validate.sh
./scripts/k8s-dry-run-validate.sh templates/kubernetes/
```

---

## Key Design Principles

1. **Defense in Depth**: Security controls operate at every boundary: non-root container runtimes, read-only root filesystems, Linux capability drops, pod-level seccomp profiles, and namespace network isolation.
2. **Zero Static Credentials**: Never store AWS access keys, GCP service account JSON files, or database master passwords in CI/CD secrets. Use OpenID Connect (OIDC) federated identity tokens with temporary, scoped IAM roles.
3. **Receipt-Driven Engineering**: Every change must be verified with reproducible local evidence before delivery: image efficiency scores from `dive`, schema validation from `kubectl`, secret scanning reports from `gitleaks`, and static analysis from `trivy`.
4. **Observable by Default**: Every service must emit the 4 Golden Signals (Latency, Traffic, Errors, Saturation) and correlate application logs with distributed traces via W3C TraceContext standards (`traceparent` header).

---

## Documentation & References

Deep dive into specialized architectural guides:

- [Container Runtime Hardening](references/01-containers-runtime.md)
- [Kubernetes Cloud-Native Patterns](references/02-kubernetes-cloudnative.md)
- [Infrastructure as Code with OpenTofu & Terraform](references/03-iac-terraform-opentofu.md)
- [CI/CD Automation & GitOps Delivery](references/04-cicd-gitops.md)
- [OpenTelemetry & Site Reliability Engineering](references/05-observability-sre.md)
- [DevSecOps & Software Supply Chain Security](references/06-devsecops-supply-chain.md)
- [Open Source Governance & Engineering Standards](references/07-oss-governance-standards.md)

---

## Contributing & Security

We welcome community contributions! Please review our guidelines:

- [Contributing Guidelines](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy & Vulnerability Reporting](SECURITY.md)

---

## License

This project is licensed under the [Apache License, Version 2.0](LICENSE).
