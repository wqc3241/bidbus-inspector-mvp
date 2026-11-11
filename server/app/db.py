"""Engine, session and models (docs/06-backend.md, Tables)."""
from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from . import config

engine = create_engine(
    config.DATABASE_URL,
    pool_pre_ping=True,
    connect_args={"check_same_thread": False} if config.DATABASE_URL.startswith("sqlite") else {},
)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def now() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Inspection(Base):
    __tablename__ = "inspections"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # UUID made on the phone
    inspector: Mapped[str | None] = mapped_column(String(200))
    report_email: Mapped[str | None] = mapped_column(String(320))
    car: Mapped[dict | None] = mapped_column(JSON)  # year, make, model, trim, owner_name
    record: Mapped[dict | None] = mapped_column(JSON)  # the inspection record (samples/inspection-*.json)
    status: Mapped[str] = mapped_column(String(20), default="receiving")  # receiving, building, sent, failed
    report_token: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)
    cr: Mapped[dict | None] = mapped_column(JSON)  # tools/cr_from_inspection.py output
    validation_errors: Mapped[list | None] = mapped_column(JSON)
    files_expected: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    signed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    report_sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # with scheduler sign-in (docs/12-scheduler-sync.md): whose inspection it is, and the appointment it was started from
    member_id: Mapped[str | None] = mapped_column(String(36), index=True)  # scheduler members.id
    slot_id: Mapped[str | None] = mapped_column(String(36))  # scheduler slots.id
    booked_at: Mapped[str | None] = mapped_column(String(40))  # slots.booked_at as the scheduler gave it: with slot_id, the appointment
    vehicle_id: Mapped[str | None] = mapped_column(String(20))  # Bidbus vehicles.id (the scheduler's Listing ID)
    slot_done_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # when the scheduler job was marked completed


class File(Base):
    __tablename__ = "files"

    inspection_id: Mapped[str] = mapped_column(String(36), ForeignKey("inspections.id", ondelete="CASCADE"), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), primary_key=True)
    size: Mapped[int] = mapped_column(Integer)
    content_type: Mapped[str | None] = mapped_column(String(100))
    sha256: Mapped[str] = mapped_column(String(64))
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


def get_session():
    with SessionLocal() as s:
        yield s
