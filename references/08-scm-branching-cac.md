# SCM Branching Strategies, Monorepos & Configuration as Code (CaC)

## 1. Executive Overview

Source Code Management (SCM) and Configuration as Code (CaC) constitute the foundational layer of repeatable software delivery. Without deterministic branching semantics and immutable operating system baselines, downstream Continuous Integration and deployment automation inherit instability and operational friction.

This guide standardizes:

1. **Branching Workflows**: Moving from high-friction GitFlow to high-velocity Trunk-Based Development (TBD).
2. **Repository Topology**: Architectural trade-offs, governance, and build optimization between Monorepos and Polyrepos.
3. **Configuration as Code**: Building hardened, immutable Golden Images with HashiCorp Packer and Ansible before compute instances join production infrastructure.

---

## 2. Trunk-Based Development vs. GitFlow & GitHub Flow

### 2.1 Branching Matrix Comparison

| Dimension | GitFlow | GitHub Flow | Trunk-Based Development (TBD) |
| :--- | :--- | :--- | :--- |
| **Branch Lifespan** | Weeks to months (`develop`, `release/*`, `feature/*`) | Days (`feature/*`) | Hours to < 1 day (Short-lived topic branches) |
| **Integration Frequency** | Infrequent batch merges (High conflict surface) | On PR merge to `main` | Continuous (Multiple integrations daily to `main`) |
| **Release Mechanism** | Dedicated release branches and tags | Continuous deployment from `main` | Fast-forward release tags or short release branches from `main` |
| **Feature Isolation** | Long-running branches | Branch deployment / review apps | Feature Flags (In-code runtime toggles) |
| **Lead Time to Changes** | Days or weeks | Hours | Minutes |
| **Merge Overhead** | High ("Merge Hell", manual cherry-picking) | Low to Medium | Minimal (Rebase onto trunk continuously) |

### 2.2 Trunk-Based Development Engineering Rules

1. **Short-Lived Branches**: Topic branches MUST NOT survive more than 24 hours without merging into the trunk (`main`).
2. **Small Batches**: Pull requests MUST stay below 400 lines of authored diff to protect reviewer cognitive focus and lower blast radius.
3. **Feature Toggles**: Unfinished or risky business logic MUST be guarded behind runtime feature flags rather than deferred across stale branches.
4. **Fast Feedback**: CI test suites on PR branches MUST execute within 5–10 minutes via parallel test runners, test splitting, and aggressive layer caching.
5. **Linear History**: Repositories MUST enforce `Rebase and merge` or `Squash and merge` to prevent non-linear merge bubble pollution in the Git graph.

### 2.3 Merge Queue & Continuous Merge Patterns

When high-velocity teams integrate dozens of PRs per hour, semantic merge conflicts and broken `main` builds emerge even when individual PR CI passes against stale bases.

```text
PR #101 [Target: main@v1] ──┐
                            ├─► Merge Queue ─► Speculative Build (main@v1 + PR#101 + PR#102) ─► Merge to main
PR #102 [Target: main@v1] ──┘
```

- **Speculative Execution**: The merge queue system (GitHub Merge Queue, Bors-ng) combines pending PRs against the latest trunk tip in an isolated branch.
- **Batched Testing**: Multiple PRs are tested together. If the batch fails, bisection isolates the culprit PR without stalling the queue.
- **Zero Broken Trunks**: Commits only land on `main` when verified against the true integrated HEAD.

---

## 3. Monorepo vs. Polyrepo Architectural Governance

### 3.1 Repository Strategy Matrix

```text
       Monorepo Topology                      Polyrepo Topology
 ┌───────────────────────────┐         ┌──────────┐      ┌──────────┐
 │  /apps                    │         │ ServiceA │      │ ServiceB │
 │    ├── web-portal         │         │   Repo   │      │   Repo   │
 │    └── payment-api        │         └────┬─────┘      └─────┬────┘
 │  /packages                │              │                  │
 │    ├── auth-client        │              └────────┬─────────┘
 │    └── ui-tokens          │                       ▼
 └───────────────────────────┘             Separate CI/CD & Versioning
```

### 3.2 Decision Gates

- **Adopt Monorepo when**:
  - Multiple services share internal libraries, data schemas, or protocol buffers.
  - Atomic cross-boundary refactoring is required in a single commit.
  - Build tooling can compute Directed Acyclic Graphs (DAG) and artifact hashes (e.g., Turborepo, Nx, Bazel) to rebuild only affected packages.
  - Teams seek unified dependency management, standardized linting, and centralized security scanning.
- **Adopt Polyrepo when**:
  - Autonomous business units operate with completely disjoint lifecycles, permissions, and security boundaries.
  - Regulatory or compliance boundaries require strict source code air-gapping.
  - Teams lack dedicated platform engineering resources to manage monorepo build caching and distributed task execution.

### 3.3 Monorepo Tooling & DAG Change Detection

In enterprise monorepos, running full test and build suites on every pull request is cost-prohibitive. Build systems compute a dependency graph and hash source inputs:

- **Turborepo / Nx**: Fast JavaScript/TypeScript caching and change tracking.
- **Bazel**: Multi-language, hermetic, bit-for-bit reproducible builds with remote caching.
- **Git Change Detection**: In lightweight setups, Git tree diffs identify affected subdirectories:

```bash
#!/usr/bin/env bash
# Determine affected directories between origin/main and HEAD
AFFECTED_DIRS=$(git diff --name-only origin/main...HEAD | awk -F/* '{print $1"/"$2}' | sort -u)

for dir in ${AFFECTED_DIRS}; do
  if [[ -f "${dir}/package.json" ]] || [[ -f "${dir}/Makefile" ]]; then
    echo "Triggering scoped CI for: ${dir}"
  fi
done
```

### 3.4 SCM Branch Protection & Code Owners Governance

Enterprise repositories enforce strict branch protections on `main`:

1. **Required Status Checks**: Unit tests, linting, SAST (Semgrep), and container security scans (Trivy) must pass before merge.
2. **Signed Commits**: GPG or SSH commit signatures must be cryptographically verified (`git commit -S`).
3. **CODEOWNERS Enforcement**: Critical directories (infrastructure, security policies, core libraries) require sign-off from designated owners:

```text
# Infrastructure & Terraform
/terraform/          @org/cloud-infra-team
/.github/workflows/  @org/devops-security

# Security policies & IAM
/policies/           @org/appsec-team
/templates/cac/      @org/platform-security
```

---

## 4. Configuration as Code: Packer & Ansible Golden Images

### 4.1 Immutable Infrastructure Pattern

Mutating live virtual machines via ad-hoc SSH commands or unversioned shell scripts is an anti-pattern that leads to configuration drift and CVE vulnerability window expansion. Configuration as Code establishes that virtual machines (VMs) are stamped out from versioned Golden Images.

```text
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────────────┐
│ Packer Template  │ ───► │ Ansible Playbook │ ───► │ Hardened Golden Image    │
│ (HCL2 Blueprint) │      │ (CIS Hardening)  │      │ (AWS AMI / Azure / GCP)  │
└──────────────────┘      └──────────────────┘      └──────────────────────────┘
```

1. **Packer** provisions a clean base operating system (e.g., Amazon Linux 2023 or Debian 12) inside a temporary VPC/subnet.
2. **Ansible** runs locally (`connection: local`) inside the temporary build instance, applying CIS Benchmark Level 1/2 hardening:
   - Disabling unnecessary legacy kernel modules (`dccp`, `sctp`, `cramfs`).
   - Configuring strict SSH daemon parameters (`PermitRootLogin no`, `PasswordAuthentication no`, `ClientAliveInterval 300`).
   - Tuning `sysctl` network stack protections (SYN cookies, reverse path filtering, disabling ICMP redirects).
   - Configuring `auditd` logging rules for system call monitoring.
   - Creating dedicated non-root application users.
3. **Image Baking & Signing**: Packer shuts down the instance, registers the immutable Machine Image, and tags it with commit SHA and release metadata.

### 4.2 Automated Golden Image Baking Pipeline

Golden Images must be rebuilt on a scheduled cadence (e.g., weekly) and upon base OS patch notifications:

```text
Schedule/Patch Event ─► Packer Build ─► Ansible Hardening ─► Goss/InSpec Validation ─► AMI Tagged & Shared ─► Terraform / ASG Refresh
```

- **Image Testing**: Before publishing, test suites (using Goss, InSpec, or Testinfra) verify that ports, files, users, and sysctl settings conform to the compliance baseline.
- **Image Retirement**: Obsolete AMIs older than 60–90 days are automatically deregistered and underlying EBS snapshots deleted to prevent stale usage.
