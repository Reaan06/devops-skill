# Feature: Robust DevOps Skill (Tier-1 Enterprise Cloud-Native)

Tracking specification document for upgrading `devops-skill` into a Tier-1 Enterprise DevOps & DevSecOps standard repository.

## Specs

- S1: Container Runtimes: Add production Dockerfiles for Rust (`cargo-chef` + musl static + distroless nonroot), Java 21 (Eclipse Temurin, layered JAR extraction, cgroups v2 memory limits), and Next.js (standalone output, non-root `nextjs:nodejs`, BuildKit cache mounts).
- S2: Kubernetes Packaging & GitOps: Implement production Helm Chart (`templates/helm/app-chart/`) with `Chart.yaml`, `values.yaml`, `values.schema.json`, templates for Deployment (PSS Restricted), Service, Ingress, HPA, PDB, NetworkPolicy, ServiceAccount, and `_helpers.tpl`. Implement Kustomize structure (`templates/kustomize/base/` and `templates/kustomize/overlays/{staging,production}/`).
- S3: Kubernetes Day-2 Ops & Security: Provide `ClusterIssuer` (cert-manager ACME HTTP-01/DNS-01), `PrometheusRule` (multi-window multi-burn-rate SLOs + golden signals), Gateway API manifests (`Gateway` + `HTTPRoute`), and External Secrets Operator (`ExternalSecret` + `ClusterSecretStore`).
- S4: Multi-Cloud IaC: Provide Terraform/OpenTofu backend templates for GCP (`backend-gcs.tf` with CMEK) and Azure (`backend-azurerm.tf` with Blob lease and CMK), plus native OpenTofu 1.8+ state encryption block (`versions.tf` / `backend-encryption.tf`). Add Infracost & Checkov CI workflow template.
- S5: Unified Tooling: Root `Makefile` with targets (`all`, `fmt`, `lint`, `validate`, `scan`, `test`) and `scripts/validate-all.sh` CLI wrapper with colored output and strict exit codes.
- S6: Internal CI Hardening: `.github/workflows/ci.yml` must execute `terraform fmt -check` & `terraform validate`, `kubeconform` (against K8s 1.31 schemas), `hadolint`, `shellcheck`, `actionlint`, `yamllint`, and `markdownlint`.
- S7: Security & Verification: Ensure 0 gitleaks findings, 0 PSS violations, 0 insecure supply-chain dependencies, and full test suite execution via subagents.

## Tasks

- T1 (linked S1): Implement Rust, Java 21, and Next.js Dockerfiles in `templates/containers/`.
- T2 (linked S2, S3): Implement Helm Chart, Kustomize overlays, PrometheusRule, ClusterIssuer, Gateway API, and ESO templates.
- T3 (linked S4): Implement GCP & Azure IaC backends, OpenTofu native encryption, and Infracost/Checkov workflow.
- T4 (linked S5): Implement root `Makefile` and `scripts/validate-all.sh`.
- T5 (linked S6): Update `.github/workflows/ci.yml` and references/documentation.
- T6 (linked S7): Verification and security audit via subagents.
- T7: Commit, push to GitHub `main`, and register in persistent memory.

## Log

- L1: User requested a plan to implement all phases and integrate the complete package to make `devops-skill` as robust as possible.
