from alembic import context
from sqlalchemy import text

from source_app.db import make_engine
from source_app.models import Base
from source_app.settings import DatabaseSettings

config = context.config


def include_name(name, type_, parent_names) -> bool:
    # alembic_version shares the schema with the app tables; never diff it.
    return not (type_ == "table" and name == "alembic_version")


def run_migrations_online() -> None:
    db = config.attributes.get("db_settings") or DatabaseSettings()
    engine = make_engine(db)

    with engine.connect() as connection:
        # On AWS, db-init creates the schema and the app user can't create schemas, and
        # Postgres checks that privilege even for CREATE SCHEMA IF NOT EXISTS.
        exists = connection.execute(
            text("SELECT 1 FROM pg_namespace WHERE nspname = :name"), {"name": db.schema_name}
        ).first()
        if not exists:
            connection.execute(text(f'CREATE SCHEMA "{db.schema_name}"'))
        # End the implicit transaction, so Alembic's own transaction below commits.
        connection.commit()

        context.configure(
            connection=connection,
            target_metadata=Base.metadata,
            version_table_schema=db.schema_name,
            include_name=include_name,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    raise SystemExit("Offline mode is not supported; run against a database.")

run_migrations_online()
