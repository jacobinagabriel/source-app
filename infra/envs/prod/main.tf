# source-app's own infrastructure. The network, the ECR repository and the IAM
# permissions boundary come from main-terraform; ECS and the contract parameters
# are added here in later changes.
module "shared" {
  source = "../../modules/shared"

  base_ssm_prefix = var.base_ssm_prefix
}

module "database" {
  source = "../../modules/database"

  vpc_id         = module.shared.vpc_id
  subnet_ids     = module.shared.private_subnet_ids
  instance_class = var.db_instance_class
  alarm_email    = var.alarm_email
}
