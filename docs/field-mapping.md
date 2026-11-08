# Inspector App to Seller Self-Inspect Field Mapping

Reference for the record, AI readings, issue lists and CR generation. The seller self-inspect columns (`vehicles.*`) belong to the company backend; this build stores `vehicle_patch` but does not use it.

The inspector app (Bidbus Field phase 1, Internal MVP V71) fills every field the seller self-inspect flow fills, so the seller app, admin, dealer pages and listing gates work unchanged. Everything else (videos, the 360 view, tread depth, readings, damage place and size, every check result, the signature) goes to the new Bidbus CR store. Checked against bidbus-v3 main (commit 69a14942).

## Where the data lands

The seller self-inspect flow has three steps (Upload photos, Report damages, Self-Inspection) and stores all of it as JSON on the vehicle row. The inspector app writes into the same places first, then puts the rest into the Bidbus CR.

| Store today | What the seller fills | What the inspector app writes |
|---|---|---|
| `vehicles.vehicle_photos` | 12 required slots (15 photos, tire x4) + `additional` | Same 12 slots from the inspector shots, plus new position keys for the extra shots |
| `vehicles.damage_photos` | Yes/no for 8 damage types, each Yes needs at least 1 photo with a description; `additional_damage` optional | Every type answered: Yes with labelled photos, or No when the inspector found nothing |
| `vehicles.self_inspection_data` | 13 answers (sunroof, interior, technology, mechanical, check engine, drivable, overall condition, wrap, modifications, features, frame, first owner, tires) + free text | Answers derived from the checks; seller answers kept only for what the inspector does not check |
| `vehicles.modification_photos` | Photos + description per modification | Modification photos on Exterior, Interior and Mechanicals |
| Vehicle documents | Driver license, registration (required), title and others | Nothing: the seller uploads them in the seller app as today; if they are missing at Start, the inspector sends the seller an upload link |
| New: Bidbus CR store (`vehicle_inspections`) | Nothing | Full report: one issue list (place, type, severity, size, level, CR row, photo), every check (OK or problem + level), tread, readings, videos, 360 frames, signature, times, GPS, inspector |

Rule for every field: the inspector answer replaces the seller answer for anything the inspector checked. Photo objects keep today's shape `{cloudflare_id, description, uploaded_at, original_filename, content_type, file_size}` and add `source: "inspector"`, so admin can tell seller and inspector photos apart.

## Photos

Twelve inspector shots fill the 12 required seller slots one to one, so `has_all_required_photos` is true and the seller never sees a Photos step. The other 30 or so shots have no slot today; they get new position keys so the dealer viewer can group them (Exterior, Interior, Tires, Underbody, Mechanicals, OBDII, Additionals). Every photo is stored under the section of its question in the question list (question-list.csv), not the camera pass it was taken in: underbody shots are taken in the Underbody pass and stored as Underbody, the scan tool and EV screen shots are OBDII, and the VIN, odometer and keys photos are Additionals. `transformed_vehicle_photos` already returns every key in `vehicle_photos`, so new keys need only labels and icons in the dealer UI.

| Inspector photo (question id) | Seller slot today | Action | Note |
|---|---|---|---|
| Front left corner (360 frame 1) | `front_left` Front Driver Side | Reuse | Frame of the walk-around video |
| Front right corner (360 frame 28) | `front_right` Front Passenger Side | Reuse | Video frame |
| Rear left corner (360 frame 10) | `rear_left` Rear Driver Side | Reuse | Video frame |
| Rear right corner (360 frame 19) | `rear_right` Rear Passenger Side | Reuse | Video frame |
| Rear, plate visible (360 frame 14) | `rear` Rear | Reuse | Video frame |
| Roof (`ph_ext_roof`) | `roof` Roof | Reuse | Separate still |
| Dash with the screen on (`ph_int_dash`) | `dashboard` Dashboard | Reuse |  |
| Front seats (`ph_int_front`) | `driver_seat` Driver Seat | Reuse | Wider shot than the seller's, same slot |
| Rear seats (`ph_int_rear`) | `rear_seat` Rear Seat | Reuse |  |
| Odometer, car on, warning lights visible (`ph_odo`) | `odometer` Odometer | Reuse | AI reads the mileage from it (see Other fields) |
| Engine bay (`ph_engine_bay`), EV: front trunk (`ph_frunk`) | `engine` Engine | Reuse |  |
| Whole tire, each wheel (`tire_photo` x4) | `tire` x4 Tire | Transform | One array of 4 in the order LF, RF, RR, LR; description "Left front: Michelin, 245/50R19, tread 7/32 in"; AI reads brand and size from it |
| Front, left side, right side (360 frames 32, 5, 23) | none | New keys `front`, `left_side`, `right_side` | Video frames |
| Tread gauge in the lowest groove, each wheel (`tread_photo` x4) | none | New key `tread_gauge` | AI reads the tread depth from it |
| Infotainment screen, on (`ph_int_screen`) | none | New key `infotainment` |  |
| Cargo area (`ph_int_cargo`) | none | New key `cargo` |  |
| Underbody, 6 photos in this order: left front, left rear, rear, right rear, right front, front (`ph_under_lf`, `ph_under_lr`, `ph_under_rear`, `ph_under_rr`, `ph_under_rf`, `ph_under_front`) | none | New key `underbody` | One question id per photo |
| Catalytic converters (`ph_under_cats`, optional) | none | New key `underbody` |  |
| Engine oil on the dipstick (`ph_engine_oil`), charge port on EVs and plug-in hybrids (`ph_ev_port`) | none | New key `mechanicals` | No oil cap, coolant or emission label photo |
| Paint meter on the panel, 11 panels (`paint`, one per panel) | none | New key `paint_meter` | Panel and mils in the description; AI reads the mils |
| OBD-II, gas: current, past and emission codes (`ph_obd_current`, `ph_obd_past`, `ph_obd_emission`) and other images (`ph_obd_other`, optional); EV: service-mode alerts (`ph_ev_alerts`), battery health (`ph_ev_battery`) and charging (`ph_ev_charging`), both optional | none | New key `obdii` |  |
| VIN through the windshield, door-jamb VIN label (`ph_vin_dash`, `ph_vin_door`) | none | New key `vin` | AI reads the VIN from both |
| All keys together (`ph_keys`) | none | New key `keys` |  |
| Driver license, registration (`ph_license`, `ph_reg`) | Documents `driver_license`, `registration` | Reuse | Uploaded by the seller, not shot by the inspector; if missing at Check ID, the inspector texts the upload link, or photographs a missing one on site. Private, never in `vehicle_photos`, never shown to dealers |
| Family proof (when the seller is family), uploaded by the seller or photographed at Check ID | Additional documents | Reuse | Private |
| Damage photos, Damage shutter at any point of the camera pass | `damage_photos` | Transform | See Damages |
| Modification photos, Mod shutter (`ph_mod_ext`, `ph_mod_int`, `ph_mod_mech` by section) | `modification_photos` | Transform | One entry per photo, described as "Exterior modification"; any photo sets `has_modifications` to Yes, none sets No |

## Videos and the 360 view

Listings have no video today: the seller flow has no video step, `vehicle_photos` holds only Cloudflare Images ids, and the dealer web page has no player. All four media items are new and live in the Bidbus CR store, because only inspected cars have them.

| Inspector media (question id) | Today | Action | Where it goes |
|---|---|---|---|
| Walk-around, 360 degrees, engine off, up to 60 s (`video_360`) | none | New | Cloudflare Stream (or R2, which already holds vehicle documents); `vehicle_inspections.media.walkaround` = `{stream_id, duration_s, uploaded_at}` |
| Engine sound at first start, up to 30 s (`video_engine`), gas and hybrid only | none | New | `media.engine_sound`, same shape |
| Exhaust at idle and revving, up to 30 s (`video_exhaust`), gas and hybrid only | none | New | `media.exhaust`, same shape |
| 360 spin: 36 frames cut from the walk-around | none | New | Each frame is a Cloudflare Images id in `media.spin_frames` (36, in order); the dealer page shows them with Cloudimage 360 View |

1. The inspector shoots the walk-around once; the app cuts 36 frames from it.
2. 8 of the frames (1, 5, 10, 14, 19, 23, 28, 32) become the exterior photos: 5 go into the existing slots above, 3 into `front`, `left_side`, `right_side`.
3. In phase 3, Ravin AI reads the same walk-around; findings the inspector keeps become damage entries.
4. The API adds the videos and the spin to the listing response next to `transformed_vehicle_photos`, so the dealer viewer can hold photos and videos in one strip (the CR mockup layout).

The seller flow stays photo only. A later seller video step could reuse the same `media` shape.

## Damages

The seller answers Yes or No for 8 damage types and adds a photo with a description for each Yes. The inspector takes one photo per damage with the Damage shutter anywhere in the camera pass. In the Damages step each photo gets a place (from the issue catalog), a type (only those the place allows), a severity (Minor, Moderate or Severe, required) and a size (1 to 36 in, optional). AI proposes place, type and severity first; the inspector confirms or changes them, and both are sent. Underbody places (Structure, Rust, Exhaust, Suspension, Driveshaft or CV, Brakes, Battery pack) are stored as Underbody; a paint problem picked at an Exterior body panel is stored as Paint at that panel (Hood is Hood or frunk lid). A type that is a check option also answers that check; Structure answers Structure and frame with the option its place gives. Each damage becomes one `damage_photos` photo under the matching seller type, and every type with no photo is set to No, so `has_all_required_damages` is true.

| Inspector damage (section: place, type) | Seller damage type | Action |
|---|---|---|
| Exterior body panels and Other: Scratch, Scuff | `scratches` Scratches | Transform |
| Exterior body panels and Other: Dent, Hail | `dents` Dents | Transform |
| Exterior body panels and Other: Chip | `paintwork` Paint Damage | Transform |
| Paint, any of the 11 panels: every Paint and panels option (`ck_paint`): repainted, overspray or colour mismatch, uneven gaps, bolt tool marks, wrap or paint film | `previous_paint_work` Previous Paint Work | Transform |
| Exterior: Windshield, the four side windows, Rear glass (`ck_glass`) | `windshield_damage` Windshield Damage | Transform |
| Exterior body panels and Other: Crack or break; Mirror (`ck_glass`); Headlight, Tail light, Other lights (`ck_lights`); Wipers (`ck_wipers`); Fuel door (`ck_fuel_cap`) | `broken_or_missing_parts` Broken/Missing Parts | Transform |
| Interior: Warning lights (`ck_lights_dash`) | `warning_lights` Warning Lights | Transform |
| Tires: each wheel's wheel, Curb rash, Bent, Cracked, Aftermarket (`ck_wheel`) | `wheel_damage` Wheel Damage | Transform |
| Exterior: Rust bubbling, Structure; Tires: each wheel's tire (`ck_tire`); every Interior, Mechanicals and Underbody place, including Sunroof and Navigation not working | `additional_damage` Additional Damage | Transform |
| Ravin AI finding the inspector kept (phase 3) | Type from its label, as above | Transform |

Structure on an Exterior or Interior place also sets `frame_damage` to Yes (a Red level).

The seller's required description is built from the label: "Left front door: Dent, Moderate, 2 in". The parts of the label have no field today, so each damage photo gets new keys next to `description`:

| New key on a damage photo | Example | Why |
|---|---|---|
| `section` | Exterior, Paint, Tires, Interior, Mechanicals, Underbody | Group on the dealer page |
| `place` | Left front door | From the catalog's places; the dealer page groups damage photos by it and puts it on the damage map |
| `type` | Dent | Exact inspector type, finer than the 8 seller types |
| `severity` | Moderate | Minor, Moderate or Severe, required; also in the description |
| `size_in` | 2 | Whole inches, 1 to 36; optional |
| `where` | Right front door | Which panel (Paint), Where (Leak) or Which wheel (Brakes), when the place has one |
| `check_id`, `check_option` | `ck_glass`, Windshield crack | The check and option this damage answers |
| `level` | Red, Yellow, Disclosed | From the question list; drives the CR rows and the light |
| `ai_first_guess` | place, type, severity | What AI proposed, kept beside what the inspector confirmed |
| `upright_turn_deg` | 90 | How far the app turned the photo to make it upright |
| `source` | inspector, ravin | Who found it |

`transform_photo_array` passes only `description` today; it needs to pass these keys in `info` too. Damage photos are labelled on the phone, so no labelling step runs when the report is made.

## Self-inspection answers

Nine of the 13 seller answers come straight from inspector checks. The other four have their own source, so `self_inspection_completed?` passes: overall condition is a required pick on the inspector Summary, first owner comes from Carfax, and sunroof and navigation are two questions the inspector answers on the Interior page.

| Seller field | Seller question | Inspector source | Action |
|---|---|---|---|
| `check_engine_light_on` | Is the Check Engine light on? | Warning lights (`ck_lights_dash`) = Check engine | Reuse |
| `frame_damage` | Frame damage? | Structure and frame (`ck_structure`) with a Red option | Reuse |
| `vehicle_drivability` | Issues that stop safe driving? | Engine = Will not start (`ck_engine`), EV Power-on = Will not power on (`ck_ev_power`) | Transform |
| `interior_damage` | Odors, damaged dash or panels, stains, rips | Odor (`ck_odor`), Seats, carpet and trim (`ck_seats`) | Transform |
| `technology_issues` | Sound, display, backup camera, safety sensors, missing equipment | Features (`ck_features`), Navigation = Not working (`navigation`) adds `navigation`, Scan = calibration needed (`ck_scan`), Equipment (`ck_equip`) | Transform |
| `mechanical_issues` | A/C, electrical (with text), tire pressure, transmission (with text) | A/C and heat (`ck_ac`), Seat belts and airbags, Lights, Warning lights (`ck_srs`, `ck_lights`, `ck_lights_dash`), Transmission (`ck_trans`), Road test (`ck_road`); text = the options picked | Transform |
| `tire_mileage` | Great 9-11/32, Fair 5-8/32, Replace 4/32 and below; same for all four? per tire | Measured tread per tire (`tread`) mapped to the tiers; all_same when all four land in one tier | Transform |
| `has_wrap` | Wrapped now or ever? | Yes when the car is wrapped now; otherwise the seller's answer stays, since the question also covers past wraps. Paint and panels = Wrap or paint film (`ck_paint`) | Transform |
| `has_modifications` + `modification_photos` | Any modifications? + photos | Yes when any modification photo was taken (`ph_mod_ext`, `ph_mod_int`, `ph_mod_mech`), else No; those photos fill `modification_photo``s` | Transform |
| `sunroof_condition` | Works great, Doesn't work, No sunroof | Sunroof (`sunroof`, Interior page): Works, Not working, No sunroof give Works great, Doesn't work, No sunroof | Reuse |
| `additional_condition` | Free text | Inspector's note for dealers (`summary`) + battery health, keys, codes, tread line | Transform |
| `overall_condition` | Like new to Major issues | Overall condition (`overall_condition`), a required pick on the Summary with the same five answers | Reuse |
| `features` | Sunroof, Navigation | Sunroof (`sunroof`) and Navigation (`navigation`) on the Interior page: Works or Not working adds the feature, No sunroof or No navigation leaves it out, None of the above when both are missing | Transform |
| `first_time_owner` | First owner? | Carfax owner count: 1 owner = Yes, more = No | Transform |

Navigation has no condition field of its own: when the inspector answers Not working, it shows under technology issues as `navigation`; Works shows no issue.

VehicleAutoReviewJob rejects a first submission on self-inspection red flags (for example frame damage Yes). An inspected car should skip that auto review, or the inspector's own answers would send it back to the seller.

## Other fields and new data

| Inspector data (question id) | Field today | Action | Where it goes |
|---|---|---|---|
| VIN, read by AI from the windshield VIN photo (`ph_vin_dash`) and the door-jamb label (`ph_vin_door`), check digit checked, confirmed on the Summary | `vehicles.vin` | Reuse as a check | Match the car; a mismatch waits in admin Unmatched. A VIN that is not 17 characters, fails the check digit, or differs between the two photos or from the listing is flagged for the listing team |
| Current mileage, read by AI from the odometer photo (`ph_odo`) and confirmed on the Summary | `vehicles.mileage` | Direct | Required; the inspector can change the AI reading; it is the inspected mileage on the CR and is compared with the seller's mileage; a gap over a set limit goes to the listing team |
| Odor = Smoke (`ck_odor`) | `vehicles.has_smoked_in` | Reuse |  |
| Fuel (from the VIN decode) | `vehicle_mechanical.fuel_type` | Reuse | Drives the EV and gas questions |
| Owner check (`id_owner`): Yes, Family with proof, No | none | New | CR store; checked against the license the seller uploaded; No ends the visit |
| Tires match (tires_match): Match, Mismatch | none | New | CR store; Mismatch also adds a line to additional_condition |
| Tire and wheel damage photos, labelled in the Damages step with the wheel's tire or wheel place | damage_photos | Transform | Curb rash, Bent, Cracked go to wheel_damage; tire findings go to additional_damage |
| Every check with its result: OK, or Problem + options + level (37 checks) | none (seller has 13 answers) | New | CR store; dealer Bidbus CR rows show No issues or the problem |
| Tread depth per tire, 1 to 14/32 in (`tread`), read by AI from the gauge photo; tire brand and size, read by AI from the tire photo (optional) | Tier only (`tire_mileage`) | New | CR store; the tier is still written to `tire_mileage` |
| Tire and wheel problems per wheel (`ck_tire`, `ck_wheel`) | none | New | CR store, Tire Condition section |
| Paint meter reading per panel, read by AI from the meter photo; 8 mils or more is High | none | New | CR store, with the panel name |
| Engine codes typed from the scan (`ck_scan` codes) | none | New | CR store; also in `additional_condition` |
| EV battery health % (`ev_soh`) | none | New | CR store; also in `additional_condition` |
| Keys: two or more, only one, none works (`ck_keys`) | none | New | CR store |
| Ravin AI findings, Keep or Remove (phase 3) | none | New | Kept ones become damage entries; all kept in the CR store |
| Seller name, signature, agreement to the findings (`seller_name`, `seller_sign`) | none | New | CR store, private |
| Inspector, start and end time, GPS at the car (`arrived_at`, `left_at`, `arrived_gps`) | none | New | CR store, admin only |
| Not listed reasons (options at Ends the visit or Not listed until fixed) | none | New | CR store; blocks listing |

No new columns are needed on `vehicles`: new data goes into the Bidbus CR store, and the listing fields above are filled the way the seller app fills them.

## What the app sends

When the seller signs, the app sends one record per car: answers first, then the media files one at a time. Two samples are attached to DEV-190: `inspection-bmw-x3.json` (gas, 46 photos, 37 checks, 8 damage photos) and `inspection-tesla-model-y.json` (EV).

| Part | What it holds |
|---|---|
| `source` | App, listing id, inspector, start and end time and place |
| `vehicle` | Listing VIN, VIN read from the photos, door-jamb label read, listing mileage, mileage read from the odometer photo, VIN and mileage confirmed on the Summary, fuel, EV battery health, number of keys (0, 1 or 2) and whether AI read it from the keys photo |
| `owner_check`, `documents` | Owner answer; license, registration and family proof (private) |
| `photos[]` | Section (the question-list section: Start, Exterior, Paint, Tires, Underbody, Interior, Mechanicals, OBDII, Additionals), question id, wheel or panel, photo number, camera or upload, file, `upright_turn_deg`; skipped optional shots marked |
| `videos[]`, `spin_frames` | Walk-around (60 s), engine sound and exhaust (30 s each); 36 frames of the 360 view |
| `checks[]` | Every check for the car's fuel: OK, Problem or Not done; each problem with its level and whether a damage photo gave it; Which wheel or Where; engine codes |
| `tires[]`, `tires_match` | Per wheel: tread, brand, size, and whether AI read them from the photo; Match or Mismatch |
| `paint[]` | Per panel: mils, High (8 mils or more), Not on this car, read from the photo |
| `damages[]` | Per damage photo: section, place, type, severity, size, Which panel or Where, the check and option it answers (or the sunroof or navigation answer), AI first guess, confirmed |
| `features`, `overall_condition`, `inspector_note`, `signature` | Sunroof and navigation answers, overall condition, note for dealers, seller name, agreement and signature |

## AI photo reading and upright photos

AI reads each photo as soon as it is taken and fills the answer; the inspector confirms or changes it on Review or the Summary. What AI guessed is kept beside what the inspector confirmed, so the guesses can be measured.

| Reading | From which photo | Where it lands |
|---|---|---|
| Mileage | Odometer (`ph_odo`) | `vehicle.mileage_read`, confirmed on the Summary |
| VIN | Windshield VIN (`ph_vin_dash`) and door-jamb label (`ph_vin_door`), check digit checked | `vehicle.vin_read`, confirmed on the Summary |
| Tire brand and size | Whole tire (`tire_photo`), each wheel | `tires[].brand`, `size` (optional) |
| Tread depth, 1 to 14/32 in | Tread gauge in the lowest groove (`tread_photo`), each wheel | `tires[].tread_32nds` |
| Paint meter reading, mils | Meter on the panel (`paint`), 11 panels | `paint[].mils`; 8 mils or more sets High and Panel repainted |
| EV battery health, % | Battery health screen (`ph_ev_battery`) | `vehicle.ev_battery_health_pct` |
| Damage place, type, severity | Each damage photo | `damages[].ai_first_guess`; the confirmed answer goes in `place`, `type`, `severity` |

Every photo is turned upright before it is read or stored, because inspectors sometimes shoot upside down or turned 90 degrees. Use the phone's orientation at the moment of the shot (EXIF orientation); for an upload without it, an AI check that the car, label or screen is upright. The record keeps how far each photo was turned (`upright_turn_deg`: 0, 90, 180 or 270).

## Issue lists

The backend keeps one list of every issue the app can report, `issue-catalog.json` (attached to DEV-190). It is made from the app itself, so it always matches what inspectors can pick, and every record is checked against it before a report is made.

| List | Contents | Count |
|---|---|---|
| `places` | Per section, every place the inspector can pick, with its wheel, its Which panel or Where list, and the types it allows for each fuel | 78 places: Exterior 26, Interior 19, Paint 11, Tires 8, Mechanicals 7, Underbody 7 |
| `issues` | Every place and type pair, with the check and option it answers (or none), its level and the seller damage photo type it fills | 319 pairs: 267 Disclosed, 20 Yellow, 32 Red |
| `checks` | Every check with its CR row, the fuels it shows for, and each option with its level and fuels | 37 checks, 152 options |
| `check_only` | Check options no damage place gives (scan result, keys, odors, A/C, road test and so on): their place is the Which wheel or Where answer, or the check itself; their section is the check's section in the question list (keys, equipment and app account are Additionals), and they have no severity | 56 options |
| `severities`, `size_in` | Minor, Moderate, Severe; size 1 to 36 in, optional |  |
| `levels` | Ends the visit and Not listed until fixed give Not listed; Red and Yellow set the light; Disclosed is listed with no change |  |

Example rows: Exterior, Trunk or liftgate, Structure answers Structure and frame with Rear structure repaired or damaged (Red, `additional_damage`, `frame_damage` Yes). Tires, Right front wheel, Curb rash answers Wheel, each wheel (Disclosed, `wheel_damage`). Interior, Carpet, Flood signs answers Seats, carpet and trim (Red).

## CR report generation

Bidbus makes the condition report from the record as soon as it arrives. `cr_from_inspection.py` (attached to DEV-190) shows every step; it ran on both samples with no errors and wrote `cr-bmw-x3.json` and `cr-tesla-model-y.json`.

1. Check the record against the issue lists: every place, type, severity, size, Which panel or Where, check option for the car's fuel and its level; tread 1 to 14; paint panels and High; VIN check digit; VIN and mileage confirmed; sunroof, navigation and overall condition answered; seller signature; every photo upright. Anything off stops the report with the reason.
2. Build one issue list. Each damage photo is one issue: place, type, severity, size, level, CR row, photo, AI first guess and whether the inspector changed it. Each check problem no damage photo gave is one issue too: its place is the Which wheel or Where answer (a panel that reads High for Panel repainted, with its mils) or the check itself, and it has no severity. Each issue carries its text in the inspector app's own words: a damage reads "Place: Type, Severity, N in" (for example "Left front door: Scratch, Moderate, 4 in"); a check problem reads "Check: option", with "Tire:" or "Wheel:" and one issue per wheel; a second line holds the Where answer, the wheel, the High panel or the engine codes. The damage photo description is the same text.
3. Put the issues in the CR rows in dealer order: Exterior, Paint, Tires, Underbody, Mechanicals, Engine sound (not for EVs), Interior, OBD-II, Additionals. An issue goes to its check's row, so Structure seen at the trunk or carpet shows under Underbody; one with no check goes to its section's row. Each row also gets the photos stored under its section (the VIN, odometer and keys photos under Additionals) and its videos; Start photos (seller documents) go on no row. Each damage shows in its row with its photo and text; the report has no separate Damages section.
4. Add tires (tread, Replace 4/32 and below, Fair 5 to 8, Good 9 and up, brand, size, the issues on that wheel), paint readings, videos, the 360 frames, modification photos, features, overall condition, inspector note and seller signature.
5. Work out the light from the worst level (Not listed, Red, Yellow, otherwise Green) and the not-listed reasons. The light is stored; V1 dealer screens do not show it. Work out the highlight that the seller and dealer reports show first: Structural damage (Yes when a Structure problem is recorded, Not checked when the inspector could not photograph it, otherwise No), Keys (the 0, 1 or 2 the inspector confirmed), Odor (the odor problems, or OK) and Mechanical (Issue when any issue sits in Mechanicals, otherwise No issue).
6. Fill the seller self-inspect fields the listing already uses: photo slots, damage photos by seller type with has_ flags, modification photos, and the 13 answers.

The two samples show on the CR page with the highlight, every issue and every damage photo in place. The CR page is built from the same question list as the inspector app, so its words match the app's.

## Open questions

- Video store: Cloudflare Stream (playback and thumbnails built in) or R2 (already used for documents, needs our own player)?
