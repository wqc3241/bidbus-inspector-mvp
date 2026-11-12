import json
import re
import secrets
import uuid

import pytest
from conftest import CARS, ROOT, sample

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
    assert 'class="cloudimage-360"' in html and "@cloudimage/360-view@4.10.0" in html


@pytest.mark.parametrize("page", ["seller", "dealer"])
def test_obd_screens_under_obd_problems(client, page):
    # gas car with Check engine and stored codes: the OBD-II block shows its five scan screens
    token, _ = make("bmw-x3")
    html = client.get(f"/r/{token}/{page}").text
    block = html[html.index("OBD-II</dt>"):].split('<div class="ir">')[0]
    shots = re.findall(r'<a class="dth scr" href="/r/' + token + r'/media/([^"]+)" title="([^"]+)">', block)
    assert shots == [("ph_obd_current.jpg", "OBD-II current codes"), ("ph_obd_past.jpg", "OBD-II past codes"),
                     ("ph_obd_emission.jpg", "OBD-II emission codes"), ("ph_obd_other-1.jpg", "OBD-II other"), ("ph_obd_other-2.jpg", "OBD-II other")]
    assert block.index("Scan result") < block.index('class="shots"')  # under the problems
    assert html.count('class="dth scr"') == 5  # nowhere else
    # no OBD-II problem: no screens in the block (they stay in the photo viewer)
    rec = sample("bmw-x3")
    rec["checks"] = [{"id": c["id"], "result": "OK"} if c["id"] in ("ck_lights_dash", "ck_scan") else c for c in rec["checks"]]
    iid, tok = str(uuid.uuid4()), secrets.token_urlsafe(24)
    with SessionLocal() as s:
        s.add(Inspection(id=iid, report_email="tom@example.com", inspector="Tom", car=CARS["bmw-x3"], record=rec, status="sent",
                         report_token=tok, cr=build_cr(rec)))
        s.commit()
    html = client.get(f"/r/{tok}/{page}").text
    assert 'class="dth scr"' not in html and "OBD-II</dt>" in html


@pytest.mark.parametrize("page", ["seller", "dealer"])
def test_eight_exterior_views_follow_the_360_view(client, media_dir, page):
    token, iid = make("bmw-x3")
    (media_dir / iid).mkdir()
    assert 'alt="Left front"' not in client.get(f"/r/{token}/{page}").text  # no frames, no views
    for k in range(1, 37):
        (media_dir / iid / f"spin-{k:02d}.jpg").write_bytes(b"x")
    html = client.get(f"/r/{token}/{page}").text
    track = html[html.index('class="g-track"'):html.index('class="g-nav prev"')]
    slides = re.findall(r'data-lbl="([^"]*)"', track)
    views = ["Left front", "Left side", "Left rear", "Rear", "Right rear", "Right side", "Right front", "Front"]
    # the 360 view, then the eight views in the walk-around order (spin frames 1, 5, 10, 14, 19, 23, 28, 32), then the rest of Exterior
    assert slides[:9] == ["360 view"] + views
    for k, v in zip((1, 5, 10, 14, 19, 23, 28, 32), views):
        assert f'<img src="/r/{token}/media/spin-{k:02d}.jpg" alt="{v}" loading="lazy">' in track


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


def test_date_is_the_day_on_the_phone(client):
    # started 8:48 PM on Nov 7 on the phone, which is already Nov 8 in UTC on the server
    from datetime import datetime, timezone

    from app.email import date, inspected_on
    rec = sample("bmw-x3")
    rec["source"]["started"]["at"] = "2026-11-07T20:48:12.345678"
    token = secrets.token_urlsafe(24)
    with SessionLocal() as s:
        insp = Inspection(id=str(uuid.uuid4()), report_email="tom@example.com", inspector="Tom", car=CARS["bmw-x3"], record=rec, status="sent",
                          report_token=token, cr=build_cr(rec), created_at=datetime(2026, 11, 8, 5, 28, tzinfo=timezone.utc))
        s.add(insp)
        s.commit()
        assert date(inspected_on(insp)) == "Nov 7, 2026"
    assert "Nov 7, 2026" in client.get(f"/r/{token}/seller").text


def test_dealer_specs_show_the_fuel_picked_on_the_phone(client):
    # Gas and Diesel are picked apart on the phone; the record and CR keep 'Gas or diesel'
    token = secrets.token_urlsafe(24)
    with SessionLocal() as s:
        s.add(Inspection(id=str(uuid.uuid4()), report_email="tom@example.com", inspector="Tom", car={**CARS["bmw-x3"], "fuel": "Diesel"},
                         record=sample("bmw-x3"), status="sent", report_token=token, cr=build_cr(sample("bmw-x3"))))
        s.commit()
    specs = client.get(f"/r/{token}/dealer").text.split("Vehicle Details")[-1]
    assert "Diesel" in specs and ">Gas<" not in specs
    gas = client.get(f"/r/{make('bmw-x3')[0]}/dealer").text.split("Vehicle Details")[-1]
    assert ">Gas<" in gas


def test_a_trim_that_starts_with_the_model_is_not_repeated():
    from app.email import car_line
    assert car_line({"year": 2020, "make": "Lexus", "model": "LC", "trim": "LC 500h"}) == "2020 Lexus LC 500h"
    assert car_line({"year": 2020, "make": "BMW", "model": "X3", "trim": "xDrive30i"}) == "2020 BMW X3 xDrive30i"
    assert car_line({"year": 2021, "make": "Toyota", "model": "RAV4", "trim": "RAV4 Prime XSE"}) == "2021 Toyota RAV4 Prime XSE"


@pytest.mark.parametrize("name,hi,lo", [("bmw-x3", "Left rear door", "Left front fender"), ("tesla-model-y", "Right rear door", "Left front fender")])
def test_paint_highest_and_lowest(client, name, hi, lo):
    """the Paint block shows the highest and lowest panel reading; above 10 reads 10+ (both samples have one)"""
    token, _ = make(name)
    for page in ("seller", "dealer"):
        html = client.get(f"/r/{token}/{page}").text
        assert f"Highest reading 10+ mils<small>{hi}</small>" in html, page
        assert f"Lowest reading 4.3 mils<small>{lo}</small>" in html, page


def test_paint_reads_rules():
    from app.reports import mils_text, paint_reads
    assert [mils_text(m) for m in (3.0, 10.0, 10.1, 11.8)] == ["3.0", "10.0", "10+", "10+"]
    rec = {"paint": [{"panel": "Hood or frunk lid", "mils": 3.9, "not_on_car": False}, {"panel": "Roof", "mils": None, "not_on_car": True},
                     {"panel": "Left front door", "mils": 2.0, "not_on_car": True}, {"panel": "Trunk or liftgate", "mils": 6.2, "not_on_car": False}]}
    assert paint_reads(rec) == [{"icon": "↑", "text": "Highest reading 6.2 mils", "sub": "Trunk or liftgate"},
                                {"icon": "↓", "text": "Lowest reading 3.9 mils", "sub": "Hood"}]
    assert paint_reads({"paint": [{"panel": "Roof", "mils": None, "not_on_car": True}]}) == []


def test_a_report_sent_before_the_rename_shows_the_new_wording(client):
    """record and stored CR in the old option wording: the pages are the same as for a record sent today"""
    new_to_old = {n: o for o, n in json.load(open(ROOT / "data" / "option-renames.json")).items()}
    old_rec = json.loads(json.dumps(sample("bmw-x3")), object_hook=lambda d: {k: new_to_old.get(v, v) if isinstance(v, str) else v for k, v in d.items()})
    assert old_rec != sample("bmw-x3")
    old_cr = build_cr(old_rec)
    for i in old_cr["condition_report"]["issues"]:
        i["text"] = "old wording"
    token, iid = make("bmw-x3")
    old_token = secrets.token_urlsafe(24)
    with SessionLocal() as s:
        s.add(Inspection(id=str(uuid.uuid4()), report_email="tom@example.com", inspector="Tom", car=CARS["bmw-x3"], record=old_rec, status="sent",
                         report_token=old_token, cr=old_cr, created_at=s.get(Inspection, iid).created_at))
        s.commit()
    for page in ("seller", "dealer"):
        old_page = client.get(f"/r/{old_token}/{page}").text
        assert "old wording" not in old_page
        assert old_page.replace(old_token, token) == client.get(f"/r/{token}/{page}").text
