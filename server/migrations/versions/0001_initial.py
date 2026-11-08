"""inspections and files

Revision ID: 0001
Revises:
Create Date: 2026-11-07
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "inspections",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("inspector", sa.String(200)),
        sa.Column("report_email", sa.String(320)),
        sa.Column("car", sa.JSON()),
        sa.Column("record", sa.JSON()),
        sa.Column("status", sa.String(20), nullable=False, server_default="receiving"),
        sa.Column("report_token", sa.String(64)),
        sa.Column("cr", sa.JSON()),
        sa.Column("validation_errors", sa.JSON()),
        sa.Column("files_expected", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("signed_at", sa.DateTime(timezone=True)),
        sa.Column("report_sent_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_inspections_report_token", "inspections", ["report_token"], unique=True)
    op.create_table(
        "files",
        sa.Column("inspection_id", sa.String(36), sa.ForeignKey("inspections.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("name", sa.String(200), primary_key=True),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("content_type", sa.String(100)),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("files")
    op.drop_index("ix_inspections_report_token", table_name="inspections")
    op.drop_table("inspections")
