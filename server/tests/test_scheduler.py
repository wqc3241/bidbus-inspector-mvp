"""Scheduler sign-in, appointments, the Bidbus car brief and marking the scheduler job done (docs/12-scheduler-sync.md).
Supabase, the scheduler site, the Bidbus admin API, the document store and vPIC are faked at the httpx level."""
import io
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from conftest import CARS, PASS, sample

from app import bidbus, config, main, team
from app.db import Inspection, SessionLocal

SB, SCHED, BB = "https://sb.test", "https://sched.test", "https://bb.test"
ANA, BO = "aaaaaaaa-0000-4000-8000-000000000001", "aaaaaaaa-0000-4000-8000-000000000002"
S1, S2, S3, S4 = (f"bbbbbbbb-0000-4000-8000-00000000000{i}" for i in range(1, 5))
BOOKED = "2026-11-10T18:00:00.123456+00:00"
VIN = "5UXTY5C00L9B00230"  # the Bidbus car's VIN, also on its bookings


def vehicle_json(vid=412345):
    return {
        "id": vid, "year": 2020, "make": "BMW", "model": "X3", "series": "xDrive30i", "style": "Sport Utility 4D", "vin": "5UXTY5C00L9B00230",
        "mileage": 61240, "color": "Black", "zip_code": "94010", "owner_name": "Daniel Kim", "owner_phone_number": "+16505550142",
        "primary_photo_url": "https://img.test/front.jpg",
        "registration_info": {"owner_type": "single_owner", "individual_owner_names": ["Daniel Kim"]},
        "required_documents": [
            {"id": "cf1", "document_id": 9001, "document_type": "driver_license", "url": "/documents/9001",
             "metadata": {"content_type": "image/jpeg", "uploaded_at": "2026-11-10T07:58:00Z"}},
            {"id": "cf2", "document_id": None, "document_type": "registration", "url": None, "metadata": {}},
        ],
        "transformed_vehicle_photos": [{"url": "https://img.test/front.jpg", "info": {"position": "front_left"}}],
        "transformed_damage_photos": [{"url": "https://img.test/dent.jpg", "info": {"damage_type": "dents", "description": "rear door"}}],
        "self_inspection_data": {"frame_damage": "no", "vehicle_drivability": "drivable", "check_engine_light_on": "yes",
                                 "mechanical_issues": [{"name": "transmission"}]},
        "vauto_data": {"carfax": {"hasReport": True, "numOwners": 3, "accidentCount": 1, "hasAccidentIndicators": True, "hasCleanTitle": True,
                                  "hasFrameDamage": False, "hasTotalLoss": False, "hasAirbagDeployment": False, "hasOdometerRollback": False,
                                  "hasManufacturerRecall": True, "odometer_reading": "60,102 mi", "serviceRecordCount": 15,
                                  "carfax_report_url": "https://carfax.test/r/1",
                                  "damage_showcase": [{"name": "minorDamage", "label": "Minor Damage", "severity": "Minor"}],
                                  "history_overview": ["15 Service History Records", "4 Previous Owners", "Last Owned in California"]}},
        "risk": {"score": 40, "level": "medium", "reasons": [{"code": "x", "label": "New seller account"}]},
    }


class World:
    """what the fakes answer from"""

    def __init__(self, today):
        d = lambda n: (today + timedelta(days=n)).isoformat()  # noqa: E731
        self.users = {"tok-ana": "uid-ana", "tok-bo": "uid-bo", "tok-new": "uid-new"}  # access token -> auth user
        self.members = [
            {"id": ANA, "user_id": "uid-ana", "name": "Ana Inspector", "email": "ana@bidbus.com", "active": True, "is_inspector": True, "is_admin": False},
            {"id": BO, "user_id": "uid-bo", "name": "Bo", "email": "bo@bidbus.com", "active": True, "is_inspector": True, "is_admin": False},
        ]
        base = {"seller_name": "Daniel Kim", "seller_phone": "(650) 555-0142", "address": "4321 Overland Ave", "zip": "90230", "lat": 34.0,
                "lng": -118.4, "vehicle": "2020 BMW X3", "vin": None, "mileage": 61000, "notes": "Gate code 1234", "completed_at": None}
        self.slots = [
            {**base, "id": S1, "inspector_id": ANA, "date": d(0), "start_time": "10:00", "status": "booked", "listing_id": "412345", "booked_at": BOOKED,
             "vin": VIN},
            {**base, "id": S2, "inspector_id": ANA, "date": d(0), "start_time": "09:00", "status": "booked", "listing_id": None, "booked_at": BOOKED,
             "vin": "1HGCM82633A004352"},
            {**base, "id": S3, "inspector_id": BO, "date": d(0), "start_time": "09:00", "status": "booked", "listing_id": "412345", "booked_at": BOOKED,
             "vin": VIN},
            {**base, "id": S4, "inspector_id": ANA, "date": d(9), "start_time": "09:00", "status": "booked", "listing_id": None, "booked_at": BOOKED},
        ]
        self.vehicles = {"412345": vehicle_json()}
        self.rpc = []  # mark_slot_done calls
        self.rpc_missing = False
        self.bb_token = "bb-1"
        self.calls = []
        self.searches = []  # Bidbus VIN searches
        self.doc_pdf = False  # the document store holds a PDF
        self.sb_down = False  # Supabase not reached

    def me(self, headers):
        uid = self.users.get((headers or {}).get("Authorization", "")[len("Bearer "):])
        return next((m for m in self.members if m["user_id"] == uid and m["active"]), None) if uid else None

    def get(self, url, headers=None, params=None, timeout=None, follow_redirects=False):
        self.calls.append(("GET", url))
        u, q = urlparse(url), dict(params or {})
        if url.startswith(SB) and self.sb_down:
            raise httpx.ConnectError("down")
        if url.startswith(SB + "/auth/v1/user"):
            uid = self.users.get(headers["Authorization"][len("Bearer "):])
            return resp(200, {"id": uid}) if uid else resp(401, {"msg": "bad jwt"})
        if url.startswith(SB + "/rest/v1/members"):
            me = self.me(headers)
            return resp(200, [m for m in self.members if me and q["user_id"] == f"eq.{m['user_id']}"])
        if url.startswith(SB + "/rest/v1/slots"):
            if not self.me(headers):
                return resp(200, [])
            rows = [s for s in self.slots if s["status"] in ("booked", "done") and q["inspector_id"] == f"eq.{s['inspector_id']}"]
            if "id" in q:
                rows = [s for s in rows if q["id"] == f"eq.{s['id']}"]
            if "and" in q:
                first, last = q["and"][len("(date.gte."):-1].split(",date.lte.")
                rows = [s for s in rows if first <= s["date"] <= last]
            return resp(200, sorted(rows, key=lambda s: (s["date"], s["start_time"])))
        if url == BB + "/api/admin/vehicles":
            if headers.get("Authorization") != f"Bearer {self.bb_token}":
                return resp(401, {"error": "no"})
            vq = str(q.get("vehicle_query") or "")
            self.searches.append(vq)
            rows = sorted((v for v in self.vehicles.values() if len(vq) == 17 and str(v.get("vin") or "").upper() == vq.upper()),
                          key=lambda v: v.get("created_at") or "", reverse=True)
            return resp(200, {"vehicles": [{"id": v["id"], "vin": v["vin"], "created_at": v.get("created_at")} for v in rows], "total": len(rows)})
        if url.startswith(BB + "/api/admin/vehicles/"):
            if headers.get("Authorization") != f"Bearer {self.bb_token}":
                return resp(401, {"error": "no"})
            v = self.vehicles.get(u.path.rsplit("/", 1)[1])
            return resp(200, v) if v else resp(404, {"error": "not found"})
        if url.startswith(BB + "/api/admin/documents/"):
            return resp(200, {"url": "https://r2.test/doc.jpg?sig=1"})
        if url.startswith("https://r2.test/"):
            if self.doc_pdf:
                return httpx.Response(200, content=pdf_bytes(), headers={"content-type": "application/pdf"}, request=httpx.Request("GET", url))
            return httpx.Response(200, content=b"JPEGDATA", headers={"content-type": "image/jpeg"}, request=httpx.Request("GET", url))
        if "vpic.nhtsa.dot.gov" in url:
            return resp(200, {"Results": [{"FuelTypePrimary": "Gasoline", "ElectrificationLevel": "", "ModelYear": "2003", "Make": "HONDA",
                                           "Model": "Accord", "Trim": "EX"}]})
        raise AssertionError(f"unexpected GET {url}")

    def post(self, url, headers=None, json=None, timeout=None):
        self.calls.append(("POST", url))
        if url == SCHED + "/api/auth/email-check":
            ok = json["email"] in {m["email"] for m in self.members}
            return resp(200, {"allowed": ok, "error": None if ok else "This email isn't on the team list. Ask an admin to add you."})
        if url == SB + "/auth/v1/otp":
            return resp(200, {})
        if url == SB + "/auth/v1/verify":
            return resp(200, session("tok-ana")) if json["token"] == "123456" else resp(403, {"msg": "Token has expired or is invalid"})
        if url.startswith(SB + "/auth/v1/token"):
            return resp(200, session("tok-ana")) if json["refresh_token"] == "ref-ok" else resp(400, {"msg": "Invalid Refresh Token"})
        if url == SB + "/rest/v1/rpc/mark_slot_done":
            if self.rpc_missing:
                return resp(404, {"message": "Could not find the function"})
            me = self.me(headers)
            self.rpc.append(json)
            s = next((s for s in self.slots if s["id"] == json["p_slot"]), None)
            if s and me and s["inspector_id"] == me["id"] and s["status"] == "booked" and s["booked_at"] == json["p_booked_at"]:
                s["status"] = "done"
                return resp(200, "done")
            return resp(200, "skipped")
        raise AssertionError(f"unexpected POST {url}")


def pdf_bytes():
    import pypdfium2
    pdf = pypdfium2.PdfDocument.new()
    pdf.new_page(300, 200)
    pdf.new_page(300, 200)
    buf = io.BytesIO()
    pdf.save(buf)
    return buf.getvalue()


def resp(status, body):
    return httpx.Response(status, json=body, request=httpx.Request("GET", "https://x.test"))


def session(token):
    return {"access_token": token, "refresh_token": "ref-2", "expires_in": 3600, "expires_at": 1893456000, "token_type": "bearer"}


@pytest.fixture
def world(monkeypatch):
    w = World(main._la_today())
    monkeypatch.setattr(httpx, "get", w.get)
    monkeypatch.setattr(httpx, "post", w.post)
    for k, v in {"SUPABASE_URL": SB, "SUPABASE_ANON_KEY": "anon", "SCHEDULER_URL": SCHED, "BIDBUS_API_URL": BB,
                 "BIDBUS_ADMIN_TOKEN": "bb-1"}.items():
        monkeypatch.setattr(config, k, v)
    team._cache.clear()
    bidbus._vehicles.clear()
    bidbus._vins.clear()
    main._decoded.clear()
    return w


ANA_H, BO_H = {"Authorization": "Bearer tok-ana"}, {"Authorization": "Bearer tok-bo"}


# ---- sign-in ----

def test_passcode_mode_is_unchanged(client):
    assert client.get("/api/health").json() == {"ok": True}
    assert client.post("/api/auth/code", json={"email": "ana@bidbus.com"}).status_code == 404
    assert client.get("/api/appointments", headers=PASS).status_code == 404


def test_api_needs_a_scheduler_sign_in(client, world):
    assert client.get("/api/health").json() == {"ok": True, "auth": "team"}
    assert client.get("/api/health", headers=ANA_H).json() == {"ok": True, "auth": "team", "signed_in": True}
    assert client.get("/api/health", headers={"Authorization": "Bearer nope"}).json()["signed_in"] is False
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/me", headers=PASS).status_code == 404  # the passcode is no inspector: no booked jobs
    assert client.get("/api/health", headers=PASS).json() == {"ok": True, "auth": "team", "passcode_ok": True}
    assert client.get("/api/me", headers={"Authorization": "Bearer nope"}).status_code == 401
    r = client.get("/api/me", headers={"Authorization": "Bearer tok-new"})  # signed in, not linked to the team list yet
    assert r.status_code == 403 and "scheduler site" in r.json()["detail"]
    assert client.get("/api/me", headers=ANA_H).json() == {"id": ANA, "name": "Ana Inspector", "email": "ana@bidbus.com"}


def test_a_caller_who_is_not_an_inspector_is_refused(client, world):
    world.members[1]["is_inspector"] = False
    assert client.get("/api/me", headers=BO_H).status_code == 403


def test_a_removed_member_is_blocked(client, world):
    assert client.get("/api/me", headers=BO_H).status_code == 200
    world.members[1]["active"] = False
    team._cache.clear()  # the lookup is kept a minute
    assert client.get("/api/me", headers=BO_H).status_code == 403


def test_sign_in_with_an_emailed_code(client, world):
    r = client.post("/api/auth/code", json={"email": "someone@gmail.com"})
    assert r.status_code == 403 and "team list" in r.json()["detail"]
    assert ("POST", SB + "/auth/v1/otp") not in world.calls
    assert client.post("/api/auth/code", json={"email": "not an email"}).status_code == 400
    assert client.post("/api/auth/code", json={"email": " Ana@Bidbus.com "}).json() == {"sent": True}
    assert client.post("/api/auth/verify", json={"email": "ana@bidbus.com", "code": "654321"}).status_code == 401
    r = client.post("/api/auth/verify", json={"email": "ana@bidbus.com", "code": "123 456"})
    assert r.status_code == 200
    assert r.json() == {"access_token": "tok-ana", "refresh_token": "ref-2", "expires_at": 1893456000,
                        "member": {"id": ANA, "name": "Ana Inspector", "email": "ana@bidbus.com"}}
    assert client.post("/api/auth/refresh", json={"refresh_token": "ref-ok"}).json()["access_token"] == "tok-ana"
    assert client.post("/api/auth/refresh", json={"refresh_token": "old"}).status_code == 401


# ---- appointments ----

def test_appointments_are_the_inspectors_own_for_the_next_week(client, world):
    r = client.get("/api/appointments", headers=ANA_H).json()
    assert r["today"] == main._la_today().isoformat()
    assert [a["slot_id"] for a in r["appointments"]] == [S2, S1]  # by time; Bo's job and the one in 9 days are not there
    a = r["appointments"][1]
    assert a["key"] == f"{S1}@{BOOKED}" and a["vehicle_id"] == "412345" and a["seller_phone"] == "(650) 555-0142"
    assert a["address"] == "4321 Overland Ave" and a["start_time"] == "10:00" and a["notes"] == "Gate code 1234"
    assert [a["slot_id"] for a in client.get("/api/appointments", headers=BO_H).json()["appointments"]] == [S3]


def test_the_car_brief_from_bidbus(client, world):
    r = client.get(f"/api/appointments/{S1}/brief", headers=ANA_H)
    assert r.status_code == 200
    b = r.json()
    assert b["bidbus"] == "ok" and b["fuel"] == "Gas" and b["vin_differs"] is False and b["appointment"]["slot_id"] == S1
    v = b["vehicle"]
    assert v["vehicle_id"] == 412345
    assert v["car"] == {"year": 2020, "make": "BMW", "model": "X3", "series": "xDrive30i", "trim": "xDrive30i Sport Utility 4D", "vin": "5UXTY5C00L9B00230",
                        "mileage": 61240, "color": "Black", "zip": "94010"}
    assert v["owner"] == {"name": "Daniel Kim", "registered": "Daniel Kim"}
    assert v["documents"] == [{"type": "driver_license", "label": "Driver's license", "document_id": "9001", "content_type": "image/jpeg",
                               "uploaded_at": "2026-11-10T07:58:00Z"}]
    assert (v["documents_uploaded"], v["documents_required"]) == (1, 2)
    assert v["carfax"]["owners"] == "4" and v["carfax"]["accident"] is True and v["carfax"]["accident_detail"] == ["Minor Damage"]
    assert v["carfax"]["last_odometer"] == "60,102 mi" and v["carfax"]["report_url"] == "https://carfax.test/r/1"
    assert [c["text"] for c in v["checks"]] == ["Carfax: Minor Damage", "Carfax: open recall", "Seller: transmission issue",
                                                "Seller: check engine light on", "Bidbus risk medium: New seller account"]
    assert [p["label"] for p in v["photos"]] == ["front left", "dents rear door"]
    assert not any(url.endswith("/sessions") for _, url in world.calls)  # the admin token as given, no sign-in


def test_owner_count_without_a_history_line_and_no_carfax(client, world):
    cf = world.vehicles["412345"]["vauto_data"]["carfax"]
    cf.pop("history_overview")
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]["carfax"]["owners"] == "3+"
    bidbus._vehicles.clear()
    world.vehicles["412345"]["vauto_data"] = {"carfax": {}}  # some vehicles have an empty Carfax
    v = client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]
    assert v["carfax"] is None and not any(c["text"].startswith("Carfax") for c in v["checks"])


def test_a_token_no_longer_accepted_is_an_error(client, world):
    client.get(f"/api/appointments/{S1}/brief", headers=ANA_H)
    bidbus._vehicles.clear()
    bidbus._vins.clear()
    world.bb_token = "bb-2"  # the admin signed out of that session: its token is revoked
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "error"  # the app keeps its last brief
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 502


def test_the_token_as_copied_from_the_admin_site(client, world, monkeypatch):
    monkeypatch.setattr(config, "BIDBUS_ADMIN_TOKEN", ' "bb-1"\n')  # local storage keeps it in quotes
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "ok"


@pytest.mark.parametrize("answer", [resp(500, {"error": "x"}), httpx.Response(200, content=b"<html>", request=httpx.Request("GET", "https://x.test"))])
def test_a_failed_vin_search_is_an_error_not_a_missing_car(client, world, monkeypatch, answer):
    get = world.get
    monkeypatch.setattr(httpx, "get", lambda url, **kw: answer if url == BB + "/api/admin/vehicles" else get(url, **kw))
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "error"  # the app keeps its last brief
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 502


def test_brief_without_a_bidbus_vehicle(client, world, monkeypatch):
    b = client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()  # a VIN Bidbus does not have
    assert b["vehicle"] is None and b["bidbus"] == "not_found" and b["appointment"]["vin"] == "1HGCM82633A004352" and b["fuel"] == "Gas"
    assert b["decoded"] == {"year": 2003, "make": "HONDA", "model": "Accord", "trim": "EX"}  # the car without New inspection
    world.slots[1]["vin"] = None  # no VIN on the booking: nothing to look up
    assert client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()["bidbus"] == "not_found"
    assert world.searches == ["1HGCM82633A004352"]
    monkeypatch.setattr(config, "BIDBUS_ADMIN_TOKEN", " ")  # no Bidbus token on the server
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "none"


def test_brief_for_another_vin_and_unknown_fuel(client, world, monkeypatch):
    world.slots[0]["vin"] = "5UXTY5C00L9B00231"
    get = world.get
    monkeypatch.setattr(httpx, "get", lambda url, **kw: resp(200, {"Results": [{"FuelTypePrimary": "", "ElectrificationLevel": ""}]})
                        if "vpic" in url else get(url, **kw))
    b = client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()
    # the Listing ID's car has another VIN: not the booked car, no Bidbus data
    assert b["vin_differs"] is False and b["vehicle"] is None and b["bidbus"] == "not_found" and b["fuel"] is None  # vPIC did not know: no Gas guess
    assert b["decoded"] == {"year": None, "make": None, "model": None, "trim": None}
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 404
    assert not any(url.startswith(BB + "/api/admin/vehicles/") for _, url in world.calls)


def test_the_car_is_found_by_the_booking_vin_alone(client, world):
    world.slots[0]["listing_id"] = None
    b = client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()
    assert b["bidbus"] == "ok" and b["vehicle"]["vehicle_id"] == 412345
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 200
    world.slots[0]["listing_id"] = "999"  # a Listing ID that is not a car with this VIN changes nothing
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]["vehicle_id"] == 412345
    assert world.searches == [VIN]  # a match is kept 5 minutes
    assert not any(url.endswith("/vehicles/999") for _, url in world.calls)


def test_the_newest_car_with_the_vin_unless_the_listing_id_names_another(client, world):
    old = vehicle_json(400001)
    old["created_at"], old["required_documents"] = "2026-01-05T00:00:00Z", []  # an earlier Bidbus car with the same VIN
    world.vehicles["400001"] = old
    world.vehicles["412345"]["created_at"] = "2026-11-01T00:00:00Z"
    world.slots[0]["listing_id"] = None
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]["vehicle_id"] == 412345
    world.slots[0]["listing_id"] = "400001"
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]["vehicle_id"] == 400001
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 404  # not that car's document


def test_a_vin_typed_with_o_for_zero_finds_the_car(client, world):
    world.slots[0].update(vin="5uxty5cOOL9BOO230", listing_id=None)  # O for 0: Bidbus stores it as 0
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "ok"
    assert world.searches == [VIN]


def test_a_car_added_to_bidbus_later_is_found_at_once(client, world):
    assert client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()["bidbus"] == "not_found"
    honda = vehicle_json(500001)
    honda["vin"] = "1HGCM82633A004352"
    world.vehicles["500001"] = honda
    assert client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()["vehicle"]["vehicle_id"] == 500001


def test_a_listing_id_typed_onto_a_booking_does_not_open_another_sellers_car(client, world):
    # the inspector can edit the Listing ID on their own booking: with no VIN, or another VIN, nothing of that car is shown
    world.slots[1]["listing_id"] = "412345"  # S2: a Honda booking
    b = client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()
    assert b["vehicle"] is None and b["bidbus"] == "not_found"
    assert client.get(f"/api/appointments/{S2}/documents/9001", headers=ANA_H).status_code == 404
    world.slots[1]["vin"] = None
    b = client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()
    assert b["vehicle"] is None and b["bidbus"] == "not_found"  # the app then keeps no vehicle ID for the inspection
    assert client.get(f"/api/appointments/{S2}/documents/9001", headers=ANA_H).status_code == 404
    world.slots[1]["vin"] = " 5uxty5c00l9b00230"  # the same VIN, typed loosely
    assert client.get(f"/api/appointments/{S2}/brief", headers=ANA_H).json()["bidbus"] == "ok"


def test_no_car_without_a_booking_vin(client, world):
    world.vehicles["412345"]["vin"] = None  # a Bidbus car with no VIN yet, and a booking with none: not a match
    world.slots[0]["vin"] = None
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"] is None
    assert client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H).status_code == 404
    bidbus._vehicles.clear()
    world.vehicles["412345"]["vin"] = VIN
    world.slots[0]["vin"] = VIN
    world.slots[0]["listing_id"] = "../users/1"  # never sent to Bidbus: the car is found by its VIN
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "ok"
    assert not any("users" in url for _, url in world.calls)


def test_carfax_accident_count_above_one(client, world):
    cf = world.vehicles["412345"]["vauto_data"]["carfax"]
    cf.update({"accidentCount": 2, "hasAccidentIndicators": False, "damage_showcase": []})
    v = client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["vehicle"]
    assert v["carfax"]["accident"] is True and "Carfax: accident or damage" in [c["text"] for c in v["checks"]]


def test_a_pdf_document_comes_as_one_jpeg(client, world):
    world.doc_pdf = True
    r = client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H)
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg" and r.content[:3] == b"\xff\xd8\xff"
    from PIL import Image
    im = Image.open(io.BytesIO(r.content))
    assert im.size == (600, 800)  # both pages, one under the other


def test_a_huge_pdf_page_is_made_smaller(monkeypatch):
    import pypdfium2
    from PIL import Image
    pdf = pypdfium2.PdfDocument.new()
    pdf.new_page(4032, 3024)  # a phone photo saved as a PDF at 72 dpi
    buf = io.BytesIO()
    pdf.save(buf)
    im = Image.open(io.BytesIO(bidbus._pdf_jpeg(buf.getvalue())))
    assert im.size == (1600, 1200)


def test_bidbus_not_reached_is_an_error(client, world, monkeypatch):
    get = world.get
    monkeypatch.setattr(httpx, "get", lambda url, **kw: (_ for _ in ()).throw(httpx.ConnectError("down")) if url.startswith(BB) else get(url, **kw))
    assert client.get(f"/api/appointments/{S1}/brief", headers=ANA_H).json()["bidbus"] == "error"


def test_health_with_the_scheduler_down_is_not_signed_out(client, world):
    world.sb_down = True
    h = client.get("/api/health", headers={"Authorization": "Bearer tok-bo"}).json()
    assert h["auth"] == "team" and h["ok"] is False and "signed_in" not in h
    world.sb_down = False
    assert client.get("/api/health", headers={"Authorization": "Bearer tok-gone"}).json()["signed_in"] is False


def test_brief_is_only_for_the_inspectors_own_job(client, world):
    assert client.get(f"/api/appointments/{S3}/brief", headers=ANA_H).status_code == 404
    assert client.get(f"/api/appointments/{S3}/brief", headers=BO_H).status_code == 200


def test_seller_documents_only_through_the_signed_in_app(client, world):
    r = client.get(f"/api/appointments/{S1}/documents/9001", headers=ANA_H)
    assert r.status_code == 200 and r.content == b"JPEGDATA" and r.headers["content-type"] == "image/jpeg"
    assert r.headers["cache-control"] == "private, no-store"
    assert client.get(f"/api/appointments/{S1}/documents/9002", headers=ANA_H).status_code == 404  # not this car's
    assert client.get(f"/api/appointments/{S3}/documents/9001", headers=ANA_H).status_code == 404  # not her job
    assert client.get(f"/api/appointments/{S1}/documents/9001").status_code == 401


# ---- inspections: owner and closing the scheduler job ----

def put(client, iid, headers, appointment=None):
    return client.put(f"/api/inspections/{iid}", headers=headers, json={
        "report_email": "tom@example.com", "inspector": "Typed name", "car": CARS["bmw-x3"], "record": sample("bmw-x3"),
        **({"appointment": appointment} if appointment else {})})


def test_an_inspection_is_its_inspectors_only(client, world):
    iid = str(uuid.uuid4())
    assert put(client, iid, ANA_H).status_code == 200
    assert client.get(f"/api/inspections/{iid}", headers=ANA_H).status_code == 200
    assert client.get(f"/api/inspections/{iid}", headers=BO_H).status_code == 404
    assert put(client, iid, BO_H).status_code == 404
    assert client.put(f"/api/inspections/{iid}/files/signature.png", headers=BO_H, content=b"x").status_code == 404
    assert client.post(f"/api/inspections/{iid}/complete", headers=BO_H).status_code == 404
    with SessionLocal() as s:
        assert s.get(Inspection, iid).inspector == "Ana Inspector"  # the team-list name, not the typed one


def test_the_passcode_makes_its_own_inspections(client, world):
    # a phone not signed in to the scheduler: New inspection works with the app passcode, with the typed name
    iid, ana = str(uuid.uuid4()), str(uuid.uuid4())
    assert put(client, iid, PASS).status_code == 200
    assert client.get(f"/api/inspections/{iid}", headers=PASS).status_code == 200
    with SessionLocal() as s:
        assert s.get(Inspection, iid).member_id is None and s.get(Inspection, iid).inspector == "Typed name"
    assert put(client, ana, ANA_H).status_code == 200
    assert client.get(f"/api/inspections/{ana}", headers=PASS).status_code == 404  # a signed-in inspector's stays theirs
    assert put(client, ana, PASS).status_code == 404
    assert client.get("/api/appointments", headers=PASS).status_code == 404


def test_an_inspection_from_before_sign_in_is_claimed(client, world):
    iid = str(uuid.uuid4())
    with SessionLocal() as s:
        s.add(Inspection(id=iid, status="receiving"))
        s.commit()
    assert put(client, iid, BO_H).status_code == 200
    assert client.get(f"/api/inspections/{iid}", headers=ANA_H).status_code == 404


def sent(iid, ago=timedelta(0)):
    with SessionLocal() as s:
        i = s.get(Inspection, iid)
        i.status, i.report_sent_at = "sent", datetime.now(timezone.utc) - ago
        s.commit()


def test_the_scheduler_job_is_marked_done_after_the_report_is_sent(client, world):
    iid = str(uuid.uuid4())
    put(client, iid, ANA_H, {"slot_id": S1, "booked_at": BOOKED, "vehicle_id": 412345})
    with SessionLocal() as s:
        i = s.get(Inspection, iid)
        assert (i.member_id, i.slot_id, i.booked_at, i.vehicle_id) == (ANA, S1, BOOKED, "412345")
    client.get(f"/api/inspections/{iid}", headers=ANA_H)
    assert world.rpc == []  # not before the report is sent
    sent(iid)
    client.get(f"/api/inspections/{iid}", headers=ANA_H)
    assert world.rpc == [{"p_slot": S1, "p_booked_at": BOOKED}] and world.slots[0]["status"] == "done"
    client.get(f"/api/inspections/{iid}", headers=ANA_H)
    client.get("/api/appointments", headers=ANA_H)
    assert len(world.rpc) == 1  # once
    done = client.get("/api/appointments", headers=ANA_H).json()["appointments"][1]
    assert done["slot_id"] == S1 and done["status"] == "done"


def test_marking_done_is_tried_again_until_the_scheduler_has_it(client, world):
    iid = str(uuid.uuid4())
    put(client, iid, ANA_H, {"slot_id": S1, "booked_at": BOOKED, "vehicle_id": "412345"})
    sent(iid)
    world.rpc_missing = True  # scheduler migration 0006 not run yet
    client.get(f"/api/inspections/{iid}", headers=ANA_H)
    with SessionLocal() as s:
        assert s.get(Inspection, iid).slot_done_at is None
    world.rpc_missing = False
    client.get("/api/appointments", headers=ANA_H)
    assert world.slots[0]["status"] == "done"
    with SessionLocal() as s:
        assert s.get(Inspection, iid).slot_done_at is not None


def test_a_rebooked_hour_is_not_marked_done(client, world):
    iid = str(uuid.uuid4())
    put(client, iid, ANA_H, {"slot_id": S1, "booked_at": BOOKED})
    world.slots[0]["booked_at"] = "2026-11-11T01:00:00+00:00"  # cancelled and booked again for another car
    sent(iid)
    client.get(f"/api/inspections/{iid}", headers=ANA_H)
    assert world.slots[0]["status"] == "booked" and len(world.rpc) == 1
    with SessionLocal() as s:
        assert s.get(Inspection, iid).slot_done_at is not None  # nothing left to do for it


def test_marking_done_stops_after_two_days(client, world):
    iid = str(uuid.uuid4())
    put(client, iid, ANA_H, {"slot_id": S1, "booked_at": BOOKED})
    sent(iid, ago=timedelta(days=3))
    client.get("/api/appointments", headers=ANA_H)
    assert world.rpc == []
