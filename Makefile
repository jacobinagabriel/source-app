COMPOSE ?= docker compose
# Matches the db service in docker-compose.yml, for running the app from the host.
export DB_HOST ?= localhost
export DB_NAME ?= source_app
export DB_USER ?= source_app
export DB_PASSWORD ?= source_app
export DB_SCHEMA ?= demo
# The compose superuser, standing in for the Aurora master user (db-init only).
export DB_ADMIN_USER ?= postgres
export DB_ADMIN_PASSWORD ?= postgres

.PHONY: help up down reset db-init migrate seed run app lint test smoke contract-check

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-8s %s\n", $$1, $$2}'

up: ## Start Postgres (wal_level=logical) in the background
	$(COMPOSE) up -d --wait db

down: ## Stop everything (keeps the data volume)
	$(COMPOSE) down

reset: ## Stop everything and delete the data volume
	$(COMPOSE) down -v

db-init: up ## Create the app user and grant it the schema, as the admin
	uv run source-app db-init

migrate: db-init ## Apply migrations from the host
	uv run source-app migrate

seed: migrate ## Create the initial users from the host (skipped if users exist)
	uv run source-app seed

run: ## Generate traffic from the host (ARGS="--avg-qps 50 --max-iter 1000")
	uv run source-app run $(ARGS)

app: ## Run db-init, migrate, seed + the generator in containers, like ECS will
	$(COMPOSE) up --build -d app

lint: ## Ruff lint and format check
	uv run ruff check . && uv run ruff format --check .

test: up ## Unit and database tests against the compose Postgres (as the admin)
	DB_USER=$(DB_ADMIN_USER) DB_PASSWORD=$(DB_ADMIN_PASSWORD) REQUIRE_DB_TESTS=1 uv run pytest

smoke: ## Containers end to end: migrate, seed, run, then check the data
	./scripts/smoke.sh

contract-check: ## Check the SSM contract on AWS (needs AWS_PROFILE; ENV=prod)
	./scripts/contract-check.sh
