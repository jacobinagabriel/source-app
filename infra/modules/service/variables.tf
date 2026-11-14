variable "name" {
  description = "Prefix for every resource name (IAM role names must start with source-app-)"
  type        = string
  default     = "source-app"
}

variable "vpc_id" {
  description = "Shared VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets: tasks get a public IP and no inbound rules, so no NAT is needed"
  type        = list(string)
}

variable "ecr_repository_url" {
  description = "This app's ECR repository"
  type        = string
}

variable "image_tag" {
  description = "Image tag to run (the git SHA the deploy workflow built)"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Boundary every IAM role here must carry"
  type        = string
}

variable "db_security_group_id" {
  description = "Database security group; the app's ingress rule is added to it"
  type        = string
}

variable "db_host" {
  description = "Writer endpoint"
  type        = string
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_schema" {
  description = "Schema the app writes to"
  type        = string
}

variable "db_app_username" {
  description = "User the app connects as"
  type        = string
}

variable "db_app_secret_arn" {
  description = "Secret with the app user's password (JSON: username, password)"
  type        = string
}

variable "db_admin_secret_arn" {
  description = "RDS-managed secret of the master user (JSON: username, password); only the ops task gets it"
  type        = string
}

variable "generator_env" {
  description = "SIM_* settings of the generator (see the README), e.g. { SIM_AVG_QPS = \"50\" }"
  type        = map(string)
  default     = {}
}

variable "cpu" {
  description = "Fargate CPU units per task"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory (MiB) per task"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "Retention of the task logs"
  type        = number
  default     = 7
}
