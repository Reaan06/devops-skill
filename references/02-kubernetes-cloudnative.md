# Kubernetes Cloud-Native Engineering

## 1. Executive Overview

Kubernetes in production requires moving beyond basic pod deployments to resilient, defense-in-depth orchestration. An enterprise Kubernetes architecture guarantees three properties:

1. **Host & Kernel Isolation**: Enforcing Pod Security Standards (PSS) `restricted` profile to prevent container breakouts and privilege escalation.
2. **Zero-Trust Network Segmentation**: Enforcing default-deny `NetworkPolicy` controls on both ingress and egress at the namespace level.
3. **Deterministic Capacity & Availability**: Calibrated Quality of Service (QoS) classes, Horizontal Pod Autoscaling (HPA v2) driven by business and system metrics, and Pod Disruption Budgets (PDB) preventing downtime during cluster maintenance and node drains.

---

## 2. Pod Security Standards (PSS) & Admission Control

Kubernetes replaced legacy PodSecurityPolicies (PSP) with the built-in **Pod Security Admission (PSA)** controller, which categorizes workloads into three levels: `Privileged`, `Baseline`, and `Restricted`.

### 2.1 Namespace Admission Labels

Production namespaces MUST be labeled to enforce the `restricted` profile:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production-apps
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

### 2.2 Container SecurityContext Requirements

Under the `restricted` profile, every Pod and container specification MUST satisfy:

- `allowPrivilegeEscalation: false` (prevents SUID binary execution).
- `readOnlyRootFilesystem: true` (prevents tampering with binary or runtime libraries).
- `runAsNonRoot: true` (ensures container fails to start if UID is 0).
- `runAsUser` and `runAsGroup` explicit integers ($\ge 1000$).
- `capabilities.drop: ["ALL"]` (drops all 38+ Linux kernel capabilities).
- `seccompProfile.type: RuntimeDefault` (restricts system calls via Docker/containerd default seccomp filter).

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: application
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    volumeMounts:
      - name: tmp-volume
        mountPath: /tmp
volumes:
  - name: tmp-volume
    emptyDir:
      medium: Memory
      sizeLimit: 64Mi
```

---

## 3. Zero-Trust Network Policies

By default, the Kubernetes network model is completely flat: any pod in any namespace can establish TCP/UDP connections to any other pod or cluster IP.

A production-ready cluster implements **default-deny** isolation per namespace, followed by explicit whitelisting.

### 3.1 Namespace Default-Deny Manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production-apps
spec:
  podSelector: {} # Selects all pods in the namespace
  policyTypes:
    - Ingress
    - Egress
```

### 3.2 Granular Whitelisting Pattern

Once default-deny is applied, every workload requires an explicit rule allowing required ingress (e.g., from an Ingress controller) and egress (e.g., CoreDNS, database):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-traffic
  namespace: production-apps
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: backend-api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow incoming traffic from the NGINX Ingress Controller only
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow UDP/TCP DNS resolution to kube-system CoreDNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow egress to external PostgreSQL database
    - to:
        - ipBlock:
            cidr: 10.0.10.0/24
      ports:
        - protocol: TCP
          port: 5432
```

---

## 4. Kubernetes Quality of Service (QoS) Classes

The kubelet assigns each pod a Quality of Service class based on resource requests and limits. QoS dictates the Linux kernel `oom_score_adj` assigned to the container process:

| QoS Class | Criteria | `oom_score_adj` | Eviction Priority | Recommended Usage |
| --- | --- | --- | --- | --- |
| **Guaranteed** | Requests equal Limits for both CPU and Memory across all containers in the pod | `-997` (near unkillable) | Last to be evicted | Latency-critical databases, caching tiers, primary APIs |
| **Burstable** | Requests are specified and at least one Request < Limit | Calibrated between `2` and `999` based on memory requested | Middle tier | General microservices, web frontends, asynchronous workers |
| **BestEffort** | No requests or limits specified | `1000` (highest kill priority) | First to be killed upon memory pressure | Batch jobs, non-critical background scrapers |

### 4.1 Memory Limits vs. CPU Limits

- **Memory is incompressible**: If a container exceeds its memory limit, the Linux kernel terminates the process immediately with an Out-of-Memory (OOM) kill (`Exit Code 137`).
- **CPU is compressible**: If a container exceeds its CPU limit, the Completely Fair Scheduler (CFS) throttles CPU cycles. While the process will not crash, request latency spikes drastically.
- **Production Guidance**: For mission-critical workloads, allocate `Guaranteed` QoS for memory (request == limit) to avoid unpredictable host-level eviction, and set calibrated CPU limits or omit CPU limits entirely while setting strong CPU requests if running with CFS quota throttling disabled.

---

## 5. Horizontal Pod Autoscaler (HPA v2)

The `autoscaling/v2` API enables scaling based on multiple concurrent metrics, including CPU utilization, memory thresholds, and custom Prometheus metrics.

### 5.1 Multi-Metric HPA with Scaling Behavior Controls

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-autoscaler
  namespace: production-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend-api
  minReplicas: 3
  maxReplicas: 20
  metrics:
    # System metric: Average CPU utilization across pods
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    # Custom metric: Requests per second from Prometheus adapter
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0 # React immediately to traffic surges
      policies:
        - type: Percent
          value: 100 # Double capacity every 15 seconds if needed
          periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300 # Prevent flapping (5-minute cool down)
      policies:
        - type: Percent
          value: 10 # Scale down at most 10% of pods per minute
          periodSeconds: 60
```

---

## 6. Pod Disruption Budgets (PDB)

During routine cluster lifecycle events—such as Kubernetes version upgrades, node pool rotation, or cluster autoscaler scale-downs—the eviction API drains nodes. Without a PodDisruptionBudget, an upgrade could evict all replicas simultaneously.

### 6.1 High-Availability PDB Configuration

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-api-pdb
  namespace: production-apps
spec:
  # Enforce that at least 2 replicas remain running during voluntary disruptions
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: backend-api
```

Alternatively, use `maxUnavailable: 1` or a percentage (`maxUnavailable: 20%`) for larger deployments.

---

## 7. Health Probes Architecture

To guarantee zero-downtime rolling updates, configure all three health probe types:

1. **Startup Probe**: Gates liveness and readiness during slow application boot-up (e.g., warming caches or running DB migrations). Prevents premature kills.
2. **Liveness Probe**: Detects deadlocks where the process is running but cannot recover. Triggers container restart.
3. **Readiness Probe**: Determines when the pod is ready to accept incoming traffic from the Service endpoint controller. If readiness fails, endpoints are removed immediately without restarting the pod.

---

## 8. Enterprise Helm Chart Architecture

Packaging applications for Kubernetes requires strict validation, security defaults, and modular template design.

### 8.1 Schema-First Validation (`values.schema.json`)

Enterprise charts MUST provide a JSON Schema draft-07 (`values.schema.json`) that validates types, constraints, and required fields before rendering. This catches misconfigurations in CI pipelines before deployment to clusters:

- Requires non-root execution (`runAsNonRoot: true`, `runAsUser >= 1000`).
- Enforces capability dropping (`drop: ["ALL"]`).
- Validates ports (1-65535) and protocol enumerations.
- Enforces Guaranteed QoS (requests and limits must both be provided).

### 8.2 PSS-Restricted Security Contexts

The default `values.yaml` MUST configure Pod Security Standards Restricted profile out of the box:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

When `readOnlyRootFilesystem: true` is enabled, an ephemeral memory-backed volume (`emptyDir: medium: Memory`) must be mounted to `/tmp` for writable scratch space.

### 8.3 Template Modularity and Named Helpers (`_helpers.tpl`)

Standardized labels (`helm.sh/chart`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`) ensure consistent observability and GitOps tracking across all manifests.

---

## 9. Declarative GitOps with Kustomize

Kustomize provides template-free, declarative configuration customization through layers:

### 9.1 Base and Overlays Pattern

- **`base/`**: Holds canonical, environment-agnostic resource definitions satisfying PSS Restricted and Guaranteed QoS.
- **`overlays/staging/`**: Applies non-production customizations (e.g. single replica, `staging-` prefix, staging namespace) via strategic merge patches.
- **`overlays/production/`**: Enforces high-availability controls, including `HorizontalPodAutoscaler` (minReplicas: 3, maxReplicas: 10), multi-zone affinity, and production namespaces.

```text
kustomize/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml
    └── production/
        ├── kustomization.yaml
        └── hpa-patch.yaml
```

---

## 10. Next-Generation Ingress: Kubernetes Gateway API

The **Gateway API** (`gateway.networking.k8s.io/v1`) succeeds the legacy `Ingress` API by establishing role-oriented, expressive, and extensible Layer 4 - Layer 7 routing:

1. **Infrastructure Provider**: Manages `GatewayClass` (e.g., Envoy Gateway, Cilium, Istio).
2. **Cluster Operator**: Manages `Gateway` instances defining entry points (ports, protocols, TLS certificates).
3. **Application Developer**: Authors `HTTPRoute`, `GRPCRoute`, or `TCPRoute` attached to Gateways via `parentRefs`.

### 10.1 Advanced Traffic Routing & Header Filtering

`HTTPRoute` supports native request header modification, URL rewriting, traffic splitting (canary releases), and path matching without vendor-specific ingress annotations:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend-api-route
  namespace: production-apps
spec:
  parentRefs:
    - name: enterprise-gateway
      sectionName: https
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: X-Gateway-Routed
                value: "true"
      backendRefs:
        - name: backend-api
          port: 80
          weight: 100
```

---

## 11. Automated TLS Certificate Management with cert-manager

Production workloads require automated certificate issuance, validation, and zero-downtime rotation.

### 11.1 ACME Challenge Types

- **HTTP-01 Challenge**: Solves validation by exposing a temporary cryptographic challenge token over HTTP on port 80 via the Ingress controller. Suitable for public single-domain and multi-domain certificates.
- **DNS-01 Challenge**: Solves validation by creating dynamic `_acme-challenge` TXT records in the authoritative DNS provider (e.g., AWS Route53, Cloudflare). **Mandatory** for wildcard certificates (`*.example.com`) and private/internal clusters unreachable from the public internet.

### 11.2 ClusterIssuer Strategy

Maintain separate `ClusterIssuer` resources for staging and production:
- `letsencrypt-staging`: Validates configuration without risking production rate limits (5 failed orders per account per hour).
- `letsencrypt-prod`: Emits trusted browser-root certificates for production endpoints.

---

## 12. SRE Alerting & SLO Multi-Window Multi-Burn-Rate Rules

Traditional static threshold alerts suffer from high false-positive rates during low traffic and delayed detection during severe outages.

Following the **Google Site Reliability Engineering (SRE) Workbook**, multi-window multi-burn-rate alerting computes the rate of error budget consumption against the Service Level Objective (SLO):

### 12.1 Mathematical Basis for SLO 99.9%

- **Availability SLO**: 99.9% ($1 - 0.001 = 0.999$)
- **Monthly Error Budget**: 0.1% of all requests can fail.
- **Burn Rate 14.4x (Critical / Page)**: Depletes 2% of the monthly error budget in 1 hour. Requires short window (5m) and long window (1h) to both exceed $14.4 \times (1 - \text{SLO})$.
- **Burn Rate 6.0x (Warning / Ticket)**: Depletes 5% of the monthly error budget in 6 hours. Requires short window (30m) and long window (6h) to both exceed $6.0 \times (1 - \text{SLO})$.

### 12.2 Workload Golden Signals & Pod Health

In addition to SLO burn rates, `PrometheusRule` manifests must track:
- **`KubePodCrashLooping`**: Rapid restart rates indicating configuration or panic failures.
- **`ContainerOOMKilled`**: Pod termination due to memory limit breaches (Exit Code 137).
- **`KubeContainerWaiting`**: Containers stuck in `CrashLoopBackOff`, `ImagePullBackOff`, or `ErrImagePull`.
- **Latency P99**: 99th percentile response time exceeding latency SLA thresholds (> 500ms).

---

## 13. Zero-Trust Secrets Management with External Secrets Operator

Storing secrets in plain text or base64 within Git repositories violates DevSecOps compliance. The **External Secrets Operator (ESO)** bridges external enterprise secret managers with native Kubernetes secrets.

### 13.1 Architecture Overview

1. **`ClusterSecretStore`**: Cluster-wide resource configuring connection and authentication to external vaults (AWS Secrets Manager via IRSA, HashiCorp Vault via Kubernetes service account authentication).
2. **`ExternalSecret`**: Namespaced custom resource defining which remote keys to fetch, target secret name, and synchronization interval (`refreshInterval: 1h`).
3. **Native `Secret`**: Decoupled, automatically generated and rotated native Kubernetes Secret consumed by Pod environment variables and volume mounts.

