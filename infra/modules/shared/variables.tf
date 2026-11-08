variable "base_ssm_prefix" {
  description = "Where main-terraform publishes the shared layer, e.g. /main-terraform/prod"
  type        = string
}

variable "app_name" {
  description = "Name of this app's ECR repository in main-terraform"
  type        = string
  default     = "source-app"
}
