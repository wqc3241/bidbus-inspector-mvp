# Condition report page: build

The condition report page (`condition-report.html`) is built from the Internal MVP question list (the same file the inspector app is built from).

**Build**

```
python3 build.py base-v24.html ../../data/question-list.json condition-report.html
```

**Files**
- `app.js`: the page: inspection answers, seller report and dealer report, with one example inspection for a gas car and one for an EV.
- `extra.css`: styles added on top of the shared ones.
- `base-v24.html`: the earlier report page. The build takes the shared styles, icons, car drawings and damage-map positions from it.
- `build.py`: puts the page together. It checks that every example answer is an option of its check, and that every dealer checklist line in the question list points at an item that exists.

**Report levels** come from the question list: Ends the visit and Not listed until fixed give Not listed; Red gives a Red light; Yellow gives Yellow; Disclosed is listed without changing the light. Tread at 4/32 or less is listed as replace, 5 to 8/32 as fair, 9/32 and up as good (the same tiers the seller app shows).

**Highlight** (seller and dealer reports): four items. Structural damage: Yes when the inspector recorded a Structure damage or a Structure and frame problem, No otherwise (Not checked when the frame could not be photographed). Keys: the number of keys (0, 1 or 2), read by AI from the keys photo and confirmed by the inspector on Review. Odor: OK or the odor picked. Mechanical: Issue when any Mechanicals check has a problem or a damage was recorded in Mechanicals, No issue otherwise.

**Bidbus Inspection** (seller and dealer reports): one block per inspection section. Each line uses the exact words of the inspector app: a check problem reads "Check: problem" (tires and wheels as "Tire: problem" and "Wheel: problem", one line per wheel), with the part, wheel or codes below; a recorded damage reads "Place: Type, Severity, N in" with its photo, under the section it was recorded in. There is no separate Damages section.

**Photo and video viewer** (seller and dealer reports): photos and videos are one list, grouped by inspection section (Exterior, Paint, Tires, Underbody, Mechanicals, Interior, OBD-II, Additionals). Videos sit in the section they show: the walk-around in Exterior, the engine and exhaust sound in Mechanicals. The group chips sit below the thumbnail row; All is the default. Each finding's close-up is in its check's section, and each damage photo is in the section it was recorded in. The seller's driver's license and registration photos are private and never shown.
