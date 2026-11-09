# 09 Build plan

Work in this order. Each milestone ends when its checks pass; commit after each.

## M1 Skeleton and deploy

- `app/` (`flutter create --org com.yourname --platforms ios,android app`, packages from `docs/10-flutter-app.md`), `server/` (FastAPI), `Dockerfile`, `railway.json`, `docker-compose.yml`, `.env.example`.
- Server `/api/health` on Railway. App Settings screen saves the server URL and passcode and shows the health result.
- Check: the app runs on the iPhone and on an Android phone (or emulator) and reaches the Railway server.

## M2 Question list engine

- Bundle `data/question-list.json` as an asset (synced by script). Helpers: items per section and fuel (`cars`: all, gas, ev, plug-in, hybrid), checks with default OK, levels.
- State model per inspection in drift (SQLite) with media files in the documents folder: answers, photos (path + meta), damages, tires, paint, features, signature, times, GPS, phase.
- Check: unit tests list the same items per fuel as the mockup (compare counts with `verify/allq-report.json`).

## M3 Inspections, New inspection, Check ID

- Screens per `docs/02-screens.md`; VIN decode via `/api/vin/{vin}`.
- Check: Start stays off until both documents and the owner answer are in; No ends the visit.

## M4 Camera pass

- Full-screen landscape camera, three shutters, zoom, guides, Back/retake/delete, skip optional, multi-photo slots, video recording with max length, end-of-section dialog (every section but OBDII), closed-camera resume screen.
- Saves each JPEG upright to the documents folder and drift at capture; cuts the 36 spin frames after the walk-around.
- Check: on the iPhone and on Android, a full pass for gas and for EV in about 15 minutes, nothing lost after killing the app mid-pass.

## M5 AI readings

- `/api/ai/read` per `docs/04-ai-reading.md`; app queue; Read from photo marks.
- Check: odometer, VIN, tread, paint meter, keys and a damage photo read correctly on real photos; offline photos get read once online.

## M6 Damages, Review, Summary, Sign

- Damages labelling with place pictures from `damage_places`, check ticking (port `syncDamages`, `dshort` logic from the mockup), Review pages with drawers, tires pickers, paint diagram, keys row, 360 view, Summary gates, disclosure and signature pad.
- `inspectionPayload` ported; the record for a scripted run equals the shape of `samples/inspection-*.json`.
- Check: every rule in `docs/02-screens.md`; `python3 -I tools/cr_from_inspection.py` on an exported record gives `validation ok`.

## M7 Upload and backend pipeline

- Upload queue (record first, then files three at a time, resume), endpoints, Postgres models, media on the Volume, spin frames, `build_cr`, status polling on the Sent screen.
- Check: airplane-mode run uploads in full; a duplicate send updates the same inspection.

## M8 Reports and email

- Seller and dealer pages per `docs/05-reports.md`; Resend email; resend button.
- Check: the five test runs in `docs/08-phone-testing.md` pass on the iPhone and once on Android; `flutter test` and the pytest suite in `docs/06-backend.md` pass.
