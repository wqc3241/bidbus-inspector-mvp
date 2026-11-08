# 05 Seller and dealer reports

The server renders two HTML pages from `condition_report` (output of `tools/cr_from_inspection.py`) and emails both links.

- Seller report: `GET /r/{token}/seller`
- Dealer report: `GET /r/{token}/dealer`
- `token`: 32 random URL-safe characters per inspection; no login. Media inside the pages load from `/r/{token}/media/{file}`.

Look and layout: `reference/condition-report/condition-report.html` and, for the dealer side, `reference/dealer-screens/dealer-screens.html`; the seller report as one screen: `reference/inspection-journey/inspection-journey.html` (3.2) (open it in a browser; the Seller and Dealer phones). Its code is `reference/condition-report/app.js` (`sellerHTML`, `dealerHTML`, `highlights`, `gallery`, `media`, `tireCells`) and `extra.css`. Port that markup and CSS into server-side templates (Jinja2) fed by real data. Mobile first, works on desktop.

## Both reports

- **Header**: year make model trim, mileage, inspection date.
- **Photo and video viewer**: one strip of every photo and video, grouped by inspection section: Exterior, Paint, Tires, Underbody, Mechanicals, Interior, OBD-II, Additionals. Group chips below the strip; All is the default. The walk-around sits in Exterior, engine sound and exhaust in Mechanicals. Each damage photo is in the section it was recorded in. Tap opens full screen with swipe.
- **360 view**: the 36 spin frames in js-cloudimage-360-view (`https://cdn.jsdelivr.net/npm/js-cloudimage-360-view@3`, pin an exact version), first in the Exterior group.
- **Highlight** (first block after the viewer): four items from `condition_report.highlight`:
  - Structural damage: Yes, Not checked, or No
  - Keys: 0, 1 or 2
  - Odor: OK or the odor problems
  - Mechanical: Issue or No issue
- **Tires**: per wheel LF, RF, RR, LR: tread /32 with tier (Replace 4 and below, Fair 5-8, Good 9 and up), brand and size, that wheel's tire, wheel and brake issues.
- **Bidbus Inspection**: one block per CR row in this order: Exterior, Paint, Tires, Underbody, Mechanicals, Engine sound (not for EVs), Interior, OBD-II, Additionals. Each issue line is the issue's `text`, with `sub` below. Each damage shows in its row with its photo thumbnail and text. A row with no issues reads "No issues". There is no separate Damages section.
- **Never shown**: the light or any grade; driver's license, registration, family proof; GPS; the signature image.

## Seller report only

- Breadcrumb "Dashboard › Condition report".
- Issue lines without level tags.
- Closing block, three rows with green icons: More accurate price, Same-day payment, Less back-and-forth with dealers.
- Nothing about dealer protection, Purchase Protection, guarantees or buybacks.

## Dealer report only

- Title "Vehicle details".
- Tabs: Condition, Tires, Inspection, Specs (scroll to section).
- Condition: overall condition, then a Purchase Protection badge when eligible, then one banner per Not listed, Red or Yellow issue (worst first, issue `text`), then the Highlight.
  - Purchase Protection: none when the light is Not listed, or the car is older than 2011, or the mileage is 150,000 or more; "Title, odometer, legal" (limited) when the light is Red; otherwise "Purchase Protection".
- Issue lines carry a level tag for Red, Yellow and Not listed.
- "No issues · N checks" on rows without issues.
- Engine sound row (gas and hybrid): play buttons for the engine sound and exhaust videos and the Engine check result.
- Videos row, and Inspector's note row.
- Specs: VIN, year, make, model, trim, odometer, fuel, keys, battery health (EV).
- No auction fields (starting bid, auction time, Auto Bid).

## Email

Sent by Resend once the report is built.

- To: the inspection's report email. From: `EMAIL_FROM`.
- Subject: `Condition report: {year} {make} {model} {trim}`
- Body (HTML and text): the car line, mileage, inspection date, two buttons Seller report and Dealer report with the links.
- On validation failure: subject `Condition report not made: {car}` with the validation reasons.
- `POST /api/inspections/{id}/resend-email` sends it again.
