"""The car brief from the Bidbus admin API (bidbus-v3), read with one admin service account held by this server.

GET /api/admin/vehicles/:id gives the car, the seller's documents, photos, self-inspection, Carfax and risk;
GET /api/admin/documents/:id gives a document's file link. Admin tokens do not expire on their own; a 401
(logout or password change) logs in again once.
"""
import io
import logging
import re
import threading
import time

import httpx

from . import config

log = logging.getLogger(__name__)
TIMEOUT = 20
DOC_LABELS = {"driver_license": "Driver's license", "registration": "Registration"}
REQUIRED_DOCS = ("driver_license", "registration")
VEHICLE_SECONDS = 300
PDF_BYTES = 25_000_000
PDF_PX = 1600  # longest side of each page in the JPEG


class BidbusError(Exception):
    pass


def enabled() -> bool:
    return bool(config.BIDBUS_ADMIN_PHONE and config.BIDBUS_ADMIN_PASSWORD)


_token: str | None = None
_lock = threading.Lock()
_login_failed_until = 0.0  # after a failed login, calls fail at once for 30 s instead of queueing behind new logins
_pdf_lock = threading.Lock()  # PDFium is not thread-safe
_vehicles: dict[str, tuple[float, dict]] = {}


def _url(path: str) -> str:
    return config.BIDBUS_API_URL.rstrip("/") + "/api/admin" + path


def _login() -> str:
    global _login_failed_until
    if time.monotonic() < _login_failed_until:
        raise BidbusError("Bidbus login failed a moment ago")
    try:
        r = httpx.post(_url("/sessions"), json={"phone_number": config.BIDBUS_ADMIN_PHONE, "password": config.BIDBUS_ADMIN_PASSWORD}, timeout=TIMEOUT)
        if r.status_code >= 400:
            raise BidbusError(f"Bidbus login failed ({r.status_code})")
        token = r.json().get("token")
        if not token:
            raise BidbusError("Bidbus login gave no token")
        return token
    except (httpx.HTTPError, BidbusError):
        _login_failed_until = time.monotonic() + 30
        raise


def _get(path: str) -> httpx.Response:
    global _token
    try:
        with _lock:
            if not _token:
                _token = _login()
            token = _token
        r = httpx.get(_url(path), headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT)
        if r.status_code == 401:
            with _lock:
                if _token == token:  # not renewed meanwhile by another request
                    _token = _login()
                token = _token
            r = httpx.get(_url(path), headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT)
        return r
    except httpx.HTTPError as e:
        raise BidbusError(f"Bidbus not reached: {e}") from e


def vehicle(vehicle_id: str) -> dict | None:
    """the admin vehicle JSON, None when there is no such vehicle; kept 5 minutes"""
    t = time.monotonic()
    hit = _vehicles.get(vehicle_id)
    if hit and hit[0] > t:
        return hit[1]
    r = _get(f"/vehicles/{vehicle_id}")
    if r.status_code == 404:
        return None
    if r.status_code >= 400:
        raise BidbusError(f"Bidbus vehicle {vehicle_id}: {r.status_code}")
    v = r.json()
    if len(_vehicles) > 200:
        _vehicles.clear()
    _vehicles[vehicle_id] = (t + VEHICLE_SECONDS, v)
    return v


def document(document_id: str) -> tuple[bytes, str]:
    """a document's file and its content type; a PDF comes as one JPEG of its pages, so every phone can show it"""
    r = _get(f"/documents/{document_id}")
    if r.status_code >= 400:
        raise BidbusError(f"Bidbus document {document_id}: {r.status_code}")
    try:
        f = httpx.get(r.json()["url"], timeout=60, follow_redirects=True)
        f.raise_for_status()
    except (httpx.HTTPError, KeyError, ValueError) as e:
        raise BidbusError(f"Bidbus document {document_id} file: {e}") from e
    if f.content[:5] == b"%PDF-":
        if len(f.content) > PDF_BYTES:
            raise BidbusError(f"Bidbus document {document_id}: PDF too large")
        try:
            return _pdf_jpeg(f.content), "image/jpeg"
        except Exception as e:
            raise BidbusError(f"Bidbus document {document_id}: PDF not read ({e})") from e
    return f.content, (f.headers.get("content-type") or "application/octet-stream").split(";")[0]


def _pdf_jpeg(data: bytes, pages: int = 3) -> bytes:
    import pypdfium2
    from PIL import Image

    imgs = []
    with _pdf_lock:
        pdf = pypdfium2.PdfDocument(data)
        try:
            for i in range(min(len(pdf), pages)):
                page = pdf[i]
                w, h = page.get_size()
                # 2x for a normal page, smaller for a big one (a photo saved as a PDF can be thousands of points wide)
                scale = min(2.0, PDF_PX / max(w, h, 1))
                imgs.append(page.render(scale=scale).to_pil().convert("RGB"))
                page.close()
        finally:
            pdf.close()
    if not imgs:
        raise ValueError("no pages")
    w = max(i.width for i in imgs)
    out = Image.new("RGB", (w, sum(i.height for i in imgs)), "white")
    y = 0
    for i in imgs:
        out.paste(i, (0, y))
        y += i.height
    buf = io.BytesIO()
    out.save(buf, "JPEG", quality=85)
    return buf.getvalue()


# ---------- the brief ----------

def _owners(cf: dict) -> str | None:
    # numOwners stops at 3; the history line ("4 Previous Owners") has the real count when it is there
    for line in cf.get("history_overview") or []:
        if isinstance(line, str) and (mt := re.match(r"\s*(\d+) Previous Owners?\b", line)):
            return mt.group(1)
    n = cf.get("numOwners")
    if isinstance(n, (int, float)) and n > 0:
        return "3+" if n >= 3 else str(int(n))
    return None


def _carfax(v: dict) -> dict | None:
    cf = (v.get("vauto_data") or {}).get("carfax") or {}
    if cf.get("hasReport") is not True:
        return None
    n = cf.get("accidentCount")
    n = int(n) if isinstance(n, str) and n.isdigit() else n
    accident = (isinstance(n, (int, float)) and n >= 1) or cf.get("hasAccidentIndicators") is True
    return {
        "owners": _owners(cf),
        "accident": accident,
        "accident_detail": [d.get("label") for d in cf.get("damage_showcase") or [] if isinstance(d, dict) and d.get("label")],
        "clean_title": cf.get("hasCleanTitle"),
        "frame_damage": cf.get("hasFrameDamage") is True,
        "total_loss": cf.get("hasTotalLoss") is True,
        "airbag": cf.get("hasAirbagDeployment") is True,
        "odometer_rollback": cf.get("hasOdometerRollback") is True,
        "last_odometer": cf.get("odometer_reading") or None,
        "service_records": cf.get("serviceRecordCount"),
        "open_recall": cf.get("hasManufacturerRecall") is True,
        "report_url": cf.get("carfax_report_url") or None,
    }


def _checks(v: dict, cf: dict | None) -> list[dict]:
    out = []

    def add(text, level):
        out.append({"text": text, "level": level})

    if cf:
        if cf["frame_damage"]:
            add("Carfax: frame damage", "red")
        if cf["total_loss"]:
            add("Carfax: total loss", "red")
        if cf["clean_title"] is False:
            add("Carfax: title not clean", "red")
        if cf["odometer_rollback"]:
            add("Carfax: odometer rollback", "red")
        if cf["airbag"]:
            add("Carfax: airbag deployed", "amber")
        if cf["accident"]:
            add("Carfax: " + (", ".join(cf["accident_detail"]) or "accident or damage"), "amber")
        if cf["open_recall"]:
            add("Carfax: open recall", "amber")
    si = v.get("self_inspection_data") or {}
    if si.get("frame_damage") == "yes":
        add("Seller: frame damage", "red")
    if si.get("vehicle_drivability") == "not_drivable":
        add("Seller: not drivable", "red")
    if any(isinstance(i, dict) and i.get("name") == "transmission" for i in si.get("mechanical_issues") or []):
        add("Seller: transmission issue", "amber")
    if si.get("check_engine_light_on") == "yes":
        add("Seller: check engine light on", "amber")
    risk = v.get("risk") or {}
    if risk.get("level") in ("medium", "high"):
        reasons = [r.get("label") for r in risk.get("reasons") or [] if isinstance(r, dict) and r.get("label")]
        add(f"Bidbus risk {risk['level']}" + (": " + ", ".join(reasons) if reasons else ""), "red" if risk["level"] == "high" else "amber")
    return out


def _photos(v: dict) -> list[dict]:
    out = []
    for p in v.get("transformed_vehicle_photos") or []:
        if isinstance(p, dict) and p.get("url"):
            out.append({"url": p["url"], "label": str((p.get("info") or {}).get("position") or "").replace("_", " ")})
    for p in v.get("transformed_damage_photos") or []:
        if isinstance(p, dict) and p.get("url"):
            info = p.get("info") or {}
            out.append({"url": p["url"], "label": " ".join(x for x in (str(info.get("damage_type") or "").replace("_", " "), str(info.get("description") or "")) if x),
                        "damage": True})
    return out


def _registered(v: dict) -> str | None:
    ri = v.get("registration_info") or {}
    names = [n for n in ri.get("individual_owner_names") or [] if isinstance(n, str) and n.strip()]
    return ", ".join(names) or ri.get("business_name") or None


def brief(v: dict) -> dict:
    cf = _carfax(v)
    docs = [{"type": d.get("document_type"), "label": DOC_LABELS.get(d.get("document_type"), str(d.get("document_type") or "").replace("_", " ").capitalize()),
             "document_id": str(d["document_id"]), "content_type": (d.get("metadata") or {}).get("content_type"),
             "uploaded_at": (d.get("metadata") or {}).get("uploaded_at")}
            for d in v.get("required_documents") or [] if isinstance(d, dict) and d.get("document_id")]
    return {
        "vehicle_id": v.get("id"),
        "car": {"year": v.get("year"), "make": v.get("make"), "model": v.get("model"), "series": v.get("series") or None,
                "trim": " ".join(x for x in (v.get("series"), v.get("style")) if x) or None,
                "vin": v.get("vin"), "mileage": v.get("mileage"), "color": v.get("color"), "zip": v.get("zip_code")},
        "photo_url": v.get("primary_photo_url"),
        "owner": {"name": v.get("owner_name"), "registered": _registered(v)},
        "documents": docs,
        "documents_uploaded": len({d["type"] for d in docs if d["type"] in REQUIRED_DOCS}),
        "documents_required": len(REQUIRED_DOCS),
        "photos": _photos(v),
        "carfax": cf,
        "checks": _checks(v, cf),
    }
