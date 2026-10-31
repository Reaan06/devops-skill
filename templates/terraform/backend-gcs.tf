# ==============================================================================
# Enterprise Google Cloud Storage (GCS) Remote State Backend Infrastructure
# - GCS Bucket with Uniform Bucket-Level Access and Object Versioning
# - Customer-Managed Encryption Key (CMEK) via Cloud KMS with automatic rotation
# - Prevention of accidental bucket destruction
# - Public access prevention enforced
# - Lifecycle rules for noncurrent state version expiration
# ==============================================================================

# ------------------------------------------------------------------------------
# Google Cloud KMS: Customer-Managed Encryption Key (CMEK)
# ------------------------------------------------------------------------------

resource "google_kms_key_ring" "terraform_state" {
  name     = "${var.project_name}-tfstate-keyring-${var.environment}"
  location = var.gcp_region

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "terraform_state" {
  name            = "${var.project_name}-tfstate-key-${var.environment}"
  key_ring        = google_kms_key_ring.terraform_state.id
  rotation_period = "7776000s" # 90 days automatic key rotation
  purpose         = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Fetch Google Cloud Storage project service agent
data "google_storage_project_service_account" "gcs_account" {
}

# Grant GCS service agent Decrypter/Encrypter permissions on the CMEK key
resource "google_kms_crypto_key_iam_member" "gcs_kms_binding" {
  crypto_key_id = google_kms_crypto_key.terraform_state.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# ------------------------------------------------------------------------------
# GCS Bucket for Terraform / OpenTofu Remote State
# ------------------------------------------------------------------------------

resource "google_storage_bucket" "terraform_state" {
  name                        = "${var.project_name}-terraform-state-${var.environment}"
  location                    = var.gcp_region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Enforce versioning to protect state history against accidental deletion/overwrite
  versioning {
    enabled = true
  }

  # Enforce Customer-Managed Encryption Keys (CMEK)
  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state.id
  }

  # Retain historical state versions for audit and rollback; prune stale noncurrent versions
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions         = 10
      days_since_noncurrent_time = 90
    }
  }

  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = true
  }

  labels = merge(
    var.tags,
    {
      name        = "${var.project_name}-terraform-state-${var.environment}"
      environment = var.environment
      managed_by  = "terraform"
    }
  )

  depends_on = [
    google_kms_crypto_key_iam_member.gcs_kms_binding
  ]
}

# ------------------------------------------------------------------------------
# Regional Variable Specification
# ------------------------------------------------------------------------------
variable "gcp_region" {
  type        = string
  description = "Target Google Cloud region for state storage and KMS keyring"
  default     = "us-central1"
}

# ==============================================================================
# Example Backend Configuration (Include in your environment's versions.tf / backend.tf)
# GCS natively handles distributed state locking via Google Cloud Storage
# object generation preconditions (if-generation-match), requiring no external
# lock table database.
# ==============================================================================
#
# terraform {
#   required_version = ">= 1.8.0"
#
#   backend "gcs" {
#     bucket                      = "mycorp-terraform-state-prod"
#     prefix                      = "workloads/production-api"
#     kms_encryption_key          = "projects/my-gcp-project/locations/us-central1/keyRings/mycorp-tfstate-keyring-prod/cryptoKeys/mycorp-tfstate-key-prod"
#     impersonate_service_account = "terraform-deployer@my-gcp-project.iam.gserviceaccount.com"
#   }
# }
