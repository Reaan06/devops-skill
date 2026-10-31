# CI/CD, GitOps & Progressive Delivery Architecture

## 1. Explanation: Concepts and Architecture

Continuous Integration (CI), Continuous Delivery (CD), and GitOps bridge software development and production execution. Modern delivery platforms replace brittle push-based deployments with **keyless identity federation**, **declarative GitOps reconciliation**, **progressive traffic shaping**, and **self-service platform engineering**.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Developer Git Push (Trunk)                        │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Continuous Integration (GitHub Actions / GitLab CI / Jenkins K8s)      │
 │  • Short-lived OIDC Token exchange with Cloud STS (Zero Secrets)       │
 │  • Ephemeral Container Build with Kaniko / BuildKit                    │
 │  • SBOM generation (Syft) & Keyless Signing (Cosign / Fulcio / Rekor)   │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ OCI Push
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Enterprise Harbor HA Registry                                          │
 │  • Automated Trivy vulnerability gate (Block CVSS >= 7.0)              │
 │  • Immutable tag enforcement & Cosign signature validation             │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Git Tag / Commit to Config Repo
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ GitOps In-Cluster Controllers (ArgoCD / FluxCD v2)                     │
 │  • Continuous pull reconciliation & automatic drift remediation        │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Progressive Canary Delivery (Argo Rollouts)                            │
 │  • Step 1: 10% Canary traffic                                          │
 │  • Step 2: Prometheus Analysis (P99 Latency & Error Budget burn rate)  │
 │  • Step 3: Automated promotion to 100% or instant rollback             │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Zero-Static Credentials via OpenID Connect (OIDC)

Traditional CI/CD pipelines stored long-lived static cloud credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, service account JSON keys) within repository secrets. This pattern presents significant security vulnerabilities:
- Secrets are vulnerable to accidental exfiltration via misconfigured build scripts.
- Keys frequently lack rotation policies, persisting for months or years.
- Stolen static credentials grant unrestricted cloud API access outside of CI execution hours.

#### The OIDC Identity Federation Flow

1. **Workflow Trigger**: The CI runner requests an ephemeral JSON Web Token (JWT) from its native OIDC provider (e.g., `token.actions.githubusercontent.com`).
2. **Token Presentation**: The runner presents the signed JWT to the cloud provider's Security Token Service (AWS STS, GCP STS, Azure AD).
3. **Cryptographic Validation**: The cloud provider validates the signature against the CI platform's public OIDC keys (`/.well-known/openid-configuration`).
4. **Claim Evaluation**: The cloud provider verifies token claims, ensuring the `sub` (subject) matches the exact organization, repository, and branch.
5. **Short-Lived Credential Issuance**: The cloud provider issues temporary credentials valid for a bounded window (15–60 minutes), strictly scoped to the assumed IAM role.

### 1.2 Push CI vs. Pull GitOps Architecture

| Dimension | Push CI/CD (Direct Deployments) | Pull GitOps (ArgoCD / FluxCD) |
| :--- | :--- | :--- |
| **Execution Vector** | External CI runner executes `kubectl apply` or `helm upgrade`. | In-cluster controller continuously pulls desired state from Git. |
| **Cluster Access Privileges** | Cluster API credentials (`kubeconfig`) must be exposed to external CI runners. | Zero cluster credentials leave the cluster firewall. Controller runs locally inside the cluster. |
| **Configuration Drift** | Manual interventions or emergency hotfixes in the cluster remain undetected until overwritten. | Controller detects manual changes within seconds and automatically remediates live state back to declared Git state. |
| **Auditability & Rollback** | Deployment history scattered across disparate CI pipeline logs. | Git commit log serves as the single immutable audit log. Rollbacks require a simple `git revert`. |

### 1.3 Progressive Delivery Strategies

Progressive delivery decouples the technical deployment of code from its operational release to end users:

- **Rolling Update**: Sequentially replaces pods one-by-one. Inadequate for breaking changes because old and new versions run concurrently against unversioned backends without traffic segmentation.
- **Blue/Green**: Provisions a complete duplicate environment (Green) alongside live production (Blue). Shifts 100% of traffic instantly via load balancer or service selector switch once smoke tests pass.
- **Canary (Argo Rollouts)**: Directs a small fraction of real production traffic (e.g., 5% -> 20% -> 50% -> 100%) to the new release while monitoring real-time metrics (error rate, P99 latency) via automated PromQL analysis templates.
- **Shadow / Dark Launch (Traffic Mirroring)**: Clones real inbound production HTTP requests and forwards them asynchronously to the candidate release without returning candidate responses to clients. Verifies stability, database query performance, and memory consumption under full production load with zero user blast radius.

### 1.4 Platform Engineering & Internal Developer Platforms (IDP)

Modern platform teams combat developer cognitive overload by establishing **Golden Paths (Paved Roads)**:
- **Developer Portals (Backstage / Port)**: Provide a centralized software catalog, documentation-as-code (TechDocs), and one-click scaffolding templates that generate compliant code repositories with pre-configured CI/CD, security scanners, and GitOps integration.
- **Declarative Infrastructure with Crossplane**: Extends Kubernetes into a universal cloud control plane. Developers consume self-service infrastructure through Kubernetes custom resources (`PostgreSQLInstance`), while platform engineers define Composite Resource Definitions (XRDs) that compose underlying cloud provider resources (AWS RDS, VPC security groups, subnet groups) according to organizational security baselines.

### 1.5 Enterprise Artifact Management with Harbor HA

Container registries serve as the nexus between build automation and cluster execution. Enterprise requirements demand more than simple storage:
- **High-Availability Architecture**: Decouples stateless API/Registry controllers from persistent storage (AWS S3, managed PostgreSQL, Redis Sentinel).
- **Vulnerability Gating**: Automatically scans container filesystems with Trivy upon push. Images with unresolved CVEs exceeding the organizational policy threshold (`CRITICAL` or CVSS $\ge 7.0$) are prevented from being pulled by cluster nodes.
- **Tag Immutability & Cosign Attestation**: Prohibits overwriting existing image tags (`v1.2.0`) and requires Sigstore Cosign cryptographic signatures before admission into production namespaces.

---

## 2. Practical Guides: Production Blueprints and Manifests

### 2.1 GitHub Actions Workflow with OIDC Authentication & Security Gates

```yaml
name: Continuous Integration & Container Release

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

permissions:
  id-token: write # Required for OIDC JWT token generation
  contents: read
  security-events: write

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Authenticate to AWS via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111122223333:role/github-actions-production-deployer
          aws-region: us-east-1
          audience: sts.amazonaws.com

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Enterprise Harbor Registry
        uses: docker/login-action@v3
        with:
          registry: harbor.corp.internal
          username: ${{ secrets.HARBOR_ROBOT_USER }}
          password: ${{ secrets.HARBOR_ROBOT_TOKEN }}

      - name: Extract OCI Metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: harbor.corp.internal/production/backend-api
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=sha-,format=short

      - name: Build and Push Container Image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy Vulnerability Scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: harbor.corp.internal/production/backend-api:${{ steps.meta.outputs.version || 'latest' }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          ignore-unfixed: true

      - name: Upload Trivy Scan Results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
```

### 2.2 GitLab CI Enterprise Pipeline with DAG (`needs:`) & Kaniko

```yaml
stages:
  - test
  - security
  - build

variables:
  HARBOR_REGISTRY: "harbor.corp.internal"
  IMAGE_NAME: "harbor.corp.internal/production/order-service"

unit_tests:
  stage: test
  image: golang:1.24-bookworm
  script:
    - go test -v -race -coverprofile=coverage.out ./...

gitleaks_scan:
  stage: security
  image: zricethezav/gitleaks:latest
  needs: [] # Executes immediately via DAG without waiting for unit_tests
  script:
    - gitleaks detect --verbose --redact --exit-code 1

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.0-debug
    entrypoint: [""]
  needs:
    - unit_tests
    - gitleaks_scan
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"https://${HARBOR_REGISTRY}\":{\"auth\":\"$(printf "%s:%s" "${HARBOR_USER}" "${HARBOR_PASSWORD}" | base64 | tr -d '\n')\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor
      --context "${CI_PROJECT_DIR}"
      --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
      --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"
      --cache=true
      --cache-repo="${IMAGE_NAME}/cache"
```

### 2.3 Jenkins Declarative Pipeline with Dynamic Kubernetes Pod Agents

```groovy
pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    role: jenkins-agent
spec:
  containers:
    - name: golang
      image: golang:1.24-bookworm
      command: ['cat']
      tty: true
    - name: kaniko
      image: gcr.io/kaniko-project/executor:debug
      command: ['cat']
      tty: true
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
  volumes:
    - name: docker-config
      secret:
        secretName: harbor-credentials
'''
    }
  }
  stages {
    stage('Test') {
      steps {
        container('golang') {
          sh 'go test -v ./...'
        }
      }
    }
    stage('Build & Push') {
      steps {
        container('kaniko') {
          sh '/kaniko/executor --context=`pwd` --destination=harbor.corp.internal/production/service:${BUILD_NUMBER}'
        }
      }
    }
  }
}
```

### 2.4 ArgoCD Application Manifest with Automated Drift Remediation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-system-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/my-org/gitops-manifests.git'
    targetRevision: main
    path: environments/production/payment-system
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: production-apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 2.5 Argo Rollouts Canary Deployment with Automated Metric Analysis

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: order-service-rollout
  namespace: production-apps
spec:
  replicas: 10
  strategy:
    canary:
      analysis:
        templates:
          - templateName: success-rate-analysis
        args:
          - name: service-name
            value: order-service
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - setWeight: 25
        - pause: { duration: 10m }
        - setWeight: 50
        - pause: { duration: 10m }
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
        - name: app
          image: harbor.corp.internal/production/order-service:v2.5.0
          ports:
            - containerPort: 8080
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-analysis
  namespace: production-apps
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result[0] >= 0.999
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus-k8s.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{app="order-service",status!~"5.*"}[2m]))
            /
            sum(rate(http_requests_total{app="order-service"}[2m]))
```

---

## 3. Operational Reference: Commands and Workflows

### 3.1 ArgoCD CLI Management

```bash
# Log in to ArgoCD Server
argocd login argocd.corp.internal --grpc-web

# List applications and synchronization health
argocd app list

# Inspect real-time diff between Git and cluster
argocd app diff payment-system-production

# Trigger manual synchronization with pruning
argocd app sync payment-system-production --prune

# Roll back to a previous Git commit revision
argocd app rollback payment-system-production
```

### 3.2 Argo Rollouts CLI Management

```bash
# Inspect real-time rollout progress and canary traffic weights
kubectl argo rollouts get rollout order-service-rollout -n production-apps --watch

# Manually promote a paused rollout step
kubectl argo rollouts promote order-service-rollout -n production-apps

# Instantly abort candidate release and roll back traffic to stable version
kubectl argo rollouts abort order-service-rollout -n production-apps

# Retry an aborted or failed rollout
kubectl argo rollouts retry order-service-rollout -n production-apps
```

### 3.3 Signing and Verifying Artifacts with Cosign

```bash
# Sign container image keylessly via Sigstore OIDC
cosign sign --yes harbor.corp.internal/production/backend-api:v2.4.1

# Attach CycloneDX SBOM to container image in registry
cosign attach sbom --sbom sbom.cyclonedx.json harbor.corp.internal/production/backend-api:v2.4.1

# Verify signature against trusted identity before deployment
cosign verify \
  --certificate-identity "https://github.com/my-org/my-repo/.github/workflows/ci.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  harbor.corp.internal/production/backend-api:v2.4.1
```

---

## 4. Reference Mapping and Standards

### 4.1 Repository Templates Reference

| Component | Path | Description |
| :--- | :--- | :--- |
| GitHub Actions OIDC Auth | `templates/github-actions/oidc-aws-auth.yml` | Keyless AWS authentication workflow |
| CI Build, Scan & Push | `templates/github-actions/ci-docker-build-push.yml` | Multi-arch build with Trivy gate |
| GitLab CI Enterprise | `templates/gitlab/.gitlab-ci-enterprise.yml` | DAG execution with Kaniko container builder |
| Jenkins K8s Pipeline | `templates/jenkins/Jenkinsfile.declarative` | Dynamic ephemeral Pod agents on Kubernetes |
| ArgoCD Application | `templates/gitops/argocd-application.yaml` | GitOps auto-sync and self-healing definition |
| FluxCD Kustomization | `templates/gitops/fluxcd-kustomization.yaml` | Flux reconciliation and source tracking |
| Argo Rollouts Canary | `templates/gitops/argo-rollouts-canary.yaml` | Canary traffic shift with metric analysis |
| Backstage Software Template | `templates/platform/backstage-software-template.yaml` | Golden Path microservice scaffolding |
| Crossplane XRD (Postgres) | `templates/platform/crossplane-xrd-postgres.yaml` | Declarative cloud database composition |
| Harbor HA Values | `templates/artifacts/harbor-values-ha.yaml` | Enterprise Harbor on S3, Postgres, Redis |

### 4.2 Compliance Standards

- **SLSA (Supply-chain Levels for Software Artifacts) Level 3**:
  - Ephemeral and isolated build environments (GitHub-hosted, Kaniko, or isolated Pods).
  - Cryptographically attested build provenance with in-toto and Cosign.
- **CIS Supply Chain Security**:
  - Elimination of static access credentials across all build stages.
  - Mandatory signed artifact verification prior to cluster admission.
