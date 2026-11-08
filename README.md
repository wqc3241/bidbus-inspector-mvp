# Bidbus Field inspector app (home build)

Build kit for the DEV-190 inspector app: a Flutter mobile app (iOS and Android) for on-site car inspections, with a Railway backend that builds the condition report and emails a seller report link and a dealer report link.

Start a Claude Code session in this folder and say: **"Read CLAUDE.md and build the app, milestone by milestone."**

## What is here

| Path | Contents |
|---|---|
| `CLAUDE.md` | Entry point for Claude Code: goal, stack, rules, build order |
| `docs/` | Product spec, screens, data contract, AI reading, reports, backend, Railway deploy, phone testing, build plan, Flutter app |
| `data/` | Question list and issue catalog |
| `tools/cr_from_inspection.py` | Condition report generator |
| `samples/` | Two inspection records (gas, EV) and their condition reports |
| `guides/` | Camera guide outlines (SVG, PNG) |
| `reference/mockup/` | Clickable mockup of every screen (`internal-mvp.html`) and its source |
| `reference/condition-report/` | Seller and dealer report reference page and its source |
| `verify/` | Mockup test scripts (Node + Playwright) |

## You supply

A Railway account, an Anthropic API key and a Resend API key (`docs/07-deploy-railway.md`); a Mac with Xcode and a free Apple ID to install on the iPhone, Android Studio for Android (`docs/08-phone-testing.md`). No keys are stored in this repo.

Sample cars and people are made up.
