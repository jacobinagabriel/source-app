# Everything this app takes from main-terraform, read from SSM so this repo never
# depends on main-terraform's state. main-terraform (env/prod and
# bootstrap/github-oidc) must be applied first.

data "aws_ssm_parameter" "vpc_id" {
  name = "${var.base_ssm_prefix}/network/vpc_id"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "${var.base_ssm_prefix}/network/vpc_cidr"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "${var.base_ssm_prefix}/network/public_subnet_ids"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "${var.base_ssm_prefix}/network/private_subnet_ids"
}

data "aws_ssm_parameter" "ecr_repository_url" {
  name = "${var.base_ssm_prefix}/ecr/${var.app_name}/repository_url"
}

data "aws_ssm_parameter" "app_role_boundary_arn" {
  name = "${var.base_ssm_prefix}/iam/app_role_boundary_arn"
}
