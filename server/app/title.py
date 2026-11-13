"""The Title check on the dealer report: the title and history items of the ACV condition report that Bidbus can look up for the car,
from the Carfax and AutoCheck reports Bidbus pulls through vAuto (vehicle.vauto_data), the seller's title photo as Bidbus reads it
(vehicle.ocr_data), the Bidbus risk rules and the inspection itself. An item is in the check only when at least one of its sources is
there for the car; an item nothing can look up (Previous Canadian, Grey Market Vehicle, Sold on Bill of Sale, ...) is left out."""
import re

RED, YELLOW, NOTED = "Red", "Yellow", None  # levels as the report tags them (reports.LEVEL keys)
POLICE_TAXI = ("Taxi", "Police", "Government")


def _num(v) -> int | None:
    if isinstance(v, (int, float)):
        return int(v)
    d = re.sub(r"[^\d]", "", str(v or ""))
    return int(d) if d else None


def _vin(v) -> str:
    return re.sub(r"\s+", "", str(v or "")).upper().translate(str.maketrans("IOQ", "100"))


def _ocr(v: dict, kind: str) -> dict | None:
    r = ((v.get("ocr_data") or {}).get(kind)) or {}
    return r["data"] if r.get("success") and isinstance(r.get("data"), dict) and r["data"] else None


def _events(cf: dict) -> set[str]:
    return {e for r in cf.get("history") or [] if isinstance(r, dict) for e in r.get("events") or [] if isinstance(e, str)}


def _showcase(cf: dict) -> list[str]:
    return [str(x.get("name") or "") for x in cf.get("damage_showcase") or [] if isinstance(x, dict)]


def _found(issues: list[dict], word: str) -> bool:
    return any(word in (i.get("option") or "") or word in (i.get("type") or "") for i in issues)


def check(v: dict | None, rec: dict, issues: list[dict]) -> dict:
    """{"status": the title status line or None, "items": [{"name", "sources", "issues": [{"text", "sub", "level"}]}]};
    v is the Bidbus admin vehicle JSON (None without one), issues the CR's issues"""
    v = v or {}
    car = rec.get("vehicle") or {}
    cf = (v.get("vauto_data") or {}).get("carfax") or {}
    cf = cf if cf.get("hasReport") is True else {}
    ac = (v.get("vauto_data") or {}).get("autocheck") or {}
    ac = ac if (ac.get("title_brand") or {}).get("label") else {}
    title = _ocr(v, "title")
    risk = {r.get("code") for r in (v.get("risk") or {}).get("reasons") or [] if isinstance(r, dict)}
    showcase, events = _showcase(cf), _events(cf)
    items = []

    def item(name: str, sources: list[tuple[str, bool]], found: list[tuple[str, str, str | None]]):
        got = [s for s, there in sources if there]
        if got:
            merged: dict[tuple, list[str]] = {}  # one line for the same finding from several sources
            for t, sub, lv in found:
                merged.setdefault((t, lv), []).append(sub)
            items.append({"name": name, "sources": got, "issues": [{"text": t, "sub": ", ".join(subs), "level": lv}
                                                                   for (t, lv), subs in merged.items()]})

    found = []
    if title and str(title.get("brand") or "").strip():
        found.append((f"Branded Title: {str(title['brand']).strip()}", "Title", RED))
    if cf.get("hasCleanTitle") is False:
        found.append(("Branded Title", "Carfax", RED))
    if ac and ac["title_brand"]["label"] != "Clean":
        found.append(("Branded Title", "AutoCheck", RED))
    item("Branded Title", [("Carfax", bool(cf)), ("AutoCheck", bool(ac)), ("Title", bool(title))], found)

    found = []
    if cf.get("hasTotalLoss") is True or "totalLoss" in showcase:
        found.append(("Total Loss", "Carfax", RED))
    if (ac.get("insurance_loss") or {}).get("label") == "Insurance Loss Reported":
        found.append(("Total Loss", "AutoCheck: insurance loss", RED))
    item("Total Loss", [("Carfax", bool(cf)), ("AutoCheck", bool(ac))], found)

    found, miles, title_miles = [], _num(car.get("mileage_read")), _num((title or {}).get("odometer"))
    if cf.get("hasOdometerRollback") is True:
        found.append(("True Mileage Unknown/Not Actual Miles", "Carfax: odometer rollback", RED))
    if (ac.get("odometer") or {}).get("status") == "fail":
        found.append(("True Mileage Unknown/Not Actual Miles", "AutoCheck: odometer rollback", RED))
    both = miles is not None and title_miles is not None
    if both and title_miles > miles:
        found.append(("True Mileage Unknown/Not Actual Miles", f"Title: {title_miles:,} mi, odometer {miles:,} mi", RED))
    if "mileage_inconsistency" in events:
        found.append(("Mileage Inconsistency", "Carfax", YELLOW))
    if (ac.get("odometer") or {}).get("status") == "warning":
        found.append(("Mileage Inconsistency", "AutoCheck", YELLOW))
    item("True Mileage Unknown/Not Actual Miles", [("Carfax", bool(cf)), ("AutoCheck", bool(ac)), ("Title", both)], found)

    found = [("Possible Flood Damage", s, RED) for s, hit in (("Carfax", any(re.search("flood", n, re.I) for n in showcase)),
                                                              ("Inspection", _found(issues, "Flood signs"))) if hit]
    item("Possible Flood Damage", [("Carfax", bool(cf)), ("Inspection", True)], found)
    found = [("Fire Damage", s, RED) for s, hit in (("Carfax", any(re.search("fire", n, re.I) for n in showcase)),
                                                    ("Inspection", _found(issues, "Fire signs"))) if hit]
    item("Fire Damage", [("Carfax", bool(cf)), ("Inspection", True)], found)

    found = []
    if any(re.search(r"stolen|theft", n, re.I) for n in showcase):
        found.append(("Stolen Vehicle/Theft Recovery (Including History)", "Carfax", RED))
    if ac.get("theft_reported") is True:
        found.append(("Stolen Vehicle/Theft Recovery (Including History)", "AutoCheck", RED))
    item("Stolen Vehicle/Theft Recovery (Including History)", [("Carfax", bool(cf)), ("AutoCheck", bool(ac))], found)

    used = [u for u in POLICE_TAXI if u in str(ac.get("usage") or "")]
    item("Taxis, Livery, State, or Law Enforcement Vehicle", [("AutoCheck", bool(ac))],
         [("Taxis, Livery, State, or Law Enforcement Vehicle", "AutoCheck: " + ", ".join(used), NOTED)] if used else [])

    found = []
    if "registered_as_rental" in events or any(isinstance(r, dict) and r.get("owner_type") == "rental" for r in cf.get("history") or []):
        found.append(("Rental Vehicle", "Carfax", NOTED))
    if "Rental" in str(ac.get("usage") or ""):
        found.append(("Rental Vehicle", "AutoCheck", NOTED))
    item("Rental Vehicle", [("Carfax", bool(cf)), ("AutoCheck", bool(ac))], found)

    # a lien still on the title of a car the seller says is paid off (a loan or lease car's lender is in the status line)
    if v.get("title_status") == "title" and title:
        holder = str(title.get("lienholder") or "").strip()
        item("Lien on Title", [("Title", True)], [("Lien on Title", f"Title: {holder}", RED)] if holder else [])
    item("Title Washing", [("Carfax", bool(cf))], [("Title Washing", "Carfax: re-titled in another state with an open lien", YELLOW)]
         if "title_washing" in risk else [])

    vin, tvin = _vin(car.get("vin_read") or car.get("vin_listing")), _vin((title or {}).get("vin"))
    if len(vin) == 17 and len(tvin) == 17:
        item("Title VIN Mismatch", [("Title", True)], [] if tvin == vin else [("Title VIN Mismatch", f"Title: {tvin}", RED)])

    status = {"title": "Title Present", "loan": "Title Absent: loan", "lease": "Title Absent: lease"}.get(v.get("title_status"))
    lender = str((v.get("loan_info") or {}).get("lien_holder_name") or "").strip()
    if status and v.get("title_status") != "title" and lender:
        status += f", {lender}"
    return {"status": status, "items": items}
