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
