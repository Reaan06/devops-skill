# CI/CD Automation & GitOps Delivery

## 1. Executive Overview

Modern continuous integration and deployment pipelines operate under two zero-trust principles:

1. **Zero Static Credentials**: Authentication to cloud providers (AWS, Google Cloud, Azure) must use short-lived OpenID Connect (OIDC) identity federation tokens. Storing static IAM access keys (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) or service account JSON keys inside GitHub Actions secrets is strictly prohibited.
2. **GitOps as the Source of Truth**: Application state in production Kubernetes clusters is not applied by CI push jobs. Instead, an in-cluster GitOps controller (ArgoCD or Flux) continuously reconciles the declared Git repository state with live cluster state, providing drift detection and self-healing.

---

## 2. Keyless Cloud Authentication with OpenID Connect (OIDC)

GitHub Actions functions as an OpenID Connect (OIDC) Identity Provider (IdP). For each workflow run, GitHub issues an ephemeral JSON Web Token (JWT) signed by its private key. The cloud provider's Security Token Service (STS) validates the token against GitHub's public OIDC discovery endpoint (`https://token.actions.githubusercontent.com`) and issues temporary credentials.

### 2.1 AWS IAM Trust Policy Configuration

To allow GitHub Actions to assume an IAM role, define an IAM Trust Policy scoping the `sub` (subject) claim to the exact organization, repository, and branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

### 2.2 GitHub Actions OIDC Workflow Step

```yaml
permissions:
  id-token: write # Required for requesting the JWT OIDC token
  contents: read  # Required for checkout

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111122223333:role/github-actions-production-deployer
          aws-region: us-east-1
          audience: sts.amazonaws.com
```

---

## 3. Cryptographic Image Signing with Cosign (Keyless)

Sigstore Cosign provides cryptographic signing of container images and OCI artifacts without managing private keys or passphrases. It leverages:

- **Fulcio**: A free root Certificate Authority issuing short-lived X.509 certificates tied to OIDC identities.
- **Rekor**: An append-only, tamper-evident transparency log recording signatures.

### 3.1 Keyless Signing in GitHub Actions

```yaml
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Sign Container Image Keylessly
        env:
          COSIGN_EXPERIMENTAL: "true"
        run: |
          cosign sign --yes "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build-and-push.outputs.digest }}"
```

### 3.2 In-Cluster Verification with Kyverno or Policy Controller

A Kyverno `ClusterPolicy` blocks any container from running in the cluster unless verified by Cosign:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-cosign-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "ghcr.io/my-org/*"
          attestors:
            - entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/my-org/my-repo/.github/workflows/release.yml@refs/heads/main"
```

---

## 4. SLSA Provenance Generation

Supply-chain Levels for Software Artifacts (SLSA) provides end-to-end provenance demonstrating that the binary or container image was built on trusted infrastructure from a verifiable commit.

Using the official GitHub SLSA generator (`slsa-framework/slsa-github-generator`), workflows generate non-forgeable predicate attestations that are pushed directly to the container registry alongside the image.

---

## 5. GitOps Delivery with ArgoCD

In a GitOps architecture, developers never run `kubectl apply` against production. Instead, application configurations are stored declaratively in a dedicated Git repository.

### 5.1 Architecture Workflow

```text
[ Developer ] -> [ Push Git Code ]
                      │
                      ▼
               [ CI Pipeline ]
               (Test, Build, Scan, Sign, Push Image)
                      │
                      ▼
               [ Update Manifest Repo ] (e.g. Bump image tag: sha256:abc...)
                      │
                      ▼
               [ ArgoCD Controller ] (Polls or receives webhook)
                      │ (Compares Git vs Live Cluster)
                      ▼
               [ Reconciliation Loop ]
               (Applies diff, verifies health checks, alerts on drift)
```

### 5.2 Production ArgoCD Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend-api-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/gitops-manifests.git
    targetRevision: main
    path: environments/production/backend-api
  destination:
    server: https://kubernetes.default.svc
    namespace: production-apps
  syncPolicy:
    automated:
      prune: true     # Delete resources removed from Git
      selfHeal: true  # Revert out-of-band manual changes made with kubectl
      allowEmpty: false
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

### 5.3 Automated Rollbacks & Progressive Delivery

Combine ArgoCD with **Argo Rollouts** to implement Canary and Blue-Green deployments:

- Shift 10% traffic to candidate version.
- Measure latency percentiles and error rates using Prometheus metrics queries.
- Automatically roll back traffic if error budget burn rate exceeds 0.5% over a 5-minute analysis window.
