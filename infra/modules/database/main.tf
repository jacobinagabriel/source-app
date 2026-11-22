# RDS for PostgreSQL, the source of the CDC benchmark. The parameter group carries
# the settings DMS and Debezium need (logical replication), plus the rest of what
# zero-ETL to Redshift asks for (RDS docs, "Getting started with zero-ETL
# integrations"), so the bench repo can add that arm without touching this stack.

data "aws_rds_engine_version" "this" {
  engine  = "postgres"
  version = var.engine_major_version
  latest  = true
}

locals {
  engine_version = data.aws_rds_engine_version.this.version_actual
  version_parts  = [for part in split(".", local.engine_version) : tonumber(part)]
  min_parts      = [for part in split(".", var.min_engine_version) : tonumber(part)]
}

# --- Network -----------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# No rules of its own: the ECS module allows the app, and the bench repo adds its
# pipelines. No egress either; the database never calls out.
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "RDS for PostgreSQL for ${var.name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-db" }
}

# --- Parameters ----------------------------------------------------------------

# Every value is applied when the instance is created, so pending-reboot (which
# static parameters require) never actually needs a reboot.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-${data.aws_rds_engine_version.this.parameter_group_family}-"
  family      = data.aws_rds_engine_version.this.parameter_group_family
  description = "Logical replication for CDC and zero-ETL"

  dynamic "parameter" {
    for_each = {
      "rds.logical_replication" = "1"
      # Full old rows in the WAL for every table, as zero-ETL requires; DMS and
      # Debezium get complete before-images on updates and deletes too.
      "rds.replica_identity_full" = "1"
      "session_replication_role"  = "origin"
      "wal_sender_timeout"        = "0"
      "max_replication_slots"     = tostring(var.max_replication_slots)
      "max_wal_senders"           = tostring(var.max_replication_slots)
      # Never drop WAL a slot still needs; the storage alarm catches a stuck slot.
      "max_slot_wal_keep_size" = "-1"
      "rds.force_ssl"          = "1"
    }

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Instance ------------------------------------------------------------------

# Created before the instance so destroy also removes it; otherwise RDS creates it
# with no expiry and it outlives the stack.
resource "aws_cloudwatch_log_group" "postgresql" {
  #checkov:skip=CKV_AWS_158:Logs of a synthetic benchmark database; the default AWS-owned encryption is enough.
  #checkov:skip=CKV_AWS_338:Short retention on purpose; the stack is destroyed after each benchmark.
  name              = "/aws/rds/instance/${var.name}/postgresql"
  retention_in_days = var.log_retention_days
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Single-AZ on purpose; the stack is destroyed after each benchmark and zero-ETL doesn't need Multi-AZ.
  #checkov:skip=CKV_AWS_161:The app uses a password user created by db-init; IAM auth is not needed.
  #checkov:skip=CKV_AWS_293:Destroyed after each benchmark; deletion protection would block the down workflow.
  #checkov:skip=CKV_AWS_118:No enhanced monitoring; CloudWatch covers a benchmark run.
  #checkov:skip=CKV_AWS_353:Performance Insights is optional (var.performance_insights_enabled); the small classes don't offer it.
  #checkov:skip=CKV_AWS_354:Performance Insights, when on, uses the AWS managed key.
  #checkov:skip=CKV2_AWS_30:No statement logging; logging every query of the generator would distort the benchmark and cost more than the database.
  #checkov:skip=CKV2_AWS_60:Snapshots are never kept (skip_final_snapshot), so there are no tags to copy.
  identifier     = var.name
  engine         = "postgres"
  engine_version = local.engine_version
  instance_class = var.instance_class
  db_name        = var.database_name

  # A stuck replication slot fills the disk; autoscaling buys time for the alarm.
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  username                    = var.admin_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  multi_az               = false
  publicly_accessible    = false

  # Zero-ETL requires automated backups.
  backup_retention_period         = var.backup_retention_days
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.name}-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = var.performance_insights_enabled
  auto_minor_version_upgrade      = true
  apply_immediately               = true

  depends_on = [aws_cloudwatch_log_group.postgresql]

  lifecycle {
    # A newer minor version in the data source must not upgrade a running instance.
    ignore_changes = [engine_version]

    precondition {
      condition = (
        local.version_parts[0] > local.min_parts[0] ||
        (local.version_parts[0] == local.min_parts[0] && local.version_parts[1] >= local.min_parts[1])
      )
      error_message = "PostgreSQL ${local.engine_version} is older than ${var.min_engine_version}, the minimum for zero-ETL to Redshift."
    }
  }
}

# --- App user secret -------------------------------------------------------------

# Generated at apply time and written write-only: the password never lands in the
# Terraform state or plan. db-init sets the role's password from this secret.
ephemeral "random_password" "app" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  #checkov:skip=CKV_AWS_149:AWS managed key; a customer managed key adds cost and nothing for a synthetic database.
  #checkov:skip=CKV2_AWS_57:No rotation; the secret is recreated with the stack on every up.
  name                    = "${var.name}/db-app"
  description             = "Password of the ${var.app_username} database user"
  recovery_window_in_days = 0 # lets the next up recreate the same name right after a down
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string_wo = jsonencode({
    username = var.app_username
    password = ephemeral.random_password.app.result
  })
  # Bump to set a new password; db-init picks it up on the next deploy.
  secret_string_wo_version = 1
}

# --- Alarms ----------------------------------------------------------------------

# A replication slot nobody reads keeps WAL until the disk is full. These alarms
# catch WAL piling up for slots, and the disk running out anyway.
resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-db-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "replication" {
  for_each = toset(["ReplicationSlotDiskUsage", "TransactionLogsDiskUsage"])

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = "WAL kept for replication slots on ${aws_db_instance.this.identifier} is growing; a pipeline may be stopped."
  namespace           = "AWS/RDS"
  metric_name         = each.key
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.replication_disk_alarm_bytes
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${var.name}-FreeStorageSpace"
  alarm_description   = "${aws_db_instance.this.identifier} is running out of disk; check for a stuck replication slot."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.free_storage_alarm_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}
