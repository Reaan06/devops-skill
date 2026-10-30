# Open Source Governance & Engineering Standards

## 1. Executive Overview

High-performing infrastructure and DevOps projects require consistent engineering discipline, clear contribution pathways, and predictable release management. An open-source or enterprise infrastructure repository must establish:

1. **Structured Documentation Architecture**: Structuring technical prose following the **Diátaxis framework** (Tutorials, How-To Guides, Reference, Explanation).
2. **Standard Repository Invariants**: Explicit `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, and `CODE_OF_CONDUCT.md`.
3. **Pull Request Hygiene & Etiquette**: Scoped atomic commits, semantic versioning, self-describing PR descriptions, and zero-breaking-change contracts.
4. **Automated Quality Gates**: Shift-left continuous integration enforcing linters (`yamllint`, `markdownlint`, `actionlint`), formatters, and security checks on every pull request.

---

## 2. The Diátaxis Documentation Framework

Documentation often fails because it mixes distinct reader intents into a single document. The Diátaxis framework divides documentation into four quadrants based on two axes: **Practical vs. Theoretical** and **Learning vs. Working**.

```text
               PRACTICAL
                   ▲
                   │
    Tutorials      │     How-To Guides
 (Learning-oriented)│   (Problem-oriented)
                   │
◄──────────────────┼──────────────────►
                   │
   Explanation     │       Reference
(Understanding-    │  (Information-oriented)
   oriented)       │
                   ▼
              THEORETICAL
```

### 2.1 The Four Quadrants Applied to Infrastructure

1. **Tutorials (Learning-Oriented)**:
   - Takes a newcomer by the hand through a step-by-step exercise.
   - Example: *"Deploying your first hardened microservice with devops-skill in 10 minutes."*
   - Avoids branching decisions or alternative setups; focuses on a single successful journey.
2. **How-To Guides (Problem-Oriented)**:
   - Guides an engineer facing a real-world problem through specific steps.
   - Example: *"How to rotate an AWS KMS state encryption key without downtime."*
   - Assumes foundational competence; directly addresses edge cases and specific goals.
3. **Reference (Information-Oriented)**:
   - Strict technical description of the machinery (APIs, CLI flags, configuration schemas).
   - Example: *"OpenTelemetry Collector Pipeline Configuration Schema"* or *"Kubernetes Restricted SecurityContext Reference"*.
   - Accurate, complete, and austere. No storytelling or tutorials.
4. **Explanation (Understanding-Oriented)**:
   - Deep architectural discussions shedding light on choices, trade-offs, and historical context.
   - Example: *"Why Distroless is preferred over Alpine for enterprise Go runtimes."*

---

## 3. Pull Request Hygiene & Etiquette

High velocity in infrastructure teams relies on small, high-confidence pull requests that reviewers can evaluate without cognitive overload.

### 3.1 The 400-Line Rule

Pull requests modifying more than 400 lines of functional code (excluding lockfiles or auto-generated docs) introduce exponential review fatigue and increase defect escape rates. Large changes must be decomposed into chained, reviewable work units:

- **PR 1**: Scaffolding data models, schemas, and templates.
- **PR 2**: Core business logic and unit test suites.
- **PR 3**: Integration and end-to-end verification.

### 3.2 Semantic Commit Messages (Conventional Commits)

Every commit must declare its scope and intent using the Conventional Commits specification:

```text
<type>(<optional scope>): <subject>

[optional body]

[optional footer(s)]
```

Common types:

- `feat`: A new feature or configuration capability.
- `fix`: A bug fix or remediation.
- `docs`: Documentation-only changes.
- `refactor`: Code restructuring without behavioral change.
- `ci`: Changes to CI/CD workflows, runners, or build scripts.
- `security`: Vulnerability remediation or security hardening.

---

## 4. Automated Quality Gates

Every infrastructure repository must enforce continuous quality gates before any human reviewer spends time reading code:

### 4.1 YAML Quality (`yamllint`)

Prevents subtle YAML formatting bugs (indentation mismatches, duplicate keys, boolean string confusion):

```yaml
extends: default
rules:
  line-length: disable
  document-start: disable
  truthy: disable
  comments:
    min-spaces-from-content: 1
```

### 4.2 GitHub Actions Quality (`actionlint`)

Validates GitHub Actions workflow syntax, checks expression syntax (e.g. `${{ secrets.FOO }}`), verifies action versions, and detects shell script bugs inside `run:` blocks using ShellCheck.

### 4.3 Markdown Quality (`markdownlint`)

Ensures technical documentation follows clean typography, uniform heading hierarchy, no trailing whitespace, and valid code fences.
