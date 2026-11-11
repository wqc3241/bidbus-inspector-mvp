# 12. Scheduler sync

The app signs inspectors in with their inspection scheduler account (hyc492/inspection-scheduler, Supabase), lists their booked jobs, shows a car brief from Bidbus admin data, and starts the inspection filled in. Plan: Inspection Scheduler MVP Plan (Claude Doc `7dY1ei6KsNgkixvxpXkbt8`).

## Modes

| Server env | App |
|---|---|
| `SUPABASE_URL` and `SUPABASE_ANON_KEY` set | Scheduler sign-in. Every `/api` call carries the inspector's Supabase access token. Passcode and Inspector name are hidden. |
| Not set | App passcode (`APP_PASSCODE`) and Inspector name, as before. |

The app asks `GET /api/health` (`auth: "team"`) at start and when the server URL changes.

## Setup

1. Scheduler: add the two `bidbus-field-mark-done` commits (migration `0006_field_app_mark_done.sql` with `mark_slot_done`, and the rule that a job's own inspector can't set its Listing ID) and run 0006. Until 0006 runs, jobs are not marked done; nothing else breaks.
2. Railway (server): set `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the scheduler's public anon key), `SCHEDULER_URL` (the scheduler site, for its team-list email check), `BIDBUS_ADMIN_PHONE`, `BIDBUS_ADMIN_PASSWORD` (one Bidbus admin service account; the phone in any format, sent as its 10 digits). `BIDBUS_API_URL` defaults to `https://api.bidbus.com`.
3. Deploy. The server runs migration `0002_scheduler` at start.
4. Each inspector signs in once on the scheduler site with their email. That links their team-list row; the app then accepts the same email.

Who may sign in: an active scheduler member with role inspector or admin.

## Sign-in

| Call | Does |
|---|---|
| `POST /api/auth/code {email}` | Scheduler email check, then Supabase emails a code |
| `POST /api/auth/verify {email, code}` | Returns `access_token`, `refresh_token`, `expires_at`, `member {id, name, email}` |
| `POST /api/auth/refresh {refresh_token}` | New tokens. The app renews when less than 10 minutes are left |

The session is kept in the phone's secure storage. A refused sign-in (401 for a token that has not run out), a 403 (taken off the team list) or a server that stops using scheduler sign-in signs the app out and deletes the jobs, briefs and documents on the phone.

## Jobs

`GET /api/appointments`: the signed-in inspector's booked and done jobs, today to today + 7 (Los Angeles). Each job has `key` (`slot_id@booked_at`), date, time, status, seller name and phone, address, ZIP, map point, vehicle, VIN, mileage, notes, `vehicle_id` (the scheduler's Listing ID = Bidbus vehicle ID).

The app refreshes on open, on pull and every 5 minutes. A job no longer listed stays as Cancelled until its day is over; its brief and documents are deleted. Briefs and documents for today's and tomorrow's jobs are saved on the phone for use without signal. A brief is kept per booking: when an hour is booked again for another car, the old one is deleted.

## Car brief

`GET /api/appointments/{slot_id}/brief`: `{appointment, vehicle, bidbus, fuel, vin_differs}`.

- The Bidbus car is found by the booking's 17-character VIN alone (`GET /api/admin/vehicles?vehicle_query=<VIN>`, VIN read as Bidbus stores it: I, O, Q as 1, 0, 0). With several Bidbus cars on that VIN: the one the Listing ID names, else the newest. No Listing ID is needed.
- `vehicle` (from `GET /api/admin/vehicles/:id`): car, photo, owner name and registered owner, seller documents, seller photos, Carfax (owners, accident, title, frame damage, total loss, airbag, odometer, service records, recall), checks.
- `bidbus`: `ok`, `none` (no Bidbus account on the server), `not_found` (no 17-character VIN on the booking, or no Bidbus car with that VIN) or `error` (the app keeps the last brief it had for the same booking). `vin_differs` is always false.
- `fuel`: from the booking VIN's decode, only when vPIC gives it.

`GET /api/appointments/{slot_id}/documents/{document_id}`: one of that car's documents (license, registration) as a photo; a PDF comes as one JPEG of its first 3 pages, each at most 1600 px. Each call is logged with the inspector's email. Private: never on a report. Deleted from the phone once that car's report is sent.

## Inspection

Start inspection on the brief opens New inspection filled in (VIN, year, make, model, trim, mileage, owner name, fuel). The inspection keeps the appointment; the record's `source.listing_id` is the Bidbus vehicle ID. The server stores `member_id`, `slot_id`, `booked_at`, `vehicle_id` and lets only that inspector change it. The phone shows, opens and uploads an inspection only while the inspector who started it is signed in.

When the report is sent, the server calls `mark_slot_done` once: the job turns Done on the scheduler if it is still the same booking (`skipped` when it was cancelled or rebooked). A call that fails is tried again on the next calls for 2 days.
