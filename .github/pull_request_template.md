# Pull Request Description

## Description

Please provide a concise summary of the changes introduced by this pull request,
including the motivation and context.

Fixes #(issue)

---

## Type of Change

Please select the relevant option(s):

- [ ] `feat`: New capability, template, workflow, or configuration
- [ ] `fix`: Bug fix or error correction
- [ ] `docs`: Documentation updates or additions
- [ ] `refactor`: Structural or style refinement with no behavioral change
- [ ] `ci`: Pipeline or automation modification
- [ ] `chore`: Maintenance, dependencies, or tooling updates

---

## Verification & Quality Checklist

Please confirm that each item below has been verified prior to submission:

- [ ] **Strict Zero-Secrets Audit**: Ran `gitleaks detect --source . --verbose`
  locally; verified no real API keys, tokens, certificates (`.pem`, `.key`),
  or credentials exist in this diff or git history.
- [ ] **Docker Validation**: Dockerfiles tested with `hadolint` and verified to
  run unprivileged (`USER nonroot`) using multi-stage builds.
- [ ] **Kubernetes Validation**: Manifests verified using `kubeconform` (or
  `kubectl apply --dry-run=client`) against valid API schemas.
- [ ] **Terraform Validation**: Configurations checked with
  `terraform fmt -check` and `terraform validate` (if applicable).
- [ ] **GitHub Actions Validation**: Workflows validated with `actionlint`
  without warnings or syntax errors.
- [ ] **Formatting & Linting**: All YAML and Markdown files pass `yamllint`
  and `markdownlint`.
- [ ] **Documentation & References**: Clear comments, README updates, or
  external documentation references have been provided.

---

## Testing Evidence

Provide reproduction steps, command output snippets, or screenshots
demonstrating that the changes work as intended:

```bash
# Paste verification command output here (redact any sensitive local paths)
```
