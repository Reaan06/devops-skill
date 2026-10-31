# DevOps & DevSecOps Skill Documentation / Documentación

Welcome to the comprehensive technical documentation for the `devops-skill` ecosystem. This documentation follows the [Diátaxis framework](https://diataxis.fr/) (Tutorials, How-To Guides, Technical Reference, and Deep Explanation) and is fully available in both **English** and **Spanish**.

Bienvenido a la documentación técnica integral del ecosistema `devops-skill`. Esta documentación sigue el marco de trabajo [Diátaxis](https://diataxis.fr/) (Tutoriales, Guías Prácticas, Referencia Técnica y Explicación Teórica) y se encuentra completamente disponible en **Inglés** y **Español**.

---

## 🌐 Language Navigation / Navegación por Idioma

- 🇬🇧 [**English Documentation (docs/en/)**](./en/README.md)
- 🇪🇸 [**Documentación en Español (docs/es/)**](./es/README.md)

---

## 📚 Modules Overview / Módulos del Ecosistema

| Module # | Topic / Tema | English Guide | Guía en Español | Key References & Templates |
| --- | --- | --- | --- | --- |
| **01** | **Containers & Runtimes** / Contenedores y Runtimes | [01-containers-and-runtimes.md](./en/01-containers-and-runtimes.md) | [01-contenedores-y-runtimes.md](./es/01-contenedores-y-runtimes.md) | `references/01`, `templates/containers/` |
| **02** | **Kubernetes & Orchestration** / Kubernetes y Orquestación | [02-kubernetes-and-orchestration.md](./en/02-kubernetes-and-orchestration.md) | [02-kubernetes-y-orquestacion.md](./es/02-kubernetes-y-orquestacion.md) | `references/02`, `11`, `templates/kubernetes/`, `templates/helm/` |
| **03** | **IaC, CaC & DBDevOps** / Infraestructura como Código | [03-infrastructure-as-code-and-cac.md](./en/03-infrastructure-as-code-and-cac.md) | [03-infraestructura-como-codigo-y-cac.md](./es/03-infraestructura-como-codigo-y-cac.md) | `references/03`, `08`, `10`, `templates/terraform/`, `templates/cac/`, `templates/dbdevops/` |
| **04** | **CI/CD, GitOps & IDP** / Entrega Continua y Plataformas | [04-cicd-gitops-and-delivery.md](./en/04-cicd-gitops-and-delivery.md) | [04-cicd-gitops-y-entrega-continua.md](./es/04-cicd-gitops-y-entrega-continua.md) | `references/04`, `09`, `12`, `13`, `templates/github-actions/`, `templates/gitops/`, `templates/platform/` |
| **05** | **DevSecOps, Zero Trust & CWPP** / Seguridad Integral y Runtime | [05-devsecops-zero-trust-and-runtime.md](./en/05-devsecops-zero-trust-and-runtime.md) | [05-devsecops-zero-trust-y-seguridad-en-runtime.md](./es/05-devsecops-zero-trust-y-seguridad-en-runtime.md) | `references/06`, `14`, `15`, `16`, `17`, `templates/security/` |
| **06** | **SRE, FinOps & X-Ops** / Resiliencia, Costos y Especializaciones | [06-sre-observability-finops-and-xops.md](./en/06-sre-observability-finops-and-xops.md) | [06-sre-observabilidad-finops-y-xops.md](./es/06-sre-observabilidad-finops-y-xops.md) | `references/05`, `18`, `19`, `20`, `21`, `22`, `23`, `templates/observability/`, `templates/sre/`, `templates/finops/`, `templates/xops/` |

---

## 🛠️ Validation and Quality Assurance / Validación y Calidad

All modules, configurations, and reference templates undergo automated verification via the Unified Validation Suite:

```bash
./scripts/validate-all.sh
```

Checks enforced across documentation and templates:

1. **YAML Syntax** (`yamllint` with strict comment and structure validation)
2. **Markdown Standards** (`markdownlint-cli` enforcing heading blank lines and formatting)
3. **Shell Scripting** (`shellcheck` validation of all POSIX utilities)
4. **Dockerfile Standards** (`hadolint` for multi-stage and rootless guidelines)
5. **Kubernetes Validation** (`kubeconform` with strict schemas)
6. **Helm Validation** (`helm lint`)
7. **Terraform & OpenTofu** (`terraform fmt -check`)
8. **Secret Leak Detection** (`gitleaks` commit & tree audit)
