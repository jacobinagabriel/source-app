variable "name" {
  description = "Prefix for every resource name"
  type        = string
  default     = "source-app"
}

variable "vpc_id" {
  description = "Shared VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the cluster (at least two AZs)"
  type        = list(string)
}

variable "engine_major_version" {
  description = "Aurora PostgreSQL major version; the latest minor is picked at creation"
  type        = string
  default     = "17"
}

variable "min_engine_version" {
  description = "Lowest version zero-ETL to the SageMaker lakehouse supports for this major (us-east-1)"
  type        = string
  default     = "17.4"
}

variable "instance_class" {
  description = "Writer instance class (a larger one for heavy benchmark runs)"
  type        = string
  default     = "db.t4g.medium"
}

variable "database_name" {
  description = "Database the app uses"
  type        = string
  default     = "source_app"
}

variable "admin_username" {
  description = "Master user; RDS manages its password in Secrets Manager. Only db-init and the bench repo's setup use it"
  type        = string
  default     = "source_app_admin"
}

variable "app_username" {
  description = "Least-privilege user the app connects as (created by `source-app db-init`)"
  type        = string
  default     = "source_app"
}

variable "max_replication_slots" {
  description = "Replication slots and WAL senders: 3 pipelines plus headroom"
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "Automated backups (Aurora keeps at least 1 day)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Off: the stack is destroyed after each benchmark"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "The data is synthetic, so destroy doesn't keep a snapshot"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention of the exported PostgreSQL logs"
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Email subscribed to the replication alarms (empty: no subscription)"
  type        = string
  default     = ""
}

variable "replication_disk_alarm_bytes" {
  description = "Alarm when WAL held for replication slots exceeds this many bytes"
  type        = number
  default     = 10737418240 # 10 GiB
}
