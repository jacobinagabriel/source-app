from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload, selectinload

from source_app.models import Order, User


def random_user(session: Session) -> User | None:
    return session.scalars(select(User).order_by(func.random()).limit(1)).first()


def random_order(session: Session) -> Order | None:
    stmt = (
        select(Order)
        .options(joinedload(Order.user), selectinload(Order.items))
        .order_by(func.random())
        .limit(1)
    )
    return session.scalars(stmt).first()
