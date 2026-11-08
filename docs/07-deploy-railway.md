# 07 Deploy on Railway

One new Railway project with three parts: the app service (this repo), Postgres, and a Volume for media.

## Files to add to the repo

- `Dockerfile` at the root: `python:3.14-slim`, `apt-get install -y ffmpeg`, `pip install -r server/requirements.txt`, copy `server/`, `tools/`, `data/`. Start: `alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT` (working dir `server/`). The Flutter app is not part of the server image.
- `railway.json`:
  ```json
  { "$schema": "https://railway.com/railway.schema.json",
    "build": { "builder": "DOCKERFILE", "dockerfilePath": "Dockerfile" },
    "deploy": { "healthcheckPath": "/api/health", "restartPolicyType": "ON_FAILURE" } }
  ```

## Steps (Railway dashboard)

1. New Project → Deploy from GitHub repo → `wqc3241/bidbus-inspector-mvp`.
2. In the project: New → Database → PostgreSQL.
3. App service → Variables: add `DATABASE_URL` as a reference to `${{Postgres.DATABASE_URL}}`, plus the variables below.
4. App service → right-click → Attach Volume, mount path `/data`.
5. App service → Settings → Networking → Generate Domain. Copy it into `PUBLIC_BASE_URL`.
6. Redeploy. Open `https://{domain}/api/health`.

CLI alternative: `npm i -g @railway/cli`, `railway login`, `railway init`, `railway add --database postgres`, `railway variables --set KEY=VALUE`, `railway up`.

## Variables

| Name | Value |
|---|---|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| `MEDIA_DIR` | `/data/media` |
| `PUBLIC_BASE_URL` | `https://{your-app}.up.railway.app` (used in email links) |
| `APP_PASSCODE` | any long random string; typed once in the app Settings together with the server URL |
| `ANTHROPIC_API_KEY` | your Anthropic key |
| `AI_MODEL` | `claude-sonnet-5-5` |
| `RESEND_API_KEY` | your Resend key |
| `EMAIL_FROM` | `Bidbus Field <onboarding@resend.dev>` until you verify a domain |

Railway sets `PORT`. Keep the same names in `.env.example` for local runs.

## Email sender

Resend's test sender `onboarding@resend.dev` only delivers to the email address of your Resend account. To send to any address, add and verify a domain in Resend (Domains → Add, then the DNS records it lists) and set `EMAIL_FROM` to an address on it.

## Local run

```
docker compose up        # Postgres + the app on http://localhost:8000, reading .env
```
Add a `docker-compose.yml` with `postgres:16` and the app built from the Dockerfile, media in a named volume.
