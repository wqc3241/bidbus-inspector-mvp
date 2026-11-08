# 06 Backend

Python 3.12, FastAPI, SQLAlchemy 2 + Alembic, Postgres, Uvicorn. Code in `server/`. One process serves the API and the reports.

## Layout

```
server/
  app/main.py          FastAPI app, routes
  app/db.py            engine, session, models
  app/storage.py       media on disk under MEDIA_DIR/{inspection_id}/
  app/ai.py            Anthropic readings (docs/04-ai-reading.md)
  app/vin.py           NHTSA vPIC proxy
  app/cr.py            wraps tools/cr_from_inspection.py
  app/spin.py          ffmpeg fallback for spin frames
  app/reports.py       seller and dealer pages (Jinja2)
  app/email.py         Resend
  templates/           report templates
  migrations/          Alembic
  tests/
  requirements.txt
```

## Auth

Every `/api` call carries `Authorization: Bearer {APP_PASSCODE}`; wrong or missing → 401. Reports under `/r/{token}` need no auth.

## Tables

- `inspections`: `id` (UUID from the phone), `inspector`, `report_email`, `car` (JSON: year, make, model, trim, owner_name), `record` (JSON, the inspection record), `status` (receiving, building, sent, failed), `report_token`, `cr` (JSON, generator output), `validation_errors` (JSON), `files_expected` (int), `created_at`, `signed_at`, `report_sent_at`.
- `files`: `inspection_id`, `name`, `size`, `content_type`, `sha256`, `received_at`.

## API

| Method and path | Does |
|---|---|
| `GET /api/health` | `{ok: true}` |
| `GET /api/vin/{vin}` | vPIC `DecodeVinValues/{vin}?format=json` → `{year, make, model, trim, fuel}` |
| `POST /api/ai/read` | multipart `kind`, `image`, optional `section`, `fuel`, `hint` → reading JSON |
| `PUT /api/inspections/{id}` | body `{report_email, inspector, car, record}`; creates or replaces; returns the list of file names still missing |
| `PUT /api/inspections/{id}/files/{name}` | raw bytes; idempotent (same name replaces); returns missing files |
| `POST /api/inspections/{id}/complete` | called when nothing is missing; starts the build in a background task; 409 with the missing list otherwise |
| `GET /api/inspections/{id}` | status, report links when sent, validation errors |
| `POST /api/inspections/{id}/resend-email` | sends the email again |
| `GET /r/{token}/seller`, `GET /r/{token}/dealer` | report pages |
| `GET /r/{token}/media/{name}` | photo, video or spin frame; never documents or the signature |

Uploads: allow up to 200 MB per file (walk-around video). Use chunked streaming to disk; do not read whole files into memory.

## Build pipeline (on complete)

1. `status = building`.
2. Spin frames come from the phone. Fallback only when `spin-01.jpg` to `spin-36.jpg` are missing: 36 evenly spaced `ffmpeg -ss {t} -i video_360.* -frames:v 1 -vf scale=1600:-2` seeks.
3. CR: refactor `tools/cr_from_inspection.py` minimally to expose `build_cr(record: dict, carfax_owners=None) -> dict` and keep its CLI. The CLI output for both samples must stay byte-identical to `samples/cr-*.json` (test it). Call `build_cr(record)`.
4. `validation.ok` false → `status = failed`, store the errors, send the failure email.
5. Otherwise make `report_token`, store `cr`, send the email, `status = sent`, `report_sent_at = now`.

## Media rules

- Documents (`ph_license`, `ph_reg`, `ph_family`) and `signature.png` are stored but never served by `/r/...`.
- Serve photos with `Cache-Control: private, max-age=86400`; video with HTTP range support (FastAPI `FileResponse` handles Range).

## Tests

- `pytest`: the two samples go through `build_cr` with `validation.ok` true; CLI output equals `samples/cr-*.json`; a record with an unknown place is refused with its reason; report pages render for both samples and contain no license, registration, signature or light text; the seller page contains none of "protection", "guarantee", "buyback" (case-insensitive).
