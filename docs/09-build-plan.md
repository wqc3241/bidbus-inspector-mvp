# 09 Build plan

Work in this order. Each milestone ends when its checks pass; commit after each.

## M1 Skeleton and deploy

- `app/` (Vite + React + TS, PWA manifest and service worker via `vite-plugin-pwa`), `server/` (FastAPI), `Dockerfile`, `railway.json`, `docker-compose.yml`, `.env.example`.
- Server serves `app/dist` at `/` with SPA fallback, `/api/health`.
- Check: deployed on Railway; the iPhone opens it from the home screen.

## M2 Question list engine

- Load `data/question-list.json` into the app at build time. Helpers: items per section and fuel (`cars`: all, gas, ev, plug-in, hybrid), checks with default OK, levels.
- State model per inspection in IndexedDB (Dexie): answers, photos (blob + meta), damages, tires, paint, features, signature, times, GPS, phase.
- Check: unit tests list the same items per fuel as the mockup (compare counts with `verify/allq-report.json`).

## M3 Inspections, New inspection, Check ID

- Screens per `docs/02-screens.md`; VIN decode via `/api/vin/{vin}`.
- Check: Start stays off until both documents and the owner answer are in; No ends the visit.

## M4 Camera pass

- Full-screen landscape camera, three shutters, zoom, guides, Back/retake/delete, skip optional, multi-photo slots, video recording with max length, end-of-Exterior dialog, closed-camera resume screen.
- Saves each JPEG upright to IndexedDB at capture.
- Check: on the iPhone, a full pass for gas and for EV in about 15 minutes, nothing lost after killing the app mid-pass.

## M5 AI readings

- `/api/ai/read` per `docs/04-ai-reading.md`; app queue; Read from photo marks.
- Check: odometer, VIN, tread, paint meter, keys and a damage photo read correctly on real photos; offline photos get read once online.

## M6 Damages, Review, Summary, Sign

- Damages labelling with place pictures from `damage_places`, check ticking (port `syncDamages`, `dshort` logic from the mockup), Review pages with drawers, tires pickers, paint diagram, keys row, 360 view, Summary gates, disclosure and signature pad.
- `inspectionPayload` ported; the record for a scripted run equals the shape of `samples/inspection-*.json`.
- Check: every rule in `docs/02-screens.md`; `python3 -I tools/cr_from_inspection.py` on an exported record gives `validation ok`.

## M7 Upload and backend pipeline

- Upload queue (record first, then files one at a time, resume), endpoints, Postgres models, media on the Volume, spin frames, `build_cr`, status polling on the Sent screen.
- Check: airplane-mode run uploads in full; a duplicate send updates the same inspection.

## M8 Reports and email

- Seller and dealer pages per `docs/05-reports.md`; Resend email; resend button.
- Check: the five test runs in `docs/08-phone-testing.md` pass on the iPhone; pytest suite in `docs/06-backend.md` passes.
