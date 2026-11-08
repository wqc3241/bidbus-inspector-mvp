"""FastAPI app: API at /api (passcode), reports at /r/... (no auth)."""
import hmac
import logging
import mimetypes
import secrets
import threading
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Path, Request, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import ai, config, email, reports, spin, storage
from .cr import build_cr
from .db import File as FileRow
from .db import Inspection, SessionLocal, get_session, now
from .vin import decode

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_app):
    # a build cut off by a restart (deploy, crash) never finishes: run it again, off the request path so the health check is not held up
    threading.Thread(target=resume_builds, daemon=True).start()
    yield


app = FastAPI(title="Bidbus Field", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


def _passcode_ok(authorization: str | None) -> bool:
    if not config.APP_PASSCODE or not authorization or not authorization.startswith("Bearer "):
        return False
    return hmac.compare_digest(authorization[len("Bearer "):].encode(), config.APP_PASSCODE.encode())


def require_passcode(authorization: str | None = Header(default=None)) -> None:
    if not _passcode_ok(authorization):
        raise HTTPException(status_code=401, detail="Wrong or missing passcode")


@app.get("/api/health")
def health(authorization: str | None = Header(default=None)):
    # open for the Railway health check; with a passcode it also says whether the passcode is right
    out = {"ok": True}
    if authorization is not None:
        out["passcode_ok"] = _passcode_ok(authorization)
    return out


api = APIRouter(prefix="/api", dependencies=[Depends(require_passcode)])
InspectionId = Annotated[str, Path(pattern=r"^[A-Za-z0-9-]{1,36}$")]
DB = Annotated[Session, Depends(get_session)]


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


def _inspection(s: Session, inspection_id: str) -> Inspection:
    insp = s.get(Inspection, inspection_id)
    if not insp:
        raise HTTPException(status_code=404, detail="No such inspection")
    return insp


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
def put_inspection(inspection_id: InspectionId, body: InspectionIn, s: DB):
    insp = s.get(Inspection, inspection_id) or Inspection(id=inspection_id)
    insp.report_email, insp.inspector, insp.car, insp.record = body.report_email, body.inspector, body.car, body.record
    insp.status, insp.validation_errors, insp.files_expected = "receiving", None, len(storage.expected(body.record))
    insp.signed_at = _signed_at(body.record)
    s.add(insp)
    s.commit()
    return {"status": insp.status, "missing": _missing(s, insp)}


@api.put("/inspections/{inspection_id}/files/{name}")
async def put_file(inspection_id: InspectionId, name: str, request: Request, s: DB):
    if not storage.ok_name(name):
        raise HTTPException(status_code=400, detail="Bad file name")
    insp = _inspection(s, inspection_id)
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
def complete(inspection_id: InspectionId, tasks: BackgroundTasks, s: DB):
    insp = _inspection(s, inspection_id)
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
        except Exception as e:
            log.exception("build %s failed", inspection_id)
            s.rollback()
            reason = str(e) if isinstance(e, EmailNotSent) else f"{type(e).__name__}: {e}"
            insp.status, insp.validation_errors = "failed", insp.validation_errors or [reason]
            s.commit()


def resume_builds() -> None:
    """builds left in 'building' when the server stopped"""
    with SessionLocal() as s:
        ids = list(s.scalars(select(Inspection.id).where(Inspection.status == "building")))
    for i in ids:
        build(i)


@api.get("/inspections/{inspection_id}")
def get_inspection(inspection_id: InspectionId, s: DB):
    return _status(s, _inspection(s, inspection_id))


@api.post("/inspections/{inspection_id}/resend-email")
def resend_email(inspection_id: InspectionId, s: DB):
    insp = _inspection(s, inspection_id)
    if not insp.cr or not insp.report_token or insp.status not in ("sent", "failed"):
        raise HTTPException(status_code=409, detail="The report is not built")
    try:
        _send_report(insp)
    except Exception:
        log.exception("resend %s failed", inspection_id)
        raise HTTPException(status_code=502, detail="Email not sent")
    s.commit()
    return _status(s, insp)


app.include_router(api)
app.include_router(reports.router)
