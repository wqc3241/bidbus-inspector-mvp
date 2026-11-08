# CLAUDE.md

You are building the **Bidbus Field inspector app (DEV-190, phase 1)** end to end, as a home build that Tom tests on his own iPhone. This file is the entry point. Read it fully, then `docs/` in number order, before writing code.

## Goal

An inspector opens the app on an iPhone, starts an inspection by typing year, make, model and trim, does the whole inspection in one camera pass, labels damages, reviews every section, gets the seller's signature and sends it. The backend (Railway) checks the record, builds the condition report, and emails a **seller report link** and a **dealer report link** to the email address entered for that inspection.

## Differences from the company version

| Company version | This build |
|---|---|
| Cars to inspect: search synced listing leads | New inspection form: year, make, model, trim (required); VIN, mileage, owner name optional; fuel type required (prefilled from the VIN decode when a VIN is typed); report email required |
| Car brief with seller portal documents and Carfax | No car brief, no Carfax, no points to check. Check ID photographs the driver's license and registration on site |
| Text the seller an upload link | Removed |
| VIN match to a listing, Unmatched queue | Removed. The VIN read from the photo is compared with the typed VIN (chip only) |
| CR shown in the seller portal and dealer portal | Backend makes two report pages (seller, dealer) and emails both links |
| Bidbus staff login | One app passcode (`APP_PASSCODE`) and an inspector name in Settings |

Everything else follows DEV-190 exactly: question list, one camera pass, Damage and Mod shutters, AI readings, Damages labelling, Review, Summary, disclosure and signature, offline-safe upload, issue catalog validation, CR generation.

## Stack (decided)

- **app/**: installable web app (PWA). Vite + React + TypeScript. Runs in iPhone Safari and from the home screen. Camera via `getUserMedia` (rear camera, full screen), video via `MediaRecorder`. All state and media saved in IndexedDB (use Dexie) as they are taken; an upload queue sends them when online.
- **server/**: Python 3.12, FastAPI, SQLAlchemy, Postgres. Media files on a Railway Volume. `ffmpeg` cuts the 36 frames of the 360 view. Reuses `tools/cr_from_inspection.py` as a module. Serves the built app at `/`, the API at `/api`, reports at `/r/...`.
- **AI**: Anthropic API vision (Claude) for readings and the damage first guess (`docs/04-ai-reading.md`).
- **VIN decode**: NHTSA vPIC (free, no key).
- **Email**: Resend.
- **Deploy**: one Railway project, one service built from `Dockerfile` at the repo root, plus Postgres and a Volume (`docs/07-deploy-railway.md`).

## Sources of truth

| What | File |
|---|---|
| Product requirements | `docs/01-product-spec.md` |
| Every screen and its rules | `docs/02-screens.md` |
| Clickable reference of every screen (open in a browser, press Build notes for notes per screen) | `reference/mockup/internal-mvp.html` |
| Reference source code of that mockup (camera order, labelling logic, `inspectionPayload`) | `reference/mockup/src/template.html` |
| Questions, options, levels, damage places | `data/question-list.json` (never hardcode questions; render from this file) |
| Every allowed place, type, check option, level | `data/issue-catalog.json` |
| Record the app sends | `docs/03-data-contract.md`, `samples/inspection-*.json` |
| CR generation | `tools/cr_from_inspection.py`, output `samples/cr-*.json` |
| Seller and dealer reports | `docs/05-reports.md`, reference page `reference/condition-report/condition-report.html` |
| Camera guide outlines | `guides/svg`, `guides/png` |

When the mockup and a doc differ, the doc wins. When `docs/` and `data/question-list.json` differ on a question or option, the question list wins.

## Rules

- All UI text, code comments and docs in English.
- Build only what the specs ask for. No helper text, tips or extra UI elements on screens.
- Every check starts as OK. One problem per check.
- The seller never sees anything about dealer protection, guarantees or buybacks.
- The driver's license, registration and family proof are private: never on a report.
- The condition report light is computed and stored, never shown on either report.
- No secrets in the repo. Keys come from environment variables (`.env.example`).
- Keep the record shape identical to `samples/inspection-*.json` so `tools/cr_from_inspection.py` runs unchanged.

## Build order

Follow `docs/09-build-plan.md`. Each milestone ends with its checks passing. Commit after each milestone.

## Commands

```
# reference mockup (rebuild after a question list change)
python3 reference/mockup/build.py
# CR generator on a sample
python3 -I tools/cr_from_inspection.py samples/inspection-bmw-x3.json /tmp/cr.json
# regenerate the issue catalog from the mockup (needs Node + Playwright)
node verify/issue-catalog.js
```
