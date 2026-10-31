# DevSecOps Advanced Testing: Threat Modeling, SAST, DAST, and Fuzzing

## 1. Threat Modeling in System Architecture

Threat modeling is an architectural discipline that identifies security flaws, attack vectors, and mitigations before code is written or deployed to production.

```text
       [ External Untrusted Zone ]
                   |
                   v (HTTPS / TLS 1.3) [STRIDE: Spoofing, Tampering]
       ========================= [ Trust Boundary 1: Perimeter Ingress ]
                   |
             +-----------+
             | API GW /  |
             | Ingress   |
             +-----------+
                   |
                   v (mTLS / SPIFFE) [STRIDE: Information Disclosure]
       ========================= [ Trust Boundary 2: Workload Mesh ]
          /                 \
         v                   v
  +--------------+    +--------------+
  | Order Svc    |--->| Payment Svc  |
  +--------------+    +--------------+
         |                   |
         v                   v (Encrypted RDS) [STRIDE: Tampering, Repudiation]
  [(Order Store)]     [(Vault / HSM)]
```

### 1.1 The STRIDE Methodology

STRIDE categorizes threat vectors against architectural elements:

| STRIDE Threat | Violated Security Property | Architectural Target | Standard Mitigation |
| :--- | :--- | :--- | :--- |
| **S**poofing | Authenticity | External actors, API clients | Mutual TLS (mTLS), OIDC/OAuth2, SPIFFE IDs |
| **T**ampering | Integrity | Data in transit, DB records | Cryptographic signatures, HMAC, immutable audit logs |
| **R**epudiation | Non-repudiability | Transaction logs, audit events | WORM storage, signed telemetry, nonces |
| **I**nformation Disclosure | Confidentiality | Secrets, PII, memory heaps | AES-256-GCM, TLS 1.3, egress firewalls |
| **D**enial of Service | Availability | Compute nodes, ingress routers | Rate limiting, circuit breakers, autoscaling (HPA) |
| **E**levation of Privilege | Authorization | Service accounts, RBAC roles | Least privilege RBAC, non-root users, seccomp/AppArmor |

### 1.2 Data Flow Diagrams (DFDs) and OWASP Threat Dragon

Data Flow Diagrams map systems using 4 structural primitives across defined **Trust Boundaries**:

1. **Processes**: Computational workloads, microservices, background workers (`order-service`).
2. **Data Stores**: Databases, persistent volumes, object storage buckets (`postgres-db`, `s3-lake`).
3. **Data Flows**: Network communication channels, RPC calls, event queues (`gRPC`, `Kafka`).
4. **External Entities**: Third-party APIs, human actors, external webhooks (`Stripe`, `Web Browser`).

#### OWASP Threat Dragon Integration

OWASP Threat Dragon provides an open-source, machine-readable threat modeling platform (Desktop and Web versions) adhering to JSON schemas:

- **Threat Model as Code**: Threat models stored in `.json` format within Git repositories (`docs/threat-model.json`).
- **Continuous Threat Verification**: Version-controlled threat models updated in tandem with architecture RFCs and Pull Requests.
- **Rule Engine**: Automatic mapping of STRIDE mitigations to GitHub issues and Jira epics during sprint planning.

---

## 2. Deep Static Application Security Testing (SAST)

Modern SAST goes beyond syntactic AST matching by executing semantic taint tracking and control-flow analysis across codebases.

### 2.1 Semgrep Engine Architecture and Custom Rule Authoring

Semgrep executes pattern matching directly on Abstract Syntax Trees (AST) with support for taint analysis without requiring full compilation steps.

#### Custom Rule: Preventing Unsafe Subprocess Execution with User Input

```yaml
rules:
  - id: python-unsafe-subprocess-injection
    languages:
      - python
    severity: ERROR
    message: >-
      Detected subprocess invocation with user-controlled input and shell=True.
      This enables remote code execution (RCE) via command injection.
    metadata:
      cwe: "CWE-78: OS Command Injection"
      owasp: "A03:2021-Injection"
      confidence: HIGH
    mode: taint
    pattern-sources:
      - pattern: flask.request.args.get(...)
      - pattern: flask.request.json.get(...)
      - pattern: request.form[...]
    pattern-sinks:
      - patterns:
          - pattern: subprocess.$METHOD(..., shell=True, ...)
          - pattern-not: subprocess.$METHOD("...", shell=True, ...)
```

#### Rule Primitives Breakdown

- `pattern`: Exact code snippet match with metavariables (`$VAR`).
- `pattern-either`: Logical OR operator across multiple pattern branches.
- `pattern-inside`: Scopes matches within specific functions or classes.
- `pattern-not`: Negative filter eliminating false positives and safe wrappers.
- `mode: taint`: Tracks untrusted sources flowing into sensitive sinks through variable assignments.

### 2.2 SonarQube Enterprise Quality Gates

A hardened DevSecOps pipeline enforces strict Quality Gate criteria on every pull request:

```text
[PR Trigger] -> [Sonar Scanner] -> [SonarQube Analysis]
                                            |
         +----------------------------------+----------------------------------+
         |                                                                     |
   [Rating: A, 0 Vulns]                                           [Vuln >= 1 or Rating < A]
         |                                                                     |
         v                                                                     v
 [Quality Gate PASSED]                                               [Quality Gate FAILED]
         |                                                                     |
   (Merge Allowed)                                                    (Block Merge in GitHub)
```

#### Mandatory Production Quality Gate Parameters

- **Security Rating on New Code**: **A** (zero vulnerabilities permitted).
- **Security Hotspots Reviewed**: **100%** must be formally reviewed and audited.
- **Coverage on New Code**: **>= 80%**.
- **Duplicated Lines on New Code**: **< 3%**.

### 2.3 SARIF Export and Unified Security Dashboards

The **Static Analysis Results Interchange Format (SARIF)** (OASIS standard) standardizes vulnerability reporting across diverse engines (Semgrep, CodeQL, SonarQube, Trivy).

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "Semgrep OSS",
          "semanticVersion": "1.80.0",
          "rules": [
            {
              "id": "python-unsafe-subprocess-injection",
              "shortDescription": {
                "text": "OS Command Injection via Subprocess"
              },
              "defaultConfiguration": {
                "level": "error"
              }
            }
          ]
        }
      },
      "results": [
        {
          "ruleId": "python-unsafe-subprocess-injection",
          "level": "error",
          "message": {
            "text": "User input flows into subprocess with shell=True."
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/services/billing.py"
                },
                "region": {
                  "startLine": 45,
                  "startColumn": 9,
                  "endLine": 45,
                  "endColumn": 52
                }
              }
            }
          ]
        }
      ]
    }
  ]
}
```

GitHub Advanced Security automatically renders SARIF files directly inline on PR diffs with file and line annotations.

---

## 3. Automated Dynamic Application Security Testing (DAST)

DAST exercises running systems externally without internal source code knowledge, simulating black-box and grey-box attacker tactics against live staging endpoints.

### 3.1 OWASP ZAP (Zed Attack Proxy)

OWASP ZAP runs automated baseline (passive) and full active attacks against deployed web apps and API endpoints.

#### Automation Framework Plan (`zap-automation.yaml`)

```yaml
env:
  contexts:
    - name: "staging-api"
      urls:
        - "https://staging.internal.net/api/v1"
      includePaths:
        - "https://staging.internal.net/api/v1/.*"
      authentication:
        method: "bearer"
        parameters:
          token: "${ZAP_BEARER_TOKEN}"
jobs:
  - type: spider
    parameters:
      maxDepth: 5
      maxDuration: 10
  - type: activeScan
    parameters:
      policy: "API-Minimal"
      maxRuleDurationInMins: 3
  - type: report
    parameters:
      template: "traditional-json"
      reportDir: "/zap/wrk"
      reportFile: "zap-report.json"
```

### 3.2 Nuclei Vulnerability Engine

ProjectDiscovery Nuclei executes fast, configurable, YAML-templated vulnerability and misconfiguration scans.

#### Custom Nuclei Template: Unprotected Kubernetes Kubelet Read-Only Port

```yaml
id: kubelet-unprotected-ro-port
info:
  name: Kubernetes Kubelet Read-Only Port 10255 Exposure
  author: devsecops-team
  severity: high
  description: >-
    Detects unauthenticated exposure of the legacy Kubelet read-only port (10255),
    which discloses running pods, volume tokens, and environment parameters.
  reference:
    - https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
  tags: kubernetes,k8s,misconfig

http:
  - method: GET
    path:
      - "{{BaseURL}}:10255/pods"
    matchers-condition: and
    matchers:
      - type: status
        status:
          - 200
      - type: word
        words:
          - '"kind": "PodList"'
          - '"metadata":'
        condition: and
```

---

## 4. Coverage-Guided Fuzzing and Interactive Testing (IAST)

Fuzzing discovers memory corruptions, infinite loops, panics, deserialization exploits, and logic bugs by feeding mutated inputs into software components under automated instrumentation.

```text
+--------------------+      +--------------------+      +--------------------+
| Seed Corpus Input  | ---> | Mutator Engine     | ---> | Instrument SUT     |
+--------------------+      +--------------------+      +--------------------+
          ^                                                        |
          |                  New Edge / Coverage Discovered?       |
          +--------------------------------------------------------+
```

### 4.1 AFL++ (American Fuzzy Lop Plus Plus) in CI Pipelines

AFL++ is the industry standard coverage-guided fuzzer for compiled languages (C, C++, Rust, Go via cgo).

#### Step 1: Instrument Binary with LLVM Sanitizers

```bash
# Compile with AFL++ Clang wrapper and AddressSanitizer (ASan)
afl-clang-fast -fsanitize=address,undefined -g -O2 -o parse_target target.c
```

#### Step 2: Establish Corpus and Run Non-Interactive Fuzzing

```bash
# Prepare deterministic seeds
mkdir -p in out
echo -n "VALID_PACKET_HEADER_001" > in/seed1

# Run AFL++ in batch mode (timeout 300 seconds for CI gates)
afl-fuzz -i in -o out -V 300 -- ./parse_target @@
```

If crashes occur, AFL++ writes the exact reproducing payload to `out/default/crashes/id:*`.

### 4.2 JVM Jazzer Fuzzing in CI

Jazzer is a coverage-guided fuzzer for Java and JVM bytecode built on top of LLVM's `libFuzzer`.

#### Fuzz Target Implementation

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import com.example.parser.FinancialMessageParser;

public class FinancialParserFuzzTest {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        String rawInput = data.consumeRemainingAsString();
        try {
            FinancialMessageParser.parse(rawInput);
        } catch (IllegalArgumentException | ParseException expected) {
            // Expected exceptions are safe and ignored
        }
        // Uncaught exceptions (NullPointerException, StackOverflowError, OutOfMemoryError)
        // trigger actionable fuzzer findings.
    }
}
```

#### Executing Jazzer in GitHub Actions

```bash
docker run --rm -v $(pwd):/app -w /app \
  cifuzz/jazzer:latest \
  --cp=target/classes:target/test-classes \
  --target_class=FinancialParserFuzzTest \
  --runs=50000 \
  --instrument_only=com.example.parser.**
```

### 4.3 IAST (Interactive Application Security Testing)

Unlike SAST (passive source audit) and DAST (black-box HTTP tests), IAST operates from **within the running application runtime** using bytecode instrumentation and profiling agents:

| Dimension | SAST | DAST | IAST |
| :--- | :--- | :--- | :--- |
| **Mechanism** | Static code AST traversal | External HTTP fuzzing | Runtime agent bytecode instrumentation |
| **Context** | Full source code visibility | External HTTP requests/responses | Call stacks, queries, runtime memory values |
| **False Positive Rate** | Medium to High (heuristic) | Low to Medium | Very Low (proven executed paths) |
| **Pipeline Stage** | Pre-commit, Pull Request CI | Staging deployment, Post-deploy | Automated integration / E2E test suite execution |
| **Resource Overhead** | None on runtime (CPU in CI) | Network traffic to target | 5% - 15% execution latency in test environment |
