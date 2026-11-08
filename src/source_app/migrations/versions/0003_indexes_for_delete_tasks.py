"""indexes for delete tasks

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-08

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_index(
        "ix_events_ghost_created_at",
        "events",
        ["created_at"],
        unique=False,
        postgresql_where=sa.text("user_id IS NULL"),
    )
    op.create_index(
        "ix_orders_cancelled_id",
        "orders",
        ["id"],
        unique=False,
        postgresql_where=sa.text("status = 'Cancelled'"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(
        "ix_orders_cancelled_id",
        table_name="orders",
        postgresql_where=sa.text("status = 'Cancelled'"),
    )
    op.drop_index(
        "ix_events_ghost_created_at",
        table_name="events",
        postgresql_where=sa.text("user_id IS NULL"),
    )
