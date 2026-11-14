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

output "db_endpoint" {
  description = "Aurora writer endpoint"
  value       = module.database.endpoint
}

output "db_cluster_arn" {
  description = "Aurora cluster ARN"
  value       = module.database.cluster_arn
}

output "db_engine_version" {
  description = "Running Aurora PostgreSQL version"
  value       = module.database.engine_version
}

# Read by the deploy workflow (terraform output -json) to run the ops tasks and roll
# the service.
output "ecs_cluster_name" {
  description = "ECS cluster"
  value       = module.service.cluster_name
}

output "ecs_service_name" {
  description = "Generator service"
  value       = module.service.service_name
}

output "generator_task_definition_arn" {
  description = "Generator task definition for the deployed image"
  value       = module.service.generator_task_definition_arn
}

output "ops_task_definition_arn" {
  description = "Ops task definition (db-init, migrate, seed)"
  value       = module.service.ops_task_definition_arn
}

output "task_subnet_ids" {
  description = "Subnets for the tasks"
  value       = module.service.subnet_ids
}

output "task_security_group_id" {
  description = "Security group for the tasks"
  value       = module.service.app_security_group_id
}

output "task_log_group_name" {
  description = "Task logs"
  value       = module.service.log_group_name
}

output "schema_version_parameter" {
  description = "SSM parameter the deploy workflow writes the Alembic revision to"
  value       = module.contract.schema_version_parameter
}
