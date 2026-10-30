# ==============================================================================
# Terraform / OpenTofu Input Variables Specification
# - Strict type constraints
# - HCL validation blocks to catch misconfigurations during plan
# ==============================================================================

variable "project_name" {
  type        = string
  description = "Unique project or organization identifier (alphanumeric and dashes only)"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Target deployment environment (dev, staging, or prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "Target AWS deployment region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the Virtual Private Cloud (VPC)"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AWS Availability Zones for high availability subnet distribution"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "tags" {
  type        = map(string)
  description = "Common baseline tags applied to all provisioned cloud resources"
  default     = {}
}
