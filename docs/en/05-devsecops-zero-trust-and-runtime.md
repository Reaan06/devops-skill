# DevSecOps, Zero Trust Architecture & Cloud Workload Protection

## 1. Explanation: Concepts and Architecture

Modern security engineering rejects reactive, perimeter-based defenses ("castle-and-moat") in favor of a unified **Cloud-Native Application Protection Platform (CNAPP)**. In cloud-native systems, security controls must shift left into continuous integration pipelines, enforce cryptographic workload identities without static credentials, validate admission into orchestrators via Policy as Code, and actively intercept anomalous kernel syscalls at runtime.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 1. Shift-Left Pipeline Gates (Pre-Commit & CI)                         │
 │  • Secret Detection: Gitleaks (Git commit history)                    │
 │  • SAST & Taint Analysis: Semgrep (AST-based semantic matching)        │
 │  • SCA & SBOM: Trivy & Syft (CycloneDX / SPDX component inventories)   │
 │  • API Security: Spectral (OpenAPI 3.1 & GraphQL contract governance)  │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Signed OCI Image (Cosign)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 2. In-Cluster Admission Gates (Policy as Code)                         │
 │  • OPA Gatekeeper & Kyverno Admission Webhooks                         │
 │  • Enforces non-root, PSS Restricted, approved registries, signatures  │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Pod Scheduled onto Node
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 3. Zero Trust Cryptographic Identity (SPIFFE / SPIRE)                  │
 │  • Node Attestation via TPM / AWS IID / K8s SAT                        │
 │  • Workload Attestation via SPIFFE Workload API (UNIX Domain Socket)   │
 │  • X.509 SVID issued to application for zero-secret mutual TLS         │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Container Execution
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 4. Runtime Workload Protection & Auditing (CWPP & CSPM)                │
 │  • Falco / Tetragon: Kernel eBPF syscall anomaly detection             │
 │  • Prowler: Continuous CIS Cloud Benchmark scanning                    │
 │  • SOAR Quarantine: Automated pod network isolation on alert           │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Threat Modeling with STRIDE & OWASP Threat Dragon

Threat modeling is an architectural discipline executed before implementation to identify attack paths and systematically apply mitigations across trust boundaries:

| STRIDE Threat | Violated Invariant | Target Primitive | Mitigation Architecture |
| :--- | :--- | :--- | :--- |
| **S**poofing | Authenticity | Ingress APIs, inter-service traffic | SPIFFE/SPIRE X.509 SVIDs, mTLS, short-lived OIDC tokens |
| **T**ampering | Integrity | Storage, in-transit payloads, DB records | Cosign signatures, OpenTofu state encryption, HMAC signatures |
| **R**epudiation | Non-repudiability | Audit logs, financial operations | WORM storage, append-only centralized OTel audit logs |
| **I**nformation Disclosure | Confidentiality | Secrets, memory heaps, environment vars | HashiCorp Vault dynamic secrets, External Secrets Operator, TLS 1.3 |
| **D**enial of Service | Availability | Node compute, API gateways | KEDA scaling, rate limiters, memory/CPU quotas, circuit breakers |
| **E**levation of Privilege | Authorization | Service accounts, container runtimes | PSS Restricted, dropped capabilities (`ALL`), non-root UIDs |

### 1.2 Spec-Driven API Security Governance

APIs represent the primary attack surface for modern applications. The OWASP API Security Top 10 highlights vulnerabilities such as Broken Object Level Authorization (BOLA), Unrestricted Resource Consumption, and Broken Authentication.

Spec-driven security enforces API governance directly on API contracts (OpenAPI 3.1, GraphQL schemas, gRPC protobufs) using **Spectral**:
- **Strict Schema Typing**: Rejects polymorphic `anyOf` without discriminators, eliminating payload smuggling vulnerabilities.
- **Mandatory Authentication Schemes**: Enforces explicit OAuth2 or OIDC scopes on every endpoint.
- **GraphQL Depth & Cost Limiting**: Caps recursive query traversal (preventing nested graph DoS attacks) and disables introspection in production environments.

### 1.3 Zero Trust Architecture: SPIFFE/SPIRE & HashiCorp Vault

NIST SP 800-207 specifies that network locality (IP addresses or VPC subnets) must never imply trust. Every interaction requires explicit cryptographic verification:

- **SPIFFE (Secure Production Identity Framework for Everyone)**: Standardizes platform-agnostic cryptographic identity.
  - **SPIFFE ID**: A URI representing the workload (`spiffe://acme.internal/ns/production/sa/payment-service`).
  - **SVID (SPIFFE Verifiable Identity Document)**: Short-lived X.509 certificates or JWTs issued to the workload.
- **SPIRE (SPIFFE Runtime Environment)**: Implements SPIFFE via:
  - **SPIRE Server**: The cluster certificate authority that registers workloads and signs SVIDs.
  - **SPIRE Agent**: Node DaemonSet that attests local workloads through kernel metadata (UID, PID, cgroups) and serves certificates over a local UNIX domain socket without static bootstrap tokens.
- **HashiCorp Vault**: Provides centralized secrets management, generating ephemeral, dynamic credentials (e.g., short-lived PostgreSQL database passwords rotated every 60 minutes) rather than static long-lived strings.

### 1.4 Policy as Code: OPA Gatekeeper vs. Kyverno

Policy as Code intercepts Kubernetes API requests using `ValidatingAdmissionWebhook` and `MutatingAdmissionWebhook` controllers:

- **OPA Gatekeeper**: Uses the declarative query language **Rego**. Separates policy definitions into `ConstraintTemplate` (the logic) and `Constraint` (the resource binding and enforcement mode). Ideal for complex multi-cluster enterprise deployments with established OPA tooling.
- **Kyverno**: Native Kubernetes declarative policy engine authorable in standard YAML without requiring knowledge of Rego. Excels at native resource mutation, generation, and image signature verification via Cosign.

### 1.5 Cloud Workload Protection (CWPP) with Falco eBPF

Static analysis and admission controllers protect systems prior to container execution. Once a workload is running, attackers exploit zero-day vulnerabilities in application code to execute malicious commands.

**Falco** monitors kernel system calls in real time using an extended Berkeley Packet Filter (eBPF) driver or kernel module. It intercepts operations such as `execve`, `openat`, `socket`, and `setuid`, comparing them against behavioral rule profiles to detect:
- Spawning interactive shells (`/bin/sh`, `/bin/bash`) inside running pods.
- Execution of binaries outside standard container directories (e.g., running scripts from `/tmp` or `/dev/shm`).
- Modification of release binaries or system configuration files (`/etc/passwd`, `/etc/shadow`).
- Attempts to alter namespaces or mount host storage filesystems.

---

## 2. Practical Guides: Production Security Blueprints

### 2.1 Semgrep Custom SAST Ruleset (`semgrep-sast.yml`)

Detect dangerous subprocess executions and raw SQL concatenations:

```yaml
rules:
  - id: prevent-shell-injection
    languages:
      - python
    message: "Potential shell injection: subprocess invoked with shell=True and dynamic arguments."
    severity: ERROR
    metadata:
      cwe: "CWE-78: Improper Neutralization of Special Elements used in an OS Command"
      owasp: "A03:2021 - Injection"
    patterns:
      - pattern-either:
          - pattern: subprocess.Popen(..., shell=True, ...)
          - pattern: subprocess.call(..., shell=True, ...)
          - pattern: subprocess.run(..., shell=True, ...)
      - pattern-not: subprocess.Popen("...", shell=True, ...)

  - id: detect-raw-sql-concatenation
    languages:
      - go
    message: "Raw SQL string concatenation detected. Utilize parameterized queries to prevent SQL injection."
    severity: ERROR
    metadata:
      cwe: "CWE-89: SQL Injection"
    pattern: $DB.Query(fmt.Sprintf(...))
```

### 2.2 Spectral OpenAPI 3.1 Security Governance Ruleset

Save this configuration as `.spectral.yaml` to enforce strict API contracts in CI pipelines:

```yaml
extends: ["spectral:oas"]

rules:
  openapi-enforce-https:
    description: "All server endpoints must enforce secure HTTPS transport."
    severity: error
    given: "$.servers[*].url"
    then:
      function: pattern
      functionOptions:
        match: "^https://"

  openapi-mandatory-security:
    description: "Every API operation must declare an explicit security scheme."
    severity: error
    given: "$.paths[*][get,post,put,delete,patch]"
    then:
      field: security
      function: defined

  openapi-no-empty-descriptions:
    description: "API operations must provide comprehensive descriptions for documentation."
    severity: warn
    given: "$.paths[*][get,post,put,delete,patch].description"
    then:
      function: length
      functionOptions:
        min: 15
```

### 2.3 OPA Gatekeeper ConstraintTemplate & Constraint

Enforce that all running pods drop all kernel capabilities:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirecontainerdropall
spec:
  crd:
    spec:
      names:
        kind: K8sRequireContainerDropAll
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequirecontainerdropall

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not has_drop_all(container)
          msg := sprintf("Container '%v' must explicitly drop ALL capabilities in securityContext.capabilities.drop", [container.name])
        }

        has_drop_all(container) {
          drop := container.securityContext.capabilities.drop
          drop[_] == "ALL"
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireContainerDropAll
metadata:
  name: require-drop-all-production
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - "production-apps"
```

### 2.4 Falco eBPF Runtime Detection Rules for Kubernetes

```yaml
- rule: Terminal Shell Spawned in Container
  desc: Detects interactive shell execution within a production container
  condition: >
    container.id != host and
    spawned_process and
    proc.name in (bash, sh, zsh, ksh, dash) and
    not k8s.ns.name in (kube-system, build-system)
  output: >
    ALERT: Shell spawned inside container (user=%user.name pod=%k8s.pod.name
    ns=%k8s.ns.name container=%container.name cmdline=%proc.cmdline parent=%proc.pname)
  priority: CRITICAL
  tags: [mitre_execution, runtime, container]

- rule: Write below root or usr directory in container
  desc: Detects modifications to immutable system directories inside a running container
  condition: >
    container.id != host and
    open_write and
    fd.name glob "/bin/*" or fd.name glob "/sbin/*" or fd.name glob "/usr/bin/*"
  output: >
    CRITICAL: Container binary directory tampered with (user=%user.name pod=%k8s.pod.name
    file=%fd.name cmdline=%proc.cmdline)
  priority: EMERGENCY
  tags: [mitre_persistence, integrity]
```

### 2.5 SPIRE Server and Agent Deployment Baseline

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-agent-config
  namespace: spire
data:
  agent.conf: |
    agent {
      data_dir = "/run/spire"
      log_level = "INFO"
      server_address = "spire-server.spire.svc.cluster.local"
      server_port = "8081"
      socket_path = "/run/spire/sockets/agent.sock"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "enterprise.corp.internal"
    }
    plugins {
      NodeAttestor "k8s_psat" {
        plugin_data {
          cluster = "production-cluster-01"
        }
      }
      KeyManager "memory" {
        plugin_data {}
      }
      WorkloadAttestor "k8s" {
        plugin_data {
          skip_kubelet_verification = false
        }
      }
    }
```

---

## 3. Operational Reference: Security Commands and Incident Triage

### 3.1 Pre-Commit and CI Secret Detection

```bash
# Scan repository working tree and uncommitted changes
gitleaks detect --source . --verbose --redact

# Scan specific git commit range in CI
gitleaks detect \
  --log-opts="${CI_COMMIT_BEFORE_SHA}..${CI_COMMIT_SHA}" \
  --redact \
  --exit-code 1
```

### 3.2 SAST & DAST Execution Workflows

```bash
# Run Semgrep static analysis with SARIF output
semgrep scan \
  --config p/ci \
  --config p/owasp-top-ten \
  --sarif \
  --output semgrep-report.sarif \
  --error

# Execute dynamic application security testing with Nuclei
nuclei \
  -target https://staging-api.bank.corp \
  -tags cve,owasp-top-10,misconfiguration \
  -severity critical,high \
  -validate \
  -json-export nuclei-findings.json
```

### 3.3 CSPM Auditing with Prowler

```bash
# Execute Prowler CIS Amazon Web Services benchmark audit
prowler aws \
  --compliance cis_3.0_aws \
  --severity critical high \
  --output-modes json,csv,html \
  --output-directory prowler-reports
```

### 3.4 Runtime Incident Response: Compromised Workload Containment

When Falco or kernel audit logs alert on unauthorized shell execution or credential exfiltration:

```bash
# 1. Inspect live container processes from the node host
PID=$(kubectl get pod compromised-pod-8b9f-lk2 -n production-apps \
  -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's/containerd:\/\///')
crictl inspect --output go-template --template '{{.info.pid}}' $PID

# 2. Apply emergency network isolation NetworkPolicy to sever all ingress and egress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-isolate-pod
  namespace: production-apps
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: compromised-service
  policyTypes:
    - Ingress
    - Egress
EOF

# 3. Capture memory core dump for offline digital forensics before terminating
gdb --pid=$PID --batch -ex "gcore /tmp/forensics-pod-dump.core"
```

---

## 4. Reference Mapping and Standards

### 4.1 Repository Templates Reference

| Component | Path | Description |
| :--- | :--- | :--- |
| Falco eBPF Rules | `templates/security/falco-rules-k8s.yaml` | Runtime kernel syscall anomaly detection |
| OPA Gatekeeper Constraint | `templates/security/opa-gatekeeper-constraint.yaml` | Admission webhook policy enforcement |
| Spectral API Ruleset | `templates/security/spectral-openapi-ruleset.yaml` | OpenAPI 3.1 & GraphQL contract governance |
| SPIRE Agent/Server | `templates/security/spire-agent-server-k8s.yaml` | Cryptographic SPIFFE workload identity |
| Vault HA Raft Cluster | `templates/security/vault-cluster-raft-values.yaml` | Clustered dynamic secrets management |
| Semgrep SAST Workflow | `templates/github-actions/semgrep-sast.yml` | Static application security testing in CI |
| Nuclei DAST Workflow | `templates/github-actions/nuclei-dast-scan.yml` | Dynamic staging application testing |
| Prowler CSPM Audit | `templates/github-actions/prowler-cspm-audit.yml` | Continuous cloud security posture management |

### 4.2 Compliance Standards

- **NIST SP 800-207**: Zero Trust Architecture Implementation Framework.
- **NIST SP 800-190**: Application Container Security Guide.
- **CIS Kubernetes Benchmark**: Controls 5.2.1 through 5.2.13 (Container runtime hardening).
- **OWASP API Security Top 10 (2023)**:
  - API1: Broken Object Level Authorization (BOLA).
  - API2: Broken Authentication.
  - API4: Unrestricted Resource Consumption.
