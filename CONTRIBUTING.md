# Contributing to devops-skill

Thank you for your interest in contributing to `devops-skill`! We welcome
contributions, bug reports, and enhancements from the community. To keep our
codebase reliable, secure, and maintainable, please follow these guidelines.

---

## Code of Conduct

All contributors and maintainers are expected to adhere to our
[Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project,
you agree to uphold its standards.

---

## Branching Strategy and Workflow

We follow a GitHub Flow model with protected branches:

1. **Base Branch**: All production-ready code lives on `main`. Pull requests
   must target `main`.
2. **Branch Naming**: Create dedicated topic branches from an up-to-date `main`.
   Use descriptive names matching your change:
   - `feat/<short-description>`: New skills, templates, or capabilities.
   - `fix/<short-description>`: Bug fixes or corrections.
   - `docs/<short-description>`: Documentation additions or updates.
   - `refactor/<short-description>`: Structural improvements without changes.
   - `chore/<short-description>`: Tooling, dependency, or maintenance tasks.
3. **Synchronization**: Keep your branch rebased onto `main` to avoid merge
   conflicts and preserve linear history:

   ```bash
   git fetch origin
   git rebase origin/main
   ```

---

## Commit Message Guidelines

We enforce the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
specification. Every commit message must be structured as follows:

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Allowed Types

- `feat`: A new feature, template, or skill capability.
- `fix`: A bug fix.
- `docs`: Documentation-only changes.
- `style`: Changes that do not affect code meaning (white-space, formatting).
- `refactor`: Code changes that neither fix a bug nor add a feature.
- `perf`: Code changes that improve performance.
- `test`: Adding missing tests or correcting existing tests.
- `ci`: Changes to CI/CD configuration files and scripts.
- `chore`: Routine maintenance, updating dependencies, or tooling.

### Examples

- `feat(docker): add multi-stage distroless nodejs template`
- `fix(k8s): correct securitycontext runasnonroot setting`
- `docs(readme): update getting started prerequisites`
- `chore(deps): bump actionlint to v1.7.7`

---

## Quality Standards and Local Validation

Before submitting a Pull Request, you must run local validation on your changes.
PRs failing CI linting or security checks will not be merged.

### 1. Docker Validation

Ensure Dockerfiles adhere to best practices (minimal base images, non-root users,
explicit tag pinning, multi-stage builds):

```bash
# Lint Dockerfiles with Hadolint
hadolint path/to/Dockerfile

# Test build syntax
docker build --check -f path/to/Dockerfile .
```

### 2. Kubernetes Manifests (`kubeconform`)

Validate Kubernetes manifests against OpenAPI schemas and best practices:

```bash
# Validate against standard Kubernetes JSON schemas
kubeconform -strict -summary -schema-location default path/to/k8s/
```

### 3. Terraform (`fmt` and `validate`)

If contributing Terraform definitions or modules:

```bash
# Format check
terraform fmt -check -recursive

# Validate syntax and configuration
terraform init -backend=false
terraform validate
```

### 4. GitHub Actions Workflows (`actionlint`)

All workflow files in `.github/workflows/` must pass Actionlint:

```bash
# Lint GitHub Actions workflow definitions
actionlint
```

### 5. YAML and Markdown Linting

Run `yamllint` and `markdownlint` across the repository:

```bash
# Validate YAML formatting
yamllint .

# Validate Markdown style
markdownlint "**/*.md"
```

### 6. Local Secrets Detection (`gitleaks`)

Run `gitleaks` to verify no credentials, keys, or sensitive tokens are committed:

```bash
# Scan repository for secrets
gitleaks detect --source . --verbose
```

---

## Strict Zero-Secrets Policy

Security is paramount. We enforce a **zero-tolerance policy** for committed
secrets or private credentials:

- **Never commit**:
  - API keys, personal access tokens (PATs), OAuth tokens.
  - Private cryptographic keys (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa*`).
  - Passwords, connection strings, or cloud provider credentials.
  - Real production, staging, or development `.env` files.
- **Example configuration**:
  - Use `.env.example` with redacted placeholders (e.g. `API_KEY=YOUR_API_KEY_HERE`).
  - Use standard RFC reserved IP addresses (e.g., `192.0.2.0/24`) and example
    domain names (`example.com`).
- **Remediation**:
  - If a secret is committed by mistake, notify the maintainers immediately.
    The credential must be rotated and invalidated at once. History rewrites
    will be required.

---

## Pull Request Process

1. **Open an Issue First**: For non-trivial features or architecture modifications,
   please open an Issue to discuss the proposal before writing code.
2. **Fill Out the PR Template**: Complete all sections of the
   [Pull Request Template](.github/pull_request_template.md).
3. **Verify CI Checks**: Ensure all automated workflows (`ci.yml`, `security-scan.yml`)
   pass cleanly.
4. **Code Review**: A maintainer will review your contribution. Be responsive
   to feedback and discussions. Once approved, the PR will be squash-merged into `main`.

---

## Need Help?

If you have questions or need assistance, feel free to open a Discussion on GitHub
or reach out to the maintainers at `esteban0609ye@gmail.com`.
