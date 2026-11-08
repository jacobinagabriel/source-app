# source-app's own infrastructure. The network, the ECR repository and the IAM
# permissions boundary come from main-terraform; RDS, ECS and the contract
# parameters are added here in later changes.
module "shared" {
  source = "../../modules/shared"

  base_ssm_prefix = var.base_ssm_prefix
}
