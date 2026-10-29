# Lights Back On: project brief for Claude Code

A Windows/Steam game in which 1-4 players (or one) restore a storm-damaged neighborhood by diagnosing and repairing an
abstract power network. Godot 4.7.2 (standard, not .NET), typed GDScript. Owner: Levon (Anrixa).
Repo: github.com/AnrixaLabs/LightsBackON. Local checkout: `C:\LightsBackOn`.

**State today:** planning only. Blueprint v1.0 (27 Oct 2026) exists; no game code is verified. Current progress is
whatever `python3 tools/backlog.py summary` says, not what this file says.

## 0. Where the truth lives (read order)

1. This file: locked decisions, exact rules, working protocol.
2. `docs/blueprint/` : the Development Blueprint PDF and, if present, the package files (`02-Implementation-Backlog.json`,
   `03-Screen-Specifications.md`, `04-Acceptance-Test-Matrix.md`, `05-Content-and-Asset-Manifest.json`,
   `06-Contract-Design-Sheets.md`, `design/*.png`). The Python reference model lives in `reference/`.
3. `docs/backlog.json`: the 66 ordered tasks (transcribed from blueprint section 4) plus status. Use `tools/backlog.py`.
4. `docs/adr/`: decisions that deviate from or clarify the blueprint. A silent deviation is a bug.
5. `docs/HANDOFF.md`: session prompts and the cloud/local runbook.

Do not read the whole PDF each session. It is 46 pages; read only the pages a task needs (Read tool, `pages` parameter):
master blueprint 3-17 (decisions 3, pillars/C01 pacing 4, contract list 4-5, Alder layout 5-6, **power rules 6-7**, controls 8,
co-op 9, modules and **host authority/save contract 9-11**, UI/art/audio 11-12, economy 12, roadmap/gates 13-14, build/QA/Steam 14-15,
risks/cut order 15-16, references 16-17); contract sheets C01-C12 18-21; screens S01-S12 22-24; backlog 25-36; acceptance matrix 37-39;
asset register 40-41; the five 1920x1080 UI references 42-46.

Evidence labels in the blueprint: VERIFIED PLATFORM FACT, DESIGN DECISION, TARGET (test it), ESTIMATE (not a guarantee).
All gameplay numbers are design choices until measured.

## 1. Locked decisions (do not re-litigate; changing one needs the owner)

Solo + 1-4 online players, friends-only Steam lobbies first. First person, visible tool and gloved hands. Windows x64,
keyboard/mouse and controller. Godot 4.7.2 standard, **typed GDScript**, **Compatibility renderer** baseline. Stylized 3D,
modular 4 m kit, warm restored windows against cool rain. Three compact districts x six service locations x four contracts = 12
contracts (C01-C12). Demo = Alder Street C01 with its tutorial. Premium purchase (proposed US $12.99, validate after demo).
Host owns the campaign world; every participant keeps personal completion and reward receipts; credits are personal.
All essential tools are available from the start; upgrades are sidegrades/convenience. No death/revive loop; failures are recoverable.

**Out of scope for v1.0:** open-world driving (a depot loading transition replaces it), public matchmaking, host migration,
simulated rope physics, terrain deformation, real fluid simulation, procedural city generation, NPC schedules, combat,
custom online backend, built-in voice chat (deferred; the game must be completable with pings alone; do not advertise voice).
Weather = authored VFX and timed state changes. Flooding = a water-height scalar plus access checks.
Cables = authored curves between sockets, never replicated rigid bodies.

**Cut order if capacity is exceeded:** voiced barks, cosmetic variants, seeded replay variants, contracts 12 to 8, districts 3 to 2.
Never cut: the power puzzle, recoverable failures, solo support, working co-op, save integrity, readable feedback.
Removing co-op is a product decision for the owner, not a scope cut.

## 2. Pillars (apply to every feature)

1. Understand a fault: a meter gives evidence to infer the cause. Markers may point at a building but must not reveal the exact repair.
2. Make a useful tradeoff: temporary supply helps one branch but cannot supply everything.
3. See and hear recovery: windows, signs, fans, music; recovery must stay legible without darkness hiding the scene.
If testers can finish every mission by following markers and holding Interact, fix the fault layout before adding content.

## 3. Power network rules (exact)

Abstract capacity puzzle in invented **PU**. It is not an electrical simulator.

- Nodes: sources, junctions, consumers. Edge = directed potential supply path with `enabled`, `healthy`, PU `capacity`, stable ID.
  Junction can be isolated, have a failed component, or have a tripped breaker. Consumer has PU demand + enable switch.
- A consumer has at most one energized incoming route. Alternate potential routes are allowed only while at most one is active.
- Energized graph = directed trees, one source per component. **Reject** cycles, source-to-source connections, and two simultaneously
  energized incoming routes. Invalid topology is **refused before any state change**; the map highlights the conflicting tie.
- Overload when value is **strictly greater** than capacity. Equality is allowed (SIM08).
- Fixed host tick order: (1) validate IDs/topology, sort traversal by stable ID; (2) drop disabled/broken edges and isolated/failed/tripped
  junctions; (3) traverse out from online sources, mark reachable healthy consumers supplied; (4) sum enabled demand back toward the
  source, record downstream PU on each active edge; (5) compare sources and edges to capacity; (6) per overloaded protected branch,
  accumulate a timer at 10 Hz, trip the designated upstream breaker at 1.5 continuous seconds, healthy demand resets the timer to zero;
  (7) recompute after trips; a reset is accepted only if demand and topology are valid, and a refused reset must not start trip cycles;
  (8) emit authoritative state changes. Clients animate from them and never decide whether a building is supplied.
- Reversing node/edge input order must not change canonical output (SIM11).

**Implementation interpretations to confirm in ADR-003 (not stated verbatim in the blueprint):**
use **integer PU** (never float) and **integer ticks** (10 Hz, trip when the overload counter reaches 15). Define one canonical state
serialization (sorted IDs, ints only, no positions/visual data) and hash it; the Python reference and the GDScript port must agree byte for byte.

**C01 test oracle** (Alder Street; full text blueprint p.7, data in `reference/data/first_shift.json` if the package is present):

| Edge / consumer | Capacity or demand | Start |
|---|---|---|
| GRID source | 24 PU | online |
| GRID -> JW | 12 | west fuse failed, breaker tripped |
| GRID -> JE | 12 | east trunk broken |
| JW -> APT_W / MARKET | 4 / 5 | healthy consumers |
| JE -> PUB / APT_E / WORKSHOP | 4 / 4 / 3 | healthy consumers |
| GEN -> TEMP | 6 | generator off |
| TEMP -> PUMP | 4 | disconnected, required access task |
| TEMP -> PUB (alternate) | 4 | optional, disconnected |
| JE -> SIGN (training load) | 3 | disabled; excluded from stars/bonuses |

West 9 + east required 11 = 20 PU required. Generator can run pump (4/6) **or** pub, never both (8/6 trips after 1.5 s). Enabling the sign after repairs
gives east edge 14/12 and grid 23/24. The pub must never have temporary and grid routes energized together. Pump needs 12 continuous
supplied seconds, then the drain **latches** (switching off does not refill). Final: all five required consumers on grid supply for 10 continuous
seconds, equipment stowed, everyone in the extraction zone, host starts a 5 s countdown, cancellable.
Known-valid C01 solution: blueprint p.7. Every contract must ship with a solution trace that a validator replays.

**Repair state machine:** undiagnosed, diagnosed, isolated, opened, component removed, replacement installed, closed, tested, restored.
Cancel keeps the last durable state. Repairs on an unisolated panel are refused with a reason. No hold longer than 1.2 s by default.
One repair lock owner at a time; host releases it on out-of-range, cancel, disconnect, or no heartbeat for 2 s. Unknown readings show `?`, never 0.

## 4. Authority and networking

Host is authoritative for grid, repairs, equipment, objectives, mission clock, rewards. Clients send intentions only: `inspect`,
`request_lock`, `repair_step`, `toggle_switch`, `place_item`, `ping`, `ready`, `request_extract`, each with session ID, sequence, entity ID,
bounded payload. Host takes sender identity from the transport and validates membership, distance, state, inventory, lock owner,
rate, content version; dedupes by session + sender sequence; replies with a revision. Host-local actions use the same path.
Targets (to test, not facts): 30 Hz host movement sim, 15 Hz snapshots, 10 Hz grid; reliable ordered for durable events, unreliable
sequenced for movement; **single reliable channel is the compatibility baseline**, do not assume ENet channels exist in a Steam peer;
remote interpolation about 100 ms. Stable object IDs come from authored content, never scene-tree order; every peer builds identical
gameplay node paths before accepting RPCs. Join/reconnect: freeze in a joining screen, manifest + bounded chunks, verify content hashes,
apply snapshot, then queued newer deltas.
**The Steam transport is not qualified until F02/F06 pass on two real PCs on separate networks.** Localhost/ENet is a development
transport only and never satisfies a network gate.

## 5. Repo layout and module ownership

`project.godot` at the repo root. Root dirs: `scenes/ scripts/ content/ assets/ tests/ tools/ docs/ reference/ art_source/`.
Modules live under `scripts/`. The blueprint lists them without that prefix and also lists `scripts/` as a root dir, so the bootstrap session records this as ADR-001:

| Path | Owns | Must not own |
|---|---|---|
| `scripts/autoload/game_session.gd` | session state, scene transitions | grid maths, UI drawing |
| `scripts/network/transport_adapter.gd` | offline / ENet dev / Steam peer selection | mission rewards |
| `scripts/network/session_host.gd` | admission, input validation, snapshots, entity IDs | rendering |
| `scripts/simulation/power_grid.gd` | pure graph evaluation, capacities, trip timers | Steam calls, scene lookups |
| `scripts/simulation/mission_director.gd` | objectives, events, route predicates, extraction | player-owned progression |
| `scripts/interaction/interaction_service.gd` | reachability, locks, state transitions | client-authoritative repairs |
| `scripts/actors/player_controller.gd` | local input, predicted motion, interaction requests | reward issuance |
| `scripts/world/service_location.gd` | building presentation from supplied state | deciding whether supply is valid |
| `scripts/persistence/save_service.gd` | versioned saves, backup, atomic replace | broad Cloud configuration |
| `scripts/progression/reward_service.gd` | receipt IDs, deduplicated rewards | rendering, transport |
| `scripts/ui/`, `scenes/ui/` | views, presenters, focus/input hints | simulation changes without commands |
| `content/` | typed definitions, imported JSON | executable downloaded scripts |

`power_grid.gd` must run with **no scene tree and no autoloads** so it can be unit-tested headless and compared with the Python reference.
Scenes: Boot, MainMenu, Depot, Lobby, MissionRoot (NetworkRoot, DistrictRoot, Players, Equipment, MissionDirector, HUD), PauseOverlay, Results.
Original art sources stay in `art_source/` (Git LFS, `.gdignore`), never in the exported tree. `docs/`, `tools/`, `reference/` also get `.gdignore`.

Saves: `user://profiles/<account_key>/{campaign,profile,receipts}.json` and `checkpoints/<campaign_id>.json`. Write temp file in the same
dir, flush/close, keep one previous valid backup, atomic replace. Fields: `schema_version`, `build_id`, `content_revision`, UTC timestamp,
stable record IDs. Checksum detects corruption, it is not anti-cheat. Host checkpoint every 60 s and after durable repairs; load recomputes
derived power state from saved causes, never from light states. Receipt key = `campaign_id + contract_instance_id + account_key`, applied once.
Never silently erase an unreadable or newer-schema save.

Code style: static types on every variable, parameter and return; `class_name` only where needed (tests extend by path); no string
`get_node` lookups in simulation; typed signals; no magic numbers outside `content/`; small functions; comments explain why.

## 6. Working protocol (every session)

1. `python3 tools/backlog.py next --env cloud` (cloud session) or `--env local` (your PC). On Windows use `python` or `py -3`.
2. Read only that task (`backlog.py show ID`) and the blueprint pages it needs. Do the **first unblocked task**; do not skip ahead
   and do not start art or content while the current interaction/network model is unproven.
3. Branch `task/<ID>-<slug>` (cloud sessions may be forced onto `claude/...`; put the task ID in every commit: `G01: port evaluator`).
4. Write tests first or alongside. Name them after matrix IDs (`test_SIM08_...`). Run `bash tools/run_tests.sh`. Test authoritative state, not visuals.
5. Write `docs/evidence/<ID>.md` from `docs/evidence/_TEMPLATE.md`: commit, environment, exact commands, observed results, what was NOT verified.
6. Set status with `backlog.py set`. **DONE** needs every dependency DONE and the evidence file. **CLOUD_VERIFIED** (needs `--pending-local`) means tests
   pass headless in the cloud but real hardware / network / people / Windows are still needed, or a dependency is only CLOUD_VERIFIED.
   A cloud session may never set a task to DONE if its acceptance needs a real PC, device, network or person.
7. Open a PR into `main`. Never push to `main` directly; never force-push. Commit and push after each logical step, because a session can end at any time.
8. Before stopping, update the `Resume notes` section of the evidence file for the task in progress.
9. At the last task of a milestone, write the gate report (what the gate required, evidence links, open risks, hours actually spent) and **stop for the owner**.
   A failed gate moves the schedule; it is not rounded up.

**Stop and ask the owner before:** creating or touching Steamworks accounts, app IDs, depots or any publishing action; changing a locked decision
or the cut order; adding any third-party addon, font, model, sound or image (license, source and version must be recorded first);
committing anything under `private/`, tokens, `steam_appid.txt` or Steamworks SDK files; enabling telemetry upload; deleting or migrating save data;
choosing the public game name (no trademark clearance exists); spending money.

## 7. Cloud vs local

Cloud sessions are Linux, headless, no GPU, no Steam client, no second machine; network is an allowlist (GitHub, package registries; **no**
Steam, no downloads.godotengine.org; GodotSteam's GitHub releases page and Codeberg were blocked when tested). A SessionStart hook installs the pinned Godot via
`bash tools/setup_godot_linux.sh`. Cloud is good for: pure logic, tests, validators, save/reward logic, content data, tooling, docs.
Local (Windows PC; the performance target machine is GTX 1650 4 GB class) is required for: Steam spike and real two-PC tests, editor scene work, controller, audio, visuals, profiling, exports.
`backlog.json` tags every task `cloud | split | local | human`. Do not pretend a `local` or `human` task was done from the cloud.

## 8. Honesty rules

- Only the Python reference tests have ever run. Say what was actually executed, on what, with which build.
- Do not claim the co-op architecture or Steam transport is qualified without the two-network test. Do not substitute localhost.
- Report **P95 frame time** and memory from an exported build on the target-class machine; unmeasured performance numbers are labeled targets.
- Do not advertise or imply voice chat, wishlist/sales forecasts, or unimplemented features. No market claims.
- Defect severity: P0 save loss / arbitrary file or code access / launch failure; P1 mission cannot finish, repeatable disconnect,
  duplicate reward, essential input inaccessible; P2 wrong feedback with workaround; P3 cosmetic. P0/P1 block release.

## 9. Privacy and repo hygiene

The repository may be public. Never commit secrets, Steam app IDs, Steamworks SDK files, export credentials or personal data. Analytics and
diagnostics use random session IDs, never raw Steam IDs; diagnostics strip account IDs and private paths by default; public error strings omit
peer IDs and addresses. Text chat: length cap, rate limit, escaped markup, mute, no URL launching. Debug tools exist only in internal exports.
Every production asset needs creator/source/license recorded; the release pipeline must fail on placeholder or unlicensed assets.

## 10. Commands

```
python3 tools/backlog.py next --env cloud|local     # what to do next
python3 tools/backlog.py show G01 | list | summary | validate
python3 tools/backlog.py set G01 CLOUD_VERIFIED --pending-local "rerun on Windows; ..."
bash tools/run_tests.sh [--filter=text]             # backlog check, Python reference tests, headless Godot tests
GODOT_BIN=<path to Godot 4.7.2 console exe> bash tools/run_tests.sh   # Windows (Git Bash)
```
