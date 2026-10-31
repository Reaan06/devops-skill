# ==============================================================================
# Enterprise Azure Resource Manager (ARM) Remote State Backend Infrastructure
# - Azure Resource Group and Storage Account with Zone-Redundant Storage (ZRS/GRS)
# - Enforced TLS 1.2 minimum version, disabled public access, and HTTPS-only traffic
# - Customer-Managed Keys (CMK) backed by Azure Key Vault with Purge Protection
# - Blob versioning, soft-delete retention, and native Azure Blob Leasing for locking
# - Workload Identity / OIDC passwordless authentication support
# ==============================================================================

# ------------------------------------------------------------------------------
# Resource Group for State Storage
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.project_name}-tfstate-${var.environment}"
  location = var.azure_region

  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# User-Assigned Managed Identity for Storage Encryption Access
# ------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "tfstate_storage" {
  name                = "uai-${var.project_name}-tfstate-${var.environment}"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Azure Key Vault for Customer-Managed Keys (CMK)
# ------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "tfstate" {
  name                       = "kv-${substr(replace(var.project_name, "-", ""), 0, 12)}-state-${var.environment}"
  location                   = azurerm_resource_group.tfstate.location
  resource_group_name        = azurerm_resource_group.tfstate.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  rbac_authorization_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Key Vault Key for Storage Account Server-Side Encryption
resource "azurerm_key_vault_key" "tfstate" {
  name         = "key-${var.project_name}-tfstate-${var.environment}"
  key_vault_id = azurerm_key_vault.tfstate.id
  key_type     = "RSA"
  key_size     = 4096

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Grant Storage Identity Key Vault Crypto Service Encryption User role
resource "azurerm_role_assignment" "storage_cmk_user" {
  scope                = azurerm_key_vault.tfstate.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.tfstate_storage.principal_id
}

# ------------------------------------------------------------------------------
# Azure Storage Account & Blob Container for Remote State
# ------------------------------------------------------------------------------

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${substr(replace(var.project_name, "-", ""), 0, 10)}tfstate${var.environment}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS" # Geo-Redundant storage for disaster recovery
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true # Restrict with network_rules in hardened environments

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.tfstate_storage.id]
  }

  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.tfstate.id
    user_assigned_identity_id = azurerm_user_assigned_identity.tfstate_storage.id
  }

  blob_properties {
    # Protect state history against accidental deletion or corruption
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    azurerm_role_assignment.storage_cmk_user
  ]
}

# Dedicated Container for Terraform / OpenTofu state files
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ------------------------------------------------------------------------------
# Regional Variable Specification
# ------------------------------------------------------------------------------
variable "azure_region" {
  type        = string
  description = "Target Azure region for state storage and Key Vault"
  default     = "eastus"
}

# ==============================================================================
# Example Backend Configuration (Include in your environment's versions.tf / backend.tf)
# Azure Storage natively handles distributed state locking via Azure Blob Leases
# during terraform plan/apply, preventing concurrent modifications without DynamoDB.
# ==============================================================================
#
# terraform {
#   required_version = ">= 1.8.0"
#
#   backend "azurerm" {
#     resource_group_name  = "rg-myproject-tfstate-prod"
#     storage_account_name = "stmyprojecttfstateprod"
#     container_name       = "tfstate"
#     key                  = "workloads/production-api/terraform.tfstate"
#     use_oidc             = true
#     use_azuread_auth     = true
#     tenant_id            = "00000000-0000-0000-0000-000000000000"
#     subscription_id      = "00000000-0000-0000-0000-000000000000"
#     client_id            = "00000000-0000-0000-0000-000000000000"
#   }
# }
