# source-app

A minimal OLTP traffic generator for PostgreSQL. It simulates an e-commerce shop (users, orders, order items, web events) and writes inserts, updates and deletes straight to the database, so a change data capture (CDC) pipeline has a realistic source to read from.

It is the source system for a benchmark that compares three ways of replicating RDS PostgreSQL changes into Apache Iceberg on AWS (DMS, zero-ETL and Debezium). The plan lives in [docs/PLAN.md](docs/PLAN.md). This repo knows nothing about CDC: it only offers a database worth replicating.

## Credit

This project started as a copy of the **Real-Time theLook eCommerce Data Generator** by [Factor House](https://github.com/factorhouse/examples/tree/main/datagen/thelook-ecomm) (Apache-2.0). The upstream commit history is kept in this repo. See [NOTICE](NOTICE) for details.

## Quick start

Needs Python 3.12+, [uv](https://docs.astral.sh/uv/), and a PostgreSQL database.

```bash
uv sync
export DB_HOST=localhost DB_NAME=source_app DB_USER=source_app DB_PASSWORD=source_app
uv run source-app migrate   # apply Alembic migrations: schema, products, distribution centers
uv run source-app seed      # create the initial users
uv run source-app run       # generate traffic until stopped
```

Or with Docker (the image runs `source-app run` by default):

```bash
docker build -t source-app .
docker run --rm -e DB_HOST=... -e DB_PASSWORD=... source-app
```

## Configuration

Every setting comes from an environment variable, and a command-line flag of the same name overrides it (`source-app run --help` lists them).

| Variable | Flag | Default |
|---|---|---|
| `DB_HOST`, `DB_PORT` | `--db-host`, `--db-port` | `localhost`, `5432` |
| `DB_NAME`, `DB_USER`, `DB_PASSWORD` | `--db-name`, `--db-user`, `--db-password` | `source_app` |
| `DB_SCHEMA` | `--db-schema` | `demo` |
| `SIM_AVG_QPS` | `--avg-qps` | `20` purchases/second on average |
| `SIM_MAX_ITER` | `--max-iter` | `-1` (run forever) |
| `SIM_INIT_NUM_USERS` | `--init-num-users` | `1000` (used by `seed`) |

The probabilities in the next table are set the same way (`SIM_USER_CREATE_PROB` / `--user-create-prob` and so on).

## What it generates

Each loop iteration (paced by `--avg-qps`) picks a user and writes an order, its items and the web events leading to the purchase, in one transaction. Side tasks run with their own probabilities, each in its own transaction:

| Task | Flag | Writes |
|---|---|---|
| New user | `--user-create-prob` (0.05) | insert into `users` |
| Address change | `--user-update-prob` (0.1) | update `users` |
| Order status change | `--order-update-prob` (0.4) | update `orders` and `order_items`, insert cancel/return events |
| Anonymous browsing | `--ghost-create-prob` (0.2) | insert into `events` (no `user_id`) |
| Delete a cancelled order | `--order-delete-prob` (0.05) | delete from `orders`, cascading to `order_items` |
| Purge old anonymous events | `--ghost-purge-prob` (0.05) | delete up to `--ghost-purge-batch` (100) `events` older than `--ghost-retention-minutes` (60) |

The run logs a count of committed actions by type every 1,000 iterations and when it stops.

## Local Postgres

`docker-compose.yml` runs Postgres 17 with `wal_level=logical` (the same setting the RDS instance gets), so CDC tools can read from it too.

```bash
make up        # start Postgres
make seed      # migrate + initial users, from the host
make run ARGS="--avg-qps 50"
make app       # or: migrate + generator in containers, the way ECS runs them
make smoke     # containers end to end, with checks on the resulting data
make down      # stop (make reset also deletes the data)
```

## Infrastructure

`infra/envs/prod` is this app's Terraform stack (state key `source-app/prod/terraform.tfstate`). It builds on [main-terraform](https://github.com/jacobinagabriel/main-terraform), which must be applied first: `infra/modules/shared` reads the shared VPC, subnets, this app's ECR repository and the IAM permissions boundary from SSM under `/main-terraform/prod/`. Every IAM role here must set that boundary (checked by checkov and enforced by AWS).

CI (`terraform`) runs fmt, validate, tflint and checkov on every PR, and comments a plan once the GitHub OIDC roles are set up. Everything Terraform-related lives under `infra/`, including the tflint (`.tflint.hcl`) and checkov (`.checkov.yaml`, `.checkov/checks/`) config, so run those tools from there.

## Development

```bash
uv sync
uv run pre-commit install
uv run ruff check . && uv run ruff format --check .
uv run pytest                 # DB tests run when DB_* points at a reachable Postgres (make test)
```

The schema is managed with SQLAlchemy models (`src/source_app/models.py`) and Alembic migrations (`src/source_app/migrations/`). After changing a model:

```bash
uv run alembic revision --autogenerate -m "describe the change"
uv run alembic upgrade head
```

Changes land through pull requests into `main`. CI (`ci`) must pass before a PR can be merged.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
