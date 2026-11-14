import asyncio
import os
import uuid

import pytest
from faker import Faker
from sqlalchemy import create_engine, text

from source_app.admin import init_database
from source_app.settings import AdminSettings, DatabaseSettings, SimulationSettings
from source_app.simulator import TheLookECommSimulator


@pytest.fixture(scope="module")
def db_settings():
    """A throwaway schema in the database pointed to by DB_*; skipped without a database."""
    db = DatabaseSettings(schema_name=f"test_{uuid.uuid4().hex[:8]}")
    engine = create_engine(db.url())
    try:
        with engine.connect():
            pass
    except Exception as e:
        if os.getenv("REQUIRE_DB_TESTS"):
            raise
        pytest.skip(f"no database available: {e}")

    yield db

    with engine.begin() as conn:
        conn.execute(text(f'DROP SCHEMA IF EXISTS "{db.schema_name}" CASCADE'))
    engine.dispose()


def scalar(db: DatabaseSettings, sql: str) -> int:
    engine = create_engine(db.url(), connect_args={"options": f"-c search_path={db.schema_name}"})
    with engine.connect() as conn:
        value = conn.execute(text(sql)).scalar_one()
    engine.dispose()
    return value


def run(db: DatabaseSettings, command: str, **sim) -> TheLookECommSimulator:
    Faker.seed(7)
    simulator = TheLookECommSimulator(db, SimulationSettings(**sim), Faker())
    try:
        asyncio.run(getattr(simulator, command)())
    finally:
        asyncio.run(simulator.close())
    return simulator


def test_migrate_seed_and_run(db_settings):
    run(db_settings, "migrate")
    assert scalar(db_settings, "SELECT version_num FROM alembic_version") == "0004"
    assert scalar(db_settings, "SELECT count(*) FROM products") == 29120
    assert scalar(db_settings, "SELECT count(*) FROM dist_centers") == 10

    run(db_settings, "seed", init_num_users=50)
    assert scalar(db_settings, "SELECT count(*) FROM users") == 50
    # A second seed is a no-op, so deploys can always run it.
    run(db_settings, "seed", init_num_users=50)
    assert scalar(db_settings, "SELECT count(*) FROM users") == 50

    run(
        db_settings,
        "run",
        max_iter=100,
        avg_qps=1000,
        order_update_prob=0.9,
        order_delete_prob=0,
        ghost_purge_prob=0,
    )
    assert scalar(db_settings, "SELECT count(*) FROM orders") == 100
    assert scalar(db_settings, "SELECT count(*) FROM orders WHERE status <> 'Processing'") > 0
    # Every order's items carry the order's status.
    assert (
        scalar(
            db_settings,
            "SELECT count(*) FROM order_items i JOIN orders o ON o.id = i.order_id"
            " WHERE i.status <> o.status",
        )
        == 0
    )
    assert scalar(db_settings, "SELECT count(*) FROM events") > 0


def test_random_rows_spread_across_the_table(db_settings):
    # Runs after test_migrate_seed_and_run, so the schema has users and orders.
    from source_app import repository
    from source_app.db import make_sessionmaker

    Session = make_sessionmaker(db_settings)
    with Session() as session:
        users = {repository.random_user(session).id for _ in range(50)}
        orders = [repository.random_order(session) for _ in range(20)]
    Session.kw["bind"].dispose()

    assert len(users) > 10
    assert all(order is not None and order.items for order in orders)


def test_deletes_cancelled_orders_and_purges_ghost_events(db_settings):
    # Runs after test_migrate_seed_and_run. Cancel five orders by hand so the delete
    # task has something to pick, whatever the random status changes did.
    engine = create_engine(
        db_settings.url(), connect_args={"options": f"-c search_path={db_settings.schema_name}"}
    )
    with engine.begin() as conn:
        conn.execute(
            text(
                "UPDATE orders SET status = 'Cancelled', cancelled_at = now()"
                " WHERE id IN (SELECT id FROM orders WHERE status <> 'Cancelled' LIMIT 5)"
            )
        )
    engine.dispose()
    cancelled_before = scalar(db_settings, "SELECT count(*) FROM orders WHERE status = 'Cancelled'")
    ghosts_before = scalar(db_settings, "SELECT count(*) FROM events WHERE user_id IS NULL")
    assert ghosts_before > 0

    simulator = run(
        db_settings,
        "run",
        max_iter=3,
        avg_qps=1000,
        user_create_prob=0,
        user_update_prob=0,
        order_update_prob=0,
        ghost_create_prob=0,
        order_delete_prob=1,
        ghost_purge_prob=1,
        ghost_retention_minutes=0,
        ghost_purge_batch=1000,
    )

    assert simulator.stats["order_deleted"] == 3
    assert (
        scalar(db_settings, "SELECT count(*) FROM orders WHERE status = 'Cancelled'")
        == cancelled_before - 3
    )
    # Items of deleted orders went with them (deleted by the app; the key doesn't cascade).
    assert (
        scalar(
            db_settings,
            "SELECT count(*) FROM order_items i LEFT JOIN orders o ON o.id = i.order_id"
            " WHERE o.id IS NULL",
        )
        == 0
    )
    assert simulator.stats["ghost_event_purged"] == ghosts_before
    assert scalar(db_settings, "SELECT count(*) FROM events WHERE user_id IS NULL") == 0


def test_foreign_keys_do_not_cascade(db_settings):
    # Runs after test_migrate_seed_and_run. Zero-ETL fails tables with cascading keys.
    assert (
        scalar(
            db_settings,
            "SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace"
            f" WHERE n.nspname = '{db_settings.schema_name}' AND c.contype = 'f'"
            " AND (c.confdeltype <> 'a' OR c.confupdtype <> 'a')",
        )
        == 0
    )


@pytest.fixture
def app_user(db_settings):
    """A new app user and schema, set up by db-init and dropped afterwards by the admin."""
    suffix = uuid.uuid4().hex[:8]
    app = DatabaseSettings(
        user=f"test_app_{suffix}", password=f"pw_{suffix}", schema_name=f"test_app_{suffix}"
    )
    admin = AdminSettings()
    yield app, admin

    engine = create_engine(admin.url(app))
    with engine.begin() as conn:
        conn.execute(text(f'DROP SCHEMA IF EXISTS "{app.schema_name}" CASCADE'))
        conn.execute(text(f'DROP OWNED BY "{app.user}"'))
        conn.execute(text(f'DROP ROLE IF EXISTS "{app.user}"'))
    engine.dispose()


def test_db_init_lets_the_app_user_migrate(app_user):
    app, admin = app_user
    init_database(app, admin)
    init_database(app, admin)  # reruns are safe: the role and the schema already exist

    run(app, "migrate")

    assert scalar(app, "SELECT current_user") == app.user
    assert (
        scalar(
            app,
            "SELECT count(*) FROM pg_tables"
            f" WHERE schemaname = '{app.schema_name}' AND tableowner <> '{app.user}'",
        )
        == 0
    )
    assert scalar(app, "SELECT count(*) FROM products") == 29120
