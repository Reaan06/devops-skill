# ==============================================================================
# Terraform / OpenTofu Outputs Specification
# ==============================================================================

output "vpc_id" {
  description = "Identifier of the provisioned Virtual Private Cloud"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets across availability zones"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets for workloads and compute"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ip" {
  description = "Public IPv4 address of the NAT Gateway for outbound egress"
  value       = aws_eip.nat.public_ip
}

output "state_bucket_arn" {
  description = "ARN of the encrypted S3 bucket hosting remote state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_lock_table_name" {
  description = "Name of the DynamoDB table managing distributed state locks"
  value       = aws_dynamodb_table.terraform_locks.name
}
