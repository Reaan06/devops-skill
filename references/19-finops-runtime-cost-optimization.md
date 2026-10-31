# FinOps & Runtime Cost Optimization in Kubernetes

## 1. Executive Overview

Cloud-native efficiency in 2025/2026 requires merging financial accountability with infrastructure engineering. Without automated runtime cost allocation, dynamic right-sizing, and aggressive spot capacity utilization, Kubernetes clusters frequently operate with average CPU and memory utilization below $15\%$, creating immense infrastructure waste.

Modern Cloud-Native FinOps enforces:

1. **FinOps Operational Lifecycle**: Continuous iteration across **Inform** (real-time visibility and cost allocation), **Optimize** (right-sizing and workload bin-packing), and **Operate** (automated governance, Karpenter autoscaling, and spot orchestration).
2. **Standardized Runtime Cost Allocation**: Leveraging **OpenCost** (the CNCF open-source specification) and Kubecost to trace infrastructure spending directly to namespaces, pods, deployments, and cost-center labels.
3. **Metric-Driven Resource Right-Sizing**: Using Prometheus PromQL models to quantify CPU and memory slack, paired with Vertical Pod Autoscaler (VPA) and in-place pod resizing.
4. **Resilient Spot/Preemptible Capacity**: Architecting stateless and fault-tolerant workloads to thrive on AWS Spot, GCP Spot, and Azure Spot instances, automated by Karpenter's native interruption handling and consolidation algorithms.

---

## 2. The Cloud-Native FinOps Framework

The FinOps Foundation defines an iterative, three-phase framework adapted for Kubernetes runtime environments:

```text
               ┌─────────────────────────────────────────┐
               │                 INFORM                  │
               │ Real-time visibility, cost allocation,  │
               │ showback/chargeback, and budget alerts  │
               └────────────────────┬────────────────────┘
                                    │
                                    ▼
               ┌─────────────────────────────────────────┐
               │                OPTIMIZE                 │
               │ Resource right-sizing, idle elimination,│
               │ Spot diversification, discount models   │
               └────────────────────┬────────────────────┘
                                    │
                                    ▼
               ┌─────────────────────────────────────────┐
               │                 OPERATE                 │
               │ Continuous automation via Karpenter,    │
               │ CI/CD cost checks, policy enforcement   │
               └────────────────────┬────────────────────┘
                                    │
                                    └───────> (Cycles back to Inform)
```

1. **Inform**: Make infrastructure spend visible in real time. Map raw AWS/GCP/Azure node and disk invoices directly to business dimensions (tenants, teams, products) using Kubernetes metadata (labels, namespaces).
2. **Optimize**: Identify resource slack, eliminate orphaned persistent volumes and unattached load balancers, right-size pod resource requests, and transition workloads from on-demand to spot capacity.
3. **Operate**: Automate governance through declarative policies. Workloads that do not set appropriate resource requests are flagged or resized automatically; cluster nodes scale dynamically with Karpenter down to zero.

---

## 3. OpenCost & Kubecost Runtime Architecture

OpenCost is an open-source, vendor-neutral CNCF project that calculates real-time Kubernetes cluster costs by mapping container resource allocation against cloud provider pricing APIs.

### 3.1 System Architecture

```text
┌────────────────────────────────────────────────────────────────────────┐
│ Kubernetes Worker Node                                                 │
│                                                                        │
│   [ Kubelet / cAdvisor ] ──> Emits container CPU/Memory usage metrics  │
│             │                                                          │
└─────────────┼──────────────────────────────────────────────────────────┘
              │ Scraped every 15s-60s
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Monitoring Namespace                                                   │
│                                                                        │
│   [ Prometheus / VictoriaMetrics / Thanos ]                           │
│     - node_cpu_seconds_total                                           │
│     - container_cpu_usage_seconds_total                                │
│     - container_memory_working_set_bytes                               │
│     - kube_pod_container_resource_requests                             │
│     - kube_node_status_capacity                                        │
│             ▲                                                          │
│             │ Queries Metrics                                          │
│             │                                                          │
│   ┌─────────┴──────────────────────────────────────────────────────┐   │
│   │ OpenCost In-Cluster Engine                                     │   │
│   │                                                                │   │
│   │  ┌─────────────────────────┐    ┌───────────────────────────┐  │   │
│   │  │ Prometheus Query Client │    │ Cloud Pricing Importer    │  │   │
│   │  └─────────────────────────┘    │ (AWS Pricing API, GCP,    │  │   │
│   │                                 │  Azure, Custom On-Prem)   │  │   │
│   │                                 └─────────────┬─────────────┘  │   │
│   │                                               │                │   │
│   │  ┌────────────────────────────────────────────▼─────────────┐  │   │
│   │  │ Cost Allocation & Reconciliation Engine                  │  │   │
│   │  │ - Normalizes CPU/RAM request vs actual usage             │  │   │
│   │  │ - Distributes shared node overhead & idle capacity       │  │   │
│   │  └────────────────────────────┬─────────────────────────────┘  │   │
│   └───────────────────────────────┼────────────────────────────────┘   │
│                                   │                                    │
└───────────────────────────────────┼────────────────────────────────────┘
                                    ▼
       ┌────────────────────────────┴───────────────────────────┐
       ▼                                                        ▼
 [ OpenCost API / UI ]                                  [ Prometheus Exporter ]
 Endpoint: /allocation/compute                          /metrics: opencost_cost_*
```

### 3.2 Allocation Models

OpenCost calculates cost per container by evaluating the higher of **resource requests** versus **actual resource usage**:

$$\text{Billed Capacity}_{\text{resource}} = \max(\text{Request}_{\text{resource}}, \text{Usage}_{\text{resource}})$$

$$\text{Hourly Cost}_{\text{pod}} = \left(\text{Billed CPU} \times \text{Rate}_{\text{CPU}}\right) + \left(\text{Billed RAM} \times \text{Rate}_{\text{RAM}}\right) + \text{Storage Cost} + \text{Network Cost}$$

Where:
- $\text{Rate}_{\text{CPU}}$ and $\text{Rate}_{\text{RAM}}$ are derived dynamically from the host node's hourly spot or on-demand instance rate divided by total node allocatable capacity.
- **Labels & Dimensions**: Costs aggregate dynamically along any Kubernetes metadata dimension:
  - `namespace`: Segregates tenant costs.
  - `label:app.kubernetes.io/name`: Measures application cost.
  - `label:cost-center`: Maps directly to corporate accounting ledgers.
  - `controller`: Aggregates spend by `Deployment`, `StatefulSet`, or `Job`.

### 3.3 Handling Shared and Idle Costs

A major challenge in multi-tenant Kubernetes is accounting for **Idle Capacity** (unallocated CPU and RAM on nodes waiting for load) and **Shared Platform Overhead** (system daemonsets, ingress controllers, observability agents, AWS Load Balancer Controllers).

OpenCost provides three allocation modes for idle capacity:
1. **Separated Idle**: Displays idle cost as an independent line item belonging to the infrastructure platform team.
2. **Pro-rated Idle Allocation**: Distributes idle cost proportionally across all active workloads based on their relative share of allocated resources:
   $$\text{Allocated Idle}_{\text{tenant}} = \text{Cluster Idle Cost} \times \left(\frac{\text{Direct Spend}_{\text{tenant}}}{\text{Total Allocated Spend}_{\text{all tenants}}}\right)$$
3. **Split by Workload Share**: Allocates shared namespaces (e.g., `kube-system`, `monitoring`, `ingress-nginx`) across application namespaces according to business consumption ratios.

---

## 4. Resource Right-Sizing: Eliminating Overprovisioning

### 4.1 The Overprovisioning Problem

Workload developers routinely overestimate resource requirements to guard against OOM (Out Of Memory) kills or CPU throttling. Because the Kubernetes scheduler places pods based exclusively on **resource requests** rather than actual consumption, inflated requests force cluster autoscalers to provision unneeded physical nodes.

```text
┌─────────────────────────────────────────────────────────────────┐
│ Actual Node Allocatable: 16 Cores, 32 GiB RAM                  │
├─────────────────────────────────────────────────────────────────┤
│ Pod Resource Requests (Committed): 15 Cores, 28 GiB RAM (90%)   │
│  => Scheduler considers this node full; triggers scale-up!      │
├─────────────────────────────────────────────────────────────────┤
│ Real Runtime Consumption (Actual): 2.5 Cores, 6 GiB RAM (18%)   │
│  => 82% of the physical hardware is sitting completely idle!   │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Prometheus PromQL Right-Sizing Analysis

To right-size containers mathematically, platforms evaluate the difference between configured requests and the P95/P99 actual usage over a minimum 7-to-14 day window.

#### CPU Request Overprovisioning Ratio

Quantifies the percentage of requested CPU that is never consumed across the cluster:

```promql
# Percentage of CPU requests sitting completely idle across the cluster
(
  sum(kube_pod_container_resource_requests{resource="cpu"})
  -
  sum(rate(container_cpu_usage_seconds_total[1h]))
)
/
sum(kube_pod_container_resource_requests{resource="cpu"})
* 100
```

#### Memory Slack Identification

Identifies the raw byte differential between memory requested and actual memory working set:

```promql
# Unused Memory Slack in Bytes by Deployment
sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace, pod)
-
sum(container_memory_working_set_bytes) by (namespace, pod)
```

#### Recommended Request Calculation Formula

A production right-sizing recommendation balances cost efficiency against burst safety:

$$\text{Recommended CPU Request} = \text{P95}(\text{CPU Usage}_{14d}) \times 1.25$$

$$\text{Recommended Memory Request} = \max(\text{P99}(\text{Memory Working Set}_{14d}) \times 1.20, \text{Peak Memory}_{14d})$$

$$\text{Recommended Memory Limit} = \text{Recommended Memory Request} \times 1.30 \quad (\text{Headroom for garbage collection})$$

### 4.3 Right-Sizing Automation Tools: VPA vs Goldilocks vs HPA

| Tool | Core Mechanism | Operating Modes | Best For | Caveats |
| :--- | :--- | :--- | :--- | :--- |
| **Fairwinds Goldilocks** | Builds VPA instances in audit mode; provides visual dashboard | Read-only recommendation engine | Discovery and developer self-service | Does not automate mutations directly |
| **Vertical Pod Autoscaler (VPA)** | Recommends or applies CPU/RAM requests/limits automatically | `Off`, `Initial`, `Recreate`, `Auto` | Batch jobs, single-replica stateful workloads, dev/staging environments | In standard mode, recreating pods causes brief application interruptions |
| **Horizontal Pod Autoscaler (HPA)** | Scales pod replica count based on target metrics (CPU, RAM, RPS) | Scale out / Scale in | Stateless web/API tiers with fluctuating traffic | Conflicts with VPA if both scale on CPU/Memory concurrently |
| **KEDA** | Event-driven autoscaler driven by external queues (Kafka, SQS) | Scale to zero up to max replicas | Async queue consumers, workers | Must be coordinated with Karpenter scale-up velocity |

#### In-Place Pod Resizing (Kubernetes 1.27+ Beta / 1.30+ GA)

Standard Kubernetes Historically required killing and recreating a pod to update its CPU or memory limits. In-Place Pod Resizing (`InPlacePodVerticalScaling` feature gate) allows the kubelet to dynamically modify container cgroup allocations without restarting the container, enabling true zero-downtime automated VPA adjustments.

---

## 5. Spot and Preemptible Instance Resilience

Cloud providers offer spare compute capacity at discounts of $60\%$ to $90\%$ compared to on-demand pricing. In exchange, the cloud provider can reclaim the capacity with minimal advance notice.

### 5.1 Interruption Notice Mechanics

| Cloud Provider | Capacity Term | Notice Window | Interruption Delivery Channel |
| :--- | :--- | :--- | :--- |
| **Amazon Web Services (AWS)** | EC2 Spot Instance | **2 Minutes (120s)** | Instance Metadata Service (IMDS) & Amazon EventBridge |
| **Google Cloud Platform (GCP)** | Spot VM / Preemptible VM | **30 Seconds (30s)** | Instance Metadata Service (`computeMetadata/v1/instance/preempted`) |
| **Microsoft Azure** | Azure Spot Virtual Machine | **30 Seconds (30s)** | Scheduled Events API (`http://169.254.169.254/metadata/scheduledevents`) |

### 5.2 Architectural Interruption Flow

```text
 ┌────────────────────────────────────────────────────────┐
 │ AWS EC2 Emits Spot Interruption Notice (T-120 seconds) │
 └──────────────────────────┬─────────────────────────────┘
                            │
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │ Karpenter / AWS Node Termination Handler               │
 │ Intercepts EventBridge notification or polls IMDS      │
 └──────────────────────────┬─────────────────────────────┘
                            │
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │ Instant K8s Cordoning & Draining                       │
 │  1. kubectl cordon node (Prevents new scheduling)      │
 │  2. Karpenter proactively launches replacement Spot node│
 │  3. kubectl drain node (Sends SIGTERM to active pods)  │
 └──────────────────────────┬─────────────────────────────┘
                            │
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │ Pod Lifecycle Execution                                │
 │  1. Pod receives SIGTERM                               │
 │  2. Application stops accepting new connections        │
 │  3. Finishes inflight requests (< terminationGrace)    │
 │  4. Pod terminates cleanly before AWS terminates VM    │
 └────────────────────────────────────────────────────────┘
```

---

## 6. Karpenter: High-Velocity Spot Orchestration & Consolidation

Karpenter is an open-source, high-performance Kubernetes node autoscaler built by AWS and the CNCF community. Unlike the legacy Cluster Autoscaler (which scales fixed EC2 Auto Scaling Groups), Karpenter evaluates unschedulable pods directly and provisions optimized compute instances within seconds.

### 6.1 Karpenter Spot Features

1. **Massive Instance Diversification**: Karpenter avoids single-instance-type bottlenecks. When configuring a Spot `NodePool`, you allow Karpenter to select from dozens of instance types (e.g., `c5.xlarge`, `c6i.xlarge`, `m5.xlarge`, `m6i.xlarge`, `r6i.xlarge`). Karpenter queries AWS Spot placement scores in real time to provision instances with the lowest probability of interruption.
2. **Native Event Handling**: Karpenter subscribes directly to AWS SQS queues receiving EC2 Spot Interruption Warnings, Instance Rebalance Recommendations, Scheduled Maintenance Events, and State Change Notifications. When an interruption event arrives, Karpenter starts provisioning a replacement instance immediately—well before the node is drained.
3. **Continuous Consolidation**: Karpenter continuously scans nodes for underutilization. If a set of pods running across three lightly loaded Spot nodes can fit onto one smaller or cheaper Spot node, Karpenter cordons, drains, replaces, and terminates the wasteful instances automatically.

### 6.2 AWS Node Termination Handler (NTH) vs Native Karpenter

- **AWS Node Termination Handler (NTH)**: Originally developed to monitor IMDS or SQS to drain Kubernetes nodes managed by EC2 Auto Scaling Groups.
- **Karpenter Native Handling**: Modern standard (2025/2026). Karpenter includes built-in SQS queue processor functionality, rendering external NTH deployments redundant when using Karpenter-managed node pools.

---

## 7. Application Architecture for Spot Survivability

Running production workloads on Spot instances requires strict adherence to cloud-native resiliency patterns:

### 7.1 PodDisruptionBudgets (PDB)

A PodDisruptionBudget ensures that a minimum number or percentage of healthy replicas remain available during voluntary disruptions (such as node drains initiated by Karpenter or Spot rebalance events):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-service-pdb
  namespace: production-apps
spec:
  minAvailable: 2 # Guarantees at least 2 pods remain operational
  selector:
    matchLabels:
      app.kubernetes.io/name: api-service
```

### 7.2 Graceful Termination Lifecycle

Containers must handle the `SIGTERM` Unix signal and cleanly drain connections within `terminationGracePeriodSeconds`:

```yaml
spec:
  terminationGracePeriodSeconds: 60 # Complete drain before SIGKILL
  containers:
    - name: api
      lifecycle:
        preStop:
          exec:
            # Sleep 5s to allow Kubernetes endpoint propagation before closing socket
            command: ["/bin/sh", "-c", "sleep 5"]
```

### 7.3 Topology Spread Constraints

Distribute replicas evenly across multiple Availability Zones to prevent a localized AWS Spot capacity shortage in a single zone from taking down the entire service:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: api-service
```
