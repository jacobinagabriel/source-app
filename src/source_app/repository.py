import datetime
import uuid

from sqlalchemy import Select, delete, select
from sqlalchemy.orm import Session, joinedload, selectinload

from source_app.models import Event, Order, OrderStatus, User, utcnow


def _random_row(session: Session, stmt: Select, id_column):
    """Picks a row by jumping to a random UUID in the primary-key index.

    Ids are random UUIDs, so the first id at or after a random pivot is close to a
    uniform pick. Unlike ORDER BY random(), this reads one index entry instead of
    scanning and sorting the whole table. If the pivot lands after the last id, it
    wraps around to the first one.
    """
    pivot = uuid.uuid4()
    row = session.scalars(stmt.where(id_column >= pivot).order_by(id_column).limit(1)).first()
    if row is None:
        row = session.scalars(stmt.order_by(id_column).limit(1)).first()
    return row


def has_users(session: Session) -> bool:
    return session.scalars(select(User.id).limit(1)).first() is not None


def random_user(session: Session) -> User | None:
    return _random_row(session, select(User), User.id)


def random_order(session: Session) -> Order | None:
    stmt = select(Order).options(joinedload(Order.user), selectinload(Order.items))
    return _random_row(session, stmt, Order.id)


def random_cancelled_order(session: Session) -> Order | None:
    stmt = select(Order).where(Order.status == OrderStatus.CANCELLED.value)
    return _random_row(session, stmt, Order.id)


def purge_ghost_events(session: Session, older_than: datetime.timedelta, limit: int) -> int:
    """Deletes up to `limit` of the oldest anonymous events older than `older_than`."""
    oldest = (
        select(Event.id)
        .where(Event.user_id.is_(None), Event.created_at < utcnow() - older_than)
        .order_by(Event.created_at)
        .limit(limit)
    )
    result = session.execute(delete(Event).where(Event.id.in_(oldest)))
    return result.rowcount
