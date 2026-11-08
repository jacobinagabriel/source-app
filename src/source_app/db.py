from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import sessionmaker

from source_app.settings import DatabaseSettings


def make_engine(db: DatabaseSettings) -> Engine:
    # Tables are unqualified in the models and migrations; the schema comes from search_path.
    return create_engine(
        db.url(),
        echo=db.echo,
        pool_pre_ping=True,
        connect_args={"options": f"-c search_path={db.schema_name}"},
    )


def make_sessionmaker(db: DatabaseSettings) -> sessionmaker:
    return sessionmaker(make_engine(db), expire_on_commit=False)
