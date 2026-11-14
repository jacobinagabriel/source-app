"""order_items foreign key without ON DELETE CASCADE

Zero-ETL integrations fail tables whose foreign keys cascade, so the app deletes an
order's items itself before the order.

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-14

"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

FK = "order_items_order_id_fkey"


def upgrade() -> None:
    """Upgrade schema."""
    op.drop_constraint(FK, "order_items", type_="foreignkey")
    op.create_foreign_key(FK, "order_items", "orders", ["order_id"], ["id"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint(FK, "order_items", type_="foreignkey")
    op.create_foreign_key(FK, "order_items", "orders", ["order_id"], ["id"], ondelete="CASCADE")
