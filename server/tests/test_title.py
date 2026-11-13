import copy
import re

from conftest import sample
from test_reports import make

from app import title
from app.cr import build_cr
from app.db import Inspection, SessionLocal

CLEAN = {
    "vin": "5UXTY5C00L9B00230", "title_status": "title", "loan_info": {},
    "vauto_data": {
        "carfax": {"hasReport": True, "hasCleanTitle": True, "hasTotalLoss": False, "hasOdometerRollback": False,
                   "damage_showcase": [{"name": "noAccident"}], "history": [{"owner_type": "personal", "events": ["title_issued_or_updated"]}]},
        "autocheck": {"title_brand": {"label": "Clean"}, "insurance_loss": {"label": "No Issue"}, "odometer": {"status": "pass"}, "usage": "Personal"},
    },
    "ocr_data": {"title": {"success": True, "data": {"vin": "5UXTY5C00L9B00230", "brand": None, "lienholder": None, "odometer": 61000}}},
    "risk": {"reasons": []},
}


def names(out):
    return {i["name"]: i for i in out["items"]}


def test_clean_car_lists_every_item_it_can_look_up_with_no_record():
    rec = sample("bmw-x3")
    out = title.check(CLEAN, rec, [])
    got = names(out)
    assert out["status"] == "Title Present"
    assert list(got) == ["Branded Title", "Total Loss", "True Mileage Unknown/Not Actual Miles", "Possible Flood Damage", "Fire Damage",
                         "Stolen Vehicle/Theft Recovery (Including History)", "Taxis, Livery, State, or Law Enforcement Vehicle",
                         "Rental Vehicle", "Lien on Title", "Title Washing", "Title VIN Mismatch"]
    assert all(not i["issues"] for i in got.values())
    assert got["Branded Title"]["sources"] == ["Carfax", "AutoCheck", "Title"]
    for missing in ("Previous Canadian", "Grey Market Vehicle", "Sold on Bill of Sale"):
        assert missing not in got


def test_without_a_bidbus_car_only_what_the_inspection_checks():
    out = title.check(None, sample("bmw-x3"), [{"option": "Flood signs"}])
    assert out["status"] is None
    assert [(i["name"], i["sources"]) for i in out["items"]] == [("Possible Flood Damage", ["Inspection"]), ("Fire Damage", ["Inspection"])]
    assert out["items"][0]["issues"] == [{"text": "Possible Flood Damage", "sub": "Inspection", "level": "Red"}]


def test_problems_in_acv_wording_with_their_source():
    v = copy.deepcopy(CLEAN)
    v["vauto_data"]["carfax"].update(hasCleanTitle=False, hasOdometerRollback=True)
    v["vauto_data"]["carfax"]["history"].append({"owner_type": "rental", "events": ["registered_as_rental", "mileage_inconsistency"]})
    v["vauto_data"]["autocheck"].update(title_brand={"label": "Title Brand Reported"}, theft_reported=True, usage="Fleet, Taxi",
                                        insurance_loss={"label": "Insurance Loss Reported"})
    v["ocr_data"]["title"]["data"].update(brand="Salvage", lienholder="Ally Bank", odometer=90000, vin="5UXTY5C00L9B00231")
    v["risk"]["reasons"] = [{"code": "title_washing"}]
    got = names(title.check(v, sample("bmw-x3"), []))
    assert [(x["text"], x["sub"]) for x in got["Branded Title"]["issues"]] == [("Branded Title: Salvage", "Title"), ("Branded Title", "Carfax, AutoCheck")]
    odo = [(x["text"], x["level"]) for x in got["True Mileage Unknown/Not Actual Miles"]["issues"]]
    assert ("True Mileage Unknown/Not Actual Miles", "Red") in odo and ("Mileage Inconsistency", "Yellow") in odo
    assert any("90,000 mi" in x["sub"] for x in got["True Mileage Unknown/Not Actual Miles"]["issues"])
    assert got["Total Loss"]["issues"][0]["sub"] == "AutoCheck: insurance loss"
    assert got["Stolen Vehicle/Theft Recovery (Including History)"]["issues"][0]["sub"] == "AutoCheck"
    assert got["Taxis, Livery, State, or Law Enforcement Vehicle"]["issues"][0]["sub"] == "AutoCheck: Taxi"
    assert [x["sub"] for x in got["Rental Vehicle"]["issues"]] == ["Carfax"]
    assert got["Lien on Title"]["issues"][0]["sub"] == "Title: Ally Bank"
    assert got["Title Washing"]["issues"][0]["level"] == "Yellow"
    assert got["Title VIN Mismatch"]["issues"][0]["level"] == "Red"


def test_loan_car_status_names_the_lender_and_has_no_lien_item():
    v = copy.deepcopy(CLEAN)
    v.update(title_status="loan", loan_info={"lien_holder_name": "Toyota Financial"})
    out = title.check(v, sample("bmw-x3"), [])
    assert out["status"] == "Title Absent: loan, Toyota Financial"
    assert "Lien on Title" not in names(out)


def test_no_reports_leave_their_items_out():
    v = {"title_status": "title", "vauto_data": {"carfax": {"hasReport": False}, "autocheck": {}}}
    assert [i["name"] for i in title.check(v, sample("bmw-x3"), [])["items"]] == ["Possible Flood Damage", "Fire Damage"]


def test_dealer_page_shows_the_title_check_and_the_seller_page_does_not(client):
    token, iid = make("bmw-x3")
    v = copy.deepcopy(CLEAN)
    v["vauto_data"]["autocheck"]["theft_reported"] = True
    with SessionLocal() as s:
        insp = s.get(Inspection, iid)
        cr = build_cr(sample("bmw-x3"))
        cr["title"] = title.check(v, insp.record, cr["condition_report"]["issues"])
        insp.cr = cr
        s.commit()
    html = client.get(f"/r/{token}/dealer").text
    sec = html[html.index('id="d-title"'):html.index('id="d-specs"')]
    assert '<a href="#d-title">Title</a>' in html and "<h2>Title Check</h2>" in sec and "Title Present" in sec
    assert "No record · Carfax, AutoCheck, Title" in sec
    assert re.search(r"Stolen Vehicle/Theft Recovery \(Including History\) <em class=\"lvt sev\">Red</em><small>AutoCheck</small>", sec)
    assert "registration" not in html.lower() and "Title Check" not in client.get(f"/r/{token}/seller").text


def test_a_report_built_before_the_title_check_has_no_title_section(client):
    token, _ = make("bmw-x3")
    html = client.get(f"/r/{token}/dealer").text
    assert 'id="d-title"' not in html and "#d-title" not in html


def test_build_takes_the_bidbus_car_by_appointment_or_vin(monkeypatch):
    from app import bidbus, main
    monkeypatch.setattr(bidbus, "enabled", lambda: True)
    monkeypatch.setattr(bidbus, "vehicle_ids", lambda vin: ["7"] if vin == CLEAN["vin"] else [])
    monkeypatch.setattr(bidbus, "vehicle", lambda vid: dict(CLEAN, id=vid))
    rec = sample("bmw-x3")
    assert main._title_car(Inspection(id="a", record=rec, vehicle_id=None))["id"] == "7"
    assert main._title_car(Inspection(id="b", record=rec, vehicle_id="9"))["id"] == "9"
    other = copy.deepcopy(rec)
    other["vehicle"].update(vin_read="1HGCM82633A004352", vin_listing="1HGCM82633A004352")
    assert main._title_car(Inspection(id="c", record=other, vehicle_id="9")) is None  # a car with another VIN is not used

    def down(_vid):
        raise bidbus.BidbusError("down")
    monkeypatch.setattr(bidbus, "vehicle", down)
    assert main._title_car(Inspection(id="d", record=rec, vehicle_id="9")) is None
