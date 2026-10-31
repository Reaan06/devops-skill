# DevOps & DevSecOps Engineering Skill

[![Author: Reaan](https://img.shields.io/badge/Author-Reaan-blue.svg)](https://github.com/Reaan)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NPM Version](https://img.shields.io/npm/v/@reaan_dev/devops-skill.svg)](https://www.npmjs.com/package/@reaan_dev/devops-skill)
[![CI](https://github.com/Reaan06/devops-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/Reaan06/devops-skill/actions/workflows/ci.yml)
[![Security Scan](https://github.com/Reaan06/devops-skill/actions/workflows/security-scan.yml/badge.svg)](https://github.com/Reaan06/devops-skill/actions/workflows/security-scan.yml)
[![DevSecOps Trivy](https://img.shields.io/badge/Security-Trivy%20Gated-brightgreen.svg)](https://trivy.dev/)
[![Supply Chain SLSA 3](https://img.shields.io/badge/Supply%20Chain-SLSA%20L3%20Ready-blueviolet.svg)](https://slsa.dev/)
[![OpenTelemetry Ready](https://img.shields.io/badge/Observability-OpenTelemetry%20v1.30%2B-orange.svg)](https://opentelemetry.io/)

Production-grade 2025/2026 DevOps and DevSecOps engineering skill for cloud-native systems, authored by **Reaan**. Features universal multi-channel distribution across AI coding agents including Pi Coding Agent, Claude Code, Cursor, Windsurf, GitHub Copilot, and Open Standard agents. Covers container runtime hardening, production Kubernetes manifests with zero-trust network policies, immutable Infrastructure as Code with OpenTofu/Terraform, keyless OIDC CI/CD pipelines, GitOps reconciliation with ArgoCD, OpenTelemetry collector architectures, and end-to-end supply chain security.

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

## Universal Installation

`devops-skill` is distributed through three universal distribution channels to provide zero-friction installation across any AI agent environment, CLI, or CI/CD workflow:

### Canal 1: Pi Coding Agent

Pi Coding Agent features native package management and direct git/npm skill installation:

- **Install via NPM package registry**:

  ```bash
  pi install npm:@reaan_dev/devops-skill
  ```

- **Install directly via Git repository**:

  ```bash
  pi install git:github.com/Reaan06/devops-skill
  ```

- **Native Discovery**:
  Pi automatically detects and registers the skill when placed in any of the standard discovery paths:
  - Global agent skills standard: `~/.agents/skills/devops-skill`
  - Pi user skills directory: `~/.pi/agent/skills/devops-skill`
  - Project-local workspace: `.pi/skills/devops-skill`

---

### Canal 2: NPM / npx (Universal CLI)

The `@reaan_dev/devops-skill` package includes a cross-platform, zero-dependency CLI installer that configures all detected or targeted agents:

- **Zero-Install Execution (`npx`)**:
  Run directly without global installation. It automatically scans your environment, detects installed agents, and provisions skill assets:

  ```bash
  npx @reaan_dev/devops-skill install
  ```

- **Global CLI Installation**:
  Install globally for ongoing maintenance and batch operations:

  ```bash
  npm install -g @reaan_dev/devops-skill
  devops-skill install --all
  ```

- **Target Specific Agents**:
  Selectively install to individual agent harnesses:

  ```bash
  devops-skill install --pi          # Pi Coding Agent
  devops-skill install --claude      # Claude Code
  devops-skill install --cursor      # Cursor IDE (.cursor/rules/)
  devops-skill install --windsurf    # Windsurf IDE (.windsurf/rules/)
  devops-skill install --copilot     # GitHub Copilot (.github/)
  devops-skill install --agents      # Agent Skills open standard (~/.agents/skills/)
  devops-skill install --all         # Provision all detected & supported agents
  devops-skill install --target=pi,claude,cursor  # Comma-separated target list
  ```

- **Scope: Global vs Project Workspace**:
  - `--global` (default): Deploys into user home directories (`~/.pi/agent/skills/`, `~/.claude/skills/`, `~/.agents/skills/`).
  - `--project` / `-p`: Deploys rules and skills into the current project workspace (`.pi/skills/`, `.cursor/rules/`, `.windsurf/rules/`, `.github/`).

  ```bash
  # Deploy project-level Cursor rules and Copilot instructions
  devops-skill install --cursor --copilot --project

  # Deploy globally for Pi and Claude Code
  devops-skill install --pi --claude --global
  ```

- **Local Development Symlink Mode (`--symlink` / `-l`)**:
  When developing the skill locally from source, use symlink mode so modifications take effect immediately without re-copying:

  ```bash
  devops-skill install --all --symlink
  ```

- **Management Commands**:

  ```bash
  devops-skill install      # Install skill files to agents (default)
  devops-skill uninstall    # Cleanly remove skill files and rules from agents
  devops-skill list         # Show detected agent environments and installation status
  devops-skill doctor       # Validate package integrity, templates, and reference guides
  ```

---

### Canal 3: Curl Pipe (Zero-dependency POSIX)

For minimal environments, containers, CI/CD runners, or developer machines without Node.js, the standalone POSIX `install.sh` script provides single-command installation:

- **Interactive Auto-Detection**:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash
  ```

- **Install to All Agents Non-Interactively**:
  Pass options directly via bash arguments (`bash -s -- <flags>`):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash -s -- --all
  ```

- **Target Specific Agents via Flag or List**:

  ```bash
  # Target comma-separated agents
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash -s -- --target=pi,claude

  # Target individual agents with discrete flags and scope
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash -s -- --pi --cursor --project
  ```

---

## Agent Compatibility Matrix

`devops-skill` adapts to the native file format, rule protocol, and directory layout of each AI agent:

| Agent / Harness | Global Target Path | Project Target Path | Format & Artifact Type | Activation & Discovery |
| --- | --- | --- | --- | --- |
| **Pi Coding Agent** | `~/.pi/agent/skills/devops-skill/` | `.pi/skills/devops-skill/` | Full skill tree (`SKILL.md`, `references/`, `templates/`, `scripts/`) | Native package manager (`pi install`), CLI, or prompt trigger |
| **Claude Code** | `~/.claude/skills/devops-skill/` | `.claude/skills/devops-skill/` | Full skill tree with YAML metadata frontmatter | Native skill registration and contextual prompt triggers |
| **Agent Skills Standard** | `~/.agents/skills/devops-skill/` | `.agents/skills/devops-skill/` | Open standard skill directory | Auto-indexed by standard-compliant harnesses |
| **Cursor IDE** | *N/A (Workspace rule)* | `.cursor/rules/devops-skill.mdc` | MDC Rule with metadata frontmatter & file globs | Auto-applied on `Dockerfile*`, `*.tf`, `*.tofu`, `k8s/**/*.yaml` |
| **Windsurf IDE** | *N/A (Workspace rule)* | `.windsurf/rules/devops-skill.md` | Cascade Rule markdown document | Auto-loaded in Windsurf Cascade workspace context |
| **GitHub Copilot** | *N/A (Workspace rule)* | `.github/copilot-instructions.md` | Repository-wide custom instructions markdown | Loaded on all Copilot Chat and code completion interactions |
| **OpenCode / Roo Code / Cline** | `~/.agents/skills/devops-skill/` or `~/.claude/skills/devops-skill/` | `.agents/skills/devops-skill/` | Open standard skill tree or system prompt reference | Indexed via standard agent path or prompt rule reference |

---

## Directory Structure

```text
devops-skill/
├── Makefile                          # Unified orchestration targets (lint, validate, scan, fmt)
├── SKILL.md                          # Main skill specification & agent execution contract
├── README.md                         # Project documentation and onboarding
├── LICENSE                           # MIT open-source license
├── SECURITY.md                       # Vulnerability disclosure and security policy
├── CONTRIBUTING.md                   # Engineering standards, linting, and PR workflow
├── CODE_OF_CONDUCT.md                # Community covenant code of conduct
├── package.json                      # NPM package manifest & Pi package integration
├── install.sh                        # Zero-dependency POSIX curl installer
├── bin/
│   └── cli.js                        # Cross-platform CLI installer (npx @reaan_dev/devops-skill)
├── references/                       # In-depth architectural references & deep dives
│   ├── 01-containers-runtime.md      # Container hardening, distroless, dive efficiency
│   ├── 02-kubernetes-cloudnative.md  # K8s PSS Restricted, NetworkPolicies, QoS, HPA, PDB
│   ├── 03-iac-terraform-opentofu.md  # Clean IaC architecture, remote state locking, KMS
│   ├── 04-cicd-gitops.md             # Keyless OIDC, Cosign signing, SLSA, ArgoCD GitOps
│   ├── 05-observability-sre.md       # OpenTelemetry collector, 4 golden signals, JSON logs
│   ├── 06-devsecops-supply-chain.md  # Syft SBOMs, Trivy CVE gating, Gitleaks, SLSA L3
│   └── 07-oss-governance-standards.md# Diátaxis docs, PR etiquette, quality gates
├── templates/                        # Battle-tested production templates
│   ├── containers/                   # Hardened multi-stage Dockerfiles & compose
│   │   ├── Dockerfile.distroless.go  # Go 1.23 CGO-free static binary on gcr.io/distroless/static:nonroot
│   │   ├── Dockerfile.distroless.rust# Rust cargo-chef musl static binary on distroless/static:nonroot
│   │   ├── Dockerfile.slim.node      # Node.js 22 LTS Debian Bookworm-slim with pnpm and dumb-init
│   │   ├── Dockerfile.standalone.nextjs # Next.js 15 standalone output with non-root nextjs:nodejs
│   │   ├── Dockerfile.slim.python    # Python 3.12 slim with virtualenv isolation and wheel builder
│   │   ├── Dockerfile.temurin21.java # Java 21 Eclipse Temurin with layered JAR extraction and cgroups v2
│   │   ├── compose.hardened.yaml     # Hardened Docker Compose specification (read-only rootfs, cap drops)
│   │   └── .dockerignore             # Enterprise zero-leak build context exclusions
│   ├── kubernetes/                   # Core production manifests & Day-2 operations
│   │   ├── deployment-hardened.yaml  # PSS Restricted Deployment with non-root user and read-only rootfs
│   │   ├── service-ingress.yaml      # ClusterIP Service and TLS Ingress with security annotations
│   │   ├── network-policy-default-deny.yaml # Default-deny ingress/egress network isolation
│   │   ├── hpa-v2.yaml               # HorizontalPodAutoscaler v2 with CPU/Memory/Prometheus metrics
│   │   ├── pdb.yaml                  # PodDisruptionBudget with minAvailable protection
│   │   ├── cert-manager-cluster-issuer.yaml # ACME Let's Encrypt HTTP-01 and Route53 DNS-01 ClusterIssuers
│   │   ├── external-secrets-operator.yaml # AWS Secrets Manager & HashiCorp Vault ClusterSecretStore
│   │   ├── gateway-api-httproute.yaml# Gateway API Gateway and HTTPRoute traffic routing definitions
│   │   └── prometheus-rule-slo-alerts.yaml # Multi-window multi-burn-rate SLO alerting rules
│   ├── helm/                         # Enterprise Helm Chart packaging
│   │   └── app-chart/                # Production chart with values.schema.json, PSS templates, and helpers
│   ├── kustomize/                    # GitOps environment overlay architecture
│   │   ├── base/                     # Reusable foundational manifests (Deployment, Service, kustomization)
│   │   └── overlays/                 # Environment-specific patches
│   │       ├── staging/              # Staging overlay (replicas, ingress hosts, config maps)
│   │       └── production/           # Production overlay (HA replicas, strict resources, PDB)
│   ├── terraform/                    # Multi-cloud remote state & root baseline modules
│   │   ├── backend-s3-dynamodb.tf    # AWS S3 KMS-encrypted state bucket with DynamoDB LockID table
│   │   ├── backend-gcs.tf            # GCP GCS CMEK-encrypted state bucket with precondition locking
│   │   ├── backend-azurerm.tf        # Azure Storage CMK with Key Vault and native Blob lease locking
│   │   ├── opentofu-state-encryption.tf # OpenTofu 1.8+ native client-side PBKDF2/KMS state & plan encryption
│   │   ├── main.tf                   # Multi-AZ VPC network baseline with private/public subnets
│   │   ├── variables.tf              # Strongly-typed input variables with validation rules
│   │   ├── outputs.tf                # Secure output contracts
│   │   └── versions.tf               # Version and provider constraint declarations
│   ├── github-actions/               # Enterprise CI/CD workflow blueprints
│   │   ├── oidc-aws-auth.yml         # Keyless AWS authentication via GitHub Actions OIDC token
│   │   ├── ci-docker-build-push.yml  # Multi-arch BuildKit compilation, Cosign signing, and SLSA provenance
│   │   ├── gitleaks-trivy-scan.yml   # Shift-left secret detection and container vulnerability scanner
│   │   ├── checkov-iac-scan.yml      # Static IaC policy and compliance scanner with SARIF export
│   │   └── infracost-finops.yml      # Automated pull request cloud infrastructure cost assessment
│   ├── gitops/                       # Declarative ArgoCD GitOps application manifests
│   └── observability/                # OpenTelemetry collector configuration and JSON log spec
└── scripts/                          # Reusable verification and auditing scripts
    ├── validate-all.sh               # Unified cascading validation suite with Docker fallbacks
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

This project is licensed under the [MIT License](LICENSE).
