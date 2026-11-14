# The generator as an ECS service, plus an ops task definition for the one-off
# commands (db-init, migrate, seed) the deploy workflow runs before each rollout.
#
# Terraform creates the service with no tasks and never changes its task definition
# or count afterwards: the deploy workflow does both, after the ops tasks have
# migrated the database, so new code never starts against an old schema.

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  image = "${var.ecr_repository_url}:${var.image_tag}"

  environment = [for k, v in merge(
    {
      DB_HOST                 = var.db_host
      DB_PORT                 = tostring(var.db_port)
      DB_NAME                 = var.db_name
      DB_SCHEMA               = var.db_schema
      DB_USER                 = var.db_app_username
      PYTHONDONTWRITEBYTECODE = "1" # the root filesystem is read-only
    },
    var.generator_env,
  ) : { name = k, value = v }]

  app_secrets = [
    { name = "DB_PASSWORD", valueFrom = "${var.db_app_secret_arn}:password::" },
  ]
  admin_secrets = [
    { name = "DB_ADMIN_USER", valueFrom = "${var.db_admin_secret_arn}:username::" },
    { name = "DB_ADMIN_PASSWORD", valueFrom = "${var.db_admin_secret_arn}:password::" },
  ]

  container = {
    name                   = "source-app"
    image                  = local.image
    essential              = true
    readonlyRootFilesystem = true
    environment            = local.environment
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "source-app"
      }
    }
  }
}

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights costs extra; task logs and RDS metrics cover a benchmark run.
  name = var.name
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Logs of a synthetic workload; the default AWS-owned encryption is enough.
  #checkov:skip=CKV_AWS_338:Short retention on purpose; the stack is destroyed after each benchmark.
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# --- Network ---------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Generator tasks: no inbound, outbound to the database, ECR and Secrets Manager"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app" }
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  #checkov:skip=CKV_AWS_382:Tasks reach ECR, Secrets Manager and CloudWatch through the internet gateway (no NAT or endpoints, to keep idle cost at zero).
  security_group_id = aws_security_group.app.id
  description       = "ECR, Secrets Manager, CloudWatch Logs and the database"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = var.db_security_group_id
  description                  = "PostgreSQL from the ${var.name} tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.app.id
}

# --- IAM ---------------------------------------------------------------------------

# Only an execution role (pull the image, write logs, read the two secrets). The app
# itself doesn't call AWS, so the tasks get no task role.
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name                 = "${var.name}-ecs-execution"
  description          = "Pulls the ${var.name} image, writes its logs and reads its database secrets"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_app_secret_arn, var.db_admin_secret_arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "database-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}

# --- Tasks ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "generator" {
  family                   = "${var.name}-generator"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([merge(local.container, {
    command = ["run"]
    secrets = local.app_secrets
  })])
}

# Same image and settings plus the admin credentials, for db-init. The deploy
# workflow overrides the command to run migrate and seed with it too.
resource "aws_ecs_task_definition" "ops" {
  family                   = "${var.name}-ops"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([merge(local.container, {
    command = ["db-init"]
    secrets = concat(local.app_secrets, local.admin_secrets)
  })])
}

resource "aws_ecs_service" "generator" {
  #checkov:skip=CKV_AWS_333:Public IP with no inbound rules: tasks reach AWS APIs through the internet gateway, avoiding NAT and endpoint costs.
  name            = "${var.name}-generator"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.generator.arn
  desired_count   = 0 # the deploy workflow scales it up after migrating
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
