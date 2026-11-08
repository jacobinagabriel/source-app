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
