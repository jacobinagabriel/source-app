COMPOSE ?= docker compose
# Matches the db service in docker-compose.yml, for running the app from the host.
export DB_HOST ?= localhost
export DB_NAME ?= source_app
export DB_USER ?= source_app
export DB_PASSWORD ?= source_app
export DB_SCHEMA ?= demo

.PHONY: help up down reset migrate seed run app lint test smoke

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-8s %s\n", $$1, $$2}'

up: ## Start Postgres (wal_level=logical) in the background
	$(COMPOSE) up -d --wait db

down: ## Stop everything (keeps the data volume)
	$(COMPOSE) down

reset: ## Stop everything and delete the data volume
	$(COMPOSE) down -v

migrate: up ## Apply migrations from the host
	uv run source-app migrate

seed: migrate ## Create the initial users from the host
	uv run source-app seed

run: ## Generate traffic from the host (ARGS="--avg-qps 50 --max-iter 1000")
	uv run source-app run $(ARGS)

app: ## Run migrate + the generator in containers, like ECS will
	$(COMPOSE) up --build -d app

lint: ## Ruff lint and format check
	uv run ruff check . && uv run ruff format --check .

test: up ## Unit and database tests against the compose Postgres
	REQUIRE_DB_TESTS=1 uv run pytest

smoke: ## Containers end to end: migrate, seed, run, then check the data
	./scripts/smoke.sh
