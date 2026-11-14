# source-app's own infrastructure. The network, the ECR repository and the IAM
# permissions boundary come from main-terraform; the contract parameters are added
# here in a later change.

locals {
  db_schema = "demo"
}
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

module "service" {
  source = "../../modules/service"

  vpc_id                   = module.shared.vpc_id
  subnet_ids               = module.shared.public_subnet_ids
  ecr_repository_url       = module.shared.ecr_repository_url
  image_tag                = var.image_tag
  permissions_boundary_arn = module.shared.app_role_boundary_arn

  db_security_group_id = module.database.security_group_id
  db_host              = module.database.endpoint
  db_port              = module.database.port
  db_name              = module.database.database_name
  db_schema            = local.db_schema
  db_app_username      = module.database.app_username
  db_app_secret_arn    = module.database.app_secret_arn
  db_admin_secret_arn  = module.database.admin_secret_arn

  generator_env = var.generator_env
}
