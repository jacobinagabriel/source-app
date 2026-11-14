variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "base_ssm_prefix" {
  description = "Where main-terraform publishes the shared layer"
  type        = string
  default     = "/main-terraform/prod"
}

variable "db_instance_class" {
  description = "Aurora writer instance class (a larger one for heavy benchmark runs)"
  type        = string
  default     = "db.t4g.medium"
}

variable "alarm_email" {
  description = "Email for the replication alarms (empty: no subscription)"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Image tag to deploy; the deploy workflow passes the git SHA it built"
  type        = string
}

variable "generator_env" {
  description = "SIM_* settings of the generator, e.g. { SIM_AVG_QPS = \"50\" }"
  type        = map(string)
  default     = {}
}
