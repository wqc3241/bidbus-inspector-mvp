# 08 Testing on the iPhone

The camera needs HTTPS, so test on the Railway URL (or a tunnel), not on `http://` LAN addresses.

## On Railway

1. Open `https://{your-app}.up.railway.app` in Safari on the iPhone.
2. Share → Add to Home Screen. Open it from the home screen (full screen, no Safari bars).
3. Settings: inspector name, the `APP_PASSCODE`, default report email.
4. Allow camera, microphone and location when asked. If refused once: iPhone Settings → Safari → Camera / Microphone / Location → Allow (or Settings → the web app).

## Against a local server

- `cloudflared tunnel --url http://localhost:8000` (or `ngrok http 8000`) and open the https URL it prints on the phone.
- Vite dev server with hot reload: run `vite --host` behind the same tunnel and proxy `/api` and `/r` to the local server.

## Test runs

1. **Clean car**: start with YMMT only, take every shot, no damage, accept every OK, sign. Expect the email with two links within 2 minutes; Highlight all green; every row No issues.
2. **Damages**: take 3 Damage shots (one at a paint panel, one at a tire, one inside), 1 Mod shot. Check the AI first guess, relabel one, confirm all. Expect each damage in its section on both reports with its photo.
3. **Airplane mode**: turn it on after New inspection, finish the whole inspection, sign. Status Saved on phone. Close the app. Turn airplane mode off, reopen. Expect Uploading then Report sent with nothing missing.
4. **EV**: fuel Electric (EV). Engine bay, engine sound and exhaust are gone; EV OBDII shots and charging items show; Engine sound row is absent on the dealer report.
5. **Seller check**: open the seller report and search the page for protection, guarantee, buyback: none.

## Desktop checks

- Playwright on the built app with a fake camera: Chromium flags `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream`, viewport 844×390 for camera screens and 390×844 for forms. Script the clean-car run end to end against a local server and assert the email payload (mock Resend) and both report pages.
