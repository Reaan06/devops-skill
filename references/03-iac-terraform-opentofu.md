# Infrastructure as Code with Terraform & OpenTofu

## 1. Executive Overview

Infrastructure as Code (IaC) in 2025/2026 demands strict isolation between infrastructure state, configuration, and execution privileges. Whether using **OpenTofu** (the Linux Foundation open-source fork) or **HashiCorp Terraform**, production architectures must enforce:

1. **State Immutability & Encryption**: Remote state stored in object storage with server-side Customer Managed Keys (AWS KMS / GCP Cloud KMS), object versioning, and strict access controls.
2. **Distributed Concurrency Locking**: State locking via DynamoDB or native state locking to prevent concurrent apply race conditions and state corruption.
3. **Clean Modular Hierarchy**: Separation of reusable modules from root deployment environments (`dev`, `staging`, `prod`), avoiding monolithic state files.
4. **Shift-Left Static Analysis**: Automated linting with `tflint`, code formatting enforcement (`tofu/terraform fmt -check`), and security vulnerability / misconfiguration scanning with `trivy config`.

---

## 2. Remote State & Distributed Locking

The Terraform/OpenTofu state file contains a complete mapping of your declared configuration to physical cloud resources. It frequently contains sensitive data (database passwords, generated keys, resource IDs) in unencrypted JSON.

### 2.1 Threat Vectors of Local or Unencrypted State

- **State File Poisoning**: Concurrent developers or CI jobs executing `terraform apply` simultaneously will interleave writes, leading to state corruption and orphaned cloud resources.
- **Credential Exposure**: Committing `terraform.tfstate` to Git exposes plain-text credentials and secrets.
- **Accidental Deletion**: Lack of object versioning means a failed write or accidental delete permanently destroys the infrastructure map.

### 2.2 S3 + DynamoDB Locking Pattern

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

#### S3 Bucket Security Baseline Requirements

1. **Server-Side Encryption with KMS**: Enforce AWS KMS customer-managed key (CMK) encryption. Disable legacy SSE-S3.
2. **Versioning Enabled**: Protects against accidental deletion and provides audit history of state changes over time.
3. **Public Access Block**: Block all four S3 public access settings (`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicBuckets`).
4. **Bucket Policy Restricting Transport**: Require TLS 1.2+ via `aws:SecureTransport` conditional policies.
5. **DynamoDB Lock Table**: A table with primary partition key `LockID` of type `String`.

---

## 3. Clean Modular Architecture

A maintainable IaC codebase separates **reusable building blocks** (modules) from **stateful deployment targets** (live environments).

### 3.1 Recommended Repository Layout

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

### 3.2 Principles of Module Design

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

## 4. Static Linting & Security Scanning

Integrating static analysis into developer pre-commit hooks and CI/CD pull request gates prevents syntax errors, deprecated provider arguments, and misconfigurations from ever reaching code review.

### 4.1 TFLint Configuration (`.tflint.hcl`)

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

### 4.2 Security & Misconfiguration Gating with Trivy

Trivy parses HCL directly without requiring cloud credentials, detecting insecure defaults (e.g., unencrypted EBS volumes, open security groups, missing logging):

```bash
trivy config \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --ignorefile .trivyignore \
  .
```

---

## 5. Execution Lifecycle & CI/CD Guardrails

Never run `apply` directly from developer workstations in production. Enforce automated pipelines:

1. **Pull Request Trigger**:
   - `tofu fmt -check`
   - `tflint`
   - `trivy config`
   - `tofu plan -no-color -out=tfplan`
   - Post sanitized plan summary as a pull request comment.
2. **Main Branch Merge**:
   - Apply only the previously approved plan artifact (`tofu apply tfplan`).
   - Store deployment logs in a centralized, immutable audit store.
