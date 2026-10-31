# Enterprise Artifact Management with Harbor & OCI Registries

## 1. Executive Overview

In enterprise software delivery, the artifact registry is the central nervous system connecting CI/CD compilation pipelines to runtime Kubernetes clusters. Modern cloud-native registries must manage far more than standard Docker images; they store Open Container Initiative (OCI) artifacts, Helm charts, WebAssembly (WASM) modules, in-toto attestations, Software Bills of Materials (SBOMs), and cryptographic signatures.

Cloud provider registries (AWS ECR, GCP Artifact Registry, Azure ACR) provide baseline storage, but lack unified cross-cloud governance, granular multi-tenancy, integrated vulnerability gating, and customizable cryptographic verification. **Harbor** (a CNCF graduated project) fulfills these enterprise needs.

This reference guide establishes the architecture and operational standard for:

- **High-Availability (HA) Harbor Architecture**: Decoupling stateless controllers from distributed cloud storage (S3), external managed PostgreSQL, and clustered Redis.
- **Vulnerability Scanning & Policy Gating**: Automated continuous scanning with Trivy and enforcement of zero-tolerance CVE thresholds.
- **Cryptographic Signing (Cosign / Sigstore)**: Enforcing admission gates that block unsigned images from running in production.
- **Governance & Storage Optimization**: Tag immutability regex rules, time-based retention policies, and safe online garbage collection.
- **Multi-Region Replication**: Hub-and-spoke active replication across multi-cloud edge clusters.

---

## 2. High-Availability (HA) Harbor Architecture

A production Harbor deployment must eliminate all single points of failure (SPOFs) and avoid legacy shared filesystem protocols (NFS), which suffer from file-lock contention and performance degradation under concurrent pulls.

```text
                                 User / CI/CD / Kubernetes Node
                                               │
                                               ▼
                                 ┌───────────────────────────┐
                                 │   Kubernetes Ingress /    │
                                 │ TLS Termination (Envoy/NG)│
                                 └─────────────┬─────────────┘
                                               │
               ┌───────────────────────────────┼───────────────────────────────┐
               │                               │                               │
               ▼                               ▼                               ▼
  ┌─────────────────────────┐     ┌─────────────────────────┐     ┌─────────────────────────┐
  │   Harbor Core API (x3)  │     │   Harbor Registry (x3)  │     │  Harbor Jobservice (x2) │
  │ (Auth, RBAC, Webhooks)  │     │   (OCI Spec, Blob Push) │     │ (Replication, Retention)│
  └────────────┬────────────┘     └────────────┬────────────┘     └────────────┬────────────┘
               │                               │                               │
               ├───────────────────────────────┴───────────────────────────────┤
               │                                                               │
               ▼                               ▼                               ▼
  ┌─────────────────────────┐     ┌─────────────────────────┐     ┌─────────────────────────┐
  │   External Managed DB   │     │    External Clustered   │     │    Object Storage S3    │
  │  (PostgreSQL HA - RDS)  │     │    Redis (Sentinel/HA)  │     │  (AWS S3 / MinIO / GCS) │
  └─────────────────────────┘     └─────────────────────────┘     └─────────────────────────┘
```

### 2.1 Decoupled Stateless Components

1. **Harbor Core**: The administrative and authorization engine. Handles authentication, RBAC, project management, webhook dispatching, and token issuance. Runs statelessly behind an HPA.
2. **Harbor Registry**: Standard CNCF distribution registry engine wrapped with Harbor authorization filters. Handles high-throughput layer uploads and downloads.
3. **Harbor Portal**: Lightweight React-based web user interface and administration console.
4. **Harbor Jobservice**: Background asynchronous worker pool executing image replication, vulnerability scans, garbage collection, and webhook dispatches.
5. **Trivy Scanner Adapter**: Decoupled scanning microservice that unpacks container filesystems, extracts OS/package dependencies, and compares them against up-to-date vulnerability databases.

### 2.2 Storage & Persistence Backends

- **Object Storage (S3 / GCS / Azure Blob)**: All OCI blobs, manifests, and signatures are persisted to cloud object storage. Local volumes or NFS mounts are strictly forbidden in production due to locking bugs.
- **External PostgreSQL**: Managed database service (e.g., AWS Aurora PostgreSQL, Cloud SQL) with automated multi-AZ failover storing user accounts, project configurations, scan results, and audit logs.
- **External Redis**: High-availability Redis instance (clustered or Sentinel) managing user sessions, caching registry authentication tokens, and queuing Jobservice tasks.

---

## 3. Vulnerability Scanning & Governance with Trivy

Security policies must prevent vulnerable images from ever reaching a cluster node. Harbor integrates Trivy directly into the artifact lifecycle.

### 3.1 Continuous Automated Scanning

Harbor triggers vulnerability scans across two operational vectors:

1. **Scan on Push**: The instant an engineer or CI pipeline pushes an image tag, Jobservice immediately dispatches a scan job to Trivy.
2. **Periodic Scheduled Scans**: A nightly cron job resyncs Trivy's vulnerability database and rescans all existing images, detecting zero-day vulnerabilities disclosed *after* an image was built.

### 3.2 Automated CVE Threshold Gating

Harbor enforces deployment gates by blocking image pulls based on vulnerability severity:

```text
Developer CI Push
       │
       ▼
┌──────────────────────────────────────────────┐
│  Harbor Project: `production-apps`           │
│                                              │
│  [ Policy: Prevent vulnerable images ]       │
│  Severity Threshold: HIGH                    │
│                                              │
│  Trivy Scan Results:                         │
│  - CRITICAL: 1 (CVE-2024-XXXX)               │
│  - HIGH:     3                               │
│  - MEDIUM:   5                               │
│                                              │
│  GATE VERDICT: BLOCKED                       │
│  HTTP 412 Precondition Failed                │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
Kubernetes Kubelet Image Pull Fails (ErrImagePull / PreconditionFailed)
```

- **Project Configuration**: Under `Project Settings -> Configuration`, enable **"Prevent vulnerable images from running"** and set the severity threshold to `High` or `Critical`.
- **Enforcement Mechanics**: When a `docker pull` or `crictl pull` request arrives, Harbor checks the latest scan status. If un-scanned or exceeding the threshold, Harbor responds with `HTTP 412 Precondition Failed`, halting container startup.

### 3.3 Managed CVE Waivers (Vulnerability Whitelisting)

Zero-tolerance policies can block urgent hotfixes due to non-exploitable CVEs (e.g., a vulnerability in an unused CLI utility inside a base image). Harbor resolves this with **Vulnerability Allowlisting**:

- **System-Wide & Project-Level Allowlist**: Platform administrators or security officers register specific CVE IDs (e.g., `CVE-2024-21626`).
- **Expiration Dates**: Every waiver must include an expiration timestamp (e.g., 14 days). Once expired, Harbor resumes blocking the image until remediated.
- **Audit Trails**: All waiver modifications are logged with the authorizing engineer's identity.

---

## 4. Cryptographic Signing & Verification: Cosign Integration

Vulnerability scanning validates the *contents* of an image; cryptographic signing validates its *provenance and integrity*.

### 4.1 Sigstore Cosign Architecture

Cosign signs OCI artifacts without requiring centralized key management infrastructure. Signatures are stored directly in Harbor as OCI image manifests referencing the target digest (`sha256-...sig`).

```text
CI/CD Pipeline (GitHub Actions)
       │
       ├─ 1. Build and Push Image -> registry.infra.example.com/apps/api:v1.2.0
       │
       ├─ 2. Keyless Sign with Cosign (OIDC token -> Sigstore Fulcio -> Rekor)
       │     cosign sign --yes registry.infra.example.com/apps/api:v1.2.0
       │
       ▼
Harbor Registry
       ├── apps/api:v1.2.0 (OCI Image)
       ├── apps/api:sha256-abc...sig (Cosign Signature)
       └── apps/api:sha256-abc...att (SBOM / In-Toto Attestation)
```

### 4.2 Harbor Content Trust & Admission Enforcement

Unsigned images must be rejected at two distinct security barriers:

#### Barrier 1: Harbor-Level Enforcement

In Harbor project settings, enable **"Prevent unsigned images from running"**. Harbor checks for the presence of a valid signature associated with the image digest before authorizing a pull.

#### Barrier 2: In-Cluster Admission Control (Kyverno / OPA Gatekeeper)

Harbor-level checks protect against pulls, but a zero-trust architecture requires the Kubernetes cluster to verify the signature cryptographically before pod scheduling:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
  annotations:
    policies.kyverno.io/title: Verify Cosign Signatures
    policies.kyverno.io/subject: Pod
spec:
  validationFailureAction: Enforce
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-signature-rule
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "registry.infra.example.com/production-apps/*"
          attestors:
            - entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/enterprise-org/*"
                    rekor:
                      url: "https://rekor.sigstore.dev"
```

---

## 5. Tag Immutability & Storage Retention Policies

### 5.1 Tag Immutability Rules

Overwriting image tags (such as pushing a revised binary to `v1.0.0` or mutating `latest`) breaks deployment reproducibility, invalidates audit trails, and opens container supply chains to tag hijacking attacks.

Harbor provides declarative **Tag Immutability Rules** using regex matching:

- **Immutability Scope**: Match release tags (`^v[0-9]+\.[0-9]+\.[0-9]+.*$`) or environment tags (`^(prod|staging)-.*$`).
- **Enforcement**: Once an image is pushed with a matching tag, subsequent pushes targeting the same tag fail immediately with `HTTP 409 Conflict`.

### 5.2 Automated Retention Policies

Unchecked artifact registries accumulate gigabytes of obsolete build artifacts, inflating cloud storage bills and slowing down scanner indexing.

#### Recommended Enterprise Retention Rule Matrix

| Rule Priority | Target Tag Pattern | Condition | Action |
| --- | --- | --- | --- |
| **Rule 1 (Protected)** | `^v[0-9]+\.[0-9]+\.[0-9]+$` | Retain Always | Never Delete (Official SemVer Releases) |
| **Rule 2 (Mainline)** | `^main-[a-f0-9]{7}$` | Retain Last 15 tags | Retain recent integration builds |
| **Rule 3 (PR Ephemeral)** | `^pr-[0-9]+-.*$` | Retain tags pushed within last 7 days | Purge ephemeral branch builds |
| **Rule 4 (Untagged)** | `**` | Delete if un-pulled for > 30 days | Purge stale development snapshots |

### 5.3 Online Garbage Collection (GC)

Deleting a tag in Harbor only removes the manifest pointer; the underlying filesystem layer blobs remain in storage.

- **Mark-and-Sweep**: Harbor's garbage collection identifies all unreferenced layer blobs and deletes them from the S3 bucket.
- **Read-Only Mode**: In legacy versions, GC required placing Harbor into read-only mode. In modern Harbor, configure non-blocking GC or schedule GC executions during off-peak automated maintenance windows:

```yaml
# Helm Jobservice GC Cron Configuration
schedule:
  type: Custom
  cron: "0 0 3 * * 0" # Every Sunday at 03:00 UTC
```

---

## 6. Multi-Region Replication & Disaster Recovery

For geographically distributed engineering teams and multi-cloud Kubernetes clusters, a single centralized registry creates severe cross-region data transfer latency and cost.

```text
                   ┌─────────────────────────────────────────┐
                   │        Central Build Harbor (US)        │
                   │      registry.build.example.com         │
                   └────────────────────┬────────────────────┘
                                        │
                 Push Replication Filter│ (Tags: ^v[0-9]+\.[0-9]+\.[0-9]+$)
                                        │
           ┌────────────────────────────┴────────────────────────────┐
           ▼                                                         ▼
┌─────────────────────────────┐           ┌─────────────────────────────┐
│  Edge Harbor EU (Frankfurt) │           │  Edge Harbor APAC (Tokyo)   │
│   eu-registry.example.com   │           │  apac-registry.example.com  │
│                             │           │                             │
│ Local K8s Cluster Pulls     │           │ Local K8s Cluster Pulls     │
└─────────────────────────────┘           └─────────────────────────────┘
```

### 6.1 Replication Strategies

1. **Push Replication**: Central build registry automatically pushes matching artifacts to edge registries immediately upon push. Ideal for global release distribution.
2. **Pull Replication**: Edge Harbor instances autonomously poll the central registry and replicate required images on demand.
3. **Proxy Cache (Pull-Through Cache)**: Edge Harbor acts as an unauthenticated transparent pull-through cache for upstream public registries (`docker.io`, `quay.io`, `ghcr.io`), evading Docker Hub rate limits and guaranteeing availability even if the external registry experiences an outage.

---

## 7. Production Hardening Checklist

- [ ] **Pod Security Standards (PSS) Restricted**: Ensure all Harbor pods (Core, Registry, Jobservice, Portal, Trivy) run with non-root user IDs (UID 10000), `readOnlyRootFilesystem: true`, and `capabilities.drop: ["ALL"]`.
- [ ] **Externalized State**: Zero local persistent volumes; all state resides in S3-compatible object storage, managed PostgreSQL, and clustered Redis.
- [ ] **TLS 1.3 Termination**: Ingress terminates TLS with certificates automatically renewed via cert-manager.
- [ ] **Automated Scanning on Push**: All projects enforce Trivy vulnerability scanning on push with automatic blocking on `HIGH` or `CRITICAL` findings.
- [ ] **Tag Immutability Active**: Regex rule `^v.*` configured on all production-facing projects to prevent overwrite attacks.
- [ ] **Cosign Signature Admission**: Kyverno or Gatekeeper cluster policy configured to block images lacking valid cryptographic signatures.
- [ ] **Object Storage Lifecycle & Versioning**: Enable AWS S3 bucket versioning with a 30-day noncurrent version expiration policy to protect against accidental blob purging.
