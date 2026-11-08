output "vpc_id" {
  description = "Shared VPC"
  value       = module.shared.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets for ECS tasks"
  value       = module.shared.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnets for RDS"
  value       = module.shared.private_subnet_ids
}

output "ecr_repository_url" {
  description = "Where the image is pushed"
  value       = module.shared.ecr_repository_url
}

output "app_role_boundary_arn" {
  description = "Permissions boundary for this repo's IAM roles"
  value       = module.shared.app_role_boundary_arn
}
