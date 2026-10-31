# Kubernetes Orchestration & Cloud-Native Architecture

## 1. Explanation: Concepts and Architecture

Kubernetes serves as the control plane for modern cloud-native infrastructure. In production environments, container orchestration must move beyond default declarative manifests to enforce **kernel-level isolation**, **zero-trust network segmentation**, **deterministic autoscaling**, and **automated resilience**.

```text
                                  Internet
                                     │
                                     ▼
                   ┌───────────────────────────────────┐
                   │        Cloud Load Balancer        │
                   └─────────────────┬─────────────────┘
                                     │
                                     ▼
                   ┌───────────────────────────────────┐
                   │    Gateway API / Envoy Proxy      │
                   │ (HTTPRoute / TLS Termination SNI) │
                   └─────────────────┬─────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   │   Cilium eBPF / Ambient ztunnel   │
                   │ (mTLS / L7 Filtering / Encrypted) │
                   └─────────────────┬─────────────────┘
                                     │
     ┌───────────────────────────────┴───────────────────────────────┐
     │ Namespace: production-apps (Enforce: Restricted PSS)          │
     │                                                               │
     │  ┌─────────────────────────────────────────────────────────┐  │
     │  │ Deployment (Guaranteed QoS)                             │  │
     │  │  ┌───────────────────────────────────────────────────┐  │  │
     │  │  │ Pod (readOnlyRootFilesystem, nonroot UID 10001)   │  │  │
     │  │  │  • Container: app                                 │  │  │
     │  │  │  • Volume: tmpfs (/tmp)                           │  │  │
     │  │  │  • SecurityContext: drop ALL, RuntimeDefault      │  │  │
     │  │  └───────────────────────────────────────────────────┘  │  │
     │  └────────────────────────────┬────────────────────────────┘  │
     │                               │                               │
     │  ┌────────────────────────────┴────────────────────────────┐  │
     │  │ PodDisruptionBudget (maxUnavailable: 1)                │  │
     │  └─────────────────────────────────────────────────────────┘  │
     │                                                               │
     │  ┌─────────────────────────────────────────────────────────┐  │
     │  │ NetworkPolicy (Default Deny Ingress & Egress)           │  │
     │  └─────────────────────────────────────────────────────────┘  │
     └───────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
     ┌───────────────────────────────────────────────────────────────┐
     │ Autoscaling Controllers                                       │
     │  • KEDA Operator (Scale to zero on Prometheus / Queue depth)  │
     │  • HPA v2 (Horizontal scaling)                                │
     │  • VPA (Recommendation mode only, no restart conflicts)       │
     └───────────────────────────────────────────────────────────────┘
```

### 1.1 Pod Security Standards (PSS) and Admission Control

Kubernetes replaces legacy `PodSecurityPolicy` (PSP) with the native **Pod Security Admission (PSA)** controller, which validates pods against three profiles defined by the Kubernetes community:

1. **Privileged**: Completely unrestricted permissions. Intended exclusively for cluster networking plugins (CNI), storage drivers (CSI), and node management daemons.
2. **Baseline**: Minimally restrictive policy preventing known privilege escalations (prohibits host network/PID namespaces and privileged execution).
3. **Restricted**: Strictly hardened policy adhering to container security best practices. Required for all production application workloads.

Under `restricted`, workloads must run as non-root users, drop all Linux kernel capabilities (`ALL`), enforce `readOnlyRootFilesystem: true`, prevent privilege escalation (`allowPrivilegeEscalation: false`), and enable the default seccomp profile (`RuntimeDefault`).

### 1.2 Kubernetes Quality of Service (QoS) Mechanics

The kubelet assigns one of three Quality of Service classes to every pod based on its resource requests and limits:

| QoS Class | Condition | Eviction Priority under Host Node Pressure | CPU Throttling Characteristics |
| :--- | :--- | :--- | :--- |
| **Guaranteed** | `requests == limits` for both CPU and Memory across all containers. | Last to be terminated. `oom_score_adj = -997`. | Static CPU manager allocation when integer limits specified. Eliminates CFS throttling jitter. |
| **Burstable** | `requests < limits`, or requests specified without matching limits. | Intermediate priority. `oom_score_adj` dynamically scaled between 2 and 999 based on memory consumption relative to request. | Throttled by Completely Fair Scheduler (CFS) quota when exceeding CPU request. |
| **BestEffort** | Neither `requests` nor `limits` specified. | First to be killed when node faces memory starvation. `oom_score_adj = 1000`. | Strictly opportunistic CPU cycles; subject to severe throttling and termination. |

Production workloads with sensitive tail latencies (P99 SLAs) must always be configured with the **Guaranteed** QoS class to prevent noisy-neighbor memory eviction and unpredictable CFS CPU throttling.

### 1.3 Service Mesh Architecture: Sidecar vs. Sidecarless / Ambient

Service meshes provide transparent mutual TLS (mTLS), layer 7 traffic shaping, and distributed telemetry. The architecture has evolved from sidecar proxies to sidecarless and ambient designs:

- **Sidecar Proxy Model (Envoy per Pod)**:
  - Injects a proxy container into every application pod.
  - *Trade-offs*: Substantial memory overhead (50–150 MB per pod), increased startup latency, complex pod lifecycle dependencies, and cluster-wide redeployments when updating proxy versions.
- **Sidecarless eBPF Model (Cilium)**:
  - Implements network policy, load balancing, and L4/L7 encryption directly inside the Linux kernel using eBPF programs attached to network sockets and tc (traffic control) interfaces.
  - *Trade-offs*: Near-zero resource consumption and latency overhead, but requires modern Linux kernels (5.10+) and direct eBPF privileges on the node.
- **Ambient Mesh Model (Istio Ambient)**:
  - Splits responsibilities into two distinct tiers:
    - **L4 Zero-Trust Tunnel (`ztunnel`)**: Shared node DaemonSet handling mTLS and basic authorization.
    - **L7 Waypoint Proxy**: Dedicated Envoy instance deployed per namespace or service account for advanced L7 routing, retries, and header filtering.
  - *Trade-offs*: Avoids application pod restarts on upgrade while providing full L7 policy control only where strictly required.

### 1.4 Workload Autoscaling: KEDA, HPA, and VPA Coexistence

Modern autoscaling combines three complementary components:

1. **Horizontal Pod Autoscaler (HPA v2)**: Scales pod replicas horizontally based on CPU/memory utilization or external custom metrics.
2. **KEDA (Kubernetes Event-driven Autoscaling)**: Acts as an external metrics provider that feeds into HPA, scaling workloads based on message queue depth, database row counts, or Prometheus PromQL queries. Crucially, KEDA provides **scale-to-zero** capabilities that standard HPA cannot deliver.
3. **Vertical Pod Autoscaler (VPA)**: Dynamically adjusts CPU and memory requests and limits based on observed historical consumption.

#### The Autoscaling Anti-Conflict Rule

Running HPA and VPA concurrently on the same metrics creates an unstable feedback loop: HPA scales up replicas when load increases, causing per-pod resource utilization to decrease, which leads VPA to downsize pod requests, triggering subsequent instability.

**Golden Rule of Autoscaling Coexistence**:
- Configure HPA or KEDA to manage replica counts horizontally.
- Configure VPA strictly in `UpdateMode: "Off"` (recommendation mode). VPA calculates optimal sizing without automatically evicting or restarting running pods. Engineers or automated pipelines consume VPA recommendations to calibrate static requests and limits.

---

## 2. Practical Guides: Production Kubernetes Manifests

### 2.1 Hardened Deployment Specification (PSS Restricted & Guaranteed QoS)

The following manifest demonstrates a production deployment satisfying PSS Restricted criteria and the Guaranteed QoS class:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: production-apps
  labels:
    app.kubernetes.io/name: payment-service
    app.kubernetes.io/part-of: core-banking
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: payment-service
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: payment-service
                topologyKey: kubernetes.io/hostname
      containers:
        - name: application
          image: myorg/payment-service:v2.4.1@sha256:d8c9f...
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              cpu: "1000m"
              memory: "1024Mi"
            limits:
              cpu: "1000m"
              memory: "1024Mi"
          ports:
            - containerPort: 8080
              name: http
          startupProbe:
            httpGet:
              path: /healthz/startup
              port: 8080
            failureThreshold: 30
            periodSeconds: 2
          livenessProbe:
            httpGet:
              path: /healthz/liveness
              port: 8080
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /healthz/readiness
              port: 8080
            periodSeconds: 5
            timeoutSeconds: 2
            successThreshold: 1
            failureThreshold: 2
          volumeMounts:
            - name: ephemeral-tmp
              mountPath: /tmp
      volumes:
        - name: ephemeral-tmp
          emptyDir:
            medium: Memory
            sizeLimit: 128Mi
```

### 2.2 Zero-Trust Namespace NetworkPolicy Baseline

Apply this policy to completely block uninspected ingress and egress across the namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production-apps
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-coredns-egress
  namespace: production-apps
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 2.3 Kubernetes Gateway API HTTPRoute Specification

The Gateway API supersedes legacy Ingress objects, enabling explicit separation of infrastructure provisioning from route management:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payment-api-route
  namespace: production-apps
spec:
  parentRefs:
    - name: enterprise-gateway
      namespace: gateway-system
      sectionName: https
  hostnames:
    - "api.bank.corp"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v2/payments
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: X-Gateway-Routed
                value: "true"
      backendRefs:
        - name: payment-service
          port: 8080
          weight: 100
```

### 2.4 KEDA ScaledObject with Prometheus Metric Trigger

Scale horizontally based on active HTTP transactions and drop to zero when inactive:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: payment-service-scaler
  namespace: production-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-service
  minReplicaCount: 1
  maxReplicaCount: 20
  cooldownPeriod: 300
  pollingInterval: 15
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus-k8s.monitoring.svc.cluster.local:9090
        metricName: http_requests_per_second
        query: sum(rate(http_requests_total{app="payment-service"}[2m]))
        threshold: "150"
        activationThreshold: "5"
```

### 2.5 Pod Disruption Budget (PDB)

Protect services from downtime during voluntary disruptions (node draining, cluster autoscaling):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-service-pdb
  namespace: production-apps
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
```

---

## 3. Operational Reference: Commands and Triage

### 3.1 Pre-Flight Manifest Validation

Validate Kubernetes YAML syntax and schema conformance against strict API specifications:

```bash
# Validate manifests against official Kubernetes OpenAPI schemas
kubeconform \
  -strict \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -summary \
  templates/kubernetes/*.yaml

# Perform server-side dry run
kubectl apply --server-side --dry-run=client -f templates/kubernetes/deployment-hardened.yaml
```

### 3.2 Helm Chart Packaging and Schema Verification

```bash
# Verify values against JSON schema
helm lint templates/helm/app-chart

# Render templates locally to inspect generated manifests
helm template test-release templates/helm/app-chart \
  --values templates/helm/app-chart/values.yaml \
  --validate
```

### 3.3 Diagnostic Triage: Workload Failure Modes

#### 1. CrashLoopBackOff

- **Cause**: Application process crashes immediately after container launch.
- **Diagnostic Commands**:

  ```bash
  # Check recent container logs
  kubectl logs deployment/payment-service -n production-apps --previous

  # Inspect exit code and container termination reason
  kubectl describe pod <pod_name> -n production-apps | grep -A 10 "Last State:"
  ```

- **Resolution**:
  - Exit Code `1`: General application error; check stack trace in previous logs.
  - Exit Code `126`: Command invoked cannot be executed (missing permissions).
  - Exit Code `127`: Executable not found in container filesystem.

#### 2. OOMKilled (Exit Code 137)

- **Cause**: Container memory usage exceeded declared `resources.limits.memory` or host node memory was exhausted.
- **Diagnostic Commands**:

  ```bash
  # Check if pod was killed by OOM killer
  kubectl get pod <pod_name> -n production-apps -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'

  # Inspect real-time memory working set
  kubectl top pod <pod_name> -n production-apps --containers
  ```

- **Resolution**: Right-size memory requests and limits based on VPA recommendations, or inspect application for memory leaks.

#### 3. Pod Security Admission Violations

- **Cause**: Manifest does not conform to the namespace's `pod-security.kubernetes.io/enforce: restricted` policy.
- **Diagnostic Commands**:

  ```bash
  # Check warning events during pod creation
  kubectl get events -n production-apps --field-selector reason=FailedCreate
  ```

- **Resolution**: Verify that `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `runAsNonRoot: true`, and `capabilities.drop: ["ALL"]` are declared on all containers in the pod.

---

## 4. Reference Mapping and Standards

### 4.1 Repository Templates Reference

| Component | Path | Description |
| :--- | :--- | :--- |
| Hardened Deployment | `templates/kubernetes/deployment-hardened.yaml` | PSS Restricted, Guaranteed QoS, probes |
| NetworkPolicy Default-Deny | `templates/kubernetes/network-policy-default-deny.yaml` | Namespace-wide default ingress/egress block |
| Cilium L7 NetworkPolicy | `templates/kubernetes/cilium-networkpolicy-l7.yaml` | eBPF-driven path and method HTTP filtering |
| Gateway API HTTPRoute | `templates/kubernetes/gateway-api-httproute.yaml` | Layer 7 routing via Gateway API spec |
| KEDA ScaledObject | `templates/kubernetes/keda-scaledobject-prometheus.yaml` | Event-driven scaling with scale-to-zero |
| VPA Recommendation | `templates/kubernetes/vpa-recommendation.yaml` | Safe right-sizing without automated eviction |
| PodDisruptionBudget | `templates/kubernetes/pdb.yaml` | High availability constraints during maintenance |
| Istio Ambient Mesh | `templates/kubernetes/istio-ambient-peerauthentication.yaml` | Strict mTLS via ambient ztunnel |
| External Secrets Operator | `templates/kubernetes/external-secrets-operator.yaml` | Syncing cloud secrets into native K8s secrets |
| Enterprise Helm Chart | `templates/helm/app-chart/` | Production Helm chart with JSON schema validation |

### 4.2 Compliance Standards

- **Kubernetes Pod Security Standards**: Restricted Profile Specification.
- **CIS Kubernetes Benchmark v1.8.0**:
  - Control 5.2.1: Minimize the admission of privileged containers.
  - Control 5.3.1: Ensure that default-deny NetworkPolicies are established.
  - Control 5.4.1: Prefer secrets stored via external KMS providers over raw etcd.
