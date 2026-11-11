"""inspection owner and scheduler appointment (docs/12-scheduler-sync.md)

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-11
"""
from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("inspections", sa.Column("member_id", sa.String(36)))
    op.add_column("inspections", sa.Column("slot_id", sa.String(36)))
    op.add_column("inspections", sa.Column("booked_at", sa.String(40)))
    op.add_column("inspections", sa.Column("vehicle_id", sa.String(20)))
    op.add_column("inspections", sa.Column("slot_done_at", sa.DateTime(timezone=True)))
    op.create_index("ix_inspections_member_id", "inspections", ["member_id"])


def downgrade() -> None:
    op.drop_index("ix_inspections_member_id", table_name="inspections")
    for c in ("slot_done_at", "vehicle_id", "booked_at", "slot_id", "member_id"):
        op.drop_column("inspections", c)
