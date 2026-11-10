# 04 AI photo reading

The phone sends each photo to `POST /api/ai/read` as soon as it is taken (queued while offline). The server calls the Anthropic Messages API with the image and returns one JSON reading. The app fills the field and marks it Read from photo; the inspector confirms or changes it. The AI value is kept beside the confirmed value (`*_read_from_photo`, `ai_first_guess`).

## Server call

- SDK: `anthropic` (Python). Key `ANTHROPIC_API_KEY`; model `AI_MODEL`, default `claude-sonnet-5-5`.
- Home build: when `OPENAI_API_KEY` is set, the readings use OpenAI instead (Chat Completions with a strict JSON schema per kind, same fields and rules; model `OPENAI_MODEL`, default `gpt-5.5`).
- One request per photo: the image (JPEG, long side resized to 1568 px) as a base64 image block, then a short instruction for its kind.
- Force structured output with one tool per kind and `tool_choice: {"type": "tool", "name": ...}`. Parse the tool input; validate it against the rules below; anything out of range becomes null.
- Timeout 20 s. On error return `{ "ok": false }`; the app leaves the field for the inspector to fill.

## Kinds

| `kind` | Photo (question id) | Tool output | Rules |
|---|---|---|---|
| `odometer` | `ph_odo` | `{ mileage: int \| null }` | 0 to 999999; ignore trip meters |
| `vin` | `ph_vin_dash`, `ph_vin_door` | `{ vin: str \| null }` | 17 characters, no I, O, Q; server checks the check digit (`vin_ok` in `tools/cr_from_inspection.py`) and returns `check_digit_ok` |
| `tire` | `tire_photo` | `{ brand: str \| null, model: str \| null, size: str \| null }` | brand from the North American brand list in the mockup (`TIRE_BRANDS`); model = the tire line name on the sidewall; size `WWW/AARDD`, width 165-355, aspect 15-85, rim 13-25. After the fourth tire the app sets All 4 tires match: same brand and model on all four = Match, else Mismatch |
| `tread` | `tread_photo` | `{ tread_32nds: int \| null }` | 1 to 14 |
| `paint_meter` | `paint` (per panel) | `{ mils: number \| null }` | 0 to 99.9, one decimal; convert microns to mils (÷ 25.4) when the meter shows µm; server sets `high` at 8 or more |
| `ev_battery` | `ph_ev_battery` | `{ health_pct: int \| null }` | 1 to 100 |
| `keys` | `ph_keys` | `{ keys_count: 0 \| 1 \| 2 }` | 2 means two or more |
| `damage` | Damage shutter photos | `{ place, type, severity }` | place and type must come from the list sent in the request (below); severity Minor, Moderate or Severe |
| `upright` | library uploads without orientation | `{ turn_deg: 0 \| 90 \| 180 \| 270 }` | how far to rotate clockwise so the car, label or screen is upright |

## Damage first guess

- The app sends `section` and `fuel`. The section is the zone of the shot the Damage shutter was pressed at (docs/11): a paint panel, the roof photo or the windshield VIN Exterior, a tire Tires, cargo and the Interior shots Interior, Mechanicals; an underbody shot sends `Underbody`. In Record damage it is the zone of the section's last shot. The AI picks the place from every place of that section, not only the shots around it.
- A damage photo taken from Review for one wheel sends `hint` (that wheel's tire) instead.
- The server builds the allowed list from `data/issue-catalog.json` `places` for that section and fuel: each place with its allowed types. It sends this list in the instruction and requires the answer to be one of its pairs.
- With a `hint`, the place defaults to the hint; the AI picks type and severity.
- A pair not in the list is dropped to `{place: hint or null, type: null, severity: null}`.

## Damage dots on the 360 view (server, `app/hotspots.py`)

- `locate_parts`: one request per spin frame that can show a damaged part (a window of frames round the frame facing that part). The instruction says how the walk-around goes and where the camera is in that frame; for each damaged part the answer is `visible` and its middle as `x`, `y` from 0 to 1000. A frame seen alone is dropped when the part is seen in more than two frames; each point is the median of itself and its neighbours.
- `damage_side`: for a place with no side (Mirror, Headlight, Tail light, Fuel door) and no Left or Right picked by the inspector (`where`), the damage photo answers `left`, `right` or `unknown`; unknown gets no dot.

## Upright photos

- Camera shots: bake the EXIF orientation written by the camera into the pixels before saving; record `upright_turn_deg` as the rotation applied (`docs/10-flutter-app.md`).
- Library uploads: bake EXIF orientation when present; otherwise call `kind: upright` and rotate by the result.
- Every stored photo is upright; the record keeps the turn.

## Cost

About 25 photo readings plus one guess per damage photo per car; no reading for interior, exterior or underbody overview shots (they have no field to fill).
