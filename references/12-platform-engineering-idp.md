# Platform Engineering & Internal Developer Platforms (IDP)

## 1. Executive Overview

Platform Engineering has emerged as the definitive discipline for scaling software delivery in high-complexity cloud environments. While early DevOps promoted "You Build It, You Run It," the proliferation of cloud-native technologies—Kubernetes, service meshes, distributed databases, complex IAM, and multi-tool CI/CD pipelines—has led to unsustainable developer cognitive overload.

An **Internal Developer Platform (IDP)** solves this crisis not by creating rigid ticket-based operational silos, but by providing **Golden Paths (Paved Roads)**: self-service, curated abstractions that empower engineering teams to deploy and manage production software autonomously, securely, and repetitively.

This guide outlines the modern IDP stack:

- **The Philosophy of Golden Paths**: Eliminating extraneous cognitive load while maintaining architectural standards.
- **Developer Portals (Backstage & Port)**: Software cataloging, TechDocs documentation-as-code, and automated scaffolding.
- **Declarative Infrastructure with Crossplane**: Kubernetes-native infrastructure composition that replaces fragmented Terraform glue scripts with continuous reconciliation loops.

---

## 2. Cognitive Overload & The Golden Path Philosophy

### 2.1 The Cognitive Load Crisis in Modern Software Delivery

Cognitive load theory categorizes mental effort into three domains:

1. **Intrinsic Load**: The inherent difficulty of the business problem (e.g., implementing an order payment settlement algorithm). This is where developer effort belongs.
2. **Germane Load**: Mental processing devoted to learning patterns and mastering domain models.
3. **Extraneous Load**: Mental effort wasted navigating unnecessary friction, tooling idiosyncrasies, and fragmented operational mechanics (e.g., deciphering IAM assume-role trust policies, debugging Helm indentation, or requesting database VPC peerings via Jira).

Without an IDP, developers spend upwards of $40\%$ of their sprint capacity grappling with extraneous cognitive load.

### 2.2 Golden Paths (Paved Roads) vs. Golden Cages

A **Golden Path** is an opinionated, supported, and automated route to production that solves a recurring engineering problem:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Engineering Landscape                           │
│                                                                        │
│   ┌──────────────────────────────────────────────────────────────┐     │
│   │               THE GOLDEN PATH (Paved Road)                   │     │
│   │  - Backstage Scaffolding (1-Click Repo + CI/CD Setup)        │     │
│   │  - Distroless, hardened container base images                │     │
│   │  - PSS Restricted Kubernetes manifests                       │     │
│   │  - Declarative Crossplane cloud database claims             │     │
│   │  - Automatic ArgoCD GitOps onboarding                        │     │
│   │  - Centralized OpenTelemetry instrumentation                 │     │
│   └──────────────────────────────────────────────────────────────┘     │
│                                                                        │
│   Off-Road (Supported with caveats):                                   │
│   Teams with exceptional requirements (e.g., custom GPU kernels)       │
│   may leave the path, but inherit operational responsibility.          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

#### Core Principles of the Golden Path

- **Paved, Not Enforced**: Developers are free to veer off the path if their technical requirements demand it, but doing so forfeits platform-tier SLA support.
- **Self-Service by Default**: Zero human approvals for standard operations (creating a repo, spinning up an ephemeral preview environment, provisioning a development database).
- **Security & Compliance Baked In**: Security policies (CIS benchmarks, Pod Security Standards, vulnerability gates) are active on day zero without developer intervention.
- **Continuous Golden Path Drift Correction**: The platform automatically propagates template fixes, security updates, and dependency patches back to onboarded services.

---

## 3. Developer Portals: Backstage & Port

The Developer Portal serves as the single pane of glass for engineers, uniting service metadata, team ownership, technical documentation, and software generation.

### 3.1 The Software Catalog

A unified software catalog provides an inventory of all software assets running across an organization, tracking ownership, dependencies, and APIs.

#### Backstage Entity Data Model

Backstage models software using a directed acyclic graph (DAG) of YAML entity definitions stored directly inside the service repository (`catalog-info.yaml`):

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: order-billing-service
  description: Handles PCI-compliant transaction settlements and invoicing
  annotations:
    github.com/project-slug: enterprise-org/order-billing-service
    backstage.io/techdocs-ref: dir:.
    argocd/app-name: order-billing-service-prod
    sonarqube.org/project-key: order-billing-service
    sentry.io/project-slug: billing-prod
  tags:
    - java
    - spring-boot
    - pci-dss
spec:
  type: service
  lifecycle: production
  owner: group:payment-engineering
  system: payments-ecosystem
  subcomponentOf: financial-engine
  providesApis:
    - order-billing-api
  consumesApis:
    - currency-exchange-api
  dependsOn:
    - resource:rds-postgres-billing
```

#### Catalog Entity Hierarchy

1. **Domain**: High-level business vertical (e.g., `FinTech`, `Logistics`).
2. **System**: Cohesive collection of services collaborating to achieve a business capability (e.g., `PaymentsEcosystem`).
3. **Component**: Individual software deployment unit (Service, Website, Mobile App, Batch Library).
4. **API**: Contract interface (`OpenAPI`, `gRPC`, `GraphQL`) published by a component.
5. **Resource**: External infrastructure dependency (`PostgreSQL`, `KafkaTopic`, `S3Bucket`).
6. **Group & User**: Organizational hierarchy defining code and operational ownership.

---

### 3.2 Backstage Software Templates (Scaffolder)

Backstage Software Templates allow platform engineers to publish standardized application skeletons. Instead of copy-pasting existing repositories (which propagates outdated dependencies and unpatched CVEs), developers fill out a web form that executes an automated scaffolding pipeline:

```text
Developer Input (Form)
       │
       ▼
┌────────────────────────────────────────────────────────┐
│             Backstage Scaffolder Engine                │
│                                                        │
│  1. fetch:template                                     │
│     Downloads skeleton, renders cookiecutter variables │
│                                                        │
│  2. publish:github                                     │
│     Creates repo, pushes rendered code, sets branch    │
│     protection and required CI checks                  │
│                                                        │
│  3. catalog:register                                   │
│     Registers new service in Software Catalog          │
│                                                        │
│  4. argocd:create-app (Optional)                       │
│     Generates GitOps Application in ArgoCD             │
└────────────────────────────────────────────────────────┘
```

### 3.3 Docs-like-Code with TechDocs

TechDocs treats technical documentation as code:

- Markdown files live alongside application code in a `/docs` directory inside the Git repository.
- A `mkdocs.yml` file configures navigation and rendering plugins.
- CI/CD builds static HTML assets and publishes them to an enterprise object storage bucket (e.g., S3).
- Backstage fetches, renders, and exposes centralized full-text search across all company repositories.

---

## 4. Declarative Infrastructure Composition with Crossplane

Traditional infrastructure delivery relies on Terraform or OpenTofu scripts triggered via CI/CD pipelines. In an IDP context, this approach faces three major challenges:

1. **State File Locks & Concurrency**: Multiple developers provisioning resources concurrently collide on state file locks.
2. **Lack of Continuous Reconciliation**: Terraform only runs when triggered; if an engineer manually alters an AWS RDS instance in the console, drift persists until the next manual pipeline run.
3. **Kubernetes Disconnect**: Developers must context-switch between Kubernetes manifests for their applications and HCL/Terraform files for their cloud dependencies.

Crossplane resolves these issues by extending the Kubernetes control plane into a universal cloud orchestrator.

```text
                      ┌──────────────────────────────────────────────┐
                      │            Developer Workload                │
                      │  kind: PostgreSQLInstance (Claim)            │
                      └──────────────────────┬───────────────────────┘
                                             │ Declares dependency
                                             ▼
                      ┌──────────────────────────────────────────────┐
                      │              Crossplane XRD                  │
                      │  CompositeResourceDefinition                 │
                      │  (Defines schema: storageGB, engineVersion)  │
                      └──────────────────────┬───────────────────────┘
                                             │ Maps via Composition
                                             ▼
                      ┌──────────────────────────────────────────────┐
                      │           Crossplane Composition             │
                      │  (Renders cloud-specific Managed Resources)  │
                      └──────┬───────────────────────────────┬───────┘
                             │                               │
                             ▼                               ▼
                 ┌───────────────────────┐       ┌───────────────────────┐
                 │ AWS RDS Instance (MR) │       │ Subnet Group / KMS Key│
                 └───────────┬───────────┘       └───────────┬───────────┘
                             │                               │
                             ▼                               ▼
                 ═════════════════════════════════════════════════════════
                              Amazon Web Services (AWS API)
```

### 4.1 Crossplane Resource Hierarchy

1. **Managed Resource (MR)**: A high-fidelity, 1:1 Kubernetes custom resource representing a single cloud API primitive (e.g., `rds.aws.upbound.io/v1beta1 Instance`, `storage.gcp.upbound.io/v1beta1 Bucket`).
2. **Composite Resource Definition (XRD)**: Cluster-scoped CRD defining a custom, enterprise-standard abstraction. It exposes a minimal, simplified schema while hiding cloud vendor implementation details.
3. **Composition**: The infrastructure template that fulfills an XRD. It specifies which Managed Resources to create and how to patch composite inputs (e.g., mapping `tier: small` to `instanceClass: db.t4g.small`).
4. **Composite Resource Claim (Claim / XRC)**: A namespaced custom resource created by application developers in the same namespace as their pods, requesting infrastructure as easily as a `PersistentVolumeClaim`.

### 4.2 Crossplane vs. Terraform Comparison

| Architectural Dimension | HashiCorp Terraform / OpenTofu | Crossplane |
| --- | --- | --- |
| **Control Model** | Procedural / CI/CD pipeline triggers | Declarative / Continuous control plane reconciliation loop |
| **Drift Management** | Detected only during pipeline execution | Continuously reconciled (reverted automatically) in real time |
| **Interface** | HCL (HashiCorp Configuration Language) | Native Kubernetes Custom Resources (YAML) |
| **Multi-Tenancy** | Workspace-based / Git branching | Kubernetes RBAC, Namespaces, and Claims |
| **Credential Storage** | State files (often containing plaintext secrets) | Native Kubernetes `Secrets` with RBAC and external Vault sync |
| **Self-Service Model** | PRs modifying Terraform modules | Developers declare Claims in their application GitOps manifests |

---

## 5. End-to-End Self-Service Golden Path Lifecycle

Here is the operational lifecycle of a new microservice provisioned via this IDP architecture:

```text
1. Developer opens Backstage Portal -> Selects "Hardened Go Service" Template.
2. Developer fills form:
   - Service Name: `order-checkout`
   - Owner: `team-checkout`
   - Database: `PostgreSQL` (Tier: Small)
3. Backstage Scaffolder executes:
   - Generates GitHub repository: `enterprise-org/order-checkout`
   - Commits Distroless Dockerfile, Go source code, and Helm chart.
   - Commits `PostgreSQLInstance` Claim manifest.
   - Registers service in Software Catalog (`catalog-info.yaml`).
4. ArgoCD detects new repository and creates Application:
   - Syncs Kubernetes Deployment, Service, and KEDA ScaledObject.
   - Syncs `PostgreSQLInstance` Claim into namespace `production-apps`.
5. Crossplane Operator intercepts Claim:
   - Evaluates XRD and Composition for AWS RDS.
   - Provisions AWS RDS DB instance, subnet groups, security groups, and KMS keys.
   - Emits Kubernetes Secret `order-checkout-conn-secret` containing connection strings.
6. Pod starts:
   - Injects DB secret via environment variables.
   - Enters service mesh (Cilium eBPF / Istio Ambient).
   - Starts serving traffic; KEDA scales replicas dynamically based on traffic.
```

---

## 6. Production Pitfalls & Anti-Patterns

### Anti-Patterns to Avoid

1. **Building a Portal Without a Clear Consumer**: Treating the IDP as an infrastructure playground rather than an internal software product. Always staff a dedicated Platform Team with an active Product Manager.
2. **The "Ticket Queue Behind a Portal" Trap**: Building a pretty web interface that simply generates a ServiceNow ticket for manual platform team approval defeats the purpose of self-service.
3. **Leaking Cloud-Specific Primitives to Developers**: Exposing raw Terraform or raw Crossplane Managed Resources directly to product developers re-introduces the exact cognitive overload the platform was meant to solve. Always curate XRDs.
4. **Ignoring Golden Path Maintenance**: Failing to automate version upgrades of scaffolding templates leaves newly created services immediately burdened with technical debt.
5. **Neglecting Secret Security in Claims**: Storing database passwords in plain Git. Ensure Crossplane writes connection secrets directly to cluster `Secrets` or synchronizes with External Secrets Operator (ESO) backed by Vault or AWS Secrets Manager.
