"""seed reference data (distribution centers, products)

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-08

"""

from collections.abc import Sequence
from decimal import Decimal

import sqlalchemy as sa
from alembic import op

from source_app.utils import generate_from_csv

# revision identifiers, used by Alembic.
revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Table definitions are frozen here instead of importing the ORM models, so this
# migration keeps working when the models change later.
dist_centers = sa.table(
    "dist_centers",
    sa.column("id", sa.BigInteger),
    sa.column("name", sa.Text),
    sa.column("latitude", sa.Double),
    sa.column("longitude", sa.Double),
)

products = sa.table(
    "products",
    sa.column("id", sa.BigInteger),
    sa.column("cost", sa.Numeric(12, 2)),
    sa.column("category", sa.Text),
    sa.column("name", sa.Text),
    sa.column("brand", sa.Text),
    sa.column("retail_price", sa.Numeric(12, 2)),
    sa.column("department", sa.Text),
    sa.column("sku", sa.Text),
    sa.column("distribution_center_id", sa.BigInteger),
)


def _money(value: str) -> Decimal:
    return Decimal(value).quantize(Decimal("0.01"))


def upgrade() -> None:
    op.bulk_insert(
        dist_centers,
        [
            {
                "id": int(row["id"]),
                "name": row["name"],
                "latitude": float(row["latitude"]),
                "longitude": float(row["longitude"]),
            }
            for row in generate_from_csv("distribution_centers.csv")
        ],
    )
    op.bulk_insert(
        products,
        [
            {
                "id": int(row["id"]),
                "cost": _money(row["cost"]),
                "category": row["category"],
                "name": row["name"] or None,
                "brand": row["brand"] or None,
                "retail_price": _money(row["retail_price"]),
                "department": row["department"],
                "sku": row["sku"],
                "distribution_center_id": int(row["distribution_center_id"]),
            }
            for row in generate_from_csv("products.csv")
        ],
    )


def downgrade() -> None:
    op.execute(products.delete())
    op.execute(dist_centers.delete())
