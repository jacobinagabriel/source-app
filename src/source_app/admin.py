import logging

from psycopg2 import sql
from sqlalchemy import create_engine

from source_app.settings import AdminSettings, DatabaseSettings


def init_database(db: DatabaseSettings, admin: AdminSettings) -> None:
    """Creates the app user and its schema, connecting as the admin. Safe to rerun.

    The schema is owned by the admin, and the app user gets USAGE and CREATE on it, so it
    owns the tables its migrations create. Making the app user the schema owner would
    need the admin to SET ROLE to it, which an RDS master user can't do by default.
    """
    user = sql.Identifier(db.user)
    password = sql.Literal(db.password.get_secret_value())
    schema = sql.Identifier(db.schema_name)

    engine = create_engine(admin.url(db))
    conn = engine.raw_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (db.user,))
            if cur.fetchone():
                logging.info(f"Role {db.user} exists; resetting its password.")
                cur.execute(sql.SQL("ALTER ROLE {} WITH LOGIN PASSWORD {}").format(user, password))
            else:
                logging.info(f"Creating role {db.user}...")
                cur.execute(sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD {}").format(user, password))
            cur.execute(
                sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(sql.Identifier(db.name), user)
            )
            cur.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(schema))
            cur.execute(sql.SQL("GRANT USAGE, CREATE ON SCHEMA {} TO {}").format(schema, user))
        conn.commit()
    finally:
        conn.close()
        engine.dispose()
    logging.info(f"Database ready: role {db.user} can use schema {db.schema_name}.")
