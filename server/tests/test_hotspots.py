"""Damage dots on the 360 view: which damages get one, the frames asked about, what the AI answers becoming dots, the saved file,
the background run, and the report's viewer settings."""
import json
import re
import secrets
import uuid

import pytest
from conftest import CARS, sample

from app import hotspots, main, spin
from app.cr import build_cr
from app.db import Inspection, SessionLocal

PARTS = ["Left front door", "Front bumper", "Hood", "Right front wheel"]


def rec_with(places, **over):
    rec = sample("bmw-x3")
    base = dict(rec["damages"][0])
    sec = lambda p: "Tires" if "wheel" in p or "tire" in p else "Exterior"  # noqa: E731
    rec["damages"] = [{**base, "n": i + 1, "section": sec(p), "place": p, "file": f"damage-{i + 1}.jpg", "confirmed": True, **over}
                      for i, p in enumerate(places)]
    return rec


def frames(d):
    for k in range(1, 37):
        (d / spin.frame(k)).write_bytes(b"jpg")


class FakeAI:
    """answers each frame from a table: part -> {frame: (x, y) 0-1000}; damage photos answer a side"""

    def __init__(self, seen, side="left"):
        self.seen, self.side, self.asked = seen, side, []

    def __call__(self, name, props, text, image):
        if name == "damage_side":
            self.asked.append(("side", None))
            return {"side": self.side}
        k = int(re.search(r"frame (\d+) of", text)[1])
        parts = props["parts"]["items"]["properties"]["part"]["enum"]
        self.asked.append((k, tuple(parts)))
        return {"parts": [{"part": p, "visible": k in self.seen.get(p, {}), "x": self.seen.get(p, {}).get(k, (None, None))[0],
                           "y": self.seen.get(p, {}).get(k, (None, None))[1]} for p in parts]}


@pytest.fixture
def ai_on(monkeypatch):
    monkeypatch.setattr(hotspots.ai, "configured", lambda: True)


def test_which_damages_get_a_dot():
    rec = rec_with(["Left front door", "Hood or frunk lid", "Mirror", "Other", "Right front wheel"])
    rec["damages"].append({**rec["damages"][0], "n": 6, "place": "Carpet", "section": "Interior"})
    rec["damages"].append({**rec["damages"][0], "n": 7, "confirmed": False})
    rec["damages"].append({**rec["damages"][0], "n": 8, "file": None})
    rec["damages"].append({**rec["damages"][0], "n": '1"><img src=x onerror=alert(1)>'})  # a number that is not a number: never on the page
    # confirmed, with a photo, seen from outside, on a part the 360 can show; a Paint place of the hood is the hood
    assert [(d["n"], d["place"]) for d in hotspots.marked(rec)] == [(1, "Left front door"), (2, "Hood"), (3, "Mirror"), (5, "Right front wheel")]


def test_frames_asked_about_round_the_walk():
    assert hotspots.frames_for(32.5, 8) == [1, 2, 3, 4] + list(range(25, 37))  # the front: round the end of the walk
    assert hotspots.frames_for(5, 5) == list(range(1, 11)) + [36]
    assert len(hotspots.frames_for(18.5, 18)) == 36  # the roof: any frame
    assert [hotspots.where(k) for k in (1, 5, 10, 14, 19, 23, 28, 32, 36)] == [
        "left front corner", "left side", "left rear corner", "rear", "right rear corner", "right side", "right front corner", "front", "left front corner"]


def test_answers_become_dots(media_dir, monkeypatch, ai_on):
    d = media_dir / "i1"
    d.mkdir()
    frames(d)
    door = {k: (500 + 10 * k, 420) for k in range(2, 9)} | {6: (990, 10)}  # frame 6 jumps: the median with its neighbours puts it back
    seen = {"left front door": door | {20: (100, 100)},  # frame 20 alone, far from the rest: dropped
            "front bumper": {1: (260, 600), 36: (280, 570), 35: (300, 560)},
            "right front wheel and tire": {27: (550, 570)}}  # seen in one frame only: kept
    fake = FakeAI(seen)
    monkeypatch.setattr(hotspots.ai, "ask", fake)
    spots = hotspots.compute(d, rec_with(["Left front door", "Front bumper", "Right front wheel", "Left front door"]))
    by = {s["part"]: s for s in spots}
    assert set(by) == {"Left front door", "Front bumper", "Right front wheel and tire"}
    assert by["Left front door"]["damages"] == [1, 4]  # two damages on one part: one dot
    pos = by["Left front door"]["positions"]
    assert "19" not in pos and list(pos)[0] == "1"  # frame 2 is key "1" (frames counted from 0)
    assert pos["1"] == [52.0, 42.0] and pos["5"] == [57.0, 42.0]  # percent of the photo; frame 6's jump smoothed
    assert by["Right front wheel and tire"]["positions"] == {"26": [55.0, 57.0]}
    # each frame is asked once, about only the damaged parts it can show
    ks = [a[0] for a in fake.asked]
    assert len(ks) == len(set(ks)) and 14 not in ks and 1 in ks
    assert dict(fake.asked)[3] == ("front bumper", "left front door")


def test_a_wheel_and_its_tire_share_one_dot(media_dir, monkeypatch, ai_on):
    d = media_dir / "i9"
    d.mkdir()
    frames(d)
    fake = FakeAI({"left front wheel and tire": {3: (450, 620)}})
    monkeypatch.setattr(hotspots.ai, "ask", fake)
    spots = hotspots.compute(d, rec_with(["Left front wheel", "Left front tire"]))
    assert spots == [{"part": "Left front wheel and tire", "damages": [1, 2], "positions": {"2": [45.0, 62.0]}}]
    assert all(parts == ("left front wheel and tire",) for _, parts in fake.asked)


def test_a_place_with_no_side_takes_its_side_from_the_photo(media_dir, monkeypatch, ai_on):
    d = media_dir / "i2"
    d.mkdir()
    frames(d)
    (d / "damage-1.jpg").write_bytes(b"jpg")
    fake = FakeAI({"left side mirror": {3: (400, 300), 4: (420, 300)}})
    monkeypatch.setattr(hotspots.ai, "ask", fake)
    spots = hotspots.compute(d, rec_with(["Mirror"]))
    assert spots == [{"part": "Left mirror", "damages": [1], "positions": {"2": [40.0, 30.0], "3": [42.0, 30.0]}}]
    fake.side = "unknown"
    assert hotspots.compute(d, rec_with(["Mirror"])) == []  # no side, no dot


def test_nothing_to_work_out(media_dir, monkeypatch):
    d = media_dir / "i3"
    d.mkdir()
    assert hotspots.compute(d, rec_with(["Carpet"])) == []  # no outside damage: no dots, nothing asked
    monkeypatch.setattr(hotspots.ai, "configured", lambda: False)
    frames(d)
    assert hotspots.compute(d, rec_with(["Hood"])) is None  # no AI: try again later
    monkeypatch.setattr(hotspots.ai, "configured", lambda: True)
    (d / spin.frame(7)).unlink()
    assert hotspots.compute(d, rec_with(["Hood"])) is None  # frames missing


def test_saved_once_until_the_damages_change(media_dir):
    d = media_dir / "i4"
    d.mkdir()
    rec = rec_with(["Hood"])
    assert hotspots.load(d, rec) is None
    hotspots.save(d, rec, [{"part": "Hood", "damages": [1], "positions": {"0": [1, 2]}}])
    assert hotspots.load(d, rec)[0]["part"] == "Hood"
    assert hotspots.load(d, rec_with(["Hood", "Roof"])) is None  # another damage list: worked out again
    (d / "hotspots.json").write_text("{not json")
    assert hotspots.load(d, rec) is None


def test_worked_out_in_the_background_once(media_dir, monkeypatch, ai_on):
    d = media_dir / "i5"
    d.mkdir()
    frames(d)
    runs, started = [], []
    monkeypatch.setattr(hotspots, "compute", lambda folder, rec: runs.append(1) or [])
    monkeypatch.setattr(hotspots.threading, "Thread", lambda target, daemon: started.append(target) or type("T", (), {"start": lambda self: None})())
    monkeypatch.setattr(hotspots, "_tried", {})
    monkeypatch.setattr(hotspots, "_fails", {})
    rec = rec_with(["Hood"])
    assert hotspots.ensure("i5", d, rec) is None and len(started) == 1
    assert hotspots.ensure("i5", d, rec) is None and len(started) == 1  # running: not started twice
    started[0]()  # the run ends
    assert hotspots.ensure("i5", d, rec) == []  # saved: shown from now on
    # a failed run is tried again only after RETRY_S
    d2 = media_dir / "i6"
    d2.mkdir()
    frames(d2)
    monkeypatch.setattr(hotspots, "compute", lambda folder, rec: None)
    hotspots.ensure("i6", d2, rec)
    started[-1]()
    assert hotspots.ensure("i6", d2, rec) is None and len(started) == 2
    # a run that raises is counted in the file; after MAX_FAILS no more runs, whatever the visits
    d3 = media_dir / "i8"
    d3.mkdir()
    frames(d3)
    monkeypatch.setattr(hotspots, "compute", lambda folder, rec: 1 / 0)
    monkeypatch.setattr(hotspots, "_tried", {})
    for n in range(1, 4):
        monkeypatch.setattr(hotspots.time, "time", lambda n=n: 10_000 * n)  # far enough apart
        hotspots.ensure("i8", d3, rec)
        started[-1]()
        assert json.loads((d3 / "hotspots.json").read_text())["fails"] == n
        hotspots._tried.clear()
    before = len(started)
    monkeypatch.setattr(hotspots.time, "time", lambda: 10 ** 9)
    assert hotspots.ensure("i8", d3, rec) is None and len(started) == before
    # another damage list (the record sent again) is worked out at once, not held back by the last run's wait
    monkeypatch.setattr(hotspots, "compute", lambda folder, rec: [])
    monkeypatch.setattr(hotspots.time, "time", lambda: 10 ** 9 + 10)
    assert hotspots.ensure("i8", d3, rec_with(["Hood", "Roof"]), wait=True) == []
    # a result that cannot be saved (a full disk) is counted too: no endless paid runs
    d4 = media_dir / "i10"
    d4.mkdir()
    frames(d4)
    write = hotspots._write
    monkeypatch.setattr(hotspots, "_write", lambda folder, data: 1 / 0)
    for n in range(3):
        hotspots._tried.clear()
        hotspots.ensure("i10", d4, rec, wait=True)
    hotspots._tried.clear()
    before = len(started)
    assert hotspots.ensure("i10", d4, rec) is None and len(started) == before
    assert hotspots._fails[("i10", hotspots.key_of(rec))] == 3
    monkeypatch.setattr(hotspots, "_write", write)
    # the build waits for it
    monkeypatch.setattr(hotspots, "compute", lambda folder, rec: [{"part": "Hood", "damages": [1], "positions": {}}])
    assert hotspots.ensure("i7", d2, rec, wait=True) == [{"part": "Hood", "damages": [1], "positions": {}}]


def make(rec):
    iid, token = str(uuid.uuid4()), secrets.token_urlsafe(24)
    with SessionLocal() as s:
        s.add(Inspection(id=iid, report_email="t@x.co", inspector="Tom", car=CARS["bmw-x3"], record=rec, status="sent",
                         report_token=token, cr=build_cr(rec)))
        s.commit()
    return token, iid


@pytest.mark.parametrize("page", ["seller", "dealer"])
def test_report_viewer_settings(client, media_dir, monkeypatch, page):
    rec = sample("bmw-x3")
    token, iid = make(rec)
    d = media_dir / iid
    d.mkdir()
    frames(d)
    asked = []
    monkeypatch.setattr(hotspots, "ensure", lambda i, folder, r, wait=False: asked.append(i) or hotspots.load(folder, r))
    # not worked out yet: the 360 view without dots, and the work is started
    html = client.get(f"/r/{token}/{page}").text
    cfg = json.loads(re.search(r'<script type="application/json" id="spin-cfg">(.*?)</script>', html)[1])
    assert cfg["hotspots"] is None and asked == [iid]  # no list at all: the library fails on an empty one
    assert (cfg["filenameX"], cfg["amountX"], cfg["indexZeroBase"], cfg["hotspotTrigger"]) == ("spin-{index}.jpg", 36, 2, "click")
    assert "@cloudimage/360-view@4.10.0/dist/360-view.min.js" in html and 'id="spin360"' in html
    # worked out: a dot per part, on its frames, with each damage's photo and line in the card; Red level is a red dot
    n_door, n_trunk = 1, 2  # bmw-x3: Left rear door Dent Moderate (Disclosed), Trunk Structure Severe (Red)
    hotspots.save(d, rec, [{"part": "Left rear door", "damages": [n_door], "positions": {"6": [40.5, 44.0]}},
                           {"part": "Trunk or liftgate", "damages": [n_trunk, n_door], "positions": {"13": [50.0, 40.0]}}])
    html = client.get(f"/r/{token}/{page}").text
    cfg = json.loads(re.search(r'<script type="application/json" id="spin-cfg">(.*?)</script>', html)[1])
    a, b = cfg["hotspots"]
    assert a["id"] == "dmg-1" and a["positions"] == {"6": {"x": 40.5, "y": 44.0}} and a["orientation"] == "x"
    assert a["className"] == "hs-dmg" and a["label"] == "Left rear door"
    assert f'src="/r/{token}/media/damage-1.jpg"' in a["content"] and "<b>Left rear door</b>Dent, Moderate, 2 in" in a["content"]
    assert b["className"] == "hs-dmg hs-sev hs-n2" and b["label"] == "Trunk or liftgate · 2 damages" and b["content"].count('class="hs-it"') == 2
    assert "<script" not in html.split('id="spin-cfg">')[1].split("</script>")[0]  # the cards are data, never markup on the page


def test_the_build_works_out_the_dots_after_the_email(client, monkeypatch):
    order = []
    monkeypatch.setattr(main, "_send_report", lambda insp: order.append("email"))
    monkeypatch.setattr(main.hotspots, "ensure", lambda i, folder, rec, wait=False: order.append(("dots", wait)))
    iid = str(uuid.uuid4())
    with SessionLocal() as s:
        s.add(Inspection(id=iid, report_email="t@x.co", inspector="Tom", car=CARS["bmw-x3"], record=sample("bmw-x3"), status="building"))
        s.commit()
    main.build(iid)
    assert order == ["email", ("dots", True)]
