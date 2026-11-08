output "vpc_id" {
  description = "Shared VPC"
  value       = data.aws_ssm_parameter.vpc_id.insecure_value
}

output "vpc_cidr" {
  description = "CIDR of the shared VPC"
  value       = data.aws_ssm_parameter.vpc_cidr.insecure_value
}

output "public_subnet_ids" {
  description = "Public subnets (ECS tasks, with a public IP and no inbound rules)"
  value       = split(",", data.aws_ssm_parameter.public_subnet_ids.insecure_value)
}

output "private_subnet_ids" {
  description = "Private subnets (RDS)"
  value       = split(",", data.aws_ssm_parameter.private_subnet_ids.insecure_value)
}

output "ecr_repository_url" {
  description = "This app's ECR repository"
  value       = data.aws_ssm_parameter.ecr_repository_url.insecure_value
}

output "app_role_boundary_arn" {
  description = "Permissions boundary every aws_iam_role in this repo must set"
  value       = data.aws_ssm_parameter.app_role_boundary_arn.insecure_value
}
