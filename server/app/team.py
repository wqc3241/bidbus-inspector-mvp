"""Sign-in and appointments from the inspection scheduler (hyc492/inspection-scheduler, Supabase).

Inspectors sign in with the scheduler's own accounts (emailed code). Every call to the scheduler's database
goes through Supabase's REST API with the inspector's own access token, so its access rules apply as they
do on the scheduler site: an active member reads the schedule, and the only write is mark_slot_done
(scheduler migration 0006), which changes the inspector's own booked job.
"""
import hashlib
import logging
import threading
import time
from dataclasses import dataclass

import httpx

from . import config

log = logging.getLogger(__name__)
TIMEOUT = 15
SLOT_FIELDS = "id,date,start_time,status,seller_name,seller_phone,address,zip,lat,lng,vehicle,vin,mileage,notes,listing_id,booked_at,completed_at"


class TeamError(Exception):
    """a refusal to show the inspector (status and message)"""

    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status, self.message = status, message


@dataclass(frozen=True)
class Member:
    id: str
    name: str
    email: str | None
    token: str  # the inspector's access token, for calls made on their behalf


def enabled() -> bool:
    return bool(config.SUPABASE_URL and config.SUPABASE_ANON_KEY)


def _url(path: str) -> str:
    return config.SUPABASE_URL.rstrip("/") + path


def _headers(token: str | None = None) -> dict:
    return {"apikey": config.SUPABASE_ANON_KEY, "Authorization": f"Bearer {token or config.SUPABASE_ANON_KEY}"}


def _message(r: httpx.Response, default: str) -> str:
    try:
        j = r.json()
    except ValueError:
        return default
    return j.get("msg") or j.get("error_description") or j.get("message") or default


def _session(j: dict) -> dict:
    return {"access_token": j["access_token"], "refresh_token": j["refresh_token"],
            "expires_at": j.get("expires_at") or int(time.time()) + int(j.get("expires_in") or 3600)}


# ---------- sign-in ----------

def send_code(email: str) -> None:
    """the scheduler's team-list check first (when SCHEDULER_URL is set), then Supabase emails the sign-in code"""
    if config.SCHEDULER_URL:
        try:
            r = httpx.post(config.SCHEDULER_URL.rstrip("/") + "/api/auth/email-check", json={"email": email}, timeout=TIMEOUT)
            j = r.json()
        except (httpx.HTTPError, ValueError):
            log.exception("scheduler email check")
            j = {"allowed": True}  # the check is a courtesy; the member lookup after sign-in is what decides
        if not j.get("allowed"):
            raise TeamError(403, j.get("error") or "This email isn't on the team list. Ask an admin to add you.")
    r = httpx.post(_url("/auth/v1/otp"), headers=_headers(), json={"email": email, "create_user": True}, timeout=TIMEOUT)
    if r.status_code == 429:
        raise TeamError(429, "Too many codes. Wait a minute and try again.")
    if r.status_code >= 400:
        log.warning("otp %s: %s", r.status_code, r.text[:300])
        raise TeamError(502, _message(r, "The code was not sent. Try again."))


def verify_code(email: str, code: str) -> dict:
    r = httpx.post(_url("/auth/v1/verify"), headers=_headers(), json={"type": "email", "email": email, "token": code}, timeout=TIMEOUT)
    if r.status_code in (400, 401, 403, 422):
        raise TeamError(401, "Wrong or expired code.")
    if r.status_code >= 400:
        raise TeamError(502, _message(r, "Sign-in failed. Try again."))
    s = _session(r.json())
    m = member(s["access_token"])
    return {**s, "member": {"id": m.id, "name": m.name, "email": m.email}}


def refresh(refresh_token: str) -> dict:
    r = httpx.post(_url("/auth/v1/token?grant_type=refresh_token"), headers=_headers(), json={"refresh_token": refresh_token}, timeout=TIMEOUT)
    if r.status_code in (400, 401, 403):
        raise TeamError(401, "Signed out. Sign in again.")
    if r.status_code >= 400:
        raise TeamError(502, "Sign-in could not be renewed. Try again.")
    return _session(r.json())


# ---------- who is calling ----------

_cache: dict[str, tuple[float, Member]] = {}
_lock = threading.Lock()
CACHE_SECONDS = 60  # a removed member is blocked within a minute


def _key(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def member(token: str) -> Member:
    """the active scheduler inspector (or admin) this access token belongs to; TeamError 401 or 403 otherwise"""
    k, t = _key(token), time.monotonic()
    with _lock:
        hit = _cache.get(k)
        if hit and hit[0] > t:
            return hit[1]
    try:
        u = httpx.get(_url("/auth/v1/user"), headers=_headers(token), timeout=TIMEOUT)
        if u.status_code in (401, 403):
            raise TeamError(401, "Signed out. Sign in again.")
        u.raise_for_status()
        uid = u.json()["id"]
        r = httpx.get(_url("/rest/v1/members"), headers=_headers(token), timeout=TIMEOUT,
                      params={"user_id": f"eq.{uid}", "select": "id,name,email,active,is_inspector,is_admin"})
        r.raise_for_status()
        rows = r.json()
    except httpx.HTTPError as e:
        log.warning("scheduler sign-in check failed: %s", e)
        raise TeamError(503, "The scheduler was not reached. Try again.")
    # rows come back only for a linked, active member (the scheduler's read rule); the scheduler links an account
    # to its team-list entry on the first sign-in there
    row = rows[0] if rows else None
    if not row or not row.get("active"):
        raise TeamError(403, "Sign in to the scheduler site once with this email, then try again here.")
    if not (row.get("is_inspector") or row.get("is_admin")):
        raise TeamError(403, "Your account isn't set up as an inspector. Ask an admin.")
    m = Member(id=row["id"], name=row.get("name") or "", email=row.get("email"), token=token)
    with _lock:
        if len(_cache) > 500:
            _cache.clear()
        _cache[k] = (t + CACHE_SECONDS, m)
    return m


# ---------- appointments ----------

def _get(token: str, path: str, params: dict) -> list:
    try:
        r = httpx.get(_url(path), headers=_headers(token), params=params, timeout=TIMEOUT)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPError as e:
        log.warning("scheduler read %s failed: %s", path, e)
        raise TeamError(503, "The scheduler was not reached. Try again.")


def slots(m: Member, first: str, last: str) -> list[dict]:
    """the inspector's booked and done jobs from date first to date last (Los Angeles dates, YYYY-MM-DD)"""
    return _get(m.token, "/rest/v1/slots", {"select": SLOT_FIELDS, "inspector_id": f"eq.{m.id}", "status": "in.(booked,done)",
                                            "and": f"(date.gte.{first},date.lte.{last})", "order": "date.asc,start_time.asc"})


def slot(m: Member, slot_id: str) -> dict | None:
    rows = _get(m.token, "/rest/v1/slots", {"select": SLOT_FIELDS, "id": f"eq.{slot_id}", "inspector_id": f"eq.{m.id}",
                                            "status": "in.(booked,done)"})
    return rows[0] if rows else None


def mark_done(m: Member, slot_id: str, booked_at: str) -> str | None:
    """'done' or 'skipped' (the job is no longer that booking, or is done already); None when it could not be called"""
    try:
        r = httpx.post(_url("/rest/v1/rpc/mark_slot_done"), headers=_headers(m.token), timeout=TIMEOUT,
                       json={"p_slot": slot_id, "p_booked_at": booked_at})
    except httpx.HTTPError as e:
        log.warning("mark_slot_done %s: %s", slot_id, e)
        return None
    if r.status_code >= 400:
        log.warning("mark_slot_done %s: %s %s", slot_id, r.status_code, r.text[:300])
        return None
    out = r.json()
    return out if out in ("done", "skipped") else None
