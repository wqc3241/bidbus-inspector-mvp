import re
import secrets
import uuid

import pytest
from conftest import CARS, sample

from app.cr import build_cr
from app.db import Inspection, SessionLocal

PRIVATE = ["ph_license.jpg", "ph_reg.jpg", "ph_family.jpg", "signature.png"]


def make(name: str) -> tuple[str, str]:
    """an inspection row with its CR, as the build pipeline leaves it"""
    iid, token = str(uuid.uuid4()), secrets.token_urlsafe(24)
    with SessionLocal() as s:
        s.add(Inspection(id=iid, report_email="tom@example.com", inspector="Tom", car=CARS[name], record=sample(name), status="sent",
                         report_token=token, cr=build_cr(sample(name))))
        s.commit()
    return token, iid


@pytest.mark.parametrize("name", ["bmw-x3", "tesla-model-y"])
def test_pages_render_without_private_data(client, name):
    token, _ = make(name)
    gps = sample(name)["source"]["started"]["loc"]
    for page in ("seller", "dealer"):
        r = client.get(f"/r/{token}/{page}")
        assert r.status_code == 200
        html = r.text.lower()
        for word in ("license", "registration", "signature", gps):
            assert word not in html, (page, word)
        assert not re.search(r"\blight\b", html), page  # the light is never shown ("Highlight" is a heading)
    seller = client.get(f"/r/{token}/seller").text
    for word in ("protection", "guarantee", "buyback"):
        assert word not in seller.lower()
    assert "Dashboard <b>› Condition report</b>" in seller and "Same-day payment" in seller
    assert "Left rear door: Dent, Moderate, 2 in" in seller or name != "bmw-x3"
    assert "<em class=\"lvt" not in seller  # no level tags for the seller


def test_dealer_page_parts(client):
    token, _ = make("bmw-x3")
    html = client.get(f"/r/{token}/dealer").text
    assert "Vehicle details" in html and "Title, odometer, legal" in html  # Red light: limited protection
    assert html.index("Trunk or liftgate: Structure, Severe") < html.index("Warning lights: Check engine")  # Red before Yellow
    assert '<em class="lvt sev">Red</em>' in html and "No issues · 1 check" in html  # Engine sound row, Engine check OK
    assert "Engine sound at the first start" in html and "Inspector's note" in html
    for part in ("Exterior", "Paint", "Tires", "Underbody", "Mechanicals", "Engine sound", "Interior", "OBD-II", "Additionals"):
        assert f"{part}</dt>" in html
    ev = client.get(f"/r/{make('tesla-model-y')[0]}/dealer").text
    assert "Engine sound</dt>" not in ev and "Battery health" in ev


def test_media_never_serves_documents_or_signature(client, media_dir):
    token, iid = make("bmw-x3")
    (media_dir / iid).mkdir()
    for name in PRIVATE + ["damage-1.jpg"]:
        (media_dir / iid / name).write_bytes(b"0123456789")
    for name in PRIVATE:
        assert client.get(f"/r/{token}/media/{name}").status_code == 404
    r = client.get(f"/r/{token}/media/damage-1.jpg")
    assert r.status_code == 200 and r.headers["cache-control"] == "private, max-age=86400"
    assert client.get(f"/r/{token}/media/damage-1.jpg", headers={"Range": "bytes=2-4"}).content == b"234"
    assert client.get(f"/r/{token}/media/nothing.jpg").status_code == 404
    assert client.get("/r/not-a-token/media/damage-1.jpg").status_code == 404


def test_spin_view_when_frames_are_there(client, media_dir):
    token, iid = make("bmw-x3")
    (media_dir / iid).mkdir()
    assert "class=\"cloudimage-360\"" not in client.get(f"/r/{token}/seller").text
    for k in range(1, 37):
        (media_dir / iid / f"spin-{k:02d}.jpg").write_bytes(b"x")
    html = client.get(f"/r/{token}/dealer").text
    assert 'class="cloudimage-360"' in html and "js-cloudimage-360-view@4.9.5" in html


def test_media_serves_only_public_files_with_their_type(client, media_dir):
    import json
    from conftest import SAMPLES
    from app.db import Inspection, SessionLocal
    rec = json.loads((SAMPLES / "inspection-bmw-x3.json").read_text())
    with SessionLocal() as s:
        s.add(Inspection(id="m1", record=rec, status="sent", report_token="tok-media", cr={"built": True}))
        s.commit()
    d = media_dir / "m1"
    d.mkdir(parents=True)
    photo = rec["photos"][0]["file"]
    for n in (photo, "ph_license.jpg", "signature.png", "spin-01.jpg", "notes.html"):
        (d / n).write_bytes(b"x")
    r = client.get(f"/r/tok-media/media/{photo}")
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg" and r.headers["x-content-type-options"] == "nosniff"
    assert client.get("/r/tok-media/media/spin-01.jpg").status_code == 200
    for n in ("ph_license.jpg", "PH_LICENSE.jpg", "signature.png", "notes.html", "unknown.jpg"):
        assert client.get(f"/r/tok-media/media/{n}").status_code == 404, n


def test_upload_refuses_other_file_types(client):
    from conftest import PASS
    client.put("/api/inspections/u1", headers=PASS, json={"report_email": "a@b.co", "car": {}, "record": {"photos": []}})
    assert client.put("/api/inspections/u1/files/x.html", headers=PASS, content=b"<script>").status_code == 400
    assert client.put("/api/inspections/u1/files/video_360.m3u8", headers=PASS, content=b"#EXTM3U").status_code == 400
