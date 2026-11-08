"""Report emails through the Resend REST API (docs/05-reports.md, Email)."""
import logging
from datetime import datetime
from html import escape

import httpx

from . import config

log = logging.getLogger(__name__)
BTN = 'display:inline-block;margin:0 8px 8px 0;padding:12px 18px;border-radius:8px;background:#045826;color:#fff;text-decoration:none;font-weight:600'


def car_line(car: dict) -> str:
    md, tr = str(car.get("model") or ""), str(car.get("trim") or "")
    skip = "model" if md and tr.lower().startswith(md.lower() + " ") else None  # a trim that starts with the model (Lexus "LC 500h")
    return " ".join(str(car[k]) for k in ("year", "make", "model", "trim") if car.get(k) and k != skip)


def date(d) -> str:
    return f"{d:%b} {d.day}, {d.year}"


def _at(insp, key: str):
    try:
        return datetime.fromisoformat(insp.record["source"][key]["at"])
    except (TypeError, KeyError, ValueError):
        return None


def inspected_on(insp):
    """when the inspection ended on the phone (its local time), else when it started, else when the server got it"""
    return _at(insp, "ended") or _at(insp, "started") or insp.created_at


def inspected_when(insp) -> str:
    """the date, with the time the inspection ended when the phone sent it"""
    end = _at(insp, "ended")
    return date(end) + f", {end.hour % 12 or 12}:{end.minute:02d} {'AM' if end.hour < 12 else 'PM'}" if end else date(inspected_on(insp))


def send(to: str, subject: str, html: str, text: str) -> bool:
    if not config.RESEND_API_KEY:
        log.warning("RESEND_API_KEY is empty, email not sent: %s to %s", subject, to)
        return False
    r = httpx.post("https://api.resend.com/emails", headers={"Authorization": f"Bearer {config.RESEND_API_KEY}"}, timeout=20,
                   json={"from": config.EMAIL_FROM, "to": [to], "subject": subject, "html": html, "text": text})
    r.raise_for_status()
    return True


def send_report(insp, seller_url: str, dealer_url: str) -> bool:
    car, miles = car_line(insp.car or {}), insp.cr["condition_report"]["vehicle"]["mileage"]
    lines = [car, f"{miles:,} mi" if miles is not None else "", f"Inspected {inspected_when(insp)}"]
    html = ("".join(f"<p style=\"margin:0 0 6px\">{escape(x)}</p>" for x in lines if x) +
            f'<p style="margin:18px 0"><a href="{escape(seller_url)}" style="{BTN}">Seller report</a>'
            f'<a href="{escape(dealer_url)}" style="{BTN}">Dealer report</a></p>')
    text = "\n".join(x for x in lines if x) + f"\n\nSeller report: {seller_url}\nDealer report: {dealer_url}\n"
    return send(insp.report_email, f"Condition report: {car}", html, text)


def send_failure(insp, reasons: list[str]) -> bool:
    car = car_line(insp.car or {})
    html = f"<p>{escape(car)}</p><ul>" + "".join(f"<li>{escape(r)}</li>" for r in reasons) + "</ul>"
    text = car + "\n\n" + "\n".join(f"- {r}" for r in reasons) + "\n"
    return send(insp.report_email, f"Condition report not made: {car}", html, text)
