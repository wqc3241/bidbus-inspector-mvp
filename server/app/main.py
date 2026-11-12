"""FastAPI app: API at /api (scheduler sign-in when it is set up, or the app passcode), reports at /r/... (no auth)."""
import hmac
import logging
import mimetypes
import secrets
import re
import threading
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Path, Request, UploadFile
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import ai, bidbus, config, email, hotspots, reports, spin, storage, team
from .cr import build_cr, renamed
from .db import File as FileRow
from .db import Inspection, SessionLocal, get_session, now
from .vin import decode

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_app):
    # a build cut off by a restart (deploy, crash) never finishes: run it again, off the request path so the health check is not held up
    threading.Thread(target=lambda: (reword_reports(), resume_builds()), daemon=True).start()
    yield


app = FastAPI(title="Bidbus Field", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


def _passcode_ok(authorization: str | None) -> bool:
    if not config.APP_PASSCODE or not authorization or not authorization.startswith("Bearer "):
        return False
    return hmac.compare_digest(authorization[len("Bearer "):].encode(), config.APP_PASSCODE.encode())


def require_user(authorization: str | None = Header(default=None)) -> team.Member | None:
    """the signed-in scheduler inspector (docs/12-scheduler-sync.md), or no one for a phone that sends the app passcode:
    it has no booked jobs and makes its own inspections"""
    if _passcode_ok(authorization):
        return None
    if not team.enabled():
        raise HTTPException(status_code=401, detail="Wrong or missing passcode")
    if not authorization or not authorization.startswith("Bearer ") or len(authorization) <= len("Bearer "):
        raise HTTPException(status_code=401, detail="Sign in first")
    try:
        return team.member(authorization[len("Bearer "):])
    except team.TeamError as e:
        raise HTTPException(status_code=e.status, detail=e.message)


@app.get("/api/health")
def health(authorization: str | None = Header(default=None)):
    # open for the Railway health check; with a passcode (or a sign-in) it also says whether it is right
    out = {"ok": True}
    if team.enabled():
        out["auth"] = "team"
        if _passcode_ok(authorization):
            out["passcode_ok"] = True
        elif authorization is not None:
            try:
                out["signed_in"] = require_user(authorization) is not None
            except HTTPException as e:
                if e.status_code == 401:
                    out["signed_in"] = False
                else:  # scheduler not reached, or not on the team list: not a sign-out
                    out["ok"] = False
    elif authorization is not None:
        out["passcode_ok"] = _passcode_ok(authorization)
    return out


api = APIRouter(prefix="/api", dependencies=[Depends(require_user)])
InspectionId = Annotated[str, Path(pattern=r"^[A-Za-z0-9-]{1,36}$")]
SlotId = Annotated[str, Path(pattern=r"^[0-9a-fA-F-]{36}$")]
DB = Annotated[Session, Depends(get_session)]
Me = Annotated[team.Member | None, Depends(require_user)]


# ---------- scheduler sign-in (open: these give the token) ----------

auth = APIRouter(prefix="/api/auth")
EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


class EmailIn(BaseModel):
    email: str


class CodeIn(BaseModel):
    email: str
    code: str


class RefreshIn(BaseModel):
    refresh_token: str


def _team(fn, *args):
    if not team.enabled():
        raise HTTPException(status_code=404, detail="Scheduler sign-in is not set up")
    try:
        return fn(*args)
    except team.TeamError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    except Exception:
        log.exception("scheduler sign-in")
        raise HTTPException(status_code=503, detail="The scheduler was not reached. Try again.")


def _email(raw: str) -> str:
    e = raw.strip().lower()
    if not EMAIL.match(e):
        raise HTTPException(status_code=400, detail="Enter a valid email address.")
    return e


@auth.post("/code")
def auth_code(body: EmailIn):
    _team(team.send_code, _email(body.email))
    return {"sent": True}


@auth.post("/verify")
def auth_verify(body: CodeIn):
    code = re.sub(r"\D", "", body.code)
    if not 6 <= len(code) <= 10:
        raise HTTPException(status_code=401, detail="Wrong or expired code.")
    return _team(team.verify_code, _email(body.email), code)


@auth.post("/refresh")
def auth_refresh(body: RefreshIn):
    return _team(team.refresh, body.refresh_token)


@api.get("/vin/{vin}")
def vin_decode(vin: str):
    try:
        return decode(vin.strip().upper())
    except Exception:
        log.exception("vPIC decode failed for %s", vin)
        raise HTTPException(status_code=502, detail="VIN decode failed")


@api.post("/ai/read")
def ai_read(kind: Annotated[str, Form()], image: Annotated[UploadFile, File()], section: Annotated[str | None, Form()] = None,
            fuel: Annotated[str | None, Form()] = None, hint: Annotated[str | None, Form()] = None):
    return ai.read(kind, image.file.read(), section, fuel, hint)


class InspectionIn(BaseModel):
    report_email: str
    inspector: str | None = None
    car: dict
    record: dict
    appointment: dict | None = None  # {slot_id, booked_at, vehicle_id}: the scheduler appointment it was started from


def _mine(insp: Inspection | None, me: team.Member | None) -> bool:
    # a signed-in inspector's inspection is theirs only; one made with the app passcode has no inspector
    if insp is None or insp.member_id is None:
        return insp is not None
    return insp.member_id == me.id if me is not None else not team.enabled()


def _inspection(s: Session, inspection_id: str, me: team.Member | None) -> Inspection:
    insp = s.get(Inspection, inspection_id)
    if not _mine(insp, me):
        raise HTTPException(status_code=404, detail="No such inspection")
    return insp


def _str(v, pattern: str) -> str | None:
    return v if isinstance(v, str) and re.fullmatch(pattern, v) else None


def _missing(s: Session, insp: Inspection) -> list[str]:
    got = set(s.scalars(select(FileRow.name).where(FileRow.inspection_id == insp.id)))
    return [n for n in storage.expected(insp.record) if n not in got]


def _urls(token: str) -> tuple[str, str]:
    return f"{config.PUBLIC_BASE_URL}/r/{token}/seller", f"{config.PUBLIC_BASE_URL}/r/{token}/dealer"


def _status(s: Session, insp: Inspection) -> dict:
    missing = _missing(s, insp)
    seller, dealer = _urls(insp.report_token) if insp.status == "sent" else (None, None)
    return {"status": insp.status, "missing": missing, "received": insp.files_expected - len(missing), "files_expected": insp.files_expected,
            "seller_url": seller, "dealer_url": dealer, "validation_errors": insp.validation_errors or [],
            "report_sent_at": insp.report_sent_at.isoformat() if insp.report_sent_at else None}


class EmailNotSent(Exception):
    pass


def _send_report(insp: Inspection) -> None:
    if not email.send_report(insp, *_urls(insp.report_token)):  # no RESEND_API_KEY
        raise EmailNotSent("The report was built but the email was not sent")
    insp.status, insp.report_sent_at, insp.validation_errors = "sent", now(), None


def _signed_at(record: dict) -> datetime | None:
    """when the seller signed: the record's 'ended' is taken as the seller taps Sign (stored when the phone sends its UTC offset)"""
    try:
        d = datetime.fromisoformat(record["source"]["ended"]["at"]) if record["signature"]["signed"] else None
    except (TypeError, KeyError, ValueError):
        return None
    return d if d and d.tzinfo else None


@api.put("/inspections/{inspection_id}")
def put_inspection(inspection_id: InspectionId, body: InspectionIn, s: DB, me: Me):
    insp = s.get(Inspection, inspection_id)
    if insp is not None and not _mine(insp, me):
        raise HTTPException(status_code=404, detail="No such inspection")
    insp = insp or Inspection(id=inspection_id)
    insp.report_email, insp.inspector, insp.car, insp.record = body.report_email, body.inspector, body.car, body.record
    if me is not None:
        insp.member_id, insp.inspector = me.id, me.name or body.inspector
    a = body.appointment or {}
    slot_id, booked_at = _str(a.get("slot_id"), r"[0-9a-fA-F-]{36}"), _str(a.get("booked_at"), r"[0-9T:.+\- ]{10,40}")
    if slot_id and booked_at and (slot_id, booked_at) != (insp.slot_id, insp.booked_at):
        insp.slot_id, insp.booked_at, insp.slot_done_at = slot_id, booked_at, None
    insp.vehicle_id = _str(str(a["vehicle_id"]) if a.get("vehicle_id") is not None else None, r"[0-9]{1,12}") or insp.vehicle_id
    insp.status, insp.validation_errors, insp.files_expected = "receiving", None, len(storage.expected(body.record))
    insp.signed_at = _signed_at(body.record)
    s.add(insp)
    s.commit()
    return {"status": insp.status, "missing": _missing(s, insp)}


@api.put("/inspections/{inspection_id}/files/{name}")
async def put_file(inspection_id: InspectionId, name: str, request: Request, s: DB, me: Me):
    if not storage.ok_name(name):
        raise HTTPException(status_code=400, detail="Bad file name")
    insp = _inspection(s, inspection_id, me)
    try:
        size, sha256 = await storage.save(inspection_id, name, request.stream())
    except storage.TooLarge:
        raise HTTPException(status_code=413, detail="File over 200 MB")
    row = s.get(FileRow, (inspection_id, name)) or FileRow(inspection_id=inspection_id, name=name)
    row.size, row.sha256, row.received_at = size, sha256, now()
    row.content_type = request.headers.get("content-type") or mimetypes.guess_type(name)[0]
    s.add(row)
    s.commit()
    return {"missing": _missing(s, insp)}


@api.post("/inspections/{inspection_id}/complete", status_code=202)
def complete(inspection_id: InspectionId, tasks: BackgroundTasks, s: DB, me: Me):
    insp = _inspection(s, inspection_id, me)
    if missing := _missing(s, insp):
        return JSONResponse({"missing": missing}, status_code=409)
    if insp.status in ("building", "sent"):  # a repeated call does not build or email twice
        return {"status": insp.status}
    insp.status = "building"
    insp.report_token = insp.report_token or secrets.token_urlsafe(24)  # set before the build, so a build run twice emails the same links
    s.commit()
    tasks.add_task(build, inspection_id)
    return {"status": "building"}


def build(inspection_id: str) -> None:
    """docs/06-backend.md, Build pipeline"""
    with SessionLocal() as s:
        insp = s.get(Inspection, inspection_id)
        if not insp or insp.status != "building":  # built already (an older container during a deploy) or the record was sent again
            return
        try:
            try:
                spin.ensure_frames(storage.folder(inspection_id))
            except Exception:
                log.exception("spin frames for %s", inspection_id)
            out = build_cr(insp.record)
            if not out["validation"]["ok"]:
                insp.status, insp.validation_errors, insp.cr = "failed", out["validation"]["errors"], None
                s.commit()
                email.send_failure(insp, insp.validation_errors)
                return
            insp.report_token = insp.report_token or secrets.token_urlsafe(24)
            insp.cr, insp.validation_errors = out, None
            s.commit()
            _send_report(insp)
            s.commit()
            try:  # the damage dots on the 360 view, after the email so it is not held up (a report opened meanwhile shows them later)
                hotspots.ensure(inspection_id, storage.folder(inspection_id), insp.record, wait=True)
            except Exception:
                log.exception("damage dots for %s", inspection_id)
        except Exception as e:
            log.exception("build %s failed", inspection_id)
            s.rollback()
            reason = str(e) if isinstance(e, EmailNotSent) else f"{type(e).__name__}: {e}"
            insp.status, insp.validation_errors = "failed", insp.validation_errors or [reason]
            s.commit()


def reword_reports() -> None:
    """records saved with the old option wording move to today's (data/option-renames.json), and their reports are built again"""
    try:
        with SessionLocal() as s:
            for insp in s.scalars(select(Inspection).where(Inspection.record.is_not(None))):
                new = renamed(insp.record)
                if new == insp.record:
                    continue
                insp.record = new
                if insp.cr:
                    out = build_cr(new)
                    if out["validation"]["ok"]:
                        insp.cr = out
            s.commit()
    except Exception:
        log.exception("rewording saved reports failed")


def resume_builds() -> None:
    """builds left in 'building' when the server stopped"""
    with SessionLocal() as s:
        ids = list(s.scalars(select(Inspection.id).where(Inspection.status == "building")))
    for i in ids:
        build(i)


@api.get("/inspections/{inspection_id}")
def get_inspection(inspection_id: InspectionId, s: DB, me: Me):
    insp = _inspection(s, inspection_id, me)
    if insp.status == "sent":
        _close_jobs(s, me)
    return _status(s, insp)


@api.post("/inspections/{inspection_id}/resend-email")
def resend_email(inspection_id: InspectionId, s: DB, me: Me):
    insp = _inspection(s, inspection_id, me)
    if not insp.cr or not insp.report_token or insp.status not in ("sent", "failed"):
        raise HTTPException(status_code=409, detail="The report is not built")
    try:
        _send_report(insp)
    except Exception:
        log.exception("resend %s failed", inspection_id)
        raise HTTPException(status_code=502, detail="Email not sent")
    s.commit()
    return _status(s, insp)


# ---------- scheduler appointments and the car brief (docs/12-scheduler-sync.md) ----------

def _close_jobs(s: Session, me: team.Member | None) -> None:
    """the scheduler job of each of this inspector's sent reports is marked completed, with the inspector's own sign-in;
    one that could not be (no signal, scheduler down) is tried again on the next calls, for 2 days"""
    if me is None:
        return
    rows = s.scalars(select(Inspection).where(Inspection.member_id == me.id, Inspection.status == "sent", Inspection.slot_id.is_not(None),
                                              Inspection.booked_at.is_not(None), Inspection.slot_done_at.is_(None),
                                              Inspection.report_sent_at >= now() - timedelta(days=2))
                     .order_by(Inspection.report_sent_at.desc()).limit(5)).all()
    for insp in rows:
        # skipped: done already, or the booking was cancelled or changed since; either way nothing is left to do
        if team.mark_done(me, insp.slot_id, insp.booked_at) in ("done", "skipped"):
            insp.slot_done_at = now()
            s.commit()


def _signed_in(me: team.Member | None) -> team.Member:
    if me is None:
        raise HTTPException(status_code=404, detail="Scheduler sign-in is not set up")
    return me


def _la_today() -> date:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Los_Angeles")).date()
    except Exception:  # no time zone data: Pacific standard time
        return datetime.now(timezone(timedelta(hours=-8))).date()


def _appointment(r: dict) -> dict:
    return {"key": f"{r['id']}@{r.get('booked_at')}", "slot_id": r["id"], "booked_at": r.get("booked_at"), "date": r.get("date"),
            "start_time": r.get("start_time"), "status": r.get("status"), "seller_name": r.get("seller_name"), "seller_phone": r.get("seller_phone"),
            "address": r.get("address"), "zip": r.get("zip"), "lat": r.get("lat"), "lng": r.get("lng"), "vehicle": r.get("vehicle"),
            "vin": r.get("vin"), "mileage": r.get("mileage"), "notes": r.get("notes"), "vehicle_id": r.get("listing_id")}


def _team_call(fn, *args):
    try:
        return fn(*args)
    except team.TeamError as e:
        raise HTTPException(status_code=e.status, detail=e.message)


@api.get("/me")
def me_(me: Me):
    m = _signed_in(me)
    return {"id": m.id, "name": m.name, "email": m.email}


@api.get("/appointments")
def appointments(s: DB, me: Me):
    """the inspector's booked and done jobs, today and the next 7 days (Los Angeles)"""
    m, first = _signed_in(me), _la_today()
    rows = _team_call(team.slots, m, first.isoformat(), (first + timedelta(days=7)).isoformat())
    _close_jobs(s, m)
    return {"today": first.isoformat(), "appointments": [_appointment(r) for r in rows]}


_decoded: dict[str, dict] = {}


def _decode(vin: str) -> dict | None:
    """the booking VIN's vPIC decode (fuel only when vPIC knows it), kept once vPIC answers"""
    if vin not in _decoded:
        try:
            _decoded[vin] = decode(vin, known_fuel=True)
        except Exception:
            log.warning("vPIC decode for %s failed", vin)
            return None
    return _decoded[vin]


_norm_vin = bidbus.normalize_vin


@api.get("/appointments/{slot_id}/brief")
def appointment_brief(slot_id: SlotId, me: Me):
    """the appointment with the Bidbus car brief when Bidbus has a car with the booking's VIN"""
    m = _signed_in(me)
    row = _team_call(team.slot, m, slot_id)
    if not row:
        raise HTTPException(status_code=404, detail="No such appointment")
    out = {"appointment": _appointment(row), "vehicle": None, "bidbus": "none", "fuel": None, "decoded": None, "vin_differs": False}
    booking_vin = _norm_vin(row.get("vin"))
    if bidbus.enabled():
        try:
            v = _bidbus_car(row) if len(booking_vin) == 17 else None
            out["vehicle"], out["bidbus"] = (bidbus.brief(v), "ok") if v else (None, "not_found")
        except bidbus.BidbusError:
            log.exception("Bidbus car for slot %s", slot_id)
            out["bidbus"] = "error"
    d = _decode(booking_vin) if len(booking_vin) == 17 else None
    if d:
        out["fuel"], out["decoded"] = d["fuel"], {k: d[k] for k in ("year", "make", "model", "trim")}
    return out


def _bidbus_car(row: dict) -> dict | None:
    """the booked car in Bidbus, found by the booking's 17-character VIN alone: the newest Bidbus car with that VIN,
    or the one the scheduler's Listing ID names when it is one of them"""
    ids = bidbus.vehicle_ids(_norm_vin(row.get("vin")))
    if not ids:
        return None
    lid = str(row.get("listing_id") or "").strip()
    v = bidbus.vehicle(lid if lid in ids else ids[0])
    return v if v and _booked_car(row, v) else None


def _booked_car(row: dict, v: dict) -> bool:
    """the Bidbus car is the booked car: its VIN is the booking's 17-character VIN"""
    booking_vin = _norm_vin(row.get("vin"))
    return len(booking_vin) == 17 and _norm_vin(v.get("vin")) == booking_vin


def _document_vehicle(m: team.Member, slot_id: str, document_id: str) -> str:
    """the document must be one of the seller's documents on this appointment's Bidbus car; gives the vehicle ID"""
    row = _team_call(team.slot, m, slot_id)
    if not row or len(_norm_vin(row.get("vin"))) != 17 or not bidbus.enabled():
        raise HTTPException(status_code=404, detail="No such document")
    try:
        v = _bidbus_car(row) or {}
    except bidbus.BidbusError:
        log.exception("Bidbus car for slot %s", slot_id)
        raise HTTPException(status_code=502, detail="Bidbus not reached")
    if not v or document_id not in {str(d.get("document_id")) for d in v.get("required_documents") or [] if isinstance(d, dict)}:
        raise HTTPException(status_code=404, detail="No such document")
    return str(v.get("id"))


@api.get("/appointments/{slot_id}/documents/{document_id}")
def appointment_document(slot_id: SlotId, document_id: Annotated[str, Path(pattern=r"^[0-9]{1,15}$")], me: Me):
    """a seller's document file (driver's license, registration): only through here, never on a report link"""
    m = _signed_in(me)
    vid = _document_vehicle(m, slot_id, document_id)
    log.info("seller document %s of Bidbus vehicle %s to %s (slot %s)", document_id, vid, m.email, slot_id)
    try:
        data, content_type = bidbus.document(document_id)
    except bidbus.BidbusError:
        log.exception("Bidbus document %s", document_id)
        raise HTTPException(status_code=502, detail="Bidbus not reached")
    return Response(data, media_type=content_type, headers={"Cache-Control": "private, no-store"})


app.include_router(auth)
app.include_router(api)
app.include_router(reports.router)
