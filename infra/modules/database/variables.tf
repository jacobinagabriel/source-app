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
  description = "Private subnets for the instance (at least two AZs, as RDS requires)"
  type        = list(string)
}

variable "engine_major_version" {
  description = "PostgreSQL major version; the latest minor is picked at creation"
  type        = string
  default     = "17"
}

variable "min_engine_version" {
  description = "Lowest version zero-ETL to Redshift supports for this major (us-east-1)"
  type        = string
  default     = "17.3"
}

variable "instance_class" {
  description = "Instance class (a larger, non-burstable one for measured runs)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial gp3 storage in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB"
  type        = number
  default     = 100
}

variable "performance_insights_enabled" {
  description = "Performance Insights (not offered on the micro and small classes)"
  type        = bool
  default     = false
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
  description = "Automated backups; zero-ETL needs them on"
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

variable "free_storage_alarm_bytes" {
  description = "Alarm when free storage drops below this many bytes"
  type        = number
  default     = 2147483648 # 2 GiB
}
