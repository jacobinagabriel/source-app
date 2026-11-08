import asyncio
import os
import uuid

import pytest
from faker import Faker
from sqlalchemy import create_engine, text

from source_app.settings import DatabaseSettings, SimulationSettings
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


def run(db: DatabaseSettings, command: str, **sim) -> None:
    Faker.seed(7)
    simulator = TheLookECommSimulator(db, SimulationSettings(**sim), Faker())
    try:
        asyncio.run(getattr(simulator, command)())
    finally:
        asyncio.run(simulator.close())


def test_migrate_seed_and_run(db_settings):
    run(db_settings, "migrate")
    assert scalar(db_settings, "SELECT version_num FROM alembic_version") == "0002"
    assert scalar(db_settings, "SELECT count(*) FROM products") == 29120
    assert scalar(db_settings, "SELECT count(*) FROM dist_centers") == 10

    run(db_settings, "seed", init_num_users=50)
    assert scalar(db_settings, "SELECT count(*) FROM users") == 50

    run(db_settings, "run", max_iter=100, avg_qps=1000, order_update_prob=0.9)
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
