output "cluster_name" {
  description = "ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Generator service"
  value       = aws_ecs_service.generator.name
}

output "generator_task_definition_arn" {
  description = "Generator task definition for this image tag (the deploy workflow rolls the service to it)"
  value       = aws_ecs_task_definition.generator.arn
}

output "ops_task_definition_arn" {
  description = "Ops task definition (db-init, migrate, seed)"
  value       = aws_ecs_task_definition.ops.arn
}

output "app_security_group_id" {
  description = "Security group of the tasks"
  value       = aws_security_group.app.id
}

output "subnet_ids" {
  description = "Subnets the tasks run in"
  value       = var.subnet_ids
}

output "log_group_name" {
  description = "Task logs"
  value       = aws_cloudwatch_log_group.this.name
}
