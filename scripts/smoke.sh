#!/usr/bin/env bash
# End-to-end check of the container image against the compose Postgres:
# migrate, seed, run a burst of traffic, then confirm the database saw inserts,
# updates and deletes, and that it is ready for logical replication.
set -euo pipefail

COMPOSE=${COMPOSE:-docker compose}
psql() { $COMPOSE exec -T db psql -U source_app -d source_app -tAc "$1"; }
check() {
  local name=$1 sql=$2 actual
  actual=$(psql "$sql")
  if [[ "$actual" == t ]]; then echo "ok   $name"; else echo "FAIL $name ($sql)"; exit 1; fi
}

$COMPOSE up -d --wait db
# `app` depends on `migrate`, so each run below applies migrations first (a no-op after the first).
$COMPOSE run --rm app seed --init-num-users 200
log=$($COMPOSE run --rm -T app run --max-iter 500 --avg-qps 500 \
  --order-update-prob 0.9 --order-delete-prob 0.5 --ghost-purge-prob 0.5 --ghost-retention-minutes 0 2>&1)
actions=$(grep "Actions so far" <<<"$log" | tail -1)
echo "$actions"
for action in order_created order_status_updated user_address_updated order_deleted ghost_event_purged; do
  if grep -qE "$action=[1-9]" <<<"$actions"; then echo "ok   $action"; else echo "FAIL $action"; exit 1; fi
done

check "wal_level is logical"        "SELECT current_setting('wal_level') = 'logical'"
check "migrations at head"          "SELECT version_num = '0003' FROM demo.alembic_version"
check "reference data loaded"       "SELECT count(*) = 29120 FROM demo.products"
check "orders updated in the db"    "SELECT count(*) > 0 FROM demo.orders WHERE status <> 'Processing'"
check "addresses updated in the db" "SELECT count(*) > 0 FROM demo.users WHERE updated_at > created_at"
check "no orphan order items"       "SELECT count(*) = 0 FROM demo.order_items i LEFT JOIN demo.orders o ON o.id = i.order_id WHERE o.id IS NULL"
echo "smoke test passed"
