# Plan: source-app (Fork A)

This repo is the source system for the CDC → Iceberg benchmark. The benchmark itself (pipelines, load profiles, measurement) lives in a separate repo, `cdc-iceberg-bench`. The two repos meet only through the contract below.

## Shared decisions

| Decision | Choice |
|---|---|
| Source engine | RDS for PostgreSQL, single instance, version kept as a variable (prefer 17, else 16) |
| Gate 0 (before A2) | Check that RDS for PostgreSQL supports zero-ETL to an Iceberg/lakehouse target in the chosen region, which engine versions, and which parameters. Pin the engine version to match |
| If gate 0 fails | RDS for MySQL (engine is a variable), or zero-ETL to Redshift recorded as "not Iceberg" |
| IaC | Terraform ≥ 1.10, S3 backend with `use_lockfile = true` |
| Language | Python 3.12, uv |
| ORM and schema | SQLAlchemy 2.0 declarative models; Alembic migrations stored in this repo |
| Tags | `Project=cdc-bench`, `Repo=source-app`, `Component=<x>`, `Pipeline=source` |

## Contract v2 (SSM prefix `/source-app/<env>/`)

| Parameter | Purpose |
|---|---|
| `contract_version` | `2` |
| `vpc_id`, `private_subnet_ids` | Where the pipelines run |
| `db_instance_arn`, `db_instance_id` | Zero-ETL integration, DMS endpoint |
| `db_endpoint`, `db_port`, `db_name` | Connections |
| `db_engine`, `db_engine_version` | Compatibility checks |
| `db_security_group_id` | The bench repo adds its own ingress rules |
| `db_admin_secret_arn` | Used only by the bench repo's db-setup |
| `db_app_secret_arn` | App runtime |
| `schema_version` | Latest Alembic revision applied |
| `logical_replication_enabled` | Bench refuses to run if false |
| `db_parameter_group_name` | Bench checks replication settings |
| `db_max_replication_slots` | Bench checks there is room for its pipelines |
| `db_multi_az` | Bench skips the failover scenario if false |

Rules: this repo never creates anything CDC-specific (replication users, publications, slots). The bench repo only adds things. Teardown order: bench first, then source-app.

## Phases

**A0. Bootstrap.** Repo, tooling, CI, branch protection.

**A1. Networking.** VPC with 2 AZs and private subnets, VPC endpoints instead of a NAT gateway, option to reuse an existing VPC.

**A2. Database.** `aws_db_instance` (RDS PostgreSQL) with a DB parameter group: `rds.logical_replication=1` (needs a reboot), replication slot and WAL sender limits sized for 3 pipelines plus headroom, `max_slot_wal_keep_size` as a variable (default unlimited). Storage gp3 with autoscaling, plus alarms on `FreeStorageSpace`, `OldestReplicationSlotLag` and `TransactionLogsDiskUsage` sent to SNS. Admin and app secrets in Secrets Manager.

**A3. Application (v3).** No API service: the app *is* the generator, running as the ECS service. SQLAlchemy 2.0 models; Alembic migrations in `migrations/`, applied by `source-app migrate` as a one-off ECS task, never on app startup. Reference data (products, distribution centers) is seeded by an Alembic data migration. The generator writes inserts, updates and deletes, one transaction per business action.

**A4. ECS.** Fargate service, `desired_count` as a variable (`make pause` / `make resume`), no ALB by default.

**A5. Contract outputs.** All SSM parameters above, documented, plus `make contract-check`.

**A6. Operability.** `make up/down/stop-db/start-db/bench-size/idle-size/failover/migrate/seed`, idle cost documented.

## Code changes (one PR each)

1. Tooling: package layout, uv, ruff, pre-commit, pytest, CI, Dockerfile, README, this plan.
2. Config: remove Kafka arguments, settings from env vars, CLI subcommands `migrate`, `seed`, `run`.
3. ORM + Alembic: declarative models with `uuid`, `timestamptz`, `numeric`, foreign keys; initial schema and reference-data migrations; one transaction per business action (the foreign keys require it). Migrations live in the package (`src/source_app/migrations/`) so the image can run them without extra files.
4. Sampling: indexed random row selection instead of `ORDER BY random()`.
5. Deletes: delete cancelled orders (items cascade) and purge old anonymous events.
6. Local dev: docker-compose Postgres with `wal_level=logical`, Makefile, integration test.
