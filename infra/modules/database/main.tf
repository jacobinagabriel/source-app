# Aurora PostgreSQL, the source of the CDC benchmark. The cluster parameter group
# carries the settings zero-ETL needs (Aurora docs, "Getting started with zero-ETL
# integrations"); DMS and Debezium only need the logical replication part of them.

data "aws_rds_engine_version" "this" {
  engine  = "aurora-postgresql"
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
  description = "Aurora PostgreSQL for ${var.name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-db" }
}

# --- Parameters ----------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.name}-${data.aws_rds_engine_version.this.parameter_group_family}-"
  family      = data.aws_rds_engine_version.this.parameter_group_family
  description = "Logical replication for CDC and zero-ETL"

  # The four zero-ETL settings. Enhanced logical replication writes full rows to the
  # WAL, so REPLICA IDENTITY FULL isn't needed. Toggling it later invalidates every
  # replication slot, so it's set once, at creation.
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "aurora.enhanced_logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "aurora.logical_replication_backup"
    value        = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "aurora.logical_replication_globaldb"
    value        = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_replication_slots"
    value        = tostring(var.max_replication_slots)
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = tostring(var.max_replication_slots)
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Cluster -------------------------------------------------------------------

# Created before the cluster so destroy also removes it; otherwise RDS creates it
# with no expiry and it outlives the stack.
resource "aws_cloudwatch_log_group" "postgresql" {
  #checkov:skip=CKV_AWS_158:Logs of a synthetic benchmark database; the default AWS-owned encryption is enough.
  #checkov:skip=CKV_AWS_338:Short retention on purpose; the stack is destroyed after each benchmark.
  name              = "/aws/rds/cluster/${var.name}/postgresql"
  retention_in_days = var.log_retention_days
}

resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV_AWS_139:Destroyed after each benchmark; deletion protection would block the down workflow.
  #checkov:skip=CKV_AWS_162:The app uses a password user created by db-init; IAM auth is not needed.
  #checkov:skip=CKV_AWS_327:AWS managed key; a customer managed key costs more and adds nothing for synthetic data.
  #checkov:skip=CKV2_AWS_8:No backup plan; the data is synthetic and recreated on every up.
  #checkov:skip=CKV2_AWS_27:No statement logging; logging every query of the generator would distort the benchmark and cost more than the database.
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = local.engine_version
  database_name      = var.database_name

  master_username             = var.admin_username
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_days
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.name}-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = true

  depends_on = [aws_cloudwatch_log_group.postgresql]

  lifecycle {
    # A newer minor version in the data source must not upgrade a running cluster.
    ignore_changes = [engine_version]

    precondition {
      condition = (
        local.version_parts[0] > local.min_parts[0] ||
        (local.version_parts[0] == local.min_parts[0] && local.version_parts[1] >= local.min_parts[1])
      )
      error_message = "Aurora PostgreSQL ${local.engine_version} is older than ${var.min_engine_version}, the minimum for zero-ETL to the SageMaker lakehouse."
    }
  }
}

resource "aws_rds_cluster_instance" "writer" {
  #checkov:skip=CKV_AWS_118:No enhanced monitoring; Performance Insights and CloudWatch cover a benchmark run.
  #checkov:skip=CKV_AWS_354:Performance Insights uses the AWS managed key.
  identifier                   = "${var.name}-1"
  cluster_identifier           = aws_rds_cluster.this.id
  instance_class               = var.instance_class
  engine                       = aws_rds_cluster.this.engine
  db_subnet_group_name         = aws_db_subnet_group.this.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true # 7 days of retention are free
  apply_immediately            = true
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

# Aurora storage grows by itself, so a replication slot nobody reads doesn't fill a
# disk: it quietly costs money. These alarms catch WAL piling up for slots.
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
  alarm_description   = "WAL kept for replication slots on ${aws_rds_cluster_instance.writer.identifier} is growing; a pipeline may be stopped."
  namespace           = "AWS/RDS"
  metric_name         = each.key
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.writer.identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.replication_disk_alarm_bytes
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}
