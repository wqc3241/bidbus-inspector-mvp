# 01 Product spec (DEV-190, home build)

## Users

- **Inspector**: starts an inspection, does one camera pass, labels damages, reviews, gets the seller's signature on the phone.
- **Report reader**: opens the seller report link or the dealer report link from the email.

## Flow

New inspection (YMMT) → Check ID at the car → one camera pass: Exterior (360 video, paint readings, roof, windshield VIN), Tires & Wheels, Interior, OBDII, Mechanicals, Underbody; Damage and Mod shutters at any point → Damages: confirm or label every damage photo → Review: one page per section → Summary: VIN, mileage, overall condition, note → disclosure and seller signature → upload → backend makes the condition report and emails the seller and dealer report links.

The inspection takes about 18 minutes.

## 1. UI requirements

**1.1 Inspections (first screen)**
- List of inspections on this phone. Each row: year make model trim, VIN (if any), status: In progress, Saved on phone, Uploading, Report sent, Visit ended.
- Button New inspection.
- Settings: inspector name, app passcode, default report email.

**1.2 New inspection**
- Year (1981 to next year), Make, Model, Trim: required.
- VIN (optional, 17 characters): when typed, decode with NHTSA vPIC and prefill year, make, model, trim and fuel type.
- Fuel type, required: Gas, Diesel, Hybrid, Plug-in hybrid, Electric (EV). It decides which items show; Gas and Diesel show the question list's "Gas or diesel" items, and the record's fuel stays "Gas or diesel" for both.
- Mileage (optional), owner name (optional).
- Report email, required, prefilled with the default from Settings.
- Button At the car: check ID.

**1.3 Check ID**
- Two photo cards: driver's license (front) and registration card. Both required, taken here, private.
- Owner question: Seller's license matches a registered owner: Yes; Family, with proof (one photo of the proof); No ends the visit.
- Start inspection stays off until both photos are in and the answer is Yes, or Family with the proof photo.
- Start inspection records the start time and GPS and opens the camera on Exterior.

**1.4 One camera pass, landscape**
- Six sections in order: Exterior (360 walk-around video; then one paint meter photo per panel starting at the left front fender, counter-clockwise, then hood and roof, 11 panels; roof photo; windshield VIN), Tires & Wheels, Interior, OBDII, Mechanicals, Underbody. "Tires & Wheels" is the name shown; the section key in the data stays `Tires`.
- After the last shot of each section, a dialog: "Please record any exterior damage/modification images before proceeding." (tire and wheel, interior, mechanical, underbody for the other sections) with I'm done and Record damage now. I'm done goes to the next section. Record damage now reopens that section's camera with only the Damage and Mod shutters and Next (top right) to the next section. Every section has this step but OBDII, which has no Damage and Mod shutters.
- Never stops otherwise: Damage (amber) and Mod (blue) shutters on the right take a tagged photo at any point without moving the flow. Off on videos and in OBDII.
- Every shot can go Back and be retaken; optional shots can be skipped.
- Each tire: a whole tire photo and a tread gauge photo.
- Damage tapped at a paint panel: the AI guess for the place is that panel.

**1.5 360 view** on Review Exterior: made from the walk-around; drag to turn; shows the frame number.

**1.6 Damages, Review, Summary**
- Damages: after the camera, one damage photo per screen, section by section. Place (Exterior: a drawn top view of the car; Tires: pick a wheel's tire or wheel), type and severity (Minor, Moderate, Severe) required; size optional (1-36 in) on Exterior damages only. Each photo first shows the AI guess of place, type and severity; the inspector confirms or changes it. Moves to the next photo when all three are picked.
- Structure is a type on Exterior body panels and on Interior carpet, headliner, dash, door panels and cargo; it answers Structure and frame with the option the place gives.
- Paint problems: the 11 Exterior body panels also offer the five Paint and panels problems after Structure (Panel repainted, Overspray or colour mismatch, Uneven panel gaps, Hood or fender bolts show tool marks, Wrap or paint film). Picking one answers Paint and panels with that panel; stored as Paint.
- Review: one page per section, Paint its own page (paint photos and readings; tap a photo to retake that panel in the Exterior camera). One row per check, OK by default; tap opens a bottom drawer with its problems; readings; damage photos; everything editable.
- Number of keys: AI reads 0, 1 or 2 (2 = two or more) from the keys photo; first row of Review Interior, marked Read from photo; required. 1 ticks Only one key on the Keys check; ticking or clearing Only one key sets 1 or 2.
- Summary: counts of photos, videos, problems and damage photos; findings; VIN and mileage confirm; overall condition; note.

**1.7 Disclosure and seller signature**: disclosure, agree tick, seller name and signature, then Sign. The seller sees findings only.

**1.8 Sent, or saved until signal**
- Sent: Report sent to {email}, links Open seller report and Open dealer report, start and end time, location.
- No signal: everything saved on the phone, progress per part, uploads by itself when signal returns.

## 2. Logic requirements

**2.1 App**: native Flutter app for iOS and Android, iPhone first; camera screens landscape, forms portrait. Works fully offline.

**2.2 Questions**
- `data/question-list.json` (101 items, 37 checks). Render from it.
- Every check starts as OK.
- Fuel type: EVs hide engine bay, leaks and scan result items; charging items (Charging check, charge port photo, charge port damage place, missing charge cable) show for EV and plug-in hybrid.
- Readings come from the photos by AI (2.8); photos can also be picked from the library.
- Tires: whole tire photo and tread gauge photo (gauge in the lowest groove). AI reads brand and size from the first (optional) and tread from the second (1-14/32, required per tire). Review Tires edits them with scroll pickers: brand from North American tire brands; size as width 165-355, aspect 15-85, rim R13-R25. No DOT.
- The 4 tires match (same brand, model, size): Match or Mismatch on Review Tires, required, no default; Mismatch is Disclosed.
- Tire and wheel damage photos are labelled in Damages with the wheel and the type (tire: uneven wear, sidewall cracks, bulge, plug or patch, cut; wheel: curb rash, bent, cracked, aftermarket). A label matching that wheel's tire or wheel problem ticks it.

**2.3 Sending**
- After the signature the app sends one record (`docs/03-data-contract.md`): answers, photos, videos, readings, damage labels with the AI guess, signature, start and end time and location. Answers first, then media one file at a time.
- Sending again updates the same inspection (client-generated inspection id).
- Closing the app or losing signal loses nothing.
- Photo category = the question's section in the question list (Start, Exterior, Paint, Tires, Underbody, Interior, Mechanicals, OBDII, Additionals), not the camera pass. Underbody photos are taken in the Underbody pass and stored as Underbody; damage photos at underbody places (Structure, Rust, Exhaust, Suspension, Driveshaft or CV, Brakes, Battery pack) are Underbody; scan tool and EV screen photos are OBDII; paint meter photos are taken in the Exterior pass but stored as Paint; a damage photo at a body panel with a paint problem is Paint; VIN, odometer and keys photos are Additionals.

**2.4 VIN**: read by AI from the windshield VIN photo and the door-jamb label, check digit checked, confirmed by the inspector on the Summary. If a VIN was typed at New inspection and differs, show a red chip on the Summary. No blocking.

**2.5 360 view**: the phone cuts 36 evenly spaced frames from the walk-around and saves them with the inspection. Review shows them as a drag-to-turn viewer, offline too. Frames 1, 5, 10, 14, 19, 23, 28, 32 fill the 8 exterior photo slots; the roof photo fills its own slot. The dealer report uses the same frames.

**2.6 Tracking**: per inspection: inspector, start and end time, time on site, photo count, time from signature to report sent.

**2.7 Documents**: license, registration and family proof are photographed at Check ID, stored privately, never on a report.

**2.8 AI photo reading** (`docs/04-ai-reading.md`)
- Every photo is read as soon as it is taken or uploaded (when online; queued when offline); the result fills its field; the inspector confirms or changes it on Review or Summary:
  - Mileage: odometer photo (`ph_odo`)
  - VIN: windshield VIN photo and door-jamb label, check digit
  - Tires: brand and size from the whole tire photo, tread from the gauge photo
  - Paint meter mils per panel: 8 mils or more is High and ticks Panel repainted
  - EV battery health %: battery health screen
  - Number of keys 0, 1, 2: keys photo (`ph_keys`)
  - Damage photos: place, type, severity as first guess
- The AI guess and the confirmed value are both sent (`ai_first_guess`).
- Upright: every photo is turned upright before reading and storing. Camera shots use the device orientation at capture; library uploads without orientation get an AI upright check. Save `upright_turn_deg` (0, 90, 180, 270).

**2.9 Issue catalog**: `data/issue-catalog.json` (78 places, 319 place and type pairs, 56 check-only options). Every record is checked against it before the report is made; anything not in it is refused with the reason.

**2.10 Condition report**: made automatically on receipt by `tools/cr_from_inspection.py`, then rendered as the seller and dealer reports (`docs/05-reports.md`) and emailed.

## Done when

- An inspection is started with YMMT only and finished typing only engine codes, corrections and the note.
- A car with no problems needs no taps on checks.
- Start stays off until both documents are photographed and the owner question is answered.
- One camera pass covers every section; the only stops are the end-of-section dialogs.
- The walk-around becomes a 360 view; eight of its frames are exterior photos.
- Every damage photo has a place, type and severity.
- Show the seller stays off until every section is reviewed and every required answer is in.
- The seller cannot sign without ticking the disclosure.
- An inspection done fully in airplane mode uploads in full when signal returns.
- Within 2 minutes of upload, the report email arrives with both links; the seller report has no guarantee wording; neither report shows the documents or the light.
