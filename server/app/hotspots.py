"""Damage dots on the 360 view: where each confirmed outside damage's part is in the 36 spin frames.

The spin frames come from one walk round the car: frame 1 at the left front corner, then the left side, the back, the right side
and the front (frame k at (k - 0.5) / 36 of the walk-around). Each damage has the part the inspector confirmed (its place), so for
every frame that can show a damaged part, the AI is asked where that part is in the photo, or that it cannot be seen there.
The answer is kept in the inspection's media folder (hotspots.json) and the reports draw a dot there on those frames only.
"""
import hashlib
import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import ai, spin

log = logging.getLogger(__name__)

FRAMES = spin.FRAMES
SECTIONS = ("Exterior", "Paint", "Tires")  # damages seen from outside the car
VERSION = 1

# the frame (1 to 36, fractional) facing each part, and how many frames either side may still show it
FACE = {
    "Front bumper": (32.5, 8), "Hood": (32.5, 9), "Windshield": (32.5, 8), "Wipers": (32.5, 6),
    "Left front fender": (2.5, 5), "Left front door": (5, 5), "Left front window": (5, 4), "Left rear door": (7, 5),
    "Left rear window": (7.5, 4), "Left quarter panel": (9, 5),
    "Rear bumper": (14.5, 7), "Trunk or liftgate": (14.5, 7), "Rear glass": (14.5, 6),
    "Right quarter panel": (20, 5), "Right rear window": (21.5, 4), "Right rear door": (22, 5), "Right front window": (24, 4),
    "Right front door": (24, 5), "Right front fender": (26.5, 5),
    "Roof": (18.5, 18),  # any frame may show it
    "Left front wheel": (3, 5), "Left front tire": (3, 5), "Left rear wheel": (8.5, 5), "Left rear tire": (8.5, 5),
    "Right rear wheel": (20.5, 5), "Right rear tire": (20.5, 5), "Right front wheel": (26, 5), "Right front tire": (26, 5),
}
# places that name no side: the side comes from the damage photo
SIDED = {"Mirror": {"left": (3.5, 5), "right": (26, 5)}, "Headlight": {"left": (35, 6), "right": (30, 6)},
         "Tail light": {"left": (12, 5), "right": (17, 5)}, "Fuel door": {"left": (9, 5), "right": (20, 5)}}
SAME = {"Hood or frunk lid": "Hood"}  # a Paint place that is an Exterior part
WORDS = {"Mirror": "side mirror", "Fuel door": "fuel door or charge port door", "Wipers": "windshield wipers"}


def part_of(place: str) -> tuple[str, str]:
    """the part named to the AI and shown on the dot; a wheel and its tire are one part (their dots would sit on top of each other)"""
    if place.endswith((" wheel", " tire")):
        corner = place.rsplit(" ", 1)[0]
        return f"{corner.lower()} wheel and tire", f"{corner} wheel and tire"
    return WORDS.get(place, place.lower()), place


def where(k: int) -> str:
    """where the camera is for frame k (1-36)"""
    return ("left front corner" if k in (1, 36) else "left side" if k <= 8 else "left rear corner" if k <= 11 else "rear"
            if k <= 17 else "right rear corner" if k <= 20 else "right side" if k <= 26 else "right front corner" if k <= 29 else "front")


def frames_for(face: float, half: int) -> list[int]:
    """the frames at most half frames from the facing one, round the walk"""
    return [k for k in range(1, FRAMES + 1) if min(abs(k - face), FRAMES - abs(k - face)) <= half]


def marked(rec: dict) -> list[dict]:
    """the damages that get a dot: confirmed, with a photo, outside the car, on a part the 360 can show"""
    out = []
    for d in rec.get("damages", []):
        place = SAME.get(d.get("place"), d.get("place"))
        if (d.get("confirmed") and d.get("file") and isinstance(d.get("n"), int) and not isinstance(d.get("n"), bool)
                and d.get("section") in SECTIONS and (place in FACE or place in SIDED)):
            out.append({"n": d["n"], "place": place, "file": d["file"]})
    return out


def key_of(rec: dict) -> str:
    return hashlib.sha256(json.dumps([VERSION, marked(rec)], sort_keys=True).encode()).hexdigest()[:16]


def _side(folder: Path, d: dict) -> str | None:
    """left or right for a place that names no side, from its damage photo; None when the AI cannot tell"""
    words = WORDS.get(d["place"], d["place"].lower())
    text = (f"This close-up shows damage on a car's {words}. Which side of the car is it on? The driver side is the car's left "
            "(a US car). Answer unknown if the photo does not show which side it is.")
    r = ai.ask("damage_side", {"side": {"type": "string", "enum": ["left", "right", "unknown"]}}, text, (folder / d["file"]).read_bytes())
    return r.get("side") if r.get("side") in ("left", "right") else None


def _locate(folder: Path, k: int, parts: list[str]) -> dict[str, tuple[float, float]]:
    """the parts the AI sees in frame k, each with its middle as x, y in percent of the photo"""
    text = (f"This photo is frame {k} of {FRAMES} from a video taken walking once round a car: it starts at the car's left front "
            "corner (the driver side is the car's left), goes down the left side, round the back, up the right side and round the "
            f"front. In this frame the camera is at the car's {where(k)}. For each part listed, say whether this photo shows it. "
            "If it does, give the point in the middle of that part as x and y from 0 to 1000 (x from the left edge of the photo, "
            "y from the top). A part on the far side of the car, hidden by something or out of the photo is not shown.\n"
            "Parts: " + "; ".join(parts))
    item = {"type": "object", "additionalProperties": False, "required": ["part", "visible", "x", "y"],
            "properties": {"part": {"type": "string", "enum": parts}, "visible": {"type": "boolean"},
                           "x": {"type": ["integer", "null"]}, "y": {"type": ["integer", "null"]}}}
    r = ai.ask("locate_parts", {"parts": {"type": "array", "items": item}}, text, (folder / spin.frame(k)).read_bytes())
    out = {}
    for p in r.get("parts", []):
        x, y = p.get("x"), p.get("y")
        if p.get("part") in parts and p.get("visible") and isinstance(x, int) and isinstance(y, int) and 0 <= x <= 1000 and 0 <= y <= 1000:
            out[p["part"]] = (x / 10, y / 10)
    return out


def smooth(seen: dict[int, tuple[float, float]]) -> dict[int, tuple[float, float]]:
    """a frame seen alone (neither neighbour sees the part) is dropped when the part is seen in more than two frames; each point is
    the median of itself and the neighbours that see it, so the dot does not jump as the car turns"""
    near = lambda k, d: ((k - 1 + d) % FRAMES) + 1  # noqa: E731
    if len(seen) > 2:
        seen = {k: v for k, v in seen.items() if near(k, -1) in seen or near(k, 1) in seen}
    out = {}
    for k, v in seen.items():
        xs = sorted(seen[j][0] for j in (near(k, -1), k, near(k, 1)) if j in seen)
        ys = sorted(seen[j][1] for j in (near(k, -1), k, near(k, 1)) if j in seen)
        out[k] = (round(xs[len(xs) // 2], 1), round(ys[len(ys) // 2], 1)) if len(xs) == 3 else v
    return out


def compute(folder: Path, rec: dict) -> list[dict] | None:
    """one dot per damaged part: {part, damages: [n], positions: {frame index from 0: [x %, y %]}}; None when it cannot be worked out now"""
    todo = marked(rec)
    if not todo:
        return []
    if not ai.configured() or not spin.have_frames(folder):
        return None
    parts: dict[str, dict] = {}  # name for the AI -> {frames, damages}
    for d in todo:
        if d["place"] in SIDED:
            side = _side(folder, d)
            if side is None:
                continue  # no side, no dot
            name, (face, half) = f"{side} {WORDS.get(d['place'], d['place'].lower())}", SIDED[d["place"]][side]
            label = f"{side.capitalize()} {d['place'].lower()}"
        else:
            (name, label), (face, half) = part_of(d["place"]), FACE[d["place"]]
        p = parts.setdefault(name, {"label": label, "frames": frames_for(face, half), "damages": []})
        p["damages"].append(d["n"])
    by_frame: dict[int, list[str]] = {}
    for name, p in parts.items():
        for k in p["frames"]:
            by_frame.setdefault(k, []).append(name)
    def look(k):  # one more try for a frame whose answer failed; a second failure fails the run (tried again later)
        try:
            return _locate(folder, k, sorted(by_frame[k]))
        except Exception:
            return _locate(folder, k, sorted(by_frame[k]))

    with ThreadPoolExecutor(max_workers=6) as pool:
        seen_at = dict(zip(by_frame, pool.map(look, by_frame)))
    spots = []
    for name, p in parts.items():
        seen = smooth({k: f[name] for k, f in seen_at.items() if name in f})
        if seen:
            spots.append({"part": p["label"], "damages": p["damages"], "positions": {str(k - 1): [x, y] for k, (x, y) in sorted(seen.items())}})
    return spots


# ---- kept per inspection, worked out once ----

def _path(folder: Path) -> Path:
    return folder / "hotspots.json"


def _read(folder: Path, rec: dict) -> dict:
    try:
        data = json.loads(_path(folder).read_text())
        return data if data.get("key") == key_of(rec) else {}
    except (OSError, ValueError, AttributeError):
        return {}


def load(folder: Path, rec: dict) -> list[dict] | None:
    """the dots worked out for this inspection's damages, or None when there are none yet (or the damages changed since)"""
    spots = _read(folder, rec).get("spots")
    return spots if isinstance(spots, list) else None


def _write(folder: Path, data: dict) -> None:
    tmp = folder / ".hotspots.json.part"
    tmp.write_text(json.dumps(data))
    tmp.replace(_path(folder))


def save(folder: Path, rec: dict, spots: list[dict]) -> None:
    _write(folder, {"key": key_of(rec), "spots": spots})


def failed(folder: Path, rec: dict) -> None:
    """a run that failed: counted, so a report seen often does not start it again and again (see ensure)"""
    _write(folder, {"key": key_of(rec), "spots": None, "fails": _read(folder, rec).get("fails", 0) + 1, "at": time.time()})


def build(folder: Path, rec: dict) -> list[dict] | None:
    try:
        spots = compute(folder, rec)
    except Exception:
        failed(folder, rec)
        raise
    if spots is not None:
        save(folder, rec, spots)
    return spots


# per inspection and damage list: running now, last start, failed runs (also those whose result could not be saved)
_busy: set[tuple[str, str]] = set()
_tried: dict[tuple[str, str], float] = {}
_fails: dict[tuple[str, str], int] = {}
_lock = threading.Lock()
RETRY_S, MAX_FAILS = 600, 3


def ensure(inspection_id: str, folder: Path, rec: dict, wait: bool = False) -> list[dict] | None:
    """the dots if they are worked out; otherwise work them out (once at a time, again after a failure only after RETRY_S): in the
    background, returning None, so this page shows the 360 without dots and a later visit shows them; or here, with wait (the build)"""
    spots = load(folder, rec)
    if spots is not None or not marked(rec) or not ai.configured() or not spin.have_frames(folder):
        return spots
    k, last = (inspection_id, key_of(rec)), _read(folder, rec)
    if max(last.get("fails", 0), _fails.get(k, 0)) >= MAX_FAILS or time.time() - last.get("at", 0) < RETRY_S:
        return None  # failed too often, or just now: no more runs for these damages
    with _lock:
        if k in _busy or time.monotonic() - _tried.get(k, -RETRY_S) < RETRY_S:
            return None
        _busy.add(k)
        _tried[k] = time.monotonic()

    def run():
        try:
            build(folder, rec)
        except Exception:
            _fails[k] = _fails.get(k, 0) + 1
            log.exception("damage dots for %s", inspection_id)
        finally:
            with _lock:
                _busy.discard(k)

    if wait:
        run()
        return load(folder, rec)
    threading.Thread(target=run, daemon=True).start()
    return None
