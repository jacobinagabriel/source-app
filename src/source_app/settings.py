from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class DatabaseSettings(BaseSettings):
    """Connection settings, read from DB_* environment variables."""

    model_config = SettingsConfigDict(env_prefix="DB_", populate_by_name=True)

    host: str = "localhost"
    port: int = 5432
    name: str = "source_app"
    user: str = "source_app"
    password: SecretStr = SecretStr("source_app")
    # `schema` clashes with a BaseModel attribute, so the field gets another name.
    schema_name: str = Field("demo", validation_alias="DB_SCHEMA")
    echo: bool = False

    def url(self) -> URL:
        return URL.create(
            "postgresql+psycopg2",
            username=self.user,
            password=self.password.get_secret_value(),
            host=self.host,
            port=self.port,
            database=self.name,
        )


class AdminSettings(BaseSettings):
    """Credentials of the database admin, read from DB_ADMIN_* environment variables.

    Only `db-init` uses them, to create the app user and its schema. On Aurora this is
    the master user; in docker-compose it's the postgres superuser.
    """

    model_config = SettingsConfigDict(env_prefix="DB_ADMIN_")

    user: str = "postgres"
    password: SecretStr = SecretStr("postgres")

    def url(self, db: DatabaseSettings) -> URL:
        """The app database's URL, connecting as the admin."""
        return db.url().set(username=self.user, password=self.password.get_secret_value())


class SimulationSettings(BaseSettings):
    """Traffic shape, read from SIM_* environment variables."""

    model_config = SettingsConfigDict(env_prefix="SIM_")

    avg_qps: float = 20.0
    max_iter: int = -1
    init_num_users: int = 1000
    country: str = "*"
    state: str = "*"
    postal_code: str = "*"
    user_create_prob: float = 0.05
    user_update_prob: float = 0.1
    order_update_prob: float = 0.4
    ghost_create_prob: float = 0.2
    order_delete_prob: float = 0.05
    ghost_purge_prob: float = 0.05
    ghost_retention_minutes: int = 60
    ghost_purge_batch: int = 100
