import json
import os
import sys
from pathlib import Path

# tests run on SQLite with a fixed passcode; set before the app is imported
os.environ.setdefault("DATABASE_URL", "sqlite:///" + str(Path(__file__).parent / "test.db"))
os.environ.setdefault("APP_PASSCODE", "test-passcode")
os.environ.setdefault("MEDIA_DIR", str(Path(__file__).parent / "media"))
os.environ["ANTHROPIC_API_KEY"] = os.environ["OPENAI_API_KEY"] = os.environ["RESEND_API_KEY"] = ""  # no network in tests
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402

PASS = {"Authorization": "Bearer test-passcode"}
ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ROOT / "samples"
CARS = {"bmw-x3": {"year": 2020, "make": "BMW", "model": "X3", "trim": "xDrive30i", "owner_name": "Daniel Kim"},
        "tesla-model-y": {"year": 2022, "make": "Tesla", "model": "Model Y", "trim": "Long Range AWD", "owner_name": None}}


@pytest.fixture(autouse=True)
def fresh_db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch):
    from app import config
    monkeypatch.setattr(config, "MEDIA_DIR", tmp_path)
    return tmp_path


@pytest.fixture
def client():
    return TestClient(app)


def sample(name: str) -> dict:
    return json.loads((SAMPLES / f"inspection-{name}.json").read_text())
