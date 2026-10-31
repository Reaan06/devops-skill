# Enterprise Multi-CI Architectures, Progressive Delivery & GitOps with FluxCD

## 1. Executive Overview

Modern delivery engineering decouples software installation (deployment) from traffic activation (release). Traditional all-at-once or crude rolling deployments expose production users to unvalidated faults, untested database interactions, and latent regressions.

This reference standardizes:

1. **Enterprise Multi-CI Architectures**: Comparing GitLab CI, Jenkins on Kubernetes, Tekton Pipelines, and GitHub Actions across execution models, runner scaling, and OIDC security.
2. **Progressive Delivery Paradigms**: Blue/Green, Canary, Rolling, and Shadow/Mirroring deployments.
3. **Automated Canary Analysis with Argo Rollouts**: Declarative Rollout CRDs, AnalysisTemplates, Prometheus PromQL health checks, and automated instant rollbacks.
4. **Feature Flagging with OpenFeature**: Decoupling code deployment from business release with vendor-neutral runtime evaluation.
5. **GitOps Engine: FluxCD v2**: Declarative state management, Source-Kustomize-Helm reconciliation loops, and drift detection.

---

## 2. Multi-CI Engine Comparison: GitLab CI, Jenkins & Tekton

### 2.1 Engine Architectural Matrix

| Dimension | GitLab CI | Jenkins (K8s Native) | Tekton Pipelines | GitHub Actions |
| :--- | :--- | :--- | :--- | :--- |
| **Pipeline Definition** | `.gitlab-ci.yml` (YAML) | `Jenkinsfile` (Declarative Groovy) | Kubernetes CRDs (`Pipeline`, `Task`) | `.github/workflows/*.yml` (YAML) |
| **Execution Model** | GitLab Runner (Docker/K8s executor) | Dynamic K8s Pod Agents via JNLP | In-cluster TaskRun Pods (Step containers) | GitHub-hosted or self-hosted runners |
| **Dependency Graph** | Directed Acyclic Graph (`needs:`) | Stage-based / Scripted parallel stages | Explicit DAG via `runAfter` / CRD params | Stage / Job `needs:` DAG |
| **Cloud Authentication** | OIDC JWT (`CI_JOB_JWT_V2` / `id_tokens`) | Vault plugin / OIDC or Workload ID | Workload Identity / Kubernetes SA | OIDC JWT (`id-token: write`) |
| **State Storage** | Postgres + Object Storage | Jenkins Home / Persistent Volume | Etcd (CRD State) + Workspace PVCs | Managed SaaS / S3 cache |

### 2.2 GitLab CI Architecture & Enterprise Patterns

GitLab CI leverages an autoscaling runner model that executes jobs inside isolated Docker containers or ephemeral Kubernetes pods.

```text
GitLab Server (Co-ordinator)
          │
          ├─► GitLab Runner Manager (K8s / EC2 Autoscaler)
          │         │
          │         ├─► Ephemeral Pod: Lint & SAST
          │         ├─► Ephemeral Pod: Kaniko Container Build
          │         └─► Ephemeral Pod: OIDC Keyless Cloud Deploy
```

- **DAG Pipeline Execution (`needs:`)**: By default, GitLab CI stages execute linearly. Using the `needs:` keyword converts jobs into a Directed Acyclic Graph, allowing fast jobs (e.g. security scans) to run concurrently without waiting for slow unrelated tests in prior stages.
- **Parent-Child & Multi-Project Pipelines**: Monorepos split complex pipelines into downstream child configurations (`trigger: include: artifact.yml`) to isolate failure domains.
- **Keyless Authentication (OIDC)**: GitLab CI issues cryptographically verifiable JSON Web Tokens configured via `id_tokens`:

```yaml
deploy_prod:
  stage: deploy
  id_tokens:
    AWS_JWT_TOKEN:
      aud: https://aws.amazon.com
  script:
    - >
      AWS_CREDENTIALS=$(aws sts assume-role-with-web-identity
      --role-arn arn:aws:iam::123456789012:role/gitlab-prod-role
      --role-session-name "gitlab-ci-${CI_JOB_ID}"
      --web-identity-token "${AWS_JWT_TOKEN}"
      --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]"
      --output text)
```

### 2.3 Jenkins on Kubernetes (Declarative Pod Agents)

Traditional static Jenkins VMs suffer from configuration drift and resource idling. Cloud-native Jenkins runs inside Kubernetes, spawning ephemeral Pod agents on demand:

- **JNLP Inbound Agent**: Connects to the Jenkins controller via secure TLS remoting.
- **Multi-Container Pods**: Individual steps run in specialized, purpose-built containers (e.g., Maven, Node.js, Kaniko, Helm) sharing a common `/home/jenkins/agent` workspace mount.
- **Zero Drift**: When the build terminates, Kubernetes garbage-collects the entire agent pod.

### 2.4 Cloud-Native Tekton Pipelines

Tekton represents Kubernetes-native CI/CD where every pipeline step is a first-class Kubernetes resource:

- **`Step`**: A container running a specific command within a Kubernetes Pod.
- **`Task`**: A sequential list of steps executing on the same Kubernetes node sharing an emptyDir or PVC volume.
- **`Pipeline`**: A DAG connecting multiple Tasks, defining data passing via `workspaces` and `results`.
- **`PipelineRun`**: An execution instance created manually or triggered via Tekton Triggers (EventListeners).

---

## 3. Progressive Delivery Deep Dive

Progressive delivery balances feature release velocity with blast radius reduction by exposing changes to an incrementally increasing percentage of real user traffic while continuously monitoring automated health metrics.

### 3.1 Strategy Comparison Matrix

| Strategy | Traffic Shifting | Rollback Speed | Compute Cost | Database Compatibility |
| :--- | :--- | :--- | :--- | :--- |
| **Recreate** | 0% or 100% (Instant downtime) | Slow (Re-deploy old version) | 1x (Baseline) | Breaking changes allowed |
| **Rolling Update** | Pod-by-pod replacement (e.g., maxSurge 25%) | Medium (Reverse rolling update) | 1x - 1.25x | Schema must be backwards-compatible |
| **Blue/Green** | 0% to 100% instantaneous router cutover | Instant (< 1s switch router back) | 2x (Full duplicate environment) | Schema must support both versions simultaneously |
| **Canary** | Incremental (e.g., 5% ➔ 20% ➔ 50% ➔ 100%) | Fast (Route traffic back to stable) | 1.1x - 1.5x | Schema must support both versions simultaneously |
| **Shadow / Mirror** | 100% live traffic cloned asynchronously | Zero user impact (Shadow only) | 2x (Duplicate shadow compute) | Shadow mutations must NOT write to real database |

### 3.2 Traffic Routing Mechanics

Canary and Blue/Green routing rely on Layer 7 ingress or service mesh proxies:

- **Service Mesh (Istio / Envoy)**: Splits traffic via `VirtualService` weight percentages or HTTP headers (`X-Canary: true`).
- **Ingress Controller (NGINX / Traefik)**: NGINX Ingress annotations (`nginx.ingress.kubernetes.io/canary: "true"`, `canary-weight: "10"`) split incoming HTTP requests at the ingress gateway.
- **Cloud Load Balancer (AWS ALB / GCP HTTPS LB)**: Weighted target groups forward designated proportions of client connections.

---

## 4. Argo Rollouts Mechanics & Automated Canary Analysis

Argo Rollouts replaces the standard Kubernetes `Deployment` object with a custom `Rollout` controller supporting advanced progressive delivery, traffic routing integration, and automated metric analysis.

```text
Client Traffic
      │
      ▼
Ingress / Service Router
  ├── 90% ──► Stable ReplicaSet (v1.0.0) ──► Pods (Healthy)
  └── 10% ──► Canary ReplicaSet (v1.1.0) ──► Pods
                   │
                   ▼
       AnalysisTemplate (Prometheus)
       [Checks: 99% HTTP 2xx + p95 < 300ms]
         ├── PASS ──► Step up to 20%
         └── FAIL ──► Instant Abort & Scale Canary to 0
```

### 4.1 Rollout CRD Anatomy

A `Rollout` spec mirrors a Kubernetes `Deployment` with a specialized `strategy` block:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payment-api
  namespace: production
spec:
  replicas: 10
  strategy:
    canary:
      canaryService: payment-api-canary
      stableService: payment-api-stable
      trafficRouting:
        nginx:
          stableIngress: payment-api-ingress
      steps:
        - setWeight: 10
        - pause: {duration: 5m}
        - analysis:
            templates:
              - templateName: success-rate-and-latency
        - setWeight: 30
        - pause: {duration: 10m}
        - setWeight: 60
        - pause: {duration: 15m}
```

### 4.2 Automated Analysis with AnalysisTemplate

The `AnalysisTemplate` queries external telemetry providers (Prometheus, Datadog, CloudWatch, New Relic) at configured intervals during each pause step:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-and-latency
  namespace: production
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result[0] >= 0.99
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus-k8s.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{service="payment-api-canary",status!~"5.*"}[2m]))
            /
            sum(rate(http_requests_total{service="payment-api-canary"}[2m]))

    - name: latency-p95
      interval: 1m
      successCondition: result[0] <= 0.350
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus-k8s.monitoring.svc.cluster.local:9090
          query: |
            histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="payment-api-canary"}[2m])) by (le))
```

### 4.3 Automated Rollback Thresholds & Abort Behavior

When an analysis metric violates its `successCondition` for more consecutive evaluations than `failureLimit`:

1. **State Transition**: The Rollout enters `Degraded` and triggers an immediate `Abort`.
2. **Traffic Drain**: The ingress controller immediately resets canary traffic weight to 0%. All active sessions route to the stable ReplicaSet.
3. **Canary Teardown**: The canary ReplicaSet scales down to zero pods.
4. **Notification**: Argo Rollouts sends Webhook, Slack, or PagerDuty alerts with the exact failing PromQL query and observed values.

---

## 5. Feature Flags & Decoupled Delivery with OpenFeature

Feature flagging decouples the physical deployment of binaries from the logical release of customer-facing capabilities.

```text
┌─────────────────┐      ┌─────────────────────────┐      ┌───────────────────────┐
│ Code Deployed   │ ───► │ Feature Flag Evaluator  │ ───► │ Customer Activation   │
│ to Production   │      │ (In-Memory OpenFeature) │      │ (Targeted Segments)   │
└─────────────────┘      └─────────────────────────┘      └───────────────────────┘
```

### 5.1 The OpenFeature Standard

OpenFeature is a CNCF incubating specification establishing vendor-agnostic APIs and SDKs for feature flag evaluation. Instead of hardcoding proprietary vendor SDKs (LaunchDarkly, Unleash, Flagsmith, Flipt), applications program against OpenFeature:

```typescript
import { OpenFeature } from '@openfeature/server-sdk';
import { FliptProvider } from '@openfeature/flipt-provider';

// Configure vendor provider at startup
await OpenFeature.setProviderAndWait(new FliptProvider('http://flipt:8080'));

const client = OpenFeature.getClient('billing-service');

// Evaluate flag in-memory (< 1ms latency)
const isDynamicPricingEnabled = await client.getBooleanValue(
  'dynamic-pricing-v2',
  false,
  {
    targetingKey: user.id,
    tenantTier: user.tier,
    country: user.country,
  }
);

if (isDynamicPricingEnabled) {
  return executeDynamicPricingV2(order);
}
return executeLegacyPricing(order);
```

### 5.2 Server-Side Evaluation vs. Client-Side Evaluation

- **Server-Side Evaluation**: Flag rules and targeting conditions are evaluated inside the backend microservice process using synchronized in-memory rule sets. PII is never transmitted to third-party flag providers.
- **Client-Side Evaluation**: Mobile or SPA clients fetch evaluated booleans tailored to their user context. Sensitive targeting rules remain protected on the backend.

### 5.3 Feature Flag Lifecycle & Technical Debt Control

Feature flags must follow a strict lifecycle to prevent code rot and combinatorial explosion of state branches:

1. **Temporary Release Flags**: Maximum lifespan of 30 days. Once a feature reaches 100% rollout, an automated issue is created to remove the flag check and prune dead code paths.
2. **Circuit Breaker / Kill Switches**: Permanent flags guarding external integrations or high-load endpoints, configured with default-safe fallbacks.

---

## 6. GitOps with FluxCD v2

FluxCD v2 is an event-driven, CNCF graduated GitOps engine composed of modular Kubernetes controllers.

```text
Git Repository (main)
        │
        ▼ (poll interval: 1m)
Source Controller (source.toolkit.fluxcd.io)
        │
        ▼ (emits Tarball artifact)
Kustomize Controller (kustomize.toolkit.fluxcd.io)
        │
        ├──► Validates Dry-Run against API Server
        ├──► Applies Kustomize Overlays (Prunes removed resources)
        └──► Reconciles Drift continuously (Self-Healing)
```

### 6.1 Core Controller Architecture

- **`source-controller`**: Periodically pulls from Git repositories, OCI registries, or S3-compatible buckets, generating immutable cryptographic tarball artifacts.
- **`kustomize-controller`**: Consumes artifacts from `source-controller`, runs Kustomize builds with variable substitutions and decryption (SOPS / Age), and applies resources to the cluster.
- **`helm-controller`**: Manages the lifecycle of Helm chart releases, executing declarative upgrades, rollbacks, and values overrides.
- **`notification-controller`**: Handles inbound webhooks (triggering instant reconciliation on Git push) and dispatches outbound alerts (Slack, Teams, PagerDuty).

### 6.2 Declarative Flux Custom Resources

#### GitRepository Specification

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: fleet-infra
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/enterprise-org/fleet-infra.git
  ref:
    branch: main
  secretRef:
    name: github-deploy-token
  timeout: 60s
```

#### Kustomization Specification

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: prod-workloads
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: fleet-infra
  path: ./clusters/production/workloads
  prune: true
  wait: true
  timeout: 3m
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: payment-api
      namespace: production
```

### 6.3 Drift Reconciliation & Self-Healing

The Kustomize and Helm controllers enforce absolute fidelity to the declarative Git state:

- **Periodic Polling**: Every `interval` (e.g., 5m), Flux computes a dry-run diff against live etcd state.
- **Drift Correction**: If an operator manually modifies or deletes a workload using `kubectl`, Flux detects the delta and reapplies the version-controlled Git manifest within seconds.
- **Resource Pruning**: When a manifest is deleted from Git, `prune: true` instructs Flux to safely delete the corresponding Kubernetes object, preventing orphaned resources.
