# Feature: Comprehensive DevOps, DevSecOps & X-Ops Ecosystem

Expansion of `devops-skill` into an exhaustive, 360-degree Tier-1 enterprise standard covering all 32 specialized DevOps, DevSecOps, SRE, Platform Engineering, FinOps, and X-Ops domains.

## Specs

- S1: Phase 1 - Core Pipeline & Enterprise Delivery:
  - Add `references/08-scm-branching-cac.md` covering Trunk-Based Development vs GitFlow, Monorepo tooling, and CaC with Ansible/Packer.
  - Add `references/09-multici-progressive-releases.md` covering GitLab CI, Jenkins/Tekton, Argo Rollouts Canary/BlueGreen, Shadow deployments, and OpenFeature flags.
  - Add `references/10-dbdevops-zero-downtime.md` covering Atlas, Liquibase, Flyway, and expand/contract zero-downtime database migrations.
  - Add templates: `templates/cac/packer-golden-ami.pkr.hcl`, `templates/cac/ansible-baseline-hardening.yml`, `templates/scm/.pre-commit-config.yaml`, `templates/gitlab/.gitlab-ci-enterprise.yml`, `templates/jenkins/Jenkinsfile.declarative`, `templates/gitops/argo-rollouts-canary.yaml`, `templates/gitops/fluxcd-kustomization.yaml`, `templates/dbdevops/atlas-migration.hcl`, `templates/dbdevops/flyway-migration-job.yaml`.
- S2: Phase 2 - Advanced Cloud-Native, Service Mesh & Platform Engineering:
  - Add `references/11-servicemesh-keda-autoscaling.md` covering KEDA, VPA, Cilium eBPF, and Istio Ambient Mesh.
  - Add `references/12-platform-engineering-idp.md` covering Backstage, Port, and Crossplane XRDs/Compositions.
  - Add `references/13-artifact-management-harbor.md` covering Harbor HA, replication, and Cosign policy gating.
  - Add templates: `templates/kubernetes/keda-scaledobject-prometheus.yaml`, `templates/kubernetes/vpa-recommendation.yaml`, `templates/kubernetes/cilium-networkpolicy-l7.yaml`, `templates/kubernetes/istio-ambient-peerauthentication.yaml`, `templates/platform/crossplane-xrd-postgres.yaml`, `templates/platform/backstage-software-template.yaml`, `templates/artifacts/harbor-values-ha.yaml`.
- S3: Phase 3 - DevSecOps 360°, Zero Trust & Runtime Security:
  - Add `references/14-devsecops-advanced-testing.md` covering Threat Modeling, SAST with Semgrep, DAST with Nuclei/ZAP, and Fuzzing with AFL++/Jazzer.
  - Add `references/15-spec-driven-api-security.md` covering Spectral OpenAPI validation and BOLA prevention.
  - Add `references/16-pac-cwpp-cnapp-runtime.md` covering OPA Gatekeeper, Falco/Tetragon eBPF CWPP, Prowler CSPM, and SOAR containment.
  - Add `references/17-zero-trust-spiffe-vault.md` covering SPIFFE/SPIRE architecture and HashiCorp Vault HA.
  - Add templates: `templates/github-actions/semgrep-sast.yml`, `templates/github-actions/nuclei-dast-scan.yml`, `templates/security/spectral-openapi-ruleset.yaml`, `templates/security/opa-gatekeeper-constraint.yaml`, `templates/security/falco-rules-k8s.yaml`, `templates/github-actions/prowler-cspm-audit.yml`, `templates/security/vault-cluster-raft-values.yaml`, `templates/security/spire-agent-server-k8s.yaml`.
- S4: Phase 4 - SRE Avanzado, Resiliencia y FinOps en Runtime:
  - Add `references/18-sre-chaos-engineering.md` covering SLAs/SLOs/SLIs contracts, Toil reduction, Chaos Mesh, and LitmusChaos.
  - Add `references/19-finops-runtime-cost-optimization.md` covering OpenCost/Kubecost, right-sizing, and Karpenter Spot resilience.
  - Add templates: `templates/sre/chaos-mesh-network-delay.yaml`, `templates/sre/error-budget-policy.md`, `templates/finops/opencost-k8s-values.yaml`, `templates/finops/karpenter-spot-nodepool.yaml`.
- S5: Phase 5 - Especializaciones X-Ops:
  - Add `references/20-mlops-llmops-engineering.md` covering DVC, MLflow, GPU slicing, vLLM/KServe, and Guardrails.
  - Add `references/21-dataops-pipeline-engineering.md` covering dbt CI/CD, Great Expectations, and Airflow on K8s.
  - Add `references/22-netops-network-automation.md` covering NETCONF/RESTCONF, gNMI, and Containerlab CI emulation.
  - Add `references/23-noops-serverless-event-driven.md` covering AWS Lambda, Cloud Run, Knative Serving, and EventBridge.
  - Add templates: `templates/xops/mlops-vllm-deployment.yaml`, `templates/xops/dbt-ci-pipeline.yml`, `templates/xops/containerlab-topo.yaml`, `templates/xops/knative-service-scale-to-zero.yaml`.
- S6: Core Integration & Final Verification:
  - Update `SKILL.md` with new decision matrices (Release Strategy, Security Engines, X-Ops Routing), validation gates, and complete directory index.
  - Update `scripts/validate-all.sh` to validate all new templates (YAML, Markdown, Shell, Kubernetes, Helm, Terraform).
  - Ensure all 8 validation checks pass with 0 errors and 0 warnings.
  - Merge all phase PRs into `main`.

## Tasks

- T1 (linked S1): Implement Phase 1: Core Pipeline & Enterprise Delivery on branch `feat/phase1-core-pipeline-cac-dbdevops`.
- T2 (linked S2): Implement Phase 2: Advanced Cloud-Native, Service Mesh & Platform Engineering on branch `feat/phase2-cloudnative-mesh-platform`.
- T3 (linked S3): Implement Phase 3: DevSecOps 360°, Zero Trust & Runtime Security on branch `feat/phase3-devsecops-zerotrust-cwpp`.
- T4 (linked S4): Implement Phase 4: SRE Avanzado, Resiliencia y FinOps en Runtime on branch `feat/phase4-sre-chaos-finops`.
- T5 (linked S5): Implement Phase 5: Especializaciones X-Ops on branch `feat/phase5-xops-specializations`.
- T6 (linked S6): Update `SKILL.md`, scripts, run full validation suite, and finalize all PRs.

## Log

- L1: User requested full implementation across all 5 phases as structured PRs, continuing autonomously until all 5 phases are completed and robustly integrated.
