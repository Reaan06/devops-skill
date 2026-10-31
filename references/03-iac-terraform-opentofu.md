# Infrastructure as Code with Terraform & OpenTofu

## 1. Executive Overview

Infrastructure as Code (IaC) in 2025/2026 demands strict isolation between infrastructure state, configuration, and execution privileges. Whether using **OpenTofu** (the Linux Foundation open-source fork) or **HashiCorp Terraform**, production architectures must enforce:

1. **State Immutability & Encryption**: Remote state stored in object storage with server-side Customer Managed Keys (AWS KMS, GCP Cloud KMS, Azure Key Vault), object versioning, and strict access controls.
2. **Native Client-Side State Encryption**: End-to-end payload and plan file encryption using OpenTofu 1.7+/1.8+ native client-side encryption blocks (`encryption { ... }`), guaranteeing zero-trust isolation even from cloud storage administrators.
3. **Distributed Concurrency Locking**: State locking via DynamoDB, GCS generation preconditions, or Azure Blob Storage leases to eliminate concurrent apply race conditions and state corruption.
4. **Clean Modular Hierarchy**: Separation of reusable modules from root deployment environments (`dev`, `staging`, `prod`), avoiding monolithic state files.
5. **FinOps & Security Shift-Left**: Automated cost estimation diffs on Pull Requests with Infracost, static policy scanning with Checkov and Trivy, and linting with TFLint.

---

## 2. Remote State & Distributed Locking Across Multicloud

The Terraform/OpenTofu state file contains a complete mapping of declared configuration to physical cloud resources. It frequently contains sensitive data (database passwords, generated TLS private keys, resource identifiers) in JSON format.

### 2.1 Threat Vectors of Local or Unencrypted State

- **State File Poisoning**: Concurrent developers or CI jobs executing `terraform apply` simultaneously interleave writes, leading to state corruption and orphaned cloud resources.
- **Credential Exposure**: Committing `terraform.tfstate` to Git exposes plain-text credentials and secrets.
- **Accidental Deletion**: Lack of object versioning means a failed write or accidental delete permanently destroys the infrastructure map.
- **Cloud Provider Storage Exposure**: Relying solely on default cloud-provider server-side encryption leaves state vulnerable if storage access policies are misconfigured.

### 2.2 AWS S3 + DynamoDB Locking Pattern

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
    bucket         = "corp-terraform-state-prod-us-east-1"
    key            = "workloads/backend-api/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:111122223333:key/mrk-state-encryption-key"
    dynamodb_table = "corp-terraform-locks-prod"
  }
}
```

#### S3 Security Baseline Requirements

1. **Server-Side Encryption with KMS**: Enforce AWS KMS customer-managed key (CMK) encryption. Disable legacy SSE-S3.
2. **Versioning Enabled**: Protects against accidental deletion and provides audit history of state changes over time.
3. **Public Access Block**: Block all four S3 public access settings (`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicBuckets`).
4. **Bucket Policy Restricting Transport**: Require TLS 1.2+ via `aws:SecureTransport` conditional policies.
5. **DynamoDB Lock Table**: A table with primary partition key `LockID` of type `String`.

### 2.3 Google Cloud Storage (GCS) + CMEK Locking Pattern

Google Cloud Storage provides native distributed state locking through object generation preconditions (`x-goog-if-generation-match`), removing the requirement for a separate lock database like DynamoDB.

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {
    bucket                      = "mycorp-terraform-state-prod"
    prefix                      = "workloads/production-api"
    kms_encryption_key          = "projects/my-gcp-project/locations/us-central1/keyRings/mycorp-tfstate-keyring-prod/cryptoKeys/mycorp-tfstate-key-prod"
    impersonate_service_account = "terraform-deployer@my-gcp-project.iam.gserviceaccount.com"
  }
}
```

#### GCS Security Baseline Requirements

1. **Uniform Bucket-Level Access**: Enforce `uniform_bucket_level_access = true` to disable legacy object ACLs and unify IAM control.
2. **Customer-Managed Encryption Keys (CMEK)**: Integrate with Cloud KMS symmetric keys with 90-day automatic rotation.
3. **Object Versioning & Lifecycle Rules**: Retain at least 10 noncurrent state versions for rollback and disaster recovery.
4. **Public Access Prevention**: Set `public_access_prevention = "enforced"` at the bucket resource level.
5. **Service Account Impersonation**: Leverage Workload Identity Federation / OIDC with short-lived tokens instead of exporting static service account JSON keys.

### 2.4 Azure Storage (ARM) + Key Vault CMK & Blob Lease Locking Pattern

Azure Resource Manager remote backend uses Azure Blob Storage containers, where distributed locking is handled natively through Azure Blob Leases without third-party services.

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "azurerm" {
    resource_group_name  = "rg-myproject-tfstate-prod"
    storage_account_name = "stmyprojecttfstateprod"
    container_name       = "tfstate"
    key                  = "workloads/production-api/terraform.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
    tenant_id            = "00000000-0000-0000-0000-000000000000"
    subscription_id      = "00000000-0000-0000-0000-000000000000"
    client_id            = "00000000-0000-0000-0000-000000000000"
  }
}
```

#### Azure Storage Security Baseline Requirements

1. **Enforce TLS 1.2+ & HTTPS Only**: Configure `min_tls_version = "TLS1_2"` and `https_traffic_only_enabled = true`.
2. **Customer-Managed Key (CMK)**: Store encryption keys in Azure Key Vault with `purge_protection_enabled = true` and `soft_delete_retention_days = 90`.
3. **Blob Versioning & Soft Delete**: Protect against accidental deletion or ransomware overwrites with a minimum 30-day retention window.
4. **Keyless Authentication via OIDC**: Utilize `use_oidc = true` and Microsoft Entra Workload Identity Federation to eliminate static client secrets.

---

## 3. OpenTofu Native Client-Side State & Plan Encryption (1.7+ / 1.8+)

Starting with version 1.7.0 and refined in 1.8+, OpenTofu introduced **native end-to-end client-side encryption**. This architectural enhancement addresses the fundamental flaw of legacy Terraform: sensitive data was encrypted only at rest in the storage backend, leaving it vulnerable during transit or inside plan files.

### 3.1 Architectural Advantages

- **Client-Side Encryption**: State data is encrypted by the OpenTofu binary *before* transmission over the network or writing to remote storage.
- **Plan File Protection**: Output artifacts generated via `tofu plan -out=tfplan` are fully encrypted, preventing credential leakage in CI/CD build artifacts.
- **Zero-Trust Storage Layer**: Even a compromised cloud bucket or storage administrator cannot inspect the contents of `terraform.tfstate`.

### 3.2 Native Encryption Configuration Example

```hcl
terraform {
  required_version = ">= 1.8.0"

  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase    = var.state_passphrase
      key_length    = 32     # 256-bit symmetric encryption
      iterations    = 600000 # High resistance to offline brute-force
      salt_length   = 32
      hash_function = "sha512"
    }

    # Enterprise alternative with AWS KMS:
    # key_provider "aws_kms" "aws_key" {
    #   kms_key_id = "arn:aws:kms:us-east-1:111122223333:key/12345678-..."
    #   region     = "us-east-1"
    #   key_spec   = "AES_256"
    # }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.main
      enforce  = true
    }

    plan {
      method   = method.aes_gcm.main
      enforce  = true
    }
  }
}
```

### 3.3 Zero-Downtime Key Rotation

When rotating state encryption keys, OpenTofu allows configuring a `fallback` method within the `state` block. OpenTofu decrypts historical state using the fallback key and automatically re-encrypts the new state using the primary method on the next `tofu apply`.

---

## 4. Clean Modular Architecture

A maintainable IaC codebase separates **reusable building blocks** (modules) from **stateful deployment targets** (live environments).

### 4.1 Recommended Repository Layout

```text
infrastructure/
├── modules/
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── eks-cluster/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
└── environments/
    ├── dev/
    │   ├── main.tf
    │   ├── backend.tf
    │   ├── terraform.tfvars
    │   └── versions.tf
    └── prod/
        ├── main.tf
        ├── backend.tf
        ├── terraform.tfvars
        └── versions.tf
```

### 4.2 Principles of Module Design

1. **Explicit Inputs and Outputs**: Never use undeclared variable defaults for critical attributes like CIDR blocks or cluster names.
2. **Tagging Standards**: Every resource must support customizable tags, enforcing standard schema (`Environment`, `Owner`, `ManagedBy`, `CostCenter`).
3. **No Hardcoded Credentials or IDs**: All VPC IDs, subnet IDs, and AMI numbers must be queried via `data` sources or passed as typed input variables.
4. **Validation Blocks**: Utilize HCL `validation` blocks on variables to catch invalid inputs during `plan`:

```hcl
variable "environment" {
  type        = string
  description = "Target deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "The environment variable must be one of: dev, staging, prod."
  }
}

variable "cidr_block" {
  type        = string
  description = "VPC IPv4 CIDR block"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "Must be a valid IPv4 CIDR address format (e.g. 10.0.0.0/16)."
  }
}
```

---

## 5. Static Linting & Security Scanning

Integrating static analysis into developer pre-commit hooks and CI/CD pull request gates prevents syntax errors, deprecated provider arguments, and misconfigurations from reaching code review.

### 5.1 TFLint Configuration (`.tflint.hcl`)

`tflint` finds bugs, enforces naming conventions, and validates cloud-provider-specific attributes that `terraform validate` misses:

```hcl
config {
  call_module_type = "local"
  force            = false
}

plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Environment", "ManagedBy", "CostCenter"]
}
```

Execute in CI:

```bash
tflint --init
tflint --config .tflint.hcl --recursive
```

### 5.2 Vulnerability & Configuration Gating with Trivy

Trivy parses HCL directly without requiring cloud credentials, detecting insecure defaults (e.g., unencrypted EBS volumes, open security groups, missing logging):

```bash
trivy config \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --ignorefile .trivyignore \
  .
```

### 5.3 Deep IaC Security & Policy Compliance with Checkov

Checkov (by Bridgecrew/Palo Alto) is a static code analysis tool for infrastructure as code. It scans Terraform plans, Kubernetes manifests, Helm charts, and Dockerfiles against hundreds of built-in policies adhering to CIS Benchmarks, NIST, and HIPAA.

In corporate CI/CD pipelines, Checkov exports results as SARIF (Static Analysis Results Interchange Format) to surface findings directly inside the GitHub Security tab:

```bash
checkov --directory . \
        --framework terraform,kubernetes,dockerfile \
        --output cli \
        --output sarif \
        --output-file-path console,checkov-results.sarif \
        --soft-fail false
```

---

## 6. FinOps Shift-Left with Infracost

Preventing cloud infrastructure budget overruns requires evaluating cost impact *before* provisioning resources. Infracost analyzes Terraform code and pull requests to calculate estimated monthly expenditure deltas.

### 6.1 Shift-Left Cost Analysis Flow

1. **Pull Request Trigger**: Infracost checks out the base branch (e.g., `main`) and generates a baseline cost breakdown.
2. **Diff Calculation**: Infracost parses the PR branch changes and calculates the delta in monthly cloud costs.
3. **PR Feedback**: An automated comment is posted or updated directly on the pull request with line-item breakdowns of added, modified, or removed costs.
4. **Budget Policy Enforcement**: If a pull request exceeds a predetermined monthly spending limit (e.g., +$500/month), the workflow can fail the check or require explicit FinOps approval.

```bash
# Generate baseline cost from base branch
infracost breakdown --path=/path/to/base --format=json --out-file=base.json

# Calculate delta on current branch
infracost diff --path=. --format=json --compare-to=base.json --out-file=diff.json

# Post PR comment
infracost comment github --path=diff.json \
                         --repo=$GITHUB_REPOSITORY \
                         --github-token=$GITHUB_TOKEN \
                         --pull-request=$PR_NUMBER \
                         --behavior=update
```

---

## 7. Execution Lifecycle & CI/CD Guardrails

Never run `apply` directly from developer workstations in production. Enforce automated pipelines:

1. **Pull Request Trigger**:
   - `tofu fmt -check`
   - `tflint`
   - `checkov` & `trivy config` (SARIF upload to GitHub Security)
   - `infracost diff` (post cost delta comment)
   - `tofu plan -no-color -out=tfplan`
   - Post sanitized plan summary as a pull request comment.
2. **Main Branch Merge**:
   - Apply only the previously approved plan artifact (`tofu apply tfplan`).
   - Store deployment logs in a centralized, immutable audit store.
