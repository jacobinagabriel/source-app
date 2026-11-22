output "instance_id" {
  description = "DB instance identifier"
  value       = aws_db_instance.this.identifier
}

output "instance_arn" {
  description = "DB instance ARN (the zero-ETL integration source)"
  value       = aws_db_instance.this.arn
}

output "endpoint" {
  description = "Instance host name (without the port)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Database the app uses"
  value       = aws_db_instance.this.db_name
}

output "engine" {
  description = "Engine"
  value       = aws_db_instance.this.engine
}

output "engine_version" {
  description = "Running engine version"
  value       = aws_db_instance.this.engine_version_actual
}

output "security_group_id" {
  description = "Database security group; others add their ingress rules to it"
  value       = aws_security_group.db.id
}

output "parameter_group_name" {
  description = "DB parameter group with the replication settings"
  value       = aws_db_parameter_group.this.name
}

output "max_replication_slots" {
  description = "Configured replication slots"
  value       = var.max_replication_slots
}

output "admin_secret_arn" {
  description = "RDS-managed secret of the master user (JSON with username and password)"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "app_secret_arn" {
  description = "Secret of the app user (JSON with username and password)"
  value       = aws_secretsmanager_secret.app.arn
}

output "admin_username" {
  description = "Master user name"
  value       = var.admin_username
}

output "app_username" {
  description = "App user name"
  value       = var.app_username
}
