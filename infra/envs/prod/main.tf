# source-app's own infrastructure. The network, the ECR repository and the IAM
# permissions boundary come from main-terraform; this stack adds the database, the
# generator on ECS, and the contract the bench repo reads.

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

# Contract v3 (docs/PLAN.md): the only thing cdc-iceberg-bench reads from this repo.
module "contract" {
  source = "../../modules/contract"

  prefix = "/source-app/prod"
  parameters = {
    contract_version                = "3"
    vpc_id                          = module.shared.vpc_id
    db_cluster_arn                  = module.database.cluster_arn
    db_cluster_id                   = module.database.cluster_id
    db_endpoint                     = module.database.endpoint
    db_reader_endpoint              = module.database.reader_endpoint
    db_port                         = tostring(module.database.port)
    db_name                         = module.database.database_name
    db_schema                       = local.db_schema
    db_engine                       = module.database.engine
    db_engine_version               = module.database.engine_version
    db_security_group_id            = module.database.security_group_id
    db_cluster_parameter_group_name = module.database.cluster_parameter_group_name
    db_max_replication_slots        = tostring(module.database.max_replication_slots)
    db_admin_secret_arn             = module.database.admin_secret_arn
    db_app_secret_arn               = module.database.app_secret_arn
    logical_replication_enabled     = "true"
    db_multi_az                     = "false"
    ecs_cluster_name                = module.service.cluster_name
    image_tag                       = var.image_tag
  }
  list_parameters = {
    private_subnet_ids = module.shared.private_subnet_ids
    public_subnet_ids  = module.shared.public_subnet_ids
  }
}
