output "prefix" {
  description = "SSM path of the contract"
  value       = var.prefix
}

output "schema_version_parameter" {
  description = "Parameter the deploy workflow writes the Alembic revision to"
  value       = aws_ssm_parameter.schema_version.name
}
