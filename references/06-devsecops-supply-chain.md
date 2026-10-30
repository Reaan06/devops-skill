# DevSecOps & Software Supply Chain Security

## 1. Executive Overview

Software Supply Chain security protects against attacks targeting third-party dependencies, malicious commits, compromised CI runners, and poisoned artifact registries.

Modern DevSecOps (2025/2026) operates on the principle of **continuous verification across the artifact lifecycle**:

1. **Pre-Commit & Code Gates**: Git history scanning with **Gitleaks** to prevent secret leakage at the source.
2. **Automated Vulnerability Gating**: Static configuration and container filesystem scans with **Trivy** in CI with non-zero exit codes on actionable vulnerabilities.
3. **Software Bill of Materials (SBOM)**: Generating cryptographically attested machine-readable component inventories using **Syft** (SPDX / CycloneDX).
4. **Supply-chain Levels for Software Artifacts (SLSA)**: Meeting SLSA Level 3 compliance through isolated, ephemeral build workers and signed provenance attestations.

---

## 2. Secret Scanning with Gitleaks

Committing credentials (API keys, private keys, database passwords, OAuth tokens) to Git is a catastrophic, often irreversible event due to Git's immutable commit object graph.

### 2.1 Threat Mitigation & Detection Strategy

- **Shift-Left**: Prevent commits before they reach the remote repository via pre-commit hooks.
- **Pull Request Scan**: Scan git commits in the PR range in CI before code merges to `main`.
- **Full History Auditing**: Periodically scan entire repository commit graphs to catch historical leaks.

### 2.2 Production Gitleaks Configuration (`.gitleaks.toml`)

```toml
[extend]
useDefault = true

[allowlist]
description = "Global allowlist for test fixtures and false positives"
paths = [
  '''(?i)tests?/fixtures/.*''',
  '''(?i)templates/.*'''
]
regexes = [
  '''EXAMPLE_[A-Z0-9_]+''',
  '''dummy-token-[0-9a-f]+'''
]

[[rules]]
id = "custom-internal-api-key"
description = "Internal Organization API Key"
regex = '''(?i)(?:internal_key|corp_secret)\s*[:=]\s*['"]([0-9a-zA-Z]{40})['"]'''
secretGroup = 1
keywords = ["internal_key", "corp_secret"]
```

### 2.3 Automated CI Execution

```bash
gitleaks detect \
  --source . \
  --verbose \
  --redact \
  --exit-code 1
```

---

## 3. Vulnerability Gating with Trivy

Aquasec Trivy is a comprehensive security scanner capable of auditing container images, filesystems, Git repositories, and Infrastructure as Code.

### 3.1 Enterprise Scanning Strategy

1. **Filter Out Unfixed Vulnerabilities**: Focusing on CVEs that upstream maintainers have not yet patched wastes engineering cycles. Pass `--ignore-unfixed` to isolate actionable risks.
2. **Enforce Severity Thresholds**: Block CI builds on `HIGH` and `CRITICAL` findings.
3. **Scan Multiple Layers**:
   - OS-level packages (Debian `dpkg`, Alpine `apk`, RPM).
   - Application dependencies (`npm`, `pip`, `go.mod`, `pom.xml`, `cargo`).
   - Container configuration misconfigurations (running as root, missing healthcheck).

### 3.2 Trivy CI Step Definition

```yaml
- name: Run Trivy Vulnerability Scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: "ghcr.io/my-org/my-app:${{ github.sha }}"
    format: "table"
    exit-code: "1"
    ignore-unfixed: true
    vuln-type: "os,library"
    severity: "CRITICAL,HIGH"
```

---

## 4. Software Bill of Materials (SBOM) with Syft

An SBOM provides an exhaustive, machine-readable inventory of all third-party libraries, binaries, licenses, and dependencies bundled into an artifact.

### 4.1 Formats: CycloneDX vs. SPDX

- **CycloneDX** (`cyclonedx-json`): Developed by OWASP; optimized for application security, vulnerability identification, and automated license analysis.
- **SPDX** (`spdx-json`): An ISO international standard (ISO/IEC 5962:2021) optimized for open-source license compliance and intellectual property tracking.

### 4.2 Syft CLI Execution & Attestation

Generate an SBOM from a local container image:

```bash
# Generate CycloneDX JSON SBOM
syft scan candidate-image:latest -o cyclonedx-json=sbom.cyclonedx.json

# Generate SPDX 2.3 JSON SBOM
syft scan candidate-image:latest -o spdx-json=sbom.spdx.json
```

Attest the generated SBOM directly to the container registry using Cosign:

```bash
cosign attest \
  --yes \
  --type cyclonedx \
  --predicate sbom.cyclonedx.json \
  "${IMAGE_URI}@${IMAGE_DIGEST}"
```

Once attested, security operations teams can query the registry to answer zero-day vulnerability questions (e.g. "Which running production containers bundle Log4j or vulnerable OpenSSL?") without needing access to source code.

---

## 5. SLSA Level 3 Compliance Blueprint

Supply-chain Levels for Software Artifacts (SLSA) establishes security standards across four levels:

```text
Source Track                Build Track                 Provenance Track
[ Hermetic Git ] ───▶ [ Isolated Runner ] ───▶ [ Non-Forgeable Attestation ]
```

### 5.1 SLSA L3 Checklist

1. **Source Integrity**: Code must reside in a version control system requiring multi-party review (branch protection, required PR approvals) before merge.
2. **Ephemeral Build Environment**: Build steps must execute inside an ephemeral virtual machine or isolated container created specifically for the build and destroyed immediately afterwards (standard GitHub-hosted runners satisfy this).
3. **Isolated Build Service**: Build commands cannot share memory, disk, or secrets with other tenants or subsequent runs.
4. **Non-Forgeable Provenance**: Provenance metadata must be cryptographically signed by the build system itself (not by the user running the build), proving:
   - Git repository URL and commit SHA.
   - Build workflow definition path.
   - Exact input parameters and environment variables.
   - SHA256 digest of output artifacts.
