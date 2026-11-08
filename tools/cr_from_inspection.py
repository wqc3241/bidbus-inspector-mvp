"""Bidbus CR from one inspector app record.

    python3 -I tools/cr_from_inspection.py samples/inspection-bmw-x3.json samples/cr-bmw-x3.json [carfax_owner_count]

Input: the record the inspector app sends when the seller signs (samples/inspection-*.json, made by
inspectionPayload() in the app). Lists: data/issue-catalog.json (made by verify/issue-catalog.js from the app).

Output (one JSON file):
- condition_report: the Bidbus CR store. One issue list (place, type, severity, size, level, CR row, photo),
  CR rows in dealer order, tires, paint readings, videos and 360 frames, light, seller signature.
- vehicle_patch: the seller self-inspect fields the listing already uses (vehicle_photos, damage_photos,
  modification_photos, self_inspection_data), so the listing, admin and dealer pages keep working.
- documents: private seller uploads (never shown to dealers).
- checks_for_listing_team: VIN and mileage against the listing.
- validation: every issue, answer and reading checked against the catalog. ok is false if anything is off.

Every issue carries text (and sub) in the exact words the inspector app shows: a damage photo reads
"Place: Type, Severity, N in" (the app's dmgLine), a check problem reads "Check: problem" ("Tire: ..." / "Wheel: ..." per wheel),
with the part, wheel, panel or codes as sub. The report's highlight has structural damage, number of keys, odor and mechanical.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "..", "data", "issue-catalog.json")
CAT = json.load(open(CATALOG))

CR_ROWS = ["Exterior", "Paint", "Tires", "Underbody", "Mechanicals", "Engine sound", "Interior", "OBD-II", "Additionals"]
# photo and issue categories = the sections of the question list (question-list.csv); Start photos (seller documents) are private and go on no row
SECTION_ROW = {"Exterior": "Exterior", "Paint": "Paint", "Tires": "Tires", "Interior": "Interior", "Mechanicals": "Mechanicals", "Underbody": "Underbody",
               "OBDII": "OBD-II", "Additionals": "Additionals"}
WHEEL = {"lf": "Left front", "lr": "Left rear", "rr": "Right rear", "rf": "Right front"}
SLOT_WHEEL = {"driver_front": "lf", "passenger_front": "rf", "driver_rear": "lr", "passenger_rear": "rr"}
LEVEL_RANK = {"Disclosed": 0, "Yellow": 1, "Red": 2, "Not listed until fixed": 3, "Ends the visit": 3}
LIGHT = ["Green", "Yellow", "Red", "Not listed"]
# 360 view: 36 frames cut from the walk-around (left front corner, counter-clockwise); these frames fill photo slots
SPIN_SLOTS = [(1, "front_left"), (5, "left_side"), (10, "rear_left"), (14, "rear"), (19, "rear_right"),
              (23, "right_side"), (28, "front_right"), (32, "front")]
# existing seller slots, one to one (the 12 required ones, with front_left, rear_left, rear, rear_right, front_right from the spin)
SLOT = {"ph_ext_roof": "roof", "ph_int_dash": "dashboard", "ph_int_front": "driver_seat", "ph_int_rear": "rear_seat",
        "ph_odo": "odometer", "ph_engine_bay": "engine", "ph_frunk": "engine"}
# new keys for shots the seller flow has no slot for; Underbody, OBDII and Additionals are their own photo categories
NEW_KEY = {"ph_int_screen": "infotainment", "ph_int_cargo": "cargo", "ph_vin_dash": "vin", "ph_vin_door": "vin", "ph_keys": "keys",
           "ph_engine_oil": "mechanicals", "ph_ev_port": "mechanicals", "ph_under_lf": "underbody", "ph_under_lr": "underbody",
           "ph_under_rear": "underbody", "ph_under_rr": "underbody", "ph_under_rf": "underbody", "ph_under_front": "underbody",
           "ph_under_cats": "underbody", "ph_under_pack": "underbody", "paint": "paint_meter", "tread_photo": "tread_gauge",
           "ph_obd_current": "obdii", "ph_obd_past": "obdii", "ph_obd_emission": "obdii", "ph_obd_other": "obdii",
           "ph_ev_alerts": "obdii", "ph_ev_battery": "obdii", "ph_ev_charging": "obdii"}
REQUIRED_SLOTS = ["front_left", "front_right", "rear", "rear_left", "rear_right", "roof", "driver_seat", "rear_seat", "dashboard",
                  "odometer", "engine", "tire"]
DAMAGE_TYPES = ["scratches", "dents", "paintwork", "previous_paint_work", "windshield_damage", "broken_or_missing_parts",
                "warning_lights", "wheel_damage", "additional_damage"]
OVERALL = {"Like new": "like_new", "Pretty great": "pretty_great", "Just okay": "just_okay", "Kind of rough": "kind_of_rough",
           "Major issues": "major_issues"}
VIN_MAP = {**{str(i): i for i in range(10)}, **dict(zip("ABCDEFGH", range(1, 9))), **dict(zip("JKLMN", range(1, 6))),
           "P": 7, "R": 9, **dict(zip("STUVWXYZ", range(2, 10)))}
VIN_W = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]


def dshort(place, t):
    """the app's dshort(): drop the place word the type starts with ("Seat torn" at "Front seats" stays, "Door handle broken" at "Door handle" -> "Broken")"""
    t = t or ""; p = (place or "").lower(); cands = [p, p.split(" ")[-1], p.split(" ")[0]]
    for c in cands:
        if len(c) > 2 and t.lower().startswith(c + " "):
            r = t[len(c) + 1:]
            if not re.match(r"^(or|and)\b", r): return r[:1].upper() + r[1:]
    return t


def num(x): return f"{x:g}" if isinstance(x, (int, float)) else str(x)


def plain(t): return re.sub(r"\s*\(type[^)]*\)", "", t or "")


# a paint problem picked at an Exterior panel is stored under its Paint place; the app shows the Exterior panel name
PAINT_SHOWN = {"Hood or frunk lid": "Hood"}


def vin_ok(v):
    v = (v or "").upper()
    if not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", v): return False
    s = sum(VIN_MAP[c] * w for c, w in zip(v, VIN_W)) % 11
    return v[8] == ("X" if s == 10 else str(s))


def tread_tier(t):
    if t is None: return None, None
    return ("Good", "under_10000") if t >= 9 else ("Fair", "10001_20000") if t >= 5 else ("Replace", "over_20000")


def build_cr(rec, carfax_owners=None):
    """the CR output for one record (dict in, dict out, no file IO)"""
    cat = CAT
    fuel = rec["vehicle"]["fuel"]
    ev = fuel == "Electric (EV)"
    errors = []

    def err(msg): errors.append(msg)

    def for_fuel(x): return fuel in x.get("fuels", cat["fuels"])

    checks_cat = {c["id"]: c for c in cat["checks"]}
    places_cat = {(p["section"], p["place"]): p for p in cat["places"]}
    photos = [p for p in rec["photos"] if not p.get("skipped")]

    # ---- 1. the issue list: every damage photo, then every check answer no damage photo already gives ----
    issues = []
    for d in rec["damages"]:
        n = len(issues) + 1
        pc = places_cat.get((d["section"], d["place"]))
        t = None
        if not pc: err(f"damage {d['n']}: place '{d['place']}' is not in the {d['section']} list")
        else:
            t = next((x for x in pc["types"] if x["type"] == d["type"]), None)
            if not t or not for_fuel(t): err(f"damage {d['n']}: type '{d['type']}' is not allowed at {d['section']} / {d['place']} for {fuel}"); t = t or None
            if pc.get("where") and d.get("where") and d["where"] not in pc["where"]["options"]: err(f"damage {d['n']}: where '{d['where']}' is not a {pc['where']['label']} option")
        if d["severity"] not in cat["severities"]: err(f"damage {d['n']}: severity '{d['severity']}' missing or not in {cat['severities']}")
        if d["size_in"] is not None and not (cat["size_in"]["min"] <= d["size_in"] <= cat["size_in"]["max"]): err(f"damage {d['n']}: size {d['size_in']} in is out of range")
        if not d.get("confirmed"): err(f"damage {d['n']}: not confirmed by the inspector")
        ans = (t or {}).get("answers") or {}
        if ans.get("check") and (d.get("check_id"), d.get("check_option")) != (ans["check"], ans["option"]):
            err(f"damage {d['n']}: answers {d.get('check_id')} / {d.get('check_option')}, the catalog says {ans['check']} / {ans['option']}")
        check = ans.get("check")
        row = checks_cat[check]["cr_row"] if check else SECTION_ROW[d["section"]]
        guess = d.get("ai_first_guess") or {}
        shown = PAINT_SHOWN.get(d["place"], d["place"]) if d["section"] == "Paint" else d["place"]
        ex = d.get("where") if d["section"] != "Paint" and d.get("where") and d.get("where") != d["place"] else None
        text = f"{shown}: {dshort(shown, d['type'])}" + (f" ({ex.lower()})" if ex else "") + f", {d['severity']}" + (f", {num(d['size_in'])} in" if d["size_in"] else "")
        issues.append({"id": f"I{n}", "text": text, "sub": None, "cr_row": row, "section": d["section"], "place": d["place"], "type": d["type"],
                       "severity": d["severity"], "size_in": d["size_in"], "level": (t or {}).get("level", "Disclosed"),
                       "check": check, "option": ans.get("option"), "feature": ans.get("feature"), "where": d.get("where"),
                       "wheel": (pc or {}).get("wheel"), "photo": d.get("file"), "from": "damage photo",
                       "bidbus_damage_type": (t or {}).get("bidbus_damage_type", "additional_damage"),
                       "ai_first_guess": guess or None,
                       "inspector_changed_ai": bool(guess) and (guess.get("place"), guess.get("type"), guess.get("severity")) != (d["place"], d["type"], d["severity"])})

    paint_high = [p for p in rec["paint"] if p["high"]]
    for c in rec["checks"]:
        cc = checks_cat.get(c["id"])
        if not cc: err(f"check {c['id']}: not in the catalog"); continue
        for w in c.get("where", []):
            if cc.get("where") and w not in cc["where"]["options"]: err(f"check {c['id']}: '{w}' is not a {cc['where']['label']} option")
        for pr in c.get("problems", []):
            co = next((o for o in cc["options"] if o["option"] == pr["option"]), None)
            if not co or fuel not in co["fuels"]: err(f"check {c['id']}: '{pr['option']}' is not an option for {fuel}"); continue
            if co["level"] != pr["level"]: err(f"check {c['id']}: '{pr['option']}' level {pr['level']}, the catalog says {co['level']}")
            if pr["from_damage_photo"]: continue
            head = "Tire" if c["id"] == "ck_tire" else "Wheel" if c["id"] == "ck_wheel" else cc["label"]
            base = {"text": f"{head}: {plain(pr['option'])}", "sub": None, "cr_row": cc["cr_row"], "section": cc["section"], "type": pr["option"], "severity": None, "size_in": None,
                    "level": co["level"], "check": c["id"], "option": pr["option"], "from": "check row", "photo": None}
            if c["id"] == "ck_paint" and "meter reads high" in pr["option"]:
                for p in paint_high:  # one issue per panel that reads high, with its reading
                    issues.append(dict(base, id=f"I{len(issues) + 1}", sub=PAINT_SHOWN.get(p["panel"], p["panel"]), place=p["panel"], mils=p["mils"]))
                continue
            place = ", ".join(c["where"]) if c.get("where") else WHEEL.get(c.get("wheel")) or cc["label"]
            iss = dict(base, id=f"I{len(issues) + 1}", place=place, wheel=c.get("wheel"))
            iss["sub"] = ", ".join(c["where"]) if c.get("where") else WHEEL.get(c.get("wheel"))
            if c.get("codes"): iss["codes"] = [x for x in re.split(r"[\s,;]+", c["codes"]) if x]; iss["sub"] = c["codes"]
            issues.append(iss)
    for i in issues:  # one shape for every issue
        for k in ("feature", "where", "wheel", "ai_first_guess", "sub"):
            if i.get(k) is None: i.pop(k, None)

    # ---- 2. CR rows in dealer order ----
    def row_photos(row):
        return [p["file"] for p in photos if SECTION_ROW.get(p["section"]) == row and not p.get("modification")]
    vids = {v["question_id"]: v["file"] for v in rec["videos"]}
    rows = []
    for r in CR_ROWS:
        if r == "Engine sound" and ev: continue
        ri = [i for i in issues if i["cr_row"] == r]
        e = {"row": r, "result": "Problems" if ri else "No problems", "issues": [i["id"] for i in ri], "photos": row_photos(r)}
        e["damage_photos"] = [i["photo"] for i in ri if i["photo"]]
        if r == "Exterior": e["videos"] = [vids[k] for k in ("video_360",) if k in vids]
        if r == "Engine sound": e["videos"] = [vids[k] for k in ("video_engine", "video_exhaust") if k in vids]
        rows.append(e)
    road = next((c for c in rec["checks"] if c["id"] == "ck_road"), None)

    # ---- 3. tires and paint ----
    tm = {t["wheel"]: t for t in rec["tires"]}
    if set(tm) != set(WHEEL): err(f"tires: wheels {sorted(tm)}")
    tires = []
    for w in ("lf", "lr", "rr", "rf"):
        t = tm.get(w, {})
        tr = t.get("tread_32nds")
        if tr is None or not (1 <= tr <= 14): err(f"tire {w}: tread {tr} not in 1 to 14")
        tier, code = tread_tier(tr)
        tires.append({"wheel": w, "name": WHEEL[w], "tread_32nds": tr, "tread": tier, "bidbus_tier": code, "brand": t.get("brand"),
                      "size": t.get("size"), "read_from_photo": {"tread": t.get("tread_read_from_photo"), "brand_size": t.get("read_from_photo")},
                      "issues": [i["id"] for i in issues if i.get("wheel") == w]})
    if set(p["panel"] for p in rec["paint"]) != set(cat["paint_panels"]): err("paint: panels differ from the catalog")
    for p in rec["paint"]:
        if not p["not_on_car"] and p["mils"] is None: err(f"paint {p['panel']}: no reading")
        if p["high"] != (p["mils"] is not None and p["mils"] >= cat["paint_high_mils"]): err(f"paint {p['panel']}: high flag does not match {p['mils']} mils")

    # ---- 4. light and listing ----
    worst = max([LEVEL_RANK.get(i["level"], 0) for i in issues] + [0])
    light = LIGHT[worst]
    not_listed = [f"{checks_cat[i['check']]['label']}: {i['option']}" for i in issues if i.get("check") and LEVEL_RANK.get(i["level"]) == 3]

    # ---- 5. answers and readings ----
    v = rec["vehicle"]
    if not vin_ok(v["vin_read"]): err(f"VIN read '{v['vin_read']}' fails the check digit")
    if not v["vin_mileage_confirmed"]: err("VIN and mileage not confirmed on the Summary")
    if v["mileage_read"] is None: err("no mileage read from the odometer photo")
    for k in ("sunroof", "navigation"):
        opts = {"sunroof": ["Works", "Not working", "No sunroof"], "navigation": ["Works", "Not working", "No navigation"]}[k]
        if rec["features"].get(k) not in opts: err(f"{k}: answer '{rec['features'].get(k)}' missing")
    if rec["overall_condition"] not in OVERALL: err(f"overall condition '{rec['overall_condition']}' missing")
    sig = rec["signature"]
    if not (sig["agreed"] and sig["signed"] and sig["seller_name"]): err("seller signature missing")
    for p in photos:
        if p.get("upright_turn_deg") not in (0, 90, 180, 270): err(f"photo {p['file']}: upright_turn_deg {p.get('upright_turn_deg')}")

    keys = "One key" if any(i["option"] == "Only one key" for i in issues) else "No key works" if any(i["option"] == "No key works" for i in issues) else "Two or more"
    kc = v.get("keys_count")
    if kc not in (0, 1, 2): err(f"number of keys '{kc}' missing (0, 1 or 2)")
    elif (kc == 1) != (keys == "One key"): err(f"number of keys {kc} does not match the Keys check ({keys})")
    # highlight: structural damage, number of keys, odor, mechanical
    def sec_of(i): return checks_cat[i["check"]]["section"] if i.get("check") in checks_cat else i["section"]
    st_all = [i for i in issues if i.get("check") == "ck_structure"]
    st_dmg = [i for i in st_all if "could not be photographed" not in (i.get("option") or "")]
    odor = list(dict.fromkeys(i["option"] for i in issues if i.get("check") == "ck_odor"))
    mech_i = [i["id"] for i in issues if sec_of(i) == "Mechanicals"]
    highlight = {"structural_damage": "Yes" if st_dmg else "Not checked" if st_all else "No", "structural_damage_issues": [i["id"] for i in st_dmg],
                 "keys": kc, "keys_read_from_photo": bool(v.get("keys_count_read_from_photo")),
                 "odor": odor or "OK", "mechanical": "Issue" if mech_i else "No issue", "mechanical_issues": mech_i}
    report = {
        "source": rec["source"],
        "vehicle": {"vin": v["vin_read"], "vin_matches_listing": v["vin_read"] == v["vin_listing"], "mileage": v["mileage_read"],
                    "mileage_listing": v["mileage_listing"], "fuel": fuel, "ev_battery_health_pct": v["ev_battery_health_pct"], "keys": keys, "keys_count": kc},
        "owner_check": rec["owner_check"],
        "light": light,
        "highlight": highlight,
        "not_listed_reasons": not_listed,
        "rows": rows,
        "issues": issues,
        "road_test": road["result"] if road else None,
        "tires": tires,
        "tires_match": rec["tires_match"],
        "paint": rec["paint"],
        "media": {"videos": rec["videos"], "spin_frames": [f"spin-{k:02d}.jpg" for k in range(1, rec["spin_frames"] + 1)],
                  "modification_photos": [p["file"] for p in photos if p.get("modification")]},
        "features": rec["features"],
        "overall_condition": rec["overall_condition"],
        "inspector_note": rec["inspector_note"],
        "seller_ack": sig,
    }

    # ---- 6. the seller self-inspect fields the listing already uses ----
    def has(check, word): return any(i.get("check") == check and word.lower() in (i.get("option") or "").lower() for i in issues)
    vp = {}
    if rec["spin_frames"] >= 32:
        for k, slot in SPIN_SLOTS: vp[slot] = [{"source_file": f"spin-{k:02d}.jpg", "description": "Frame of the walk-around video"}]
    for p in photos:
        q = p["question_id"]
        if q in SLOT and SLOT[q] not in vp: vp[SLOT[q]] = [{"source_file": p["file"]}]
        elif q == "tire_photo":
            t = tm[p["wheel"]]
            desc = f"{WHEEL[p['wheel']]}: " + ", ".join(x for x in (t.get("brand"), t.get("size")) if x) + f", tread {t.get('tread_32nds')}/32 in"
            vp.setdefault("tire", []).append({"source_file": p["file"], "description": desc, "wheel": p["wheel"]})
        elif q in NEW_KEY:
            desc = p.get("panel") and f"{p['panel']}: {next((x['mils'] for x in rec['paint'] if x['panel'] == p['panel']), '')} mils" or WHEEL.get(p.get("wheel"))
            vp.setdefault(NEW_KEY[q], []).append(dict({"source_file": p["file"]}, **({"description": desc} if desc else {})))
    if "tire" in vp: vp["tire"].sort(key=lambda x: ["lf", "rf", "rr", "lr"].index(x.pop("wheel")))
    missing = [s for s in REQUIRED_SLOTS if not vp.get(s) or (s == "tire" and len(vp["tire"]) < 4)]
    if missing: err(f"required photo slots empty: {missing}")
    dp = {}
    for i in issues:
        if i["photo"]:
            dp.setdefault(i["bidbus_damage_type"], []).append({"source_file": i["photo"], "description": i["text"]})
    damage_photos = {}
    for t in DAMAGE_TYPES:
        damage_photos["has_" + t] = bool(dp.get(t))
        if dp.get(t): damage_photos[t] = dp[t]
    interior = [n for n, ok in (("persistent_odors", any(has("ck_odor", w) for w in ("Smoke", "Pet", "Mildew", "freshener"))),
                                ("damaged_dashboard", any(i["section"] == "Interior" and i["place"] == "Dash" for i in issues)),
                                ("noticeable_stains", has("ck_seats", "stained") or any(i["type"] == "Stain" for i in issues)),
                                ("rips_tears", has("ck_seats", "torn") or any(i["type"] in ("Tear", "Burn") for i in issues))) if ok]
    tech = [n for n, ok in (("sound_system", has("ck_features", "audio")), ("interior_display", has("ck_features", "Screen")),
                            ("backup_camera", has("ck_features", "cameras")), ("safety_sensors", has("ck_scan", "calibration")),
                            ("missing_equipment", has("ck_equip", "Missing")), ("navigation", rec["features"].get("navigation") == "Not working")) if ok]
    mech = []
    if any(i.get("check") == "ck_ac" for i in issues): mech.append({"name": "air_conditioning"})
    elec = [i["option"] for i in issues if i.get("check") in ("ck_srs", "ck_lights", "ck_lights_dash") and i["option"] != "Check engine"]
    if elec: mech.append({"name": "electrical", "description": "; ".join(dict.fromkeys(elec))})
    trans = [i["option"] for i in issues if i.get("check") == "ck_trans" or (i.get("check") == "ck_road" and "Transmission" in i["option"])]
    if trans: mech.append({"name": "transmission", "description": "; ".join(trans)})
    tiers = {w: tread_tier(tm[w]["tread_32nds"])[1] for w in WHEEL}
    worst_tier = max((t for t in tiers.values() if t), key=["under_10000", "10001_20000", "over_20000"].index, default=None)
    notes = [rec["inspector_note"].strip()]
    if v["ev_battery_health_pct"] is not None: notes.append(f"Battery health {v['ev_battery_health_pct']}%.")
    if keys == "One key": notes.append("One key.")
    if rec["tires_match"] == "Mismatch": notes.append("Tires do not match (brand, model or size).")
    codes = [c for i in issues for c in i.get("codes", [])]
    if codes: notes.append("Codes: " + ", ".join(codes) + ".")
    notes.append("Tread (/32 in): " + ", ".join(f"{WHEEL[w]} {tm[w]['tread_32nds']}" for w in ("lf", "rf", "lr", "rr")) + ".")
    feats = [k for k in ("sunroof", "navigation") if rec["features"].get(k) in ("Works", "Not working")]
    sid = {
        "interior_damage": [{"name": n} for n in interior] or [{"name": "none"}],
        "technology_issues": [{"name": n} for n in tech] or [{"name": "none"}],
        "mechanical_issues": mech or [{"name": "none"}],
        "check_engine_light_on": "yes" if has("ck_lights_dash", "Check engine") else "no",
        "vehicle_drivability": "not_drivable" if has("ck_engine", "Will not start") or has("ck_ev_power", "Will not power on") else "drivable",
        "frame_damage": "yes" if any(i.get("check") == "ck_structure" and i["level"] == "Red" for i in issues) else "no",
        "tire_mileage": {"overall": worst_tier, "all_same": "yes" if len(set(tiers.values())) == 1 else "no",
                         "individual": {s: tiers[w] for s, w in SLOT_WHEEL.items()}},
        "additional_condition": " ".join(n for n in notes if n)[:1000],
        "features": feats or ["none"],
        "sunroof_condition": {"Works": "works_great", "Not working": "doesnt_work", "No sunroof": "no_sunroof"}.get(rec["features"].get("sunroof")),
        "overall_condition": OVERALL.get(rec["overall_condition"]),
        "has_modifications": "yes" if report["media"]["modification_photos"] else "no",
    }
    keep_from_seller = []
    if has("ck_paint", "Wrap"): sid["has_wrap"] = "yes"
    else: keep_from_seller.append("has_wrap (no wrap seen; the seller's answer also covers past wraps)")
    if carfax_owners not in (None, ""): sid["first_time_owner"] = "yes" if int(carfax_owners) == 1 else "no"
    else: keep_from_seller.append("first_time_owner (from the Carfax owner count)")
    mods = [{"source_file": p["file"], "description": f"{p['section']} modification"} for p in photos if p.get("modification")]

    out = {
        "condition_report": report,
        "vehicle_patch": {"self_inspection_data_merge": sid, "keep_from_seller": keep_from_seller, "has_smoked_in": has("ck_odor", "Smoke"),
                          "vehicle_photos": vp, "damage_photos": damage_photos, "modification_photos": mods},
        "documents": {k: v2 for k, v2 in rec["documents"].items() if v2},
        "checks_for_listing_team": {"vin_read": v["vin_read"], "vin_listing": v["vin_listing"], "vin_matches": v["vin_read"] == v["vin_listing"],
                                    "mileage_read": v["mileage_read"], "mileage_listing": v["mileage_listing"],
                                    "mileage_lower_than_listing": v["mileage_read"] is not None and v["mileage_listing"] is not None and v["mileage_read"] < v["mileage_listing"],
                                    "fuel": fuel, "ai_guesses_changed": [i["id"] for i in issues if i.get("inspector_changed_ai")]},
        "validation": {"ok": not errors, "errors": errors, "issues": len(issues), "checks": len(rec["checks"]), "photos": len(photos)},
    }
    return out


def main(src, out_path, carfax_owners=None):
    out = build_cr(json.load(open(src)), carfax_owners)
    json.dump(out, open(out_path, "w"), indent=1)
    cr, errors = out["condition_report"], out["validation"]["errors"]
    issues, rows, vp = cr["issues"], cr["rows"], out["vehicle_patch"]["vehicle_photos"]
    print(f"{os.path.basename(src)}: light {cr['light']}, issues {len(issues)} ({sum(1 for i in issues if i['from'] == 'damage photo')} from damage photos), "
          f"rows with problems {[r['row'] for r in rows if r['issues']]}, photo slots {len(vp)}, validation {'ok' if not errors else errors}")
    return not errors


if __name__ == "__main__":
    a = sys.argv[1:]
    sys.exit(0 if main(*a[:3]) else 1)
