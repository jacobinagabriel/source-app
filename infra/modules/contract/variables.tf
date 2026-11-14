variable "prefix" {
  description = "SSM path of the contract, e.g. /source-app/prod"
  type        = string
}

variable "parameters" {
  description = "Contract parameters (name => value); see docs/PLAN.md"
  type        = map(string)
}

variable "list_parameters" {
  description = "Contract parameters holding lists, stored as StringList"
  type        = map(list(string))
  default     = {}
}
