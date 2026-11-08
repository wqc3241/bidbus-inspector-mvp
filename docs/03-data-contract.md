# 03 Data contract

The app sends one **inspection record** per car. Its shape is exactly `samples/inspection-bmw-x3.json` (gas) and `samples/inspection-tesla-model-y.json` (EV). The mockup builds it in `inspectionPayload()` (`reference/mockup/src/template.html`); port that function, do not redesign the shape. Full field-by-field notes: `docs/field-mapping.md` (sections "What the app sends", "AI photo reading", "Issue lists", "CR report generation").

## Top-level parts

| Part | Holds |
|---|---|
| `source` | `system: "bidbus_field"`, `listing_id` (= the inspection id in this build), `inspector`, `started {at, loc}`, `ended {at, loc}` |
| `vehicle` | `vin_listing` (VIN typed at New inspection, or null), `vin_read`, `vin_door_jamb_read`, `mileage_listing` (typed mileage, or null), `mileage_read`, `vin_mileage_confirmed`, `keys_count`, `keys_count_read_from_photo`, `fuel`, `ev_battery_health_pct` |
| `owner_check` | Yes, Family, with proof, or No |
| `documents` | `license`, `registration`, `family_proof`: `"taken on site"` or null. Private |
| `photos[]` | `section`, `question_id`, `wheel`/`panel`, `n`, `modification`, `source` (camera or upload), `file`, `upright_turn_deg`, or `skipped: true` |
| `videos[]` | `question_id` (video_360, video_engine, video_exhaust), `file`, `max_seconds` |
| `spin_frames` | 36 |
| `checks[]` | `id`, `result` (OK, Problem, Not done), `problems[] {option, level, from_damage_photo}`, `wheel`, `where`, `codes` when the check has them |
| `tires[]`, `tires_match` | Per wheel: `tread_32nds`, `tread_read_from_photo`, `brand`, `size`, `read_from_photo`; Match or Mismatch |
| `paint[]` | `panel`, `mils`, `not_on_car`, `high`, `read_from_photo` |
| `damages[]` | `n`, `section`, `place`, `type`, `severity`, `size_in`, `source`, `taken_in`, `file`, `upright_turn_deg`, `check_id?`, `check_option?`, `ai_first_guess {place, type, severity}`, `confirmed` |
| `features` | `sunroof`, `navigation` |
| `overall_condition`, `inspector_note` | Summary answers |
| `signature` | `seller_name`, `agreed`, `signed` (the image is uploaded as file `signature.png`) |

Home build additions, outside the record (sent in the create call, not inside the record, so the CR generator is unchanged): `inspection_id` (UUID made on the phone), `report_email`, `car {year, make, model, trim, owner_name}`.

## Files

Every `file` named in the record is uploaded separately: `PUT /api/inspections/{id}/files/{file}` with the raw bytes. File names follow the mockup's `fname()`: `{question_id}-{wheel}-{panel}-{n}.jpg` lower-cased, damage photos `damage-{n}.jpg`, mods `ph_mod_ext-{n}.jpg` / `ph_mod_int-{n}.jpg` / `ph_mod_mech-{n}.jpg`, videos `{question_id}.mp4` (or `.mov`/`.webm` as recorded), signature `signature.png`, documents `ph_license.jpg`, `ph_reg.jpg`, `ph_family.jpg`.

The server makes `spin-01.jpg` to `spin-36.jpg` from `video_360.*`.

## Photo categories

`section` = the question's `section` in `data/question-list.json`, never the camera pass: paint meter photos are Paint; underbody photos are Underbody; scan tool and EV screens are OBDII; VIN, odometer and keys are Additionals; a damage photo at an underbody place is Underbody; a damage photo at a body panel with a paint problem is Paint.

## Validation

Before the report: `tools/cr_from_inspection.py` checks every place, type, severity, size, Which panel or Where, check option for the car's fuel and its level against `data/issue-catalog.json`; tread 1-14; paint panels and High (8 mils or more); VIN check digit; VIN and mileage confirmed; sunroof, navigation, overall condition; signature; every photo upright. `validation.ok` false stops the report; the reasons are returned to the app and shown on the Sent screen.

## Output

`samples/cr-*.json`: `condition_report` (source, vehicle, light, highlight, not_listed_reasons, rows, issues, road_test, tires, tires_match, paint, media, features, overall_condition, inspector_note, seller_ack), `vehicle_patch` (seller self-inspect fields; stored, not used in this build), `documents`, `checks_for_listing_team`, `validation`.
