# source-app

A minimal OLTP traffic generator for PostgreSQL. It simulates an e-commerce shop (users, orders, order items, web events) and writes inserts, updates and deletes straight to the database, so a change data capture (CDC) pipeline has a realistic source to read from.

It is the source system for a benchmark that compares three ways of replicating RDS PostgreSQL changes into Apache Iceberg on AWS (DMS, zero-ETL and Debezium). The plan lives in [docs/PLAN.md](docs/PLAN.md). This repo knows nothing about CDC: it only offers a database worth replicating.

## Credit

This project started as a copy of the **Real-Time theLook eCommerce Data Generator** by [Factor House](https://github.com/factorhouse/examples/tree/main/datagen/thelook-ecomm) (Apache-2.0). The upstream commit history is kept in this repo. See [NOTICE](NOTICE) for details.

## Quick start

Needs Python 3.12+, [uv](https://docs.astral.sh/uv/), and a PostgreSQL database.

```bash
uv sync
uv run source-app --help
uv run source-app --db-host localhost --db-user db_user --db-password db_password --db-name fh_dev --db-schema demo
```

Or with Docker:

```bash
docker build -t source-app .
docker run --rm source-app --help
```

## What it generates

Each loop iteration (paced by `--avg-qps`) picks a user and writes an order, its items and the web events leading to the purchase. Side tasks run with their own probabilities:

| Task | Flag | Writes |
|---|---|---|
| New user | `--user-create-prob` | insert into `users` |
| Address change | `--user-update-prob` | update `users` |
| Order status change | `--order-update-prob` | update `orders` and `order_items`, insert cancel/return events |
| Anonymous browsing | `--ghost-create-prob` | insert into `events` (no `user_id`) |

## Development

```bash
uv sync
uv run pre-commit install
uv run ruff check . && uv run ruff format --check .
uv run pytest
```

Changes land through pull requests into `main`. CI (`ci`) must pass before a PR can be merged.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
