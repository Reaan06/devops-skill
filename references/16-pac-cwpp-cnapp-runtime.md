# Policy as Code, CWPP, CNAPP, and Runtime Security

## 1. Cloud-Native Application Protection Platforms (CNAPP)

CNAPP unifies build-time and runtime security controls into an integrated feedback loop:

```text
               +-------------------------------------------------+
               |             Shift-Left Security                 |
               | (SAST, SCA, Secrets, IaC, Spectral, Gatekeeper) |
               +-------------------------------------------------+
                                        |
                                        v
                    +---------------------------------------+
                    |           K8s Admission Gate          |
                    | (OPA Gatekeeper / Kyverno Validation) |
                    +---------------------------------------+
                                        |
                                        v
               +-------------------------------------------------+
               |            Runtime & Workload Defense           |
               |  (CWPP: Falco/Tetragon eBPF, CSPM: Prowler)     |
               +-------------------------------------------------+
                                        |
                        [ Anomaly / Breach Detected ]
                                        |
                                        v
               +-------------------------------------------------+
               |             SOAR Automated Containment          |
               |   (NetworkPolicy Isolation, Memory Dump, Cordon)|
               +-------------------------------------------------+
```

---

## 2. Policy as Code: OPA Gatekeeper vs Kyverno

Kubernetes Dynamic Admission Controllers intercept API requests using `ValidatingAdmissionWebhook` and `MutatingAdmissionWebhook` endpoints.

### 2.1 Architectural Comparison

| Dimension | OPA Gatekeeper | Kyverno |
| :--- | :--- | :--- |
| **Policy Language** | Rego (declarative query language based on Datalog) | Pure Kubernetes YAML (declarative CRDs) |
| **Learning Curve** | High (requires mastering Rego syntax and semantics) | Low (familiar native Kubernetes resource structures) |
| **Mutation Engine** | Supported via Mutation Webhooks | First-class native YAML mutation with overlay/patches |
| **External Data Fetch** | Configurable via external data providers | Native HTTP calls, ConfigMap lookups, Image verification |
| **Audit Capabilities** | Continuous background cluster auditor | Background controller scanning existing resources |
| **Ecosystem Standard** | De-facto CNCF enterprise standard across multi-cloud | Highly popular for pure Kubernetes-native teams |

### 2.2 OPA Gatekeeper Engine Anatomy

Gatekeeper decouples policy logic from enforcement bindings using two CRD layers:

1. **`ConstraintTemplate`**: Defines the reusable Rego logic, target admission hooks, and the OpenAPI schema for constraint parameters.
2. **`Constraint`**: Instantiates a template, binds it to specific resource kinds (`Pod`, `Deployment`), specifies namespaces, and sets enforcement modes:
   - `enforcementAction: dryrun` (Audit mode: reports violations without blocking admission).
   - `enforcementAction: deny` (Enforcement mode: actively rejects mutating/validating admission requests).
   - `enforcementAction: warn` (Allows admission but emits user-facing warning headers to `kubectl` / CI).

```text
+------------------------------------+
| ConstraintTemplate                 |
| (Rego Logic + Parameters Schema)   |
+------------------------------------+
                  ^
                  | Instantiates
+------------------------------------+
| Constraint                         |
| (Match: Kind=Pod, Action=deny)     |
+------------------------------------+
                  ^
                  | Intercepts
[ kubectl apply -f pod-root.yaml ] =====> [ API Server ] =====> [ REJECTED: non-root required ]
```

---

## 3. Cloud Workload Protection (CWPP) & eBPF Kernel Tracing

Traditional user-space monitoring agents relying on `syslog` or polling `/proc` can be bypassed by container breakouts and rootkits. Modern CWPP utilizes **extended Berkeley Packet Filter (eBPF)** to run sandboxed, high-performance verification programs inside the Linux kernel.

### 3.1 Falco Runtime Threat Detection

Falco instruments the Linux kernel to evaluate real-time system calls (`execve`, `openat`, `socket`, `ptrace`) against streaming behavioral detection rules.

#### Falco Component Architecture

```text
[ User Space Workload ]
           |
           v (System Call: execve /bin/sh)
============================================== [ Linux Kernel ]
           |
     [ eBPF Probe ]  <-- Instruments kernel syscall table
           |
           v (Ring Buffer)
============================================== [ Falco Daemon ]
   [ libscap / libsinsp ] -> Extracts container, pod, & process metadata
           |
           v
   [ Falco Rule Engine ]   -> Evaluates against rule definitions
           |
           v
   [ Outputs / Falcosidekick ] -> Alerts to Slack, SIEM, SOAR Webhook
```

#### Detecting Suspicious Executions in Pods

- **Shell in Container**: Detects interactive `/bin/sh`, `/bin/bash`, or `/bin/zsh` spawned within production pods.
- **Sensitive Credential Reads**: Traps reads directed at `/etc/shadow`, `/etc/sudoers`, or Kubernetes service account tokens (`/var/run/secrets/kubernetes.io/serviceaccount/token`).
- **Namespace Traversal / Container Escape**: Detects unauthorized mounts or modifications to `/proc` or `/sys` filesystems.

### 3.2 Cilium Tetragon: In-Kernel Enforcement

While Falco prioritizes detection and notification, **Cilium Tetragon** executes deep kernel tracing and real-time enforcement directly within eBPF without round-tripping to user space:

- **TracingPolicy CRD**: Defines kernel functions (`kprobe`, `kretprobe`, `tracepoints`) to intercept.
- **Synchronous In-Kernel Kill**: Can terminate processes (`sigkill`) immediately inside the kernel system call handler before unauthorized memory writes or socket connections succeed.

---

## 4. Cloud Security Posture Management (CSPM) with Prowler

Prowler is an enterprise-grade multi-cloud security assessment, auditing, and posture management tool covering AWS, Azure, Google Cloud, and Kubernetes.

### 4.1 Compliance Framework Mappings

Prowler automates continuous compliance verification across industry frameworks:

1. **CIS Benchmarks**: Center for Internet Security (CIS AWS Foundation Benchmark v3.0, CIS Kubernetes Benchmark).
2. **SOC 2 Type II**: Security, Availability, Processing Integrity, Confidentiality, and Privacy controls.
3. **PCI-DSS v4.0**: Payment Card Industry Data Security Standard auditing for cardholder data environments.
4. **ISO/IEC 27001:2022**: Information security management systems audit.

### 4.2 Prowler Assessment Execution Pipeline

In modern DevSecOps, Prowler runs on cron-based scheduled workflows and on-demand pull requests targeting cloud infrastructure:

```bash
# Execute CIS AWS Foundations Benchmark scan with JSON and SARIF export
prowler aws \
  --compliance cis_3.0_aws \
  --severity critical high \
  --output-formats json-asff,sarif \
  --output-directory /reports
```

Findings are integrated directly into AWS Security Hub, Azure Defender, or uploaded as SARIF to GitHub Code Scanning.

---

## 5. SOAR: Automated Threat Containment

When runtime detection tools (Falco / Tetragon) identify an active intrusion, Security Orchestration, Automation, and Response (SOAR) workflows isolate the threat autonomously within milliseconds.

### 5.1 Automated Kubernetes Quarantine Pattern

```text
[ Falco Rule Alert ] ===> [ Falcosidekick ] ===> [ SOAR Webhook Controller ]
                                                             |
              +----------------------------------------------+
              | 1. Apply Quarantine Label: 'quarantine=true'
              | 2. Isolate Pod with Default-Deny NetworkPolicy
              | 3. Trigger Forensic Memory & Core Dump
              | 4. Cordon Kubernetes Node to Prevent Scheduling
              | 5. Gracefully Terminate & Retain Volume Snapshot
```

### 5.2 Quarantine NetworkPolicy Implementation

Applying the label `quarantine: "true"` to a compromised pod immediately severs all ingress and egress network communication, stopping data exfiltration and lateral movement:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-isolated-pod
  namespace: production
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  policyTypes:
    - Ingress
    - Egress
  # Ingress and Egress left empty to drop 100% of network packets
```
