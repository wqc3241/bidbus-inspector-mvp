# 11. Camera flow (mockup 1109)

The camera follows `reference/mockup-1109/internal-mvp.html` (source `reference/mockup-1109/src/template.html`: `CAMLAYOUT`, `WALK`, `CAMRUN`, `LOOK`, `ASKMOVE`, `askRows`). This file overrides the camera parts of docs 01, 02 and 04 where they differ. Review pages, Damages, Summary, the record and the CR stay as they are.

## Order

Five camera sections. Top bar: section 1/5 to 5/5 and shot count.

| # | Section | Shots |
|---|---|---|
| 1 | Exterior | Windshield VIN; 360 walk-around video (engine off, from the left front corner, counter-clockwise) |
| 2 | Interior | Door-jamb VIN; front seats; rear seats; odometer (car on); engine sound at the first start (gas, hybrid); all keys; dash; infotainment; then OBDII: gas current, past and emission code screens, other images (optional); EV service alerts, battery health, charging (optional) |
| 3 | Walk-around | From the left front, counter-clockwise: left front fender paint; left front tire and tread gauge; left front door; left rear door; left rear tire and tread gauge; left quarter panel; trunk or liftgate; cargo (floor up); right quarter panel; right rear tire and tread gauge; right rear door; right front door; right front tire and tread gauge; right front fender; hood; roof paint; roof photo |
| 4 | Mechanicals | Engine bay (EV: frunk, charge port); engine oil; exhaust video (idle, revving, reverse gear) |
| 5 | Underbody | LF, left middle, LR, rear, RR, right middle, RF, front, catalytic converters (optional); EV battery pack |

- Each shot keeps its home section from the question list: paint photos show on Review Paint, tires on Tires & Wheels, cargo on Interior, roof photo and windshield VIN on Exterior, OBDII shots on OBDII, engine sound on Mechanicals. Photo category is unchanged.
- A retake from a Review page opens the camera at that shot.
- Damage and Mod shutters: off on videos and on OBDII shots. A damage photo takes the zone of the shot it was taken at: paint panel or roof Exterior, tire Tires, cargo Interior. A mod at a tire is a Tires mod, elsewhere in the Walk-around an Exterior mod.
- Underbody corner guides (LF, LR, RR, RF): one camera from that side of the car, in the gap beside the wheel (`guides/svg` and `guides/png` `ph_under_{lf,lr,rr,rf}` and their `-ev` versions updated; copy them to `app/assets/guides/`).
- Underbody middle guides (left middle, right middle): one camera straight in from the middle of that side, between the wheels (`ph_under_{lm,rm}` and their `-ev` versions). All cars.

## Look for

Top left of every guided shot, a few words. Information only: nothing to tap, tick or save.

| Shot | Look for |
|---|---|
| Windshield VIN | Clear photo, Full VIN visible |
| 360 walk-around | Move smoothly |
| Door-jamb VIN | VIN label, Jamb repaint, Spot welds |
| Front seats | Seats, Windows, Seat belts, Airbag covers |
| Rear seats | Seats, Windows, Odor, Flood signs |
| Odometer | Warning lights, Total miles, Dash cracks |
| Engine sound | Hard start, Knock, Rough idle, Smoke |
| All keys | All keys, Key works |
| Dash | Dash cracks, A/C cold, Heat, Warning lights |
| Infotainment | Screen, Audio, Cameras, Navigation |
| Current codes | Engine codes |
| Past codes | Cleared codes |
| Emission codes | Not ready |
| Other images (OBDII) | Airbag faults, ABS faults |
| Front fenders (paint) | Repaint, Fender bolts, Panel gaps, Dents |
| Front doors (paint) | Frame damage, Repaint, A-pillar, Window |
| Rear doors (paint) | Frame damage, Repaint, B-pillar, Window |
| Quarter panels (paint) | Repaint, Dents, Panel gaps, Fuel door |
| Trunk or liftgate (paint) | Repaint, Tail lights, Panel gaps, Rear window |
| Hood (paint) | Repaint, Hood bolts, Chips |
| Roof (paint) | Repaint, Dents, Hail |
| Roof photo | Dents, Hail, Sunroof |
| Whole tire | Sidewall cracks, Bulge, Curb rash, Plug or patch |
| Tread gauge | Lowest groove, Uneven wear |
| Cargo | Trunk floor, Rails, Water, Spare tire |
| Engine bay | Aprons, Strut towers, Core support, Leaks |
| Engine oil | Sludge, Milky oil, Oil level |
| Exhaust | Rev noise, Smoke, Reverse gear |
| Frunk (EV) | Coolant, Water, Damage |
| Charge port (EV) | Scorched pins, Latch |
| Underbody corners and middles | Leaks, Rust, Frame rails, Kinks |
| Underbody rear | Rear rails, Exhaust, Leaks |
| Underbody front | Core support, Subframe, Leaks |
| Catalytic converters | Missing converter, Cut pipe |
| Battery pack (EV) | Scrapes, Dents, Bolts |

EV service alerts and battery health screens have no Look for.

## End-of-section questions

After the last shot of Interior, Walk-around, Mechanicals and Underbody (not Exterior), a dark card over the camera lists questions from the Review pages. They are the same answers as on Review: each check shows OK until tapped; required rows (keys, sunroof, navigation, tires match) show Pick until answered. A tap opens the same answer drawer as Review, drawn dark over the camera like the card. Buttons: Record damage (the camera stays with only the Damage and Mod shutters and Next at the top right) and Next: the next section.

| After | Questions |
|---|---|
| Interior | Interior (keys, sunroof, navigation and the Interior checks); OBDII checks; Mechanicals: Transmission and clutch (gas) |
| Walk-around | Exterior checks; Mechanicals: Brakes; Paint: Paint and panels; each wheel: Tire, Wheel; All 4 tires match |
| Mechanicals | Mechanicals checks without Transmission and clutch, Brakes, Exhaust and emissions, Suspension and steering, Driveshaft and CV joints |
| Underbody | Underbody checks; Mechanicals: Leaks (gas), Exhaust and emissions (gas), Suspension and steering, Driveshaft and CV joints |

Leaks shows after both Mechanicals and Underbody (one answer). Review Mechanicals still lists every Mechanicals check.

## All 4 tires match (AI)

- After the fourth whole-tire photo the AI answers it: same brand and same model on all four tires is Match, otherwise Mismatch. Size does not count.
- The row shows Read from photo; the inspector can change it (then it is no longer marked).
- The `tire` reading adds `model` (the tire line name on the sidewall, or null). The record adds `tires_match_read_from_photo` (true when the sent answer is the AI's).
- The app finding for a Mismatch reads "Tires do not match (brand or model)".
