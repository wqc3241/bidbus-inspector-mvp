"""Settings read from environment variables (names as in .env.example)."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # repo root locally, /srv in the image
DATA_DIR = ROOT / "data"
TOOLS_DIR = ROOT / "tools"


def _db_url(raw: str) -> str:
    # Railway gives postgresql:// (or postgres://); SQLAlchemy needs the psycopg 3 driver named
    for prefix in ("postgres://", "postgresql://"):
        if raw.startswith(prefix):
            return "postgresql+psycopg://" + raw[len(prefix):]
    return raw


DATABASE_URL = _db_url(os.environ.get("DATABASE_URL", "sqlite:///./inspector.db"))
MEDIA_DIR = Path(os.environ.get("MEDIA_DIR", "./media"))
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "http://localhost:8000").rstrip("/")
APP_PASSCODE = os.environ.get("APP_PASSCODE", "")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
AI_MODEL = os.environ.get("AI_MODEL", "claude-sonnet-5-5")
# with an OpenAI key the readings use OpenAI; otherwise Anthropic
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.5")
RESEND_API_KEY = os.environ.get("RESEND_API_KEY", "")
EMAIL_FROM = os.environ.get("EMAIL_FROM", "Bidbus Field <onboarding@resend.dev>")
# inspection scheduler sign-in and appointments (docs/12-scheduler-sync.md); without them the app uses APP_PASSCODE
SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
SCHEDULER_URL = os.environ.get("SCHEDULER_URL", "")
# car brief from the Bidbus admin API (one admin service account)
BIDBUS_API_URL = os.environ.get("BIDBUS_API_URL", "https://api.bidbus.com")
BIDBUS_ADMIN_PHONE = os.environ.get("BIDBUS_ADMIN_PHONE", "")
BIDBUS_ADMIN_PASSWORD = os.environ.get("BIDBUS_ADMIN_PASSWORD", "")
