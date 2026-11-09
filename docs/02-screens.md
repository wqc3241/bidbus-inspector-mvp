# 02 Screens

Open `reference/mockup/internal-mvp.html` in a desktop browser to click through every screen; Build notes shows the notes for the screen on show. Still images of each screen: `reference/field-phases/bidbus-field-phases.html` (phase 1, UI 1.1 to 1.7) and `reference/inspection-journey/inspection-journey.html` (2.1 to 2.9). Build the screens below; where the mockup shows Cars to inspect, Car brief, Carfax, points to check or Text the seller an upload link, use this file instead.

## Style

Use the mockup's final style (end of the `<style>` block in `reference/mockup/src/template.html`):
- White page. Cards only for photos, document images, the tire frame, the paint diagram, the bottom sheet and the bottom button.
- Sections split by thin lines. Spacing: 16 px side gutter, 20 between sections, 12 heading to content, 8 label to content.
- Same-kind lists are full-width rows alternating white and `#f5f5f5`, no dividers. The choice drawer keeps dividers.
- Icons: Lucide (`reference/mockup/assets/lu.js`); logo `reference/mockup/assets/logo.html`.
- Icon first, little text.

## Inspections (home)

- Rows of this phone's inspections, newest first: car, VIN, status (In progress, Saved on phone, Uploading, Report sent, Visit ended).
- Tap a row: In progress reopens where it stopped; Report sent shows the Sent screen.
- New inspection button. Settings (inspector name, passcode, default report email).

## New inspection

- Fields: VIN (optional), Year, Make, Model, Trim, Fuel type, Mileage (optional), Owner name (optional), Report email.
- Home build: Year, Make, Model and Trim are lists from `data/vehicles.json` (Honda, Toyota, Lexus, Tesla, VinFast, BMW, Mercedes-Benz, model years 2013 to 2027; each trim with its first and last model year), each ending with Other to type the value. A decoded VIN picks the entry it matches, otherwise fills Other.
- VIN of 17 characters: call `GET /api/vin/{vin}` (server proxies NHTSA vPIC `DecodeVinValues`) and prefill year, make, model, trim, fuel type. Fuel mapping: Electric → Electric (EV); Plug-in Hybrid Electric Vehicle (PHEV) → Plug-in hybrid; Hybrid (HEV) or Strong/Mild HEV → Hybrid; else Diesel when the primary fuel is Diesel, otherwise Gas. Offline: skip the decode.
- Bottom button At the car: check ID, off until the required fields are in.

## Check ID

- License and registration cards: Take photo, camera only (no pick from library). Private.
- Owner question (`id_owner`): Yes; Family, with proof (opens a photo for `ph_family`); No ends the visit (status Visit ended, end time and GPS recorded).
- Start inspection: off, with the reason, until both photos are in and the answer is Yes or Family with proof. Records start time and GPS, opens the camera.

## Camera

- Landscape, full screen; form screens stay portrait. Top bar: section (1/6 to 6/6) and shot count.
- Three shutters on the right: Damage (amber, above), the shot (big, middle), Mod (blue, below). Damage and Mod take a tagged photo without moving the flow; off on videos and in OBDII. Zoom chips .5 / 1 / 2 and pinch where the device allows.
- A guide outline (`guides/svg`) and the shot name over the camera; the camera moves on after each shot.
- Skip only on optional shots; Not on this car for a missing paint panel.
- Back goes one shot back. A taken shot can be retaken or deleted; the camera then returns to where the inspector was. Damage and Mod thumbnails can be picked and deleted.
- Order:
  - **Exterior**: walk-around video (engine off, up to 60 s, from the left front corner, counter-clockwise); one paint meter photo per panel: left front fender, left front door, left rear door, left quarter panel, trunk or liftgate, right quarter panel, right rear door, right front door, right front fender, hood, roof; roof photo; windshield VIN; then the end-of-section dialog.
  - **Tires & Wheels** LF, LR, RR, RF: whole tire, tread gauge.
  - **Interior**: door-jamb VIN, odometer (car on, warning lights visible), all keys, dash, infotainment screen (on), front seats, rear seats, cargo.
  - **OBDII**: gas: current, past and emission code screens, other images (several, optional). EV: service-mode alerts, battery health and charging screens (optional).
  - **Mechanicals**: engine bay (EV: frunk), engine oil on the dipstick, engine sound and exhaust videos (gas and hybrid, up to 30 s each, hidden when the engine will not start).
  - **Underbody**: underbody LF, LR, rear, RR, RF, front, catalytic converters (optional). A damage or mod shutter here makes a Mechanicals damage or mod.
- A slot that takes several photos stays open: each shot adds one, Remove photo N drops the last, Done · N moves on.
- Every section but OBDII ends with the end-of-section dialog ("Please record any … damage/modification images before proceeding.", I'm done or Record damage now; `docs/01-product-spec.md` 1.4).
- Photos are taken 4:3 with the whole sensor, and the preview shows the whole frame, so .5, 1 and 2 frame what the iPhone camera's .5, 1 and 2 frame. Videos are 16:9 1080p.
- Flash chip above the zoom chips (and in the damage camera's top bar): Auto (the default; fires when it is dark), On, Off, tap to go round; kept while the camera is open; hidden on video slots.
- If the camera is closed, a screen lists the sections with counts and reopens the camera where it stopped.
- After the last shot: Damages (or Review when there are no damage photos).
- The exact shot list per fuel comes from the question list (`kind: photo` and `video` items with their `cars`). The mockup's `CAPSEQ`, `capList` and `MULTI` show the order logic.

## Damages

- Every damage photo, one per screen, section by section (Exterior, Tires & Wheels, Paint, Interior, Mechanicals, Underbody). A strip of the sections with damage photos at the top: a section opens only when every section before it is labelled (shut ones show light and take no tap), and the pages stop at the last photo of the open sections. After a label the next photo to label on the same section comes first, then the first one still to label; deleting a photo stays on its section. Underbody holds the damages at underbody places, and unplaced ones taken or added there; placing one at an engine bay place moves it to Mechanicals, and the other way round.
- AI first guess of place, type and severity from that section's list; confirm or change.
- Place on a picture: Exterior is a top view of the car (each part named; side windows and rear glass are their own places; a mirror, headlight or tail light is picked on its side, left or right, and only that side shows as picked) plus tiles for other lights, wipers, fuel door, other. Paint: top view of the 11 panels. Tires & Wheels: the four wheels, each with Tire and Wheel. Interior: Cabin (seat plan, headliner, carpet, sunroof, other) and Features tabs. Mechanicals: Engine bay (Frunk on an EV) and Underbody tabs.
- Places and their types come from `damage_places` in the question list.
- Type from that place's list; severity required; size 1-36 in optional. The label drawer takes at most half the screen: the types scroll (with a scroll bar), severity, size and Done stay in view under them. A labelled photo ticks its check (or answers sunroof or navigation); relabelling or removing takes that back.
- Moves on when place, type and severity are picked. Swipe for next or previous. Retake and Remove on the photo. Review turns on when every photo is confirmed or labelled.

## Review

- One page per section: Start, Exterior, Tires & Wheels, Paint, Interior, OBDII, Mechanicals, Underbody, with Next. Underbody has the underbody photos, damages and the Structure and frame, Rust and Battery pack (EV) checks.
- One row per check, OK by default; tap opens a drawer with OK and its problems (one per check), plus panel, wheel or codes when needed. Problems show amber or red by level.
- Photos, then damages, then mods, as tiles. Tap a photo to retake; tap a damage to relabel, retake or remove; Add a damage takes a photo or an upload, then the label form.
- Section strip pinned at the top, the same look as the Damages strip (no numbers, no tick, no underline; the current section's whole cell grey): problem count, or needs something; tap to jump. While the page is unfinished the tabs after it are shut (light, no tap): a tab opens only when every page before it is complete, and tabs up to the current one stay open.
- Exterior: the 360 view tile after Walk-around; tap opens it in a bottom sheet.
- Paint: a top view of the car with each panel and its mils (High in red; a panel with no reading yet has the red frame); tap a panel to set its reading on a slider from 3.0 to 10+ mils, with - and + for 0.1 (10+ is more than 10), or to mark N/A; then panel photos, paint damage tiles, the Paint and panels row. A High reading ticks Panel repainted with that panel.
- Tires & Wheels: four wheel cards (LF, LR, RR, RF; a card has the red frame until that wheel's tread depth is in), each with photos, damages and values in scroll pickers; the Match or Mismatch question.
- Interior: number of keys first (0 red, 1 amber), sunroof and navigation (Works, Not working, No sunroof / No navigation; required, no default).
- OBDII: Engine codes stored asks for the codes in a second drawer step.
- Mechanicals: road test starts as Not done.
- Next stays off, with the reason, until the page is complete.

## Summary

- Counts: Photos, Videos, Problems and Damages (damage photos); every problem with its level and every damage, listed section by section (in Review order, each under its section heading).
- VIN and mileage read from the photos, editable. Chips: door-jamb match, typed VIN match, check digit, typed mileage. Confirm needs a 17-character VIN that passes the check digit and a mileage; any edit clears the confirm.
- Overall condition (Like new, Pretty great, Just okay, Kind of rough, Major issues), required. Inspector note, required.
- Show the seller: off, with the reason, until every section is reviewed, every shot is in, every damage photo is labelled and every required answer is in. Unreviewed sections show as buttons.

## Seller signs

- Findings in plain words, section by section like the Summary.
- Disclosure: the inspection records what our inspector could see and test at the visit, without lifting the car or taking it apart; it describes the car at that time and is not a warranty; Bidbus is not responsible for problems that appear later or could not be seen or tested; the seller has told us every problem they know of.
- Tick "I have read and agree to this disclosure"; Sign stays off until ticked.
- Name (filled from the owner name, editable) and a signature pad under "I have seen the inspection findings for this car."
- Saved: signature, name, disclosure version and agreement, end time and GPS.
- Nothing about dealer protection, guarantees or buybacks.

## Sent

- Saved on phone → Uploading (progress per part) → Report sent.
- Report sent: "Report sent to {email}", Open seller report, Open dealer report, start and end time, location, Resend email.
- A small bar on every screen shows when there is no signal.
