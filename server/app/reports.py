"""Seller and dealer report pages (docs/05-reports.md), ported from reference/condition-report/app.js."""
import json
import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.templating import Jinja2Templates
from markupsafe import Markup, escape
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import config, hotspots, spin, storage
from .cr import CAT, PAINT_SHOWN, SPIN_SLOTS
from .email import car_line, inspected_when
from .db import Inspection, get_session

router = APIRouter(prefix="/r")
templates = Jinja2Templates(directory=Path(__file__).resolve().parents[1] / "templates")

# icon paths from the reference page (lucide); I() draws one
ICONS = {
    "gauge": '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
    "calendar": '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    "tire": '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="4"/><path d="M12 2v6M12 16v6M2 12h6M16 12h6"/>',
    "clip": '<rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="m9 14 2 2 4-4"/>',
    "dollar": '<path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
    "clock": '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "swap": '<path d="m16 3 4 4-4 4M20 7H4M8 21l-4-4 4-4M4 17h16"/>',
    "car": '<path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/>',
    "key": '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
    "wind": '<path d="M17.7 7.7a2.5 2.5 0 1 1 1.8 4.3H2M9.6 4.6A2 2 0 1 1 11 8H2M12.6 19.4A2 2 0 1 0 14 16H2"/>',
    "wrench": '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94z"/>',
    "alert": '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4M12 17h.01"/>',
    "play": '<path d="m7 4 13 8-13 8z"/>',
    "video": '<path d="m22 8-6 4 6 4V8Z"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    "left": '<path d="m15 18-6-6 6-6"/>',
    "right": '<path d="m9 18 6-6-6-6"/>',
    "x": '<path d="M18 6 6 18M6 6l12 12"/>',
    "shield": '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
    "grid": '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    "brush": '<path d="m9.06 11.9 8.07-8.06a2.85 2.85 0 1 1 4.03 4.03l-8.06 8.08"/><path d="M7.07 14.94c-1.66 0-3 1.35-3 3.02 0 1.33-2.5 1.52-2 2.02 1.08 1.1 2.49 2.02 4 2.02 2.2 0 4-1.8 4-4.04a3.01 3.01 0 0 0-3-3.02z"/>',
    "layers": '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65M22 12.65l-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    "seat": '<path d="M19 9V6a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v3"/><path d="M3 16a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5a2 2 0 0 0-4 0v1.5a.5.5 0 0 1-.5.5h-9a.5.5 0 0 1-.5-.5V11a2 2 0 0 0-4 0zM5 18v2M19 18v2"/>',
    "scan": '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2M7 12h10"/>',
    "volume": '<path d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"/><path d="M16 9a5 5 0 0 1 0 6"/><path d="M19.364 18.364a9 9 0 0 0 0-12.728"/>',
}


def icon(name: str, size: int = 20, cls: str = "") -> Markup:
    return Markup(f'<svg class="i {cls}" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
                  f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>')


templates.env.globals["I"] = icon

GROUPS = [("Exterior", "car"), ("Paint", "brush"), ("Tires", "tire"), ("Underbody", "layers"), ("Mechanicals", "wrench"),
          ("Interior", "seat"), ("OBDII", "scan"), ("Additionals", "key")]
ROW_ICON = {"Exterior": "car", "Paint": "brush", "Tires": "tire", "Underbody": "layers", "Mechanicals": "wrench", "Engine sound": "volume",
            "Interior": "seat", "OBD-II": "scan", "Additionals": "key"}
VIDEOS = {"video_360": ("Exterior", "Walk-around, 360°"), "video_engine": ("Mechanicals", "Engine sound at the first start"),
          "video_exhaust": ("Mechanicals", "Exhaust at idle and revving")}
LABEL = {"paint": "Paint meter", "ph_int_screen": "Infotainment screen", "ph_obd_current": "OBD-II current codes", "ph_obd_past": "OBD-II past codes",
         "ph_obd_emission": "OBD-II emission codes", "ph_obd_other": "OBD-II other", "ph_under_lf": "Underbody, left front", "ph_under_lm": "Underbody, left middle",
         "ph_under_lr": "Underbody, left rear", "ph_under_rear": "Underbody, rear", "ph_under_rr": "Underbody, right rear", "ph_under_rm": "Underbody, right middle",
         "ph_under_rf": "Underbody, right front", "ph_under_front": "Underbody, front", "ph_under_cats": "Catalytic converter",
         "ph_under_pack": "Battery pack", "ph_mod_ext": "Exterior modification", "ph_mod_int": "Interior modification",
         "ph_mod_mech": "Mechanicals modification", "ph_odo": "Odometer and warning lights", "ph_keys": "Keys", "tire_photo": "Tire sidewall",
         "tread_photo": "Tread gauge", "ph_ev_battery": "Battery health", "ph_ev_charging": "Charging rate", "ph_ev_alerts": "Service-mode alerts",
         "ph_engine_oil": "Engine oil"}
QL_LABEL = {it["id"]: re.sub(r" \(.*\)$|, with .*$", "", it["label"])
            for it in json.loads((config.DATA_DIR / "question-list.json").read_text())["items"]}
WHEELS = ["lf", "rf", "rr", "lr"]
# the eight exterior views the CR takes from the 360 frames (SPIN_SLOTS), in the walk-around order
VIEW = {"front_left": "Left front", "left_side": "Left side", "rear_left": "Left rear", "rear": "Rear", "rear_right": "Right rear",
        "right_side": "Right side", "front_right": "Right front", "front": "Front"}
WHEEL_NAME = {w["wheel"]: w["name"] for w in CAT["wheels"]}
LEVEL = {"Ends the visit": "stop", "Not listed until fixed": "stop", "Red": "sev", "Yellow": "yel"}
LEVEL_TEXT = {"stop": "Not listed", "sev": "Red", "yel": "Yellow"}
templates.env.globals["level_text"] = LEVEL_TEXT
CHECK_ROW = {c["id"]: c["cr_row"] for c in CAT["checks"]} | {"ck_engine": "Engine sound"}  # the Engine check result sits in Engine sound
FUEL_WORD = {"Gas or diesel": "Gas", "Electric (EV)": "Electric"}


def mils_text(m: float) -> str:
    """a paint reading as the app shows it: above 10 is 10+ (the app's slider tops out there)"""
    return "10+" if m > 10 else f"{m:.1f}"


def paint_reads(rec: dict) -> list[dict]:
    """the highest and the lowest panel reading, leaving out panels not on the car (first panel wins a tie)"""
    got = [p for p in rec.get("paint", []) if not p.get("not_on_car") and p.get("mils") is not None]
    if not got:
        return []
    hi, lo = max(got, key=lambda p: p["mils"]), min(got, key=lambda p: p["mils"])
    return [{"icon": icon, "text": f"{word} reading {mils_text(p['mils'])} mils", "sub": PAINT_SHOWN.get(p["panel"], p["panel"])}
            for icon, word, p in (("↑", "Highest", hi), ("↓", "Lowest", lo))]


def spin_cfg(url, rec: dict, by_photo: dict, spots: list[dict]) -> dict:
    """the 360 viewer's settings, with a dot for each damaged part on the frames that show it; tapping a dot opens a card with each
    damage's photo and line, and tapping a damage there opens its photo in the viewer"""
    dmg = {d["n"]: d for d in rec.get("damages", [])}
    hs = []
    for i, s in enumerate(spots):
        ds = [dmg[n] for n in s["damages"] if n in dmg]
        if not ds:
            continue
        lines = [by_photo[d["file"]] if d["file"] in by_photo else {"text": d["place"], "level": None} for d in ds]
        worst = max((LEVEL.get(x.get("level")) for x in lines), key=lambda lv: ["yel", "sev", "stop"].index(lv) + 1 if lv else 0)
        items = "".join(
            f'<button type="button" class="hs-it" id="hsd-{escape(str(d["n"]))}"><img src="{escape(url(d["file"]))}" alt="">'
            f'<span><b>{escape(x["text"].split(": ", 1)[0])}</b>{escape(x["text"].split(": ", 1)[1] if ": " in x["text"] else "")}</span></button>'
            for d, x in zip(ds, lines))
        # keepOpen: the card stays until a tap elsewhere in the view (with a mouse it would close as the pointer leaves it)
        hs.append({"id": f"dmg-{i + 1}", "orientation": "x", "keepOpen": True, "label": s["part"] + (f" · {len(ds)} damages" if len(ds) > 1 else ""),
                   # amber; red for a Red (or worse) damage; the number of damages when the part has several
                   "className": " ".join(["hs-dmg"] + ({"yel": ["hs-yel"], "sev": ["hs-sev"], "stop": ["hs-sev"]}.get(worst, []))
                                         + ([f"hs-n{min(len(ds), 9)}"] if len(ds) > 1 else [])),
                   "positions": {k: {"x": x, "y": y} for k, (x, y) in s["positions"].items()},
                   "content": f'<div class="hs-card">{items}</div>'})
    return {"folder": url(""), "filenameX": "spin-{index}.jpg", "amountX": spin.FRAMES, "indexZeroBase": 2,
            # no dots: no list at all (the library's hotspot code fails on an empty one)
            "hotspots": hs or None, "hotspotTrigger": "click"}


def view(insp: Inspection) -> dict:
    """everything both report templates show, from the stored CR (condition_report) and the record"""
    token, rec, car = insp.report_token, insp.record, insp.car or {}
    cr = insp.cr["condition_report"]
    v, h, issues = cr["vehicle"], cr["highlight"], {i["id"]: i for i in cr["issues"]}
    url = lambda name: f"/r/{token}/media/{name}"  # noqa: E731
    by_photo = {i["photo"]: i for i in cr["issues"] if i["photo"]}

    def line(i):
        return {"text": i["text"], "sub": i.get("sub"), "lv": LEVEL.get(i["level"]), "photo": i["photo"] and url(i["photo"])}

    # photo and video viewer: one list grouped by section; the 360 view first in Exterior with its eight exterior views, damage photos where they were recorded
    photos = [p for p in rec["photos"] if not p.get("skipped")]
    count = {q: sum(1 for p in photos if p["question_id"] == q) for q in {p["question_id"] for p in photos}}
    seen, media = {}, []
    for g, _ in GROUPS:
        if g == "Exterior" and spin.have_frames(storage.folder(insp.id)):
            spots = hotspots.ensure(insp.id, storage.folder(insp.id), rec) or []
            media.append({"g": g, "kind": "spin", "src": url(spin.frame(1)), "lbl": "360 view", "cfg": spin_cfg(url, rec, by_photo, spots)})
            media += [{"g": g, "kind": "img", "src": url(spin.frame(k)), "lbl": VIEW[slot]} for k, slot in SPIN_SLOTS]
        media += [{"g": g, "kind": "video", "src": url(x["file"]), "lbl": VIDEOS[x["question_id"]][1]}
                  for x in rec["videos"] if VIDEOS.get(x["question_id"], ("",))[0] == g]
        for p in (p for p in photos if p["section"] == g):
            q = p["question_id"]
            seen[q] = seen.get(q, 0) + 1
            where = p.get("panel") or WHEEL_NAME.get(p.get("wheel"))
            lbl = (LABEL.get(q) or QL_LABEL.get(q, q)) + (f" · {where}" if where else f" {seen[q]}/{count[q]}" if count[q] > 1 else "")
            media.append({"g": g, "kind": "img", "src": url(p["file"]), "lbl": lbl})
        media += [{"g": g, "kind": "img", "src": url(d["file"]), "lbl": by_photo[d["file"]]["text"] if d["file"] in by_photo else d["place"]}
                  for d in rec["damages"] if d["section"] == g and d.get("file")]
    groups = [{"g": g, "icon": ic, "name": "OBD-II" if g == "OBDII" else g, "n": sum(1 for m in media if m["g"] == g)}
              for g, ic in GROUPS if any(m["g"] == g for m in media)]

    # Bidbus Inspection: one block per CR row; check problems first, then damages with their photo
    rows = []
    for r in cr["rows"]:
        ids = [i for i in r["issues"] if issues[i].get("check") != "ck_engine"]
        if r["row"] == "Engine sound":
            ids = [i["id"] for i in cr["issues"] if i.get("check") == "ck_engine"]
        lines = sorted((line(issues[i]) for i in ids), key=lambda x: bool(x["photo"]))
        checks = len({c["id"] for c in rec["checks"] if CHECK_ROW.get(c["id"]) == r["row"]})
        vids = [{"lbl": VIDEOS[x["question_id"]][1], "src": url(x["file"])} for x in rec["videos"]
                if r["row"] == "Engine sound" and x["file"] in r["videos"]]
        # OBD-II with a problem: its scan screens under it, so the codes can be seen
        shots = [{"src": url(p["file"]), "lbl": LABEL.get(p["question_id"]) or QL_LABEL.get(p["question_id"], p["question_id"])}
                 for p in photos if p["section"] == "OBDII"] if r["row"] == "OBD-II" and lines else []
        rows.append({"name": r["row"], "icon": ROW_ICON[r["row"]], "lines": lines, "checks": checks, "videos": vids,
                     "reads": paint_reads(rec) if r["row"] == "Paint" else [], "shots": shots})
    engine = any(r["name"] == "Engine sound" for r in rows)
    other_videos = [{"lbl": VIDEOS.get(x["question_id"], ("", x["question_id"]))[1], "src": url(x["file"])} for x in rec["videos"]
                    if not (engine and x["question_id"] in ("video_engine", "video_exhaust"))]

    tires = []
    for w in WHEELS:
        t = next(t for t in cr["tires"] if t["wheel"] == w)
        m = t["tread_32nds"]
        brakes = [i for i in cr["issues"] if i.get("check") == "ck_brakes" and t["name"] in re.split(r",\s*", i.get("where") or i["place"] or "")]
        tires.append({"name": t["name"], "tread": m, "word": t["tread"] or "–", "cls": "na" if m is None else "bad" if m <= 4 else "fair" if m <= 8 else "good",
                      "bar": min(100, (m or 0) * 10), "brand_size": " · ".join(x for x in (t["brand"], t["size"]) if x),
                      "issues": [issues[i]["text"] for i in t["issues"]] + [i["text"] for i in brakes]})

    kc, odor, st = h["keys"], h["odor"], h["structural_damage"]
    highlight = [("car", {"Yes": "bad", "Not checked": "na"}.get(st, "ok"), "Structural damage", st),
                 ("key", "num" if kc else "bad", "Keys", str(kc)),
                 ("wind", "ok" if odor == "OK" else "bad", "Odor", odor if odor == "OK" else ", ".join(odor)),
                 ("wrench", "bad" if h["mechanical"] == "Issue" else "ok", "Mechanical", h["mechanical"])]

    # dealer only: Purchase Protection, banners for Not listed, Red and Yellow issues (worst first), specs
    miles, light = v["mileage"] if v["mileage"] is not None else v["mileage_listing"], cr["light"]
    year = int(car["year"]) if str(car.get("year") or "").isdigit() else 0
    protection = (None if light == "Not listed" or year < 2011 or (miles or 0) >= 150000
                  else ("Title, odometer, legal", True) if light == "Red" else ("Purchase Protection", False))
    banners = sorted((line(i) for i in cr["issues"] if LEVEL.get(i["level"])), key=lambda x: ["stop", "sev", "yel"].index(x["lv"]))
    specs = [("VIN", v["vin"]), ("Year", car.get("year")), ("Make", car.get("make")), ("Model", car.get("model")), ("Trim", car.get("trim")),
             ("Odometer", f"{miles:,} mi" if miles is not None else None), ("Fuel", car["fuel"] if car.get("fuel") in ("Gas", "Diesel") else FUEL_WORD.get(v["fuel"], v["fuel"])), ("Keys", kc)]
    if v["fuel"] == "Electric (EV)" and v["ev_battery_health_pct"] is not None:
        specs.append(("Battery health", f"{v['ev_battery_health_pct']}%"))

    return {"name": " ".join(str(car[k]) for k in ("year", "make", "model") if car.get(k)), "trim": car.get("trim") or "", "title": car_line(car),
            "miles": f"{miles:,}" if miles is not None else "", "date": inspected_when(insp),
            "media": media, "groups": groups, "rows": rows, "videos": other_videos, "tires": tires, "highlight": highlight,
            "overall": cr["overall_condition"], "note": (cr["inspector_note"] or "").strip(), "protection": protection,
            "banners": banners, "specs": specs}


def _built(token: str, s: Session) -> Inspection:
    insp = s.scalar(select(Inspection).where(Inspection.report_token == token))
    if not insp or not insp.cr:
        raise HTTPException(status_code=404, detail="No such report")
    return insp


@router.get("/{token}/seller")
def seller(token: str, request: Request, s: Session = Depends(get_session)):
    return templates.TemplateResponse(request, "seller.html", view(_built(token, s)))


@router.get("/{token}/dealer")
def dealer(token: str, request: Request, s: Session = Depends(get_session)):
    return templates.TemplateResponse(request, "dealer.html", view(_built(token, s)))


@router.get("/{token}/media/{name}")
def media(token: str, name: str, s: Session = Depends(get_session)):
    insp = _built(token, s)
    path = storage.folder(insp.id) / name
    if not storage.ok_name(name) or not storage.public(insp.record or {}, name) or not path.is_file():
        raise HTTPException(status_code=404, detail="No such file")
    return FileResponse(path, media_type=storage.TYPES[name.rsplit(".", 1)[-1].lower()],
                        headers={"Cache-Control": "private, max-age=86400", "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "sandbox; default-src 'none'"})
