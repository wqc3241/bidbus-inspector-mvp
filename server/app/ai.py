"""AI photo readings with the Anthropic API (docs/04-ai-reading.md)."""
import base64
import io
import json
import logging
import re

import anthropic
import httpx
from PIL import Image

from . import config
from .cr import CAT, vin_ok

log = logging.getLogger(__name__)

# North American tire brands, as in the mockup (reference/mockup/src/template.html)
TIRE_BRANDS = ['Achilles', 'Atturo', 'BFGoodrich', 'Bridgestone', 'Continental', 'Cooper', 'Delinte', 'Dick Cepek', 'Dunlop', 'Falken',
               'Federal', 'Firestone', 'Fuzion', 'General', 'Goodride', 'Goodyear', 'GT Radial', 'Hankook', 'Hercules', 'Ironman', 'Kelly',
               'Kenda', 'Kumho', 'Laufenn', 'Lexani', 'Lionhart', 'Mastercraft', 'Maxxis', 'Michelin', 'Mickey Thompson', 'Milestar',
               'Nankang', 'Nexen', 'Nitto', 'Nokian', 'Pirelli', 'Primewell', 'Sailun', 'Sumitomo', 'Toyo', 'Uniroyal', 'Vredestein',
               'Westlake', 'Yokohama', 'Other']


def _null(t):
    return {"type": [t, "null"]}


# kind: (tool name, output properties, instruction)
KINDS = {
    "odometer": ("read_odometer", {"mileage": _null("integer")},
                 "Read the total mileage on this odometer, in whole miles. Ignore trip meters. Null if it cannot be read."),
    "vin": ("read_vin", {"vin": _null("string")},
            "Read the 17-character VIN in this photo (letters I, O and Q never appear). Null if it cannot be read."),
    "tire": ("read_tire", {"brand": {"type": ["string", "null"], "enum": TIRE_BRANDS + [None]}, "size": _null("string")},
             "Read the tire brand (one of the listed brands, Other if not listed) and the size as WWW/AARDD, for example 245/50R19. "
             "Null for anything that cannot be read."),
    "tread": ("read_tread", {"tread_32nds": _null("integer")},
              "Read the tread depth gauge, in 32nds of an inch. Null if it cannot be read."),
    "paint_meter": ("read_paint_meter", {"mils": _null("number")},
                    "Read the paint thickness meter, in mils with one decimal. If it shows microns, divide by 25.4. Null if it cannot be read."),
    "ev_battery": ("read_ev_battery", {"health_pct": _null("integer")},
                   "Read the battery health (state of health) percentage on this screen or report. Null if it cannot be read."),
    "keys": ("count_keys", {"keys_count": {"type": "integer", "enum": [0, 1, 2]}},
             "Count the car keys, fobs and key cards in this photo: 0, 1, or 2 for two or more."),
    "damage": ("label_damage", {"place": _null("string"), "type": _null("string"),
                                "severity": {"type": ["string", "null"], "enum": CAT["severities"] + [None]}},
               "Label the damage in this photo with one place and type pair from this list, and its severity."),
    "upright": ("upright_turn", {"turn_deg": {"type": "integer", "enum": [0, 90, 180, 270]}},
                "How many degrees must this photo be rotated clockwise so the car, label or screen is upright?"),
}


def allowed_pairs(section: str | None, fuel: str | None) -> dict[str, list[str]]:
    """place -> its types, from the catalog places for that section and fuel"""
    out = {}
    for p in CAT["places"]:
        types = [t["type"] for t in p["types"] if not fuel or fuel in t.get("fuels", CAT["fuels"])]
        # the app's Mechanicals damage section has the underbody places too (stored as Underbody)
        if types and (not section or p["section"] == section or (section == "Mechanicals" and p["section"] == "Underbody")):
            out[p["place"]] = list(dict.fromkeys(out.get(p["place"], []) + types))
    return out


def _int(v, lo, hi):
    return v if isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi else None


def validate(kind: str, data: dict, pairs=None, hint=None) -> dict:
    if kind == "odometer":
        return {"mileage": _int(data.get("mileage"), 0, 999999)}
    if kind == "vin":
        v = re.sub(r"\s", "", str(data.get("vin") or "")).upper()
        v = v if re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", v) else None
        return {"vin": v, "check_digit_ok": vin_ok(v)}
    if kind == "tire":
        brand = next((b for b in TIRE_BRANDS if b.lower() == str(data.get("brand") or "").lower()), None)
        size = re.sub(r"\s", "", str(data.get("size") or "")).upper()
        m = re.fullmatch(r"(\d{3})/(\d{2})R(\d{2})", size)
        ok = m and 165 <= int(m[1]) <= 355 and 15 <= int(m[2]) <= 85 and 13 <= int(m[3]) <= 25
        return {"brand": brand, "size": size if ok else None}
    if kind == "tread":
        return {"tread_32nds": _int(data.get("tread_32nds"), 1, 14)}
    if kind == "paint_meter":
        v = data.get("mils")
        mils = round(float(v), 1) if isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 99.9 else None
        return {"mils": mils, "high": mils is not None and mils >= CAT["paint_high_mils"]}
    if kind == "ev_battery":
        return {"health_pct": _int(data.get("health_pct"), 1, 100)}
    if kind == "keys":
        return {"keys_count": _int(data.get("keys_count"), 0, 2)}
    if kind == "damage":
        place = hint if hint in pairs else data.get("place")
        if data.get("type") not in pairs.get(place, []):
            return {"place": hint or None, "type": None, "severity": None}
        sev = data.get("severity")
        return {"place": place, "type": data["type"], "severity": sev if sev in CAT["severities"] else None}
    if kind == "upright":
        v = data.get("turn_deg")
        return {"turn_deg": v if v in (0, 90, 180, 270) else None}
    raise ValueError(kind)


def jpeg(image: bytes) -> str:
    img = Image.open(io.BytesIO(image)).convert("RGB")
    img.thumbnail((1568, 1568))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return base64.standard_b64encode(buf.getvalue()).decode()


def client():
    return anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY, timeout=20.0, max_retries=0)


def openai_read(name: str, props: dict, text: str, image_b64: str) -> dict:
    """OpenAI Chat Completions with a strict JSON schema: the same fields as the tool for this kind"""
    schema = {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}
    body = {"model": config.OPENAI_MODEL,
            "messages": [{"role": "user", "content": [{"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                                                      {"type": "text", "text": text}]}],
            "response_format": {"type": "json_schema", "json_schema": {"name": name, "strict": True, "schema": schema}}}
    if config.OPENAI_MODEL.startswith(("gpt-5", "o")):
        body["reasoning_effort"] = "low"
    r = httpx.post("https://api.openai.com/v1/chat/completions", json=body, timeout=20,
                   headers={"Authorization": f"Bearer {config.OPENAI_API_KEY}"})
    r.raise_for_status()
    return json.loads(r.json()["choices"][0]["message"]["content"])


def read(kind: str, image: bytes, section=None, fuel=None, hint=None) -> dict:
    if kind not in KINDS or not (config.OPENAI_API_KEY or config.ANTHROPIC_API_KEY):
        return {"ok": False}
    try:
        name, props, text = KINDS[kind]
        tool = {"name": name, "description": text, "strict": True,
                "input_schema": {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}}
        pairs = allowed_pairs(section, fuel) if kind == "damage" else None
        if pairs is not None:  # place: its types, one line per place
            text += "\n" + "\n".join(f"{p}: {'; '.join(ts)}" for p, ts in pairs.items())
            if hint:
                text += f"\nThe damage is at {hint}; use it as the place."
        if config.OPENAI_API_KEY:
            data = openai_read(name, props, text, jpeg(image))
            return {"ok": True, **validate(kind, data, pairs, hint)}
        msg = client().messages.create(
            model=config.AI_MODEL, max_tokens=2000, tools=[tool],
            # forced tool_choice ({"type": "tool"}) is refused (400) by Claude Sonnet 5.5 and Opus 5.5, so the prompt names the tool
            tool_choice={"type": "auto"}, output_config={"effort": "low"},
            messages=[{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": jpeg(image)}},
                {"type": "text", "text": f"{text}\nAnswer only by calling the {name} tool."}]}])
        data = next(b.input for b in msg.content if b.type == "tool_use" and b.name == name)
        return {"ok": True, **validate(kind, data, pairs, hint)}
    except Exception:
        log.exception("AI reading %s failed", kind)
        return {"ok": False}
