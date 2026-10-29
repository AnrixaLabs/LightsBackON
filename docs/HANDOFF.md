# Handoff: how to run Lights Back On with Claude Code (cloud first, then local)

Prepared 29 Oct 2026 from Development Blueprint v1.0. **Since 30 Oct 2026 work runs in local Claude Code desktop sessions (ADR-015);
use prompt P7.** Sections 1-6 describe the original cloud-first plan and stay as history.
**Git is the shared memory** between cloud and local sessions: the backlog status, `docs/evidence/`, ADRs and the code are what carry over.
Conversations do not.

## 1. Do this once, before the first Claude Code session (about 30 minutes, you, not Claude)

1. **Put the project files in `C:\LightsBackOn`** (unzip the handoff pack there; it only adds files).
2. **Add the blueprint package** (the PDF alone is not the whole package; the PDF refers to files that were not in it):
   - `docs/blueprint/` : the PDF plus `README.md`, `02-Implementation-Backlog.json`, `03-...md`, `04-...md`, `05-...json`, `06-...md`, `design/*.png`
   - `reference/` : the Python reference model, its `tests/` and `data/first_shift.json`, unchanged
   If you do not have these, say so in the first session; Claude Code will not invent them.
3. **Decide repo visibility.** `AnrixaLabs/LightsBackON` looked public (it can be cloned anonymously) and is currently empty. The blueprint contains the
   commercial plan. Claude Code on the web works with private repos through the GitHub connection, so making it private costs nothing.
4. `git add -A && git commit -m "Add blueprint, handoff pack and tooling" && git push -u origin main`. **Cloud sessions only see what is on GitHub**; an empty repo gives them nothing.
5. **Connect GitHub to Claude Code on the web** (claude.ai/code onboarding with the Claude GitHub App, or `/web-setup` from a terminal that has `gh`),
   then create/keep the **Default** environment with **Trusted** network access. No setup script is needed; the repo's SessionStart hook installs Godot.
6. **Local tools (needed later, not for the first cloud sprint):** Git for Windows (Git Bash), Git LFS (`git lfs install`), Python 3, Godot 4.7.2 standard
   Windows build (console exe is handy), Claude Code CLI signed in with the **same claude.ai account** (required for `--teleport`), Steam client.
7. **For the Steam gate (F02/F06) you will need:** a second PC on a different network, a second Steam account, and a Steamworks account. These are
   human tasks. The cloud sprints deliberately do not depend on them.

## 2. Things in the blueprint Claude Code must resolve or watch

| # | Issue | Handling |
|---|---|---|
| 1 | Package files (reference model, tests, JSON/MD files) are referenced but not in the PDF. G01's acceptance ("equivalent to the reference") and Day 5 need the Python oracle. | Step 1.2. If absent, re-derive from the C01 table in `CLAUDE.md`, label it "re-derived, not the original oracle", and tell the owner. |
| 2 | Blueprint lists modules as `autoload/`, `network/`... and also lists root dir `scripts/`; `content/` appears as both a root dir and a module. | ADR-001: modules under `scripts/`, `content/` at root, `project.godot` at repo root. |
| 3 | "Trip at 1.5 continuous seconds" with 10 Hz evaluation; floats would drift. | ADR-003: integer PU, integer ticks (15), one canonical serialization and hash shared with the Python reference. |
| 4 | Blueprint names `kargames/SteamMultiplayerPeer` and says no compatible pairing is established. As of 29 Oct 2026: GodotSteam 4.20 shipped alongside Godot 4.7 (24 Jun 2026); GodotSteam's own MultiplayerPeer has been folded into the main GDExtension; the separate ExpressoBits SteamMultiplayerPeer conflicts in class registration with newer GodotSteam (GodotSteam advises 4.16.2 or earlier if combining them). | F02 tests candidates in this order and pins whichever passes the real two-network test: (A) current GodotSteam GDExtension with its built-in peer; (B) ExpressoBits peer + GodotSteam 4.16.2 or earlier for lobbies; (C) the peer named in the blueprint. Export with the normal Godot templates (not GodotSteam templates) for the GDExtension. Record every source revision and binary hash. |
| 5 | Extraction cancel: C01 says "any player can cancel" the 5 s countdown; MIS04 says leaving the zone cancels. | Support both; decide in V02 and record in an ADR. |
| 6 | F01 acceptance says "imports and exports"; Day-1 proof says "imports and **launches**". | Follow the stricter one: F01 stays CLOUD_VERIFIED until an exported Windows build has launched on your PC. |
| 7 | Backlog hours total 982 (532 engineering, 302 art/UI, 148 QA/product) against a stated capacity of 1,080 engineering + 720 art/UI. The art/UI backlog covers well under half of its capacity and the asset register is large (11 kit pieces, 18 locations, props, 12 animation clips, 24 icons, 18 sound families). | Treat art/UI hours as the least reliable estimate. Record actual hours after every milestone and replace the 36-week baseline with measured velocity after the slice. One person at 30 h/week is about 60 weeks for the full 1,800 h (blueprint section 12). |
| 8 | Some "known solution" sequences depend on exact tie-switch ordering (C08 notes a possible one-tick phantom dual supply). | Write that transition test explicitly when C08 is authored (CT05). |

## 3. Which work happens where

| Milestone | Cloud (Linux, headless) | Local (your Windows PC) | Needs people / accounts |
|---|---|---|---|
| **F** Foundation | F01 scaffold, import, manifest, input actions; F03/F04/F05 logic drafts | F01 launch check, **F02 Steam spike**, F04 offline/reconnect, **F06 two-PC gate** | second PC, second Steam account |
| **G** Grid toy | **G01-G06 fully**; G07 draft | promote to DONE (rerun on Windows); G07/G08 on real peers | none |
| **V** Playable slice | V02, V08, logic for V03-V06 | V01 graybox, V07 UI, V09 ten runs | testers for V06 |
| **A** Validation | A03, parts of A04/A06 | A01, A02 | **A05 outside study, A07 owner decision** |
| **D** Demo | D02/D03 logic, strings pipeline | D01, D04, D05, D06 | D07 20 sessions, D08 Steamworks |
| **C** Content | contract data, validator, solution traces, CT07, CT09 | kits, art, animation | CT10 gate |
| **H, B, R** | save/reward hardening (H01, H02) | profiling, Cloud, controller, accessibility | QA matrix, Steam review, release |

Credit-burning plan: **F01 (cloud part), G01, G02, G03, G04, G05, G06** are the large block that can be completed without your PC. After G06 the
cloud has nothing unblocked except drafts (F03, F04, F05, G07), and everything after depends on your local gates. When `backlog.py next --env cloud`
says there is nothing left, stop spending cloud credits.

## 4. Session prompts (copy, paste, send)

Every prompt assumes `CLAUDE.md` is loaded automatically. Keep prompts short; the rules live in the repo, not in the chat.

### P0: Bootstrap and audit (run once; best on your PC in `C:\LightsBackOn`, or in a cloud session after step 1.4)

```
Read CLAUDE.md and docs/HANDOFF.md section 2. Do NOT write game code in this session.

1. Audit: git status/remote/branches; list what exists in the repo root; check whether docs/blueprint/ and reference/ contain the blueprint
   package (names in HANDOFF 1.2). Report exactly what is missing. Do not recreate missing package files.
2. Run `python3 tools/backlog.py validate` and `bash tools/run_tests.sh` (set GODOT_BIN if needed; project.godot does not exist yet, so Godot tests skip).
   If reference/tests exists run it and report the real result.
3. Write short ADRs in docs/adr/: ADR-001 repo layout (HANDOFF issue 2), ADR-002 git flow (main = integration, PRs only, tags gate-F, gate-G...,
   task branches task/<ID>-slug), ADR-003 integer PU + integer ticks + canonical serialization (issue 3).
4. Report toolchain: git, git-lfs, python, Godot version/path, claude version, Steam client present. Install nothing without telling me first.
5. Commit on branch bootstrap, push, open a PR. Finish with a status report of at most 25 lines: present, missing, and what I (the human) must do next.
```

### P1: Cloud sprint A (F01 cloud part, G01, G02, G03)

```
Cloud sprint A. Follow CLAUDE.md section 6 exactly. Work autonomously; ask only for a stop-and-ask item.
Order: F01 (cloud part), then G01, G02, G03, using `python3 tools/backlog.py next --env cloud` to confirm each.

F01: project.godot at repo root (4.7, Compatibility renderer), folder tree with .gdignore in docs/ tools/ reference/ art_source/, input actions from
blueprint section 6 (keyboard/mouse and controller defaults, all remappable), tools/build_manifest.py writing build_manifest.json with the
fields on blueprint p.41, a Windows export preset with no credentials. Verify a clean-checkout headless import. Try a Windows export only if the
templates download is practical here; otherwise leave it to my PC. Set F01 CLOUD_VERIFIED with pending_local: "launch exported Windows build; record hash".
G01: scripts/simulation/power_grid.gd as pure typed GDScript (no scene tree, no autoloads), data from content/ JSON for C01. Tests SIM01, SIM02,
SIM03 (static), SIM05, SIM06, SIM07, SIM08, SIM11. Add tools/cross_check_reference.py that evaluates the C01 cases with the Python reference
and with Godot and compares canonical hashes (skip with a clear message if reference/ is absent).
G02: 10 Hz tick, integer overload counter, trip at 15 consecutive overloaded ticks, reset validation. Tests SIM04, SIM08, SIM09, SIM10.
G03: unknown vs measured readings and the meter/evidence model. Test: an uninspected panel never reports a false zero.

Per task: tests, evidence file, backlog.py set, PR. Commit and push after each task. Stop after G03, or earlier if context is above about 70%,
after writing Resume notes. Do not start Steam, art, audio or UI work.
```

### P2: Cloud sprint B (G04, G05, G06, then drafts)

```
Cloud sprint B. Same rules as sprint A. Confirm the next task with `backlog.py next --env cloud`.
G04: interaction and repair state machine, locks (one owner, release on cancel/out of range/disconnect/2 s heartbeat timeout),
isolation preconditions, durable cancel, one replacement consumed exactly once. Test with fake clients at logic level (NET01, NET02 logic parts).
G05: generator placement anchors, route toggles, 6 PU source, unsafe source tie refused before mutation. Tests: pump OR pub works, both overload.
G06: versioned save skeleton per CLAUDE.md section 5, simulated kill during write, truncated file, newer schema (SAVE01-SAVE03 at logic level).
Then, only if I have not said stop: the drafts F03, F04, G07 behind transport_adapter.gd using an offline/ENet development transport.
Drafts may reach CLOUD_VERIFIED at most. Never claim Steam transport results. Stop when `next --env cloud` returns nothing.
```

### P3: Local Steam spike (F02, then F03/F04 acceptance, F06)

```
Local session on my PC. Goal: F02. I will provide the second PC and Steam account. Read blueprint pp.3, 9-10, 15, 16-17 first.
Prepare, do not fake: build the minimal private-lobby create/join spike (tests/manual/ or tools/) for candidate A (see HANDOFF issue 4), record
extension source revision and binary hashes, write the exact checklist I must follow on the second PC, and wait for my results.
A localhost or same-network run is a smoke test only and must be labeled that way. If A fails, move to B, then C, recording each failure.
Do not commit Steam app IDs, SDK files or credentials (use private/ and steam_appid.txt, both ignored). When the tuple passes on two accounts on separate real
networks, write docs/evidence/F02.md, pin the tuple in the manifest, then do the local acceptance for F03/F04 and the F06 gate. Stop at the F gate.
```

### P4: Local promotion pass (after cloud sprints, once)

```
Sync and promote. git fetch, switch to main, merge the reviewed PRs. Run `bash tools/run_tests.sh` on Windows. Export and launch the Windows build (F01).
For each CLOUD_VERIFIED task shown by `backlog.py next --env local`, re-run its checks on this machine, update its evidence file, and set DONE
in dependency order. Anything that still fails stays CLOUD_VERIFIED or becomes BLOCKED with a reason. Report differences between Linux and Windows results.
```

### P5: Gate report (end of every milestone)

```
Gate report for milestone <letter>. List the gate's required evidence from blueprint section 12 and the acceptance matrix, link each evidence file,
state pass/fail/not-run per item, list open risks, record actual engineering and art/UI hours against the estimate, and propose the next estimate.
Do not start the next milestone. Wait for my decision.
```

### P6: Short "continue" prompt (every later session)

```
Continue Lights Back On. Follow CLAUDE.md section 6: run `python3 tools/backlog.py next --env <cloud|local>`, read the Resume notes of any IN_PROGRESS task,
do the next task, and stop at the first stop condition.
```

### P7: Local desktop session (current default, ADR-015)

```
Continue Lights Back On locally. Follow CLAUDE.md section 6: run `python tools/backlog.py next --env local`, ignore "parked" tasks,
read the Resume notes of any IN_PROGRESS task, do the first actionable task on a branch cut from origin/main, run `bash tools/run_tests.sh`,
write the evidence file, open a PR, and stop at the first stop-and-ask item.
```

## 5. When cloud credits run out (or any time you move to your PC)

Nothing needs migrating; the repo is the memory.
1. Cloud sessions can end at any time, so CLAUDE.md requires a push after each logical step and Resume notes in the evidence file. Check claude.ai/code
   for the last branch that session pushed.
2. On your PC: `git fetch --all`, review and merge the PRs (or `git switch` to the branch), `git lfs pull` if art exists, then `bash tools/run_tests.sh`.
3. To continue the *same conversation* locally: `claude --teleport` (or `/teleport`) from a clean checkout of the same repo, same claude.ai account, with the
   session's branch pushed. The terminal gets its own copy; new work there does not appear in the cloud session.
4. Otherwise start a fresh local session with prompt P6, then run P4 once.
5. From then on, local sessions use the identical loop; you may still use `claude --cloud "<prompt>"` for cloud-suitable tasks when you have capacity.

## 6. Spending credits well

- Cloud usage counts against your plan/credits, and parallel sessions consume proportionally more. The G chain is mostly sequential, so run **one session at a time**.
- One session = one to three tasks. Use `/clear` between tasks. Never ask Claude to read the whole PDF; CLAUDE.md gives page ranges.
- Use a stronger model for the authoritative-logic tasks (G01, G02, G04, later V04) and a lighter one for scaffolding, docs and data (`/model <name>` works in cloud sessions).
- No art, audio, trailer or store work in the cloud. Keep test output short (the runner prints one line per test).
- Tell it to stop rather than guess: ambiguity goes in an ADR, not in a long chat.
