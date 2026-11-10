import base64
import io
import shutil
import subprocess
import uuid
from types import SimpleNamespace

import httpx
import pytest
from conftest import CARS, PASS, sample
from PIL import Image

from app import ai, config, email, spin, vin


def test_api_needs_the_passcode(client):
    assert client.get("/api/inspections/abc").status_code == 401
    assert client.put("/api/inspections/abc", json={}).status_code == 401
    assert client.get("/api/vin/5UXTY5C00L9B00230", headers={"Authorization": "Bearer nope"}).status_code == 401
    assert client.post("/api/ai/read").status_code == 401


# ---- VIN decode ----

@pytest.mark.parametrize("fields, fuel", [
    ({"ElectrificationLevel": "BEV (Battery Electric Vehicle)", "FuelTypePrimary": "Electric"}, "Electric (EV)"),
    ({"FuelTypePrimary": "Electric"}, "Electric (EV)"),
    ({"ElectrificationLevel": "PHEV (Plug-in Hybrid Electric Vehicle)", "FuelTypePrimary": "Gasoline"}, "Plug-in hybrid"),
    ({"ElectrificationLevel": "PHEV (Plug-in Hybrid Electric Vehicle)", "FuelTypePrimary": "Electric"}, "Plug-in hybrid"),
    ({"ElectrificationLevel": "HEV (Hybrid Electric Vehicle) - Level Unknown", "FuelTypePrimary": "Gasoline"}, "Hybrid"),
    ({"ElectrificationLevel": "Strong HEV (Hybrid Electric Vehicle)"}, "Hybrid"),
    ({"ElectrificationLevel": "Mild HEV (Hybrid Electric Vehicle)"}, "Hybrid"),
    ({"FuelTypePrimary": "Gasoline"}, "Gas"),
    ({"FuelTypePrimary": "Diesel"}, "Diesel"),
    ({"FuelTypePrimary": "Gasoline", "FuelTypeSecondary": "Diesel"}, "Gas"),
])
def test_vin_decode_fuel(client, monkeypatch, fields, fuel):
    result = {"ModelYear": "2020", "Make": "BMW", "Model": "X3", "Trim": "", "ElectrificationLevel": "", "FuelTypePrimary": "", **fields}
    monkeypatch.setattr(vin.httpx, "get", lambda url, timeout: httpx.Response(200, json={"Results": [result]}, request=httpx.Request("GET", url)))
    r = client.get("/api/vin/5UXTY5C00L9B00230", headers=PASS)
    assert r.json() == {"year": 2020, "make": "BMW", "model": "X3", "trim": None, "fuel": fuel}


def test_vin_decode_upstream_error(client, monkeypatch):
    def down(url, timeout):
        raise httpx.ConnectError("down")
    monkeypatch.setattr(vin.httpx, "get", down)
    assert client.get("/api/vin/5UXTY5C00L9B00230", headers=PASS).status_code == 502


# ---- AI readings ----

def fake_ai(monkeypatch, data, seen=None):
    monkeypatch.setattr(config, "ANTHROPIC_API_KEY", "test-key")

    def create(**kw):
        if seen is not None:
            seen.update(kw)
        return SimpleNamespace(content=[SimpleNamespace(type="tool_use", name=kw["tools"][0]["name"], input=data)])
    monkeypatch.setattr(ai, "client", lambda: SimpleNamespace(messages=SimpleNamespace(create=create)))


def photo(w=3000, h=2000) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), "gray").save(buf, "JPEG")
    return buf.getvalue()


def read(client, **form):
    return client.post("/api/ai/read", headers=PASS, data=form, files={"image": ("p.jpg", photo(), "image/jpeg")}).json()


@pytest.mark.parametrize("kind, data, want", [
    ("odometer", {"mileage": 61325}, {"mileage": 61325}),
    ("odometer", {"mileage": 1000000}, {"mileage": None}),
    ("vin", {"vin": "5uxty5c00l9b00230"}, {"vin": "5UXTY5C00L9B00230", "check_digit_ok": True}),
    ("vin", {"vin": "5UXTY5C00L9B00231"}, {"vin": "5UXTY5C00L9B00231", "check_digit_ok": False}),
    ("vin", {"vin": "5UXTY5C00L9B0023I"}, {"vin": None, "check_digit_ok": False}),
    ("tire", {"brand": "michelin", "model": " Pilot  Sport 4S ", "size": "245/50 R19"}, {"brand": "Michelin", "model": "Pilot Sport 4S", "size": "245/50R19"}),
    ("tire", {"brand": "Acme", "model": None, "size": "145/50R19"}, {"brand": None, "model": None, "size": None}),
    ("tread", {"tread_32nds": 7}, {"tread_32nds": 7}),
    ("tread", {"tread_32nds": 15}, {"tread_32nds": None}),
    ("paint_meter", {"mils": 8.04}, {"mils": 8.0, "high": True}),
    ("paint_meter", {"mils": 4.33}, {"mils": 4.3, "high": False}),
    ("paint_meter", {"mils": 120}, {"mils": None, "high": False}),
    ("ev_battery", {"health_pct": 93}, {"health_pct": 93}),
    ("ev_battery", {"health_pct": 0}, {"health_pct": None}),
    ("keys", {"keys_count": 2}, {"keys_count": 2}),
    ("keys", {"keys_count": 3}, {"keys_count": None}),
    ("upright", {"turn_deg": 90}, {"turn_deg": 90}),
    ("upright", {"turn_deg": 45}, {"turn_deg": None}),
])
def test_ai_readings_are_validated(client, monkeypatch, kind, data, want):
    fake_ai(monkeypatch, data)
    assert read(client, kind=kind) == {"ok": True, **want}


def test_ai_damage_uses_the_catalog_list(client, monkeypatch):
    seen = {}
    fake_ai(monkeypatch, {"place": "Left rear door", "type": "Dent", "severity": "Moderate"}, seen)
    assert read(client, kind="damage", section="Exterior", fuel="Gas or diesel") == {"ok": True, "place": "Left rear door", "type": "Dent", "severity": "Moderate"}
    text = seen["messages"][0]["content"][1]["text"]
    assert "\nLeft rear door: " in text and "Charge port" not in text  # Exterior places only
    img = Image.open(io.BytesIO(base64.b64decode(seen["messages"][0]["content"][0]["source"]["data"])))
    assert max(img.size) == 1568 and img.format == "JPEG"
    assert seen["model"] == config.AI_MODEL and seen["tools"][0]["name"] == "label_damage"


def test_ai_damage_pair_not_in_the_list_is_dropped(client, monkeypatch):
    fake_ai(monkeypatch, {"place": "Left rear door", "type": "Curb rash", "severity": "Minor"})
    assert read(client, kind="damage", section="Exterior", fuel="Gas or diesel") == {"ok": True, "place": None, "type": None, "severity": None}
    assert read(client, kind="damage", section="Exterior", hint="Left rear door") == {"ok": True, "place": "Left rear door", "type": None, "severity": None}
    fake_ai(monkeypatch, {"place": "Hood", "type": "Dent", "severity": "Huge"})  # the hint is the place; a bad severity is null
    assert read(client, kind="damage", section="Exterior", hint="Left rear door") == {"ok": True, "place": "Left rear door", "type": "Dent", "severity": None}


def test_ai_damage_reads_every_place_of_its_zone(client, monkeypatch):
    # the AI picks from every place of the damage's section (the zone of the shot it was taken at), not only the shots around it;
    # a near list an older app still sends is ignored
    seen = {}
    fake_ai(monkeypatch, {"place": "Hood", "type": "Dent", "severity": "Minor"}, seen)
    near = '["Left front door", "Left front window", "Mirror"]'
    assert read(client, kind="damage", section="Exterior", fuel="Gas or diesel", near=near) == {"ok": True, "place": "Hood", "type": "Dent", "severity": "Minor"}
    listed = [x.split(":")[0] for x in seen["messages"][0]["content"][1]["text"].split("\n")[1:] if ": " in x]
    assert listed == list(ai.allowed_pairs("Exterior", "Gas or diesel"))
    fake_ai(monkeypatch, {"place": "Left rear wheel", "type": "Curb rash", "severity": "Minor"}, seen)
    assert read(client, kind="damage", section="Tires")["place"] == "Left rear wheel"
    listed = [x.split(":")[0] for x in seen["messages"][0]["content"][1]["text"].split("\n")[1:] if ": " in x]
    assert listed == list(ai.allowed_pairs("Tires", None)) and len(listed) == 8
    # a hint still decides the place
    fake_ai(monkeypatch, {"place": "Left rear tire", "type": "Uneven wear", "severity": "Minor"})
    assert read(client, kind="damage", section="Tires", hint="Left front tire")["place"] == "Left front tire"


def test_ai_errors_give_ok_false(client, monkeypatch):
    assert read(client, kind="odometer") == {"ok": False}  # no ANTHROPIC_API_KEY
    fake_ai(monkeypatch, {"mileage": 5})
    assert read(client, kind="nonsense") == {"ok": False}

    def boom():
        raise anthropic_error()
    monkeypatch.setattr(ai, "client", boom)
    assert read(client, kind="odometer") == {"ok": False}


def anthropic_error():
    import anthropic
    return anthropic.APITimeoutError(request=httpx.Request("POST", "https://api.anthropic.com/v1/messages"))


# ---- inspections: record, files, build ----

def put_record(client, iid, rec):
    return client.put(f"/api/inspections/{iid}", headers=PASS,
                      json={"report_email": "tom@example.com", "inspector": "Tom", "car": CARS["bmw-x3"], "record": rec})


def upload(client, iid, names):
    r = None
    for n in names:
        r = client.put(f"/api/inspections/{iid}/files/{n}", headers=PASS, content=b"bytes of " + n.encode())
        assert r.status_code == 200, (n, r.text)
    return r


@pytest.fixture
def mails(monkeypatch):
    sent = []
    monkeypatch.setattr(email, "send", lambda to, subject, html, text: sent.append({"to": to, "subject": subject, "html": html, "text": text}) or True)
    return sent


def test_upload_flow_end_to_end(client, mails, media_dir):
    iid, rec = str(uuid.uuid4()), sample("bmw-x3")
    r = put_record(client, iid, rec)
    assert r.status_code == 200 and r.json()["status"] == "receiving"
    missing = r.json()["missing"]
    assert len(missing) == 46 + 3 + 8 + 1  # photos, videos, damage photos, signature (documents were seller uploads)
    assert {"signature.png", "damage-1.jpg", "video_360.mp4", "paint-roof.jpg"} <= set(missing)
    assert not any(n.startswith("spin-") or n.startswith("ph_license") for n in missing)
    assert client.post(f"/api/inspections/{iid}/complete", headers=PASS).json() == {"missing": missing}

    upload(client, iid, [spin.frame(k) for k in range(1, 37)])  # frames cut on the phone; never in the missing list
    r = upload(client, iid, missing[:-1])
    assert r.json() == {"missing": missing[-1:]}
    assert client.get(f"/api/inspections/{iid}", headers=PASS).json()["received"] == len(missing) - 1
    assert upload(client, iid, missing[-1:]).json() == {"missing": []}
    assert (media_dir / iid / "damage-1.jpg").read_bytes() == b"bytes of damage-1.jpg"

    r = client.post(f"/api/inspections/{iid}/complete", headers=PASS)
    assert r.status_code == 202 and r.json() == {"status": "building"}
    st = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert st["status"] == "sent", st
    token = st["seller_url"].split("/")[-2]
    assert st["seller_url"] == f"{config.PUBLIC_BASE_URL}/r/{token}/seller" and st["dealer_url"] == f"{config.PUBLIC_BASE_URL}/r/{token}/dealer"
    assert len(token) == 32 and st["missing"] == [] and st["received"] == st["files_expected"] == 58 and st["validation_errors"] == []
    assert st["report_sent_at"]
    assert len(mails) == 1 and mails[0]["to"] == "tom@example.com" and mails[0]["subject"] == "Condition report: 2020 BMW X3 xDrive30i"
    assert st["seller_url"] in mails[0]["html"] and st["dealer_url"] in mails[0]["text"] and "61,325 mi" in mails[0]["text"]
    assert client.get(f"/r/{token}/seller").status_code == 200 and client.get(f"/r/{token}/media/damage-1.jpg").content == b"bytes of damage-1.jpg"

    assert client.post(f"/api/inspections/{iid}/complete", headers=PASS).json() == {"status": "sent"}  # no second build
    assert client.post(f"/api/inspections/{iid}/resend-email", headers=PASS).json()["status"] == "sent" and len(mails) == 2

    # the phone sends the record again: same inspection, files kept, same report link after the rebuild
    r = put_record(client, iid, rec)
    assert r.json() == {"status": "receiving", "missing": []}
    assert client.post(f"/api/inspections/{iid}/resend-email", headers=PASS).status_code == 409
    client.post(f"/api/inspections/{iid}/complete", headers=PASS)
    again = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert again["status"] == "sent" and again["seller_url"] == st["seller_url"] and len(mails) == 3


def test_validation_failure(client, mails):
    iid, rec = str(uuid.uuid4()), sample("bmw-x3")
    rec["damages"][0]["place"] = "Moon roof"
    upload(client, iid, put_record(client, iid, rec).json()["missing"])
    client.post(f"/api/inspections/{iid}/complete", headers=PASS)
    st = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert st["status"] == "failed" and st["seller_url"] is None
    assert "damage 1: place 'Moon roof' is not in the Exterior list" in st["validation_errors"]
    assert mails[0]["subject"] == "Condition report not made: 2020 BMW X3 xDrive30i" and "Moon roof" in mails[0]["text"]
    assert client.post(f"/api/inspections/{iid}/resend-email", headers=PASS).status_code == 409


def test_build_cut_off_by_a_restart_runs_again(client, mails):
    # the server stopped after 'building' was saved: the next start builds it, once
    from app import main
    from app.db import Inspection, SessionLocal
    iid = str(uuid.uuid4())
    upload(client, iid, put_record(client, iid, sample("bmw-x3")).json()["missing"])
    with SessionLocal() as s:
        s.get(Inspection, iid).status = "building"
        s.commit()
    assert client.post(f"/api/inspections/{iid}/complete", headers=PASS).json() == {"status": "building"} and not mails
    main.resume_builds()
    st = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert st["status"] == "sent" and st["seller_url"] and len(mails) == 1
    main.resume_builds()
    main.build(iid)  # a late duplicate task does nothing once it is built
    assert len(mails) == 1 and client.get(f"/api/inspections/{iid}", headers=PASS).json()["seller_url"] == st["seller_url"]


def test_email_not_sent_is_a_failure(client, monkeypatch):
    # no Resend key (or Resend says no): the report is built but not called sent, and resend says so
    from app.db import Inspection, SessionLocal
    iid = str(uuid.uuid4())
    upload(client, iid, put_record(client, iid, sample("bmw-x3")).json()["missing"])
    client.post(f"/api/inspections/{iid}/complete", headers=PASS)
    st = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert st["status"] == "failed" and st["seller_url"] is None and st["report_sent_at"] is None
    assert st["validation_errors"] == ["The report was built but the email was not sent"]
    with SessionLocal() as s:
        token = s.get(Inspection, iid).report_token
    assert client.get(f"/r/{token}/seller").status_code == 200
    assert client.post(f"/api/inspections/{iid}/resend-email", headers=PASS).status_code == 502
    monkeypatch.setattr(email, "send", lambda *a: True)
    r = client.post(f"/api/inspections/{iid}/resend-email", headers=PASS)
    assert r.status_code == 200 and r.json()["status"] == "sent" and r.json()["validation_errors"] == [] and r.json()["report_sent_at"]


def test_end_time_and_signing_are_recorded(client, mails):
    # the phone sends local times with their offset; the report and email show when the inspection ended, signed_at is stored
    from app.db import Inspection, SessionLocal
    iid, rec = str(uuid.uuid4()), sample("bmw-x3")
    rec["source"]["started"]["at"], rec["source"]["ended"]["at"] = "2026-11-07T20:48:00-08:00", "2026-11-07T21:28:12-08:00"
    rec["source"]["ended"]["loc"] = "33.6819, -117.8362"  # where the seller signed
    upload(client, iid, put_record(client, iid, rec).json()["missing"])
    client.post(f"/api/inspections/{iid}/complete", headers=PASS)
    st = client.get(f"/api/inspections/{iid}", headers=PASS).json()
    assert st["status"] == "sent", st
    with SessionLocal() as s:
        insp = s.get(Inspection, iid)
        assert insp.signed_at is not None and insp.inspector == "Tom" and insp.record["source"]["ended"]["loc"] == "33.6819, -117.8362"
    assert "Inspected Nov 7, 2026, 9:28 PM" in mails[0]["text"]
    token = st["seller_url"].split("/")[-2]
    assert "Nov 7, 2026, 9:28 PM" in client.get(f"/r/{token}/seller").text and "Nov 7, 2026, 9:28 PM" in client.get(f"/r/{token}/dealer").text


def test_documents_taken_on_site_are_expected(client):
    rec = sample("bmw-x3")
    rec["documents"] = {"license": "taken on site", "registration": "taken on site", "family_proof": None}
    missing = put_record(client, str(uuid.uuid4()), rec).json()["missing"]
    assert "ph_license.jpg" in missing and "ph_reg.jpg" in missing and "ph_family.jpg" not in missing


def test_file_names_and_unknown_inspection(client):
    iid = str(uuid.uuid4())
    assert client.put(f"/api/inspections/{iid}/files/a.jpg", headers=PASS, content=b"x").status_code == 404
    put_record(client, iid, sample("bmw-x3"))
    for bad in ("a..jpg", ".hidden", "a b.jpg", "a%5Cb.jpg"):
        assert client.put(f"/api/inspections/{iid}/files/{bad}", headers=PASS, content=b"x").status_code == 400, bad
    assert client.put(f"/api/inspections/{iid}/files/..%2Fx.jpg", headers=PASS, content=b"x").status_code in (400, 404)
    assert client.get("/api/inspections/nope", headers=PASS).status_code == 404
    assert client.put("/api/inspections/bad..id", headers=PASS, json={}).status_code == 422


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="needs ffmpeg")
def test_spin_fallback_cuts_36_frames(media_dir):
    video = media_dir / "video_360.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=3:size=320x180:rate=30", "-pix_fmt", "yuv420p", str(video)], check=True)
    spin.ensure_frames(media_dir)
    assert spin.have_frames(media_dir)
    assert Image.open(media_dir / "spin-36.jpg").size == (1600, 900)


def test_ai_mechanicals_includes_underbody_places():
    from app.ai import allowed_pairs
    pairs = allowed_pairs("Mechanicals", "Gas or diesel")
    assert "Structure" in pairs and "Fluids" in pairs


def test_ai_uses_openai_when_its_key_is_set(client, monkeypatch):
    import json as _json
    from app import ai
    monkeypatch.setattr(config, "OPENAI_API_KEY", "sk-test")
    seen = {}

    def post(url, json, timeout, headers):
        seen.update(url=url, body=json, auth=headers["Authorization"])
        return httpx.Response(200, json={"choices": [{"message": {"content": _json.dumps({"mileage": 61325})}}]}, request=httpx.Request("POST", url))
    monkeypatch.setattr(ai.httpx, "post", post)
    r = client.post("/api/ai/read", headers=PASS, data={"kind": "odometer"}, files={"image": ("o.jpg", photo(), "image/jpeg")})
    assert r.json() == {"ok": True, "mileage": 61325}
    assert seen["url"].endswith("/v1/chat/completions") and seen["auth"] == "Bearer sk-test"
    fmt = seen["body"]["response_format"]["json_schema"]
    assert fmt["strict"] is True and fmt["schema"]["required"] == ["mileage"]
