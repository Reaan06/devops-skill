# Security Policy

`devops-skill` takes security and privacy very seriously. We appreciate the
work of security researchers and the community in helping us maintain the
integrity of our software and templates.

---

## Supported Versions

We provide security updates and patches for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |
| `< 1.0` | :x:                |

We strongly recommend always using the latest release or referencing templates
directly from the `main` branch.

---

## Coordinated Vulnerability Disclosure

We follow the principle of **Coordinated Vulnerability Disclosure (CVD)**.
Please do not report security vulnerabilities through public GitHub issues,
public pull requests, or community discussion boards.

### Reporting Channels

If you discover a potential vulnerability, please report it privately through
either of the following channels:

1. **GitHub Private Vulnerability Reporting (Preferred)**:
   Navigate to the **Security** tab of this repository, select **Advisories**,
   and click **Report a vulnerability**. This creates a private draft advisory
   where we can discuss, test, and patch the issue collaboratively.

2. **Email**:
   Send an encrypted or detailed report to:
   - **Contact**: `esteban0609ye@gmail.com`
   - **Subject**: `[SECURITY VULNERABILITY] devops-skill - <Brief Summary>`

### What to Include in Your Report

To help us triage and resolve the issue quickly, please provide:

- A descriptive summary of the vulnerability.
- Steps to reproduce the issue (proof-of-concept scripts, commands, or manifests).
- The potential security impact and attack scenario.
- Any suggested fixes or mitigations.
- Affected files, templates, or workflows.

---

## Response Times and SLA

Our maintainers commit to the following response timeline:

- **Initial Acknowledgment**: Within **48 hours** of receiving your report.
- **Triage & Assessment**: Within **5 business days**, detailing validity and severity level.
- **Status Updates**: Ongoing communication at least every **7 business days** until resolution.
- **Remediation & Patch**: Targeted within **30 calendar days**, coordinated with public advisory release.

---

## Security Scope

### In-Scope

- Vulnerabilities within provided CI/CD workflows, configuration templates,
  Dockerfiles, or automation scripts.
- Insecure defaults or flawed security controls that lead to privilege escalation,
  arbitrary code execution, or unintended credential exposure.
- Supply chain security vulnerabilities directly attributable to repository
  configurations.

### Out-of-Scope

- Attacks requiring physical access to a user's machine or compromised local
  developer environments.
- Denial of Service (DoS/DDoS) against third-party registries or GitHub infrastructure.
- Issues in third-party upstream tools (e.g., Docker, Kubernetes, Terraform,
  Trivy) unless caused by our specific configuration templates.
- Non-exploitable findings from automated scanners without a demonstrable
  proof-of-concept.

---

## Safe Harbor

We consider security research conducted under this policy to be:

- Authorized under relevant computer misuse laws.
- Exempt from anti-circumvention claims under copyright law (such as the DMCA).
- Lawful and conducted in good faith.

We will not pursue legal action against researchers who make a good-faith effort
to avoid privacy violations, data destruction, and service degradation, and who
allow reasonable time for remediation before public disclosure.
