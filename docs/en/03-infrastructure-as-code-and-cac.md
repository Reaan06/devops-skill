# Infrastructure as Code, Configuration as Code & Database DevOps

## 1. Explanation: Concepts and Architecture

Infrastructure as Code (IaC) and Configuration as Code (CaC) transform physical and cloud infrastructure provisioning into software engineering disciplines. Modern cloud platforms demand strict isolation between infrastructure state, configuration drift detection, automated immutable base images, and zero-downtime database schema evolutions.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Developer Git Pull Request                        │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ CI Quality Gates: TFLint ──► Checkov (IaC SAST) ──► Infracost (FinOps) │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Merge to Trunk (TBD)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ OpenTofu 1.8+ Engine                                                   │
 │  • Client-Side Encryption (AES-GCM AEAD via KMS / PBKDF2)              │
 │  • Distributed Locking (DynamoDB / GCS Preconditions)                  │
 └─────────────────┬──────────────────────────────────┬───────────────────┘
                   │                                  │
                   ▼                                  ▼
 ┌──────────────────────────────────┐ ┌───────────────────────────────────┐
 │ Remote Object Storage (S3 / GCS) │ │ Cloud Infrastructure Provisioned  │
 │  • Server-Side KMS Encryption    │ │  • VPC, EKS, Subnets, Gateways    │
 │  • Versioning & Object Lock      │ │  • Least-Privilege IAM Roles      │
 └──────────────────────────────────┘ └───────────────────────────────────┘
                   ▲
                   │
 ┌─────────────────┴──────────────────────────────────────────────────────┐
 │ Golden Image Pipeline (Packer + Ansible CIS Hardening)                 │
 │  • Builds immutable AMIs / Base OS images without runtime SSH          │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Remote State Security and Distributed Concurrency Locking

The Terraform and OpenTofu state file contains a JSON-serialized representation of managed resources, metadata, and sensitive credentials (database passwords, private keys, resource ARNs).

#### Threat Vectors of Mismanaged State

1. **State Poisoning and Race Conditions**: Without distributed locking, concurrent executions of `apply` in automated CI pipelines interleave state modifications, leading to corrupted state trees and orphaned cloud resources.
2. **Credential Exposure**: Default state files store resource attributes in plain text. Storing state in unencrypted storage or committing it to Git exposes production secrets.
3. **Accidental Deletion**: Object storage without versioning risks permanent infrastructure record destruction on accidental overwrite.

#### State Storage Matrix across Cloud Providers

| Cloud Provider | Storage Backend | Locking Mechanism | Encryption Standard |
| :--- | :--- | :--- | :--- |
| **AWS** | Amazon S3 (Versioned, Private) | DynamoDB Table (`LockID` partition key) | AWS KMS Customer Managed Keys (CMK) |
| **Google Cloud** | Google Cloud Storage (GCS) | Native generation preconditions (`x-goog-if-generation-match`) | Cloud KMS Customer Managed Encryption Keys (CMEK) |
| **Microsoft Azure** | Azure Blob Storage | Native Blob Leases | Azure Key Vault Customer-Managed Keys |

### 1.2 OpenTofu Native Client-Side State Encryption

Historically, Terraform relied exclusively on cloud storage server-side encryption (SSE). While SSE protects data at rest in the storage bucket, the state payload travels unencrypted over the wire and remains readable by any identity possessing read access to the storage bucket.

OpenTofu 1.7+ and 1.8+ introduce **native client-side encryption** (`encryption { ... }`). The OpenTofu engine encrypts both the state file and the binary plan file locally using AES-GCM (256-bit AEAD) before transmission to the remote backend. Even if a storage bucket is compromised, state contents remain unreadable without access to the designated KMS key or passphrase.

### 1.3 Configuration as Code (CaC): Immutable Golden Images

Traditional infrastructure operations relied on mutable configuration management (running Chef, Puppet, or Ansible against live production virtual machines). This model introduces **configuration drift**, where machines launched from the same initial template diverge over time due to partial package updates and manual administrator interventions.

Modern CaC enforces **Immutable Infrastructure**:
1. **HashiCorp Packer** launches an ephemeral build instance.
2. **Ansible** provisions software packages, configures kernel parameters according to CIS Benchmarks, and locks down the OS.
3. The build instance is snapshot into an Amazon Machine Image (AMI) or cloud image.
4. Production auto-scaling groups deploy the immutable image without allowing inbound SSH or ad-hoc remote modification.

### 1.4 Database DevOps (DBDevOps) & The Expand/Contract Pattern

Stateless application containers can be destroyed, restarted, or traffic-shifted instantly. In contrast, relational databases (PostgreSQL, MySQL) store persistent state and enforce relational schemas. Uncoordinated schema modifications frequently acquire `ACCESS EXCLUSIVE` table locks, blocking all read and write queries and causing system-wide outages.

#### The Three-Phase Expand/Contract Pattern

```text
Phase 1: Expand
┌───────────────────────┐       Both columns exist. Application writes to
│ users:                │       both 'name' and ('first_name', 'last_name').
│  - name (legacy)      │◄───── Reads fall back to 'name' if new columns null.
│  - first_name (new)   │
│  - last_name (new)    │
└───────────────────────┘

Phase 2: Transition
┌───────────────────────┐       Background worker backfills legacy rows.
│ Background Backfill   │──────►All application instances updated to read
│ & Dual-Write          │       exclusively from ('first_name', 'last_name').
└───────────────────────┘

Phase 3: Contract
┌───────────────────────┐       Safe removal of legacy column.
│ users:                │◄───── No running application reads or writes
│  - first_name         │       to 'name'.
│  - last_name          │
└───────────────────────┘
```

#### Database Schema Tooling Comparison

| Engine | Paradigm | Lock Safety & Linting | Execution Method | State Tracking |
| :--- | :--- | :--- | :--- | :--- |
| **Ariga Atlas** | Declarative (HCL/SQL) & Versioned | Native AST static analysis and lock detection | Standalone Go CLI / K8s Operator | `atlas_schema_revisions` table |
| **Flyway** | Imperative (Versioned SQL) | Paid enterprise add-on checks | Java CLI / Docker / K8s Job | `flyway_schema_history` table |
| **Liquibase** | Declarative / Imperative (YAML, XML, SQL) | Configurable quality checks ruleset | Java CLI / Docker / K8s Job | `DATABASECHANGELOG` table |

---

## 2. Practical Guides: Production IaC, CaC, and DBDevOps Blueprints

### 2.1 AWS S3 & DynamoDB Remote State Backend

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket         = "enterprise-tfstate-production-us-east-1"
    key            = "workloads/core-infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:111122223333:key/mrk-tfstate-key"
    dynamodb_table = "enterprise-tfstate-locks-production"
  }
}
```

### 2.2 OpenTofu 1.8+ Native Client-Side State Encryption Configuration

This block enforces AES-GCM encryption on state files and plan outputs before they leave the executing runner:

```hcl
terraform {
  required_version = ">= 1.8.0"

  encryption {
    key_provider "pbkdf2" "ci_passphrase" {
      passphrase    = var.state_passphrase
      key_length    = 32
      iterations    = 600000
      salt_length   = 32
      hash_function = "sha512"
    }

    method "aes_gcm" "state_encryption" {
      keys = key_provider.pbkdf2.ci_passphrase
    }

    state {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }
  }
}
```

### 2.3 Immutable Golden AMI Template with Packer and Ansible

Automate CIS Benchmark hardening for Amazon Linux 2023 base images:

```hcl
packer {
  required_version = ">= 1.9.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "amazon-ebs" "hardened_node" {
  ami_name      = "golden-ami-al2023-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  instance_type = "t3.medium"
  region        = "us-east-1"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"]
  }

  ssh_username = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name       = "golden-ami-al2023"
    Hardened   = "true"
    ManagedBy  = "packer"
    Compliance = "CIS-Level-1"
  }
}

build {
  name    = "build-hardened-ami"
  sources = ["source.amazon-ebs.hardened_node"]

  provisioner "ansible" {
    playbook_file = "${path.root}/ansible-baseline-hardening.yml"
    user          = "ec2-user"
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
}
```

### 2.4 Declarative Database Schema CI/CD with Ariga Atlas

Manage database schemas declaratively with automated safety checks in `atlas.hcl`:

```hcl
variable "db_url" {
  type    = string
  default = "postgres://postgres:password@localhost:5432/app_db?sslmode=disable"
}

env "production" {
  src = "file://schema.sql"
  url = var.db_url
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir    = "file://migrations"
    format = atlas
  }

  lint {
    destructive {
      error = true
    }
    concurrent_index {
      error = true
    }
    data_depend {
      error = true
    }
  }
}
```

### 2.5 Kubernetes PreSync Database Migration Job (Flyway)

Integrate database schema upgrades cleanly into GitOps workflows using ArgoCD PreSync hooks:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: schema-migration-v2-4
  namespace: production-apps
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
      containers:
        - name: flyway-migration
          image: flyway/flyway:10-alpine
          args:
            - -url=jdbc:postgresql://postgres-ha.database.svc.cluster.local:5432/app_db
            - -user=migration_runner
            - -connectRetries=10
            - migrate
          env:
            - name: FLYWAY_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: migration-password
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

---

## 3. Operational Reference: Commands and Workflows

### 3.1 OpenTofu & Terraform Execution Workflow

```bash
# Initialize backend and download provider plugins
tofu init -reconfigure

# Format code according to canonical style
tofu fmt -check -recursive

# Validate syntactic and semantic correctness
tofu validate

# Generate deterministic execution plan
tofu plan -out=production.tfplan -input=false

# Apply validated plan with concurrency controls
tofu apply -input=false production.tfplan
```

### 3.2 Security and FinOps Validation Suite

Execute shift-left testing before submitting Pull Requests:

```bash
# Lint Terraform code for deprecated syntax and provider antipatterns
tflint --init
tflint --recursive

# Scan IaC manifests for security vulnerabilities and CIS benchmark failures
checkov --directory . \
  --framework terraform \
  --output cli \
  --soft-fail=false

# Calculate financial impact and budget delta
infracost breakdown --path .
```

### 3.3 State Disaster Recovery & Lock Troubleshooting

If an automated CI pipeline fails or crashes mid-execution, the remote backend lock may remain active, blocking subsequent deployments.

```bash
# Inspect current state file content
tofu state pull > recovered-state.json

# Identify active lock ID from error message
# Error: Error acquiring the state lock: ConditionalCheckFailedException
# Lock Info: ID: 5f98a72b-426c-d1e9-9fa1-0123456789ab

# Release lock forcefully after confirming no other apply job is running
tofu force-unlock 5f98a72b-426c-d1e9-9fa1-0123456789ab
```

### 3.4 Atlas Database Schema Workflow

```bash
# Generate versioned migration script by diffing declarative schema against migrations/
atlas migrate diff add_orders_table \
  --dir "file://migrations" \
  --to "file://schema.sql" \
  --dev-url "docker://postgres/16/dev?search_path=public"

# Run automated safety checks in CI
atlas migrate lint \
  --dir "file://migrations" \
  --dev-url "docker://postgres/16/dev?search_path=public" \
  --latest 1

# Apply pending migrations to target database
atlas migrate apply \
  --dir "file://migrations" \
  --url "$DATABASE_URL"
```

---

## 4. Reference Mapping and Standards

### 4.1 Repository Templates Reference

| Component | Path | Description |
| :--- | :--- | :--- |
| AWS S3 & DynamoDB Backend | `templates/terraform/backend-s3-dynamodb.tf` | Encrypted S3 backend with DynamoDB locking |
| GCS Backend | `templates/terraform/backend-gcs.tf` | GCP Cloud Storage backend with CMEK |
| Azure Backend | `templates/terraform/backend-azurerm.tf` | Azure Blob Storage backend with native leases |
| OpenTofu State Encryption | `templates/terraform/opentofu-state-encryption.tf` | Native client-side AES-GCM state encryption |
| Packer Golden AMI | `templates/cac/packer-golden-ami.pkr.hcl` | Hardened Amazon Linux 2023 AMI builder |
| Ansible Hardening Baseline | `templates/cac/ansible-baseline-hardening.yml` | CIS Level 1 OS configuration automation |
| Atlas Migration Config | `templates/dbdevops/atlas-migration.hcl` | Declarative schema diffing with safety linting |
| Flyway Migration Job | `templates/dbdevops/flyway-migration-job.yaml` | Kubernetes PreSync batch migration job |

### 4.2 Compliance Standards

- **CIS Amazon Web Services Foundations Benchmark v3.0.0**:
  - Control 2.1.1: Ensure all S3 buckets employ encryption-at-rest with Customer Managed Keys.
  - Control 2.1.2: Ensure S3 Bucket Policy enforces `aws:SecureTransport`.
  - Control 2.1.5: Ensure S3 Bucket Public Access Block is enabled.
- **CIS Operating System Benchmarks (Level 1 Server)**:
  - Disabling unnecessary filesystems and kernel modules (`cramfs`, `squashfs`).
  - Restricting core dumps and enabling ASLR (`fs.suid_dumpable = 0`).
  - SSH daemon hardening (disabling root login, password authentication, and weak ciphers).
