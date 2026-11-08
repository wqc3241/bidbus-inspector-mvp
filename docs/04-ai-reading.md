# 04 AI photo reading

The phone sends each photo to `POST /api/ai/read` as soon as it is taken (queued while offline). The server calls the Anthropic Messages API with the image and returns one JSON reading. The app fills the field and marks it Read from photo; the inspector confirms or changes it. The AI value is kept beside the confirmed value (`*_read_from_photo`, `ai_first_guess`).

## Server call

- SDK: `anthropic` (Python). Key `ANTHROPIC_API_KEY`; model `AI_MODEL`, default `claude-sonnet-5-5`.
- One request per photo: the image (JPEG, long side resized to 1568 px) as a base64 image block, then a short instruction for its kind.
- Force structured output with one tool per kind and `tool_choice: {"type": "tool", "name": ...}`. Parse the tool input; validate it against the rules below; anything out of range becomes null.
- Timeout 20 s. On error return `{ "ok": false }`; the app leaves the field for the inspector to fill.

## Kinds

| `kind` | Photo (question id) | Tool output | Rules |
|---|---|---|---|
| `odometer` | `ph_odo` | `{ mileage: int \| null }` | 0 to 999999; ignore trip meters |
| `vin` | `ph_vin_dash`, `ph_vin_door` | `{ vin: str \| null }` | 17 characters, no I, O, Q; server checks the check digit (`vin_ok` in `tools/cr_from_inspection.py`) and returns `check_digit_ok` |
| `tire` | `tire_photo` | `{ brand: str \| null, size: str \| null }` | brand from the North American brand list in the mockup (`TIRE_BRANDS`); size `WWW/AARDD`, width 165-355, aspect 15-85, rim 13-25 |
| `tread` | `tread_photo` | `{ tread_32nds: int \| null }` | 1 to 14 |
| `paint_meter` | `paint` (per panel) | `{ mils: number \| null }` | 0 to 99.9, one decimal; convert microns to mils (÷ 25.4) when the meter shows µm; server sets `high` at 8 or more |
| `ev_battery` | `ph_ev_battery` | `{ health_pct: int \| null }` | 1 to 100 |
| `keys` | `ph_keys` | `{ keys_count: 0 \| 1 \| 2 }` | 2 means two or more |
| `damage` | Damage shutter photos | `{ place, type, severity }` | place and type must come from the list sent in the request (below); severity Minor, Moderate or Severe |
| `upright` | library uploads without orientation | `{ turn_deg: 0 \| 90 \| 180 \| 270 }` | how far to rotate clockwise so the car, label or screen is upright |

## Damage first guess

- The app sends `section`, `fuel` and, when the Damage shutter was pressed during a paint panel shot or a tire shot, `hint` (the panel or wheel).
- The server builds the allowed list from `data/issue-catalog.json` `places` for that section and fuel: each place with its allowed types. It sends this list in the instruction and requires the answer to be one of its pairs.
- With a `hint`, the place defaults to the hint; the AI picks type and severity.
- A pair not in the list is dropped to `{place: hint or null, type: null, severity: null}`.

## Upright photos

- Camera shots: the app knows the device orientation at capture (screen orientation and the video track settings) and rotates the canvas before saving the JPEG; record `upright_turn_deg` as the rotation applied.
- Library uploads: apply EXIF orientation when present (`createImageBitmap(file, { imageOrientation: "from-image" })`); otherwise call `kind: upright` and rotate by the result.
- Every stored photo is upright; the record keeps the turn.

## Cost

About 25 photo readings plus one guess per damage photo per car; no reading for interior, exterior or underbody overview shots (they have no field to fill).
