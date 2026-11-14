output "cluster_id" {
  description = "Cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Cluster ARN (the zero-ETL integration source)"
  value       = aws_rds_cluster.this.arn
}

output "endpoint" {
  description = "Writer endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "PostgreSQL port"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Database the app uses"
  value       = aws_rds_cluster.this.database_name
}

output "engine" {
  description = "Engine"
  value       = aws_rds_cluster.this.engine
}

output "engine_version" {
  description = "Running engine version"
  value       = aws_rds_cluster.this.engine_version_actual
}

output "security_group_id" {
  description = "Database security group; others add their ingress rules to it"
  value       = aws_security_group.db.id
}

output "cluster_parameter_group_name" {
  description = "Cluster parameter group with the replication settings"
  value       = aws_rds_cluster_parameter_group.this.name
}

output "max_replication_slots" {
  description = "Configured replication slots"
  value       = var.max_replication_slots
}

output "admin_secret_arn" {
  description = "RDS-managed secret of the master user (JSON with username and password)"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
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

output "writer_instance_id" {
  description = "Writer instance identifier"
  value       = aws_rds_cluster_instance.writer.identifier
}
