# Bootstrap audit (prompt P0), 29 Oct 2026

Environment: Claude Code cloud session (Linux x86_64, headless). No game code written.

## Repository
- `AnrixaLabs/LightsBackON` was empty (no branches). First commit on `main` = the handoff pack exactly as delivered.
- Bootstrap work (ADRs, this report, CLAUDE.md pointer to ADR-004) is on a `claude/...` branch with a PR into `main`.

## Blueprint package: present vs missing
| Item (HANDOFF 1.2) | State |
|---|---|
| `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf` (46 pages) | present |
| `docs/blueprint/README.md` | **missing** |
| `docs/blueprint/02-Implementation-Backlog.json` | **missing** (the 66 tasks are transcribed in `docs/backlog.json`) |
| `docs/blueprint/03-Screen-Specifications.md` | **missing** (summary only: PDF pp. 22-24) |
| `docs/blueprint/04-Acceptance-Test-Matrix.md` | **missing** (summary only: PDF pp. 37-39) |
| `docs/blueprint/05-Content-and-Asset-Manifest.json` | **missing** (register: PDF pp. 40-41) |
| `docs/blueprint/06-Contract-Design-Sheets.md` | **missing** (summary only: PDF pp. 18-21) |
| `docs/blueprint/design/*.png` | **missing** (low-res copies are PDF pp. 42-46) |
| `reference/` Python model, `reference/tests/`, `reference/data/first_shift.json` | **missing** |

None of these were recreated. Consequence for G01: unless the owner adds `reference/`, the oracle is re-derived from the C01 table
in CLAUDE.md section 3 and PDF pp. 6-7, labelled "re-derived, not the original oracle".

## Checks run
- `python3 tools/backlog.py validate` -> `OK: 66 tasks`. Summary: 66 tasks, 0 DONE, 0 CLOUD_VERIFIED.
- `bash tools/run_tests.sh` -> backlog OK; Python reference skipped (`reference/tests` absent); Godot skipped (no `project.godot`, F01). `ALL CHECKS PASSED`.
- Runner self-check: copied `tests/` into a throwaway project with a minimal `project.godot` and ran
  `godot --headless --path . -s res://tests/run_tests.gd` -> `tests: 2 passed, 0 failed, 3 assertions`, exit 0.
- `python3 tools/backlog.py next --env cloud` -> F01 (split), F03 (split, ceiling CLOUD_VERIFIED).

## Toolchain (cloud)
| Tool | Result |
|---|---|
| git | 2.43.0 |
| git-lfs | installed (`/usr/bin/git-lfs`) |
| python | 3.13.17 |
| Godot | 4.7.2.stable.official.ed1daf0bf via `tools/setup_godot_linux.sh` (SHA512 verified) at `~/.local/godot/4.7.2-stable/godot` |
| Claude Code | 2.1.312 |
| Steam client | not present (expected in cloud) |

The local Windows toolchain (HANDOFF 1.6) has not been checked; that needs a session on the owner's PC.

## Decisions written
ADR-001 repo layout, ADR-002 git flow, ADR-003 integer PU / ticks / canonical state, ADR-004 visual and UI quality bar (owner direction).

## Owner actions
1. Add the missing package files and `reference/` if you have them (HANDOFF 1.2). Otherwise G01 re-derives the oracle.
2. Decide repo visibility (HANDOFF 1.3): the PDF contains the commercial plan.
3. Local toolchain and the Steam gate prerequisites (HANDOFF 1.6, 1.7) before F02/F06.
