# ==============================================================================
# OpenTofu 1.7+ / 1.8+ Native Client-Side State & Plan Encryption
# - Protects sensitive state data and plan files locally and remotely
# - Zero-trust end-to-end encryption before transmission to remote backend storage
# - Key providers: PBKDF2 passphrase (local/CI) and Cloud KMS (AWS KMS, GCP KMS)
# - Enforced AES-GCM (256-bit) authenticated encryption for both state and plan files
# ==============================================================================

terraform {
  required_version = ">= 1.8.0"

  encryption {
    # --------------------------------------------------------------------------
    # Key Provider 1: Passphrase-derived Key (PBKDF2 with SHA-512)
    # Suitable for developer workstations, local testing, and CI/CD secret injection.
    # OpenTofu also supports environment variable injection via:
    # TF_ENCRYPTION_KEY_PROVIDER_PBKDF2_PASSPHRASE
    # --------------------------------------------------------------------------
    key_provider "pbkdf2" "passphrase" {
      passphrase    = var.state_passphrase
      key_length    = 32     # 256-bit symmetric encryption key
      iterations    = 600000 # High work factor against brute-force attacks
      salt_length   = 32
      hash_function = "sha512"
    }

    # --------------------------------------------------------------------------
    # Key Provider 2 (Enterprise Alternative): AWS KMS Key Provider
    # Automatically requests data keys from AWS KMS with IAM least-privilege.
    # --------------------------------------------------------------------------
    # key_provider "aws_kms" "aws_key" {
    #   kms_key_id = "arn:aws:kms:us-east-1:111122223333:key/12345678-1234-1234-1234-123456789abc"
    #   region     = "us-east-1"
    #   key_spec   = "AES_256"
    # }

    # --------------------------------------------------------------------------
    # Key Provider 3 (Enterprise Alternative): Google Cloud KMS Key Provider
    # Uses GCP Cloud KMS CryptoKey to protect state files with CMEK.
    # --------------------------------------------------------------------------
    # key_provider "gcp_kms" "gcp_key" {
    #   kms_encryption_key = "projects/my-gcp-project/locations/us-central1/keyRings/tf-keyring/cryptoKeys/tf-state-key"
    #   key_length         = 32
    # }

    # --------------------------------------------------------------------------
    # Encryption Method: AES-GCM Authenticated Encryption with Associated Data (AEAD)
    # References the primary active key provider.
    # --------------------------------------------------------------------------
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.passphrase
      # For AWS KMS: keys = key_provider.aws_kms.aws_key
      # For GCP KMS: keys = key_provider.gcp_kms.gcp_key
    }

    # --------------------------------------------------------------------------
    # State File Encryption Target
    # Enforces encryption on both local terraform.tfstate and remote backend state.
    # Unencrypted reads or writes are strictly blocked when enforced = true.
    # --------------------------------------------------------------------------
    state {
      method   = method.aes_gcm.main
      enforced = true

      # Fallback configuration for zero-downtime key rotation:
      # fallback {
      #   method = method.aes_gcm.legacy_key
      # }
    }

    # --------------------------------------------------------------------------
    # Plan File Encryption Target
    # Ensures binary plan artifacts (-out=tfplan) containing sensitive resources
    # and secret variable values are encrypted before hitting disk or CI artifacts.
    # --------------------------------------------------------------------------
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

# ------------------------------------------------------------------------------
# Passphrase Input Variable (Required if using PBKDF2 provider)
# ------------------------------------------------------------------------------
variable "state_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu client-side PBKDF2 state and plan encryption"
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "The state encryption passphrase must be at least 16 characters long."
  }
}
