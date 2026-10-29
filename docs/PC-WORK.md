# PC work queue (things only your Windows PC, Steam, a second machine or people can do)

**Step-by-step version: `docs/PC-RUNBOOK.md`.**

**PC pass status (owner-confirmed, 29 Oct 2026):** runbook A done, B PASS, C PASS (F01, G01-G03 DONE, PR #17).
D/E (Steam, two PCs) **not started**: no second Steam account yet, so F02 is BLOCKED. F decisions (font, HUD panels, repo visibility) still open.
Until F02 starts, the cloud continues with the logic-only V tasks (ADR-011), ceiling CLOUD_VERIFIED. Resume here at runbook session D.

Updated by every cloud session that leaves a task CLOUD_VERIFIED. Source of truth is still `python3 tools/backlog.py next --env local`;
this file adds the exact steps. Tick a box only when the evidence file is updated. Order = dependency order.

**What CI already covers (GitHub Actions, `.github/workflows/ci.yml`):** on every PR, the full `tools/run_tests.sh` runs on Linux **and on a
Windows runner**, and the Windows job exports the release build, launches it headless and uploads exe/pck + manifest + SHA256SUMS as an
artifact. That is a Windows rerun on a VM with no GPU, so it does **not** replace the checks below (real GPU, window, controller, Steam, two networks).

## 1. Promotion pass (about 30 min, prompt P4 in docs/HANDOFF.md)

- [x] **F01** launch exported Windows build; record hash (done 29 Oct 2026, GTX 1650; see docs/evidence/F01.md)
  1. `git switch main && git pull`, then `py -3 tools/build_manifest.py --godot "C:\path\Godot_v4.7.2-stable_win64_console.exe"`
  2. Open the project in the 4.7.2 editor once (imports), Project > Export > Windows Desktop > Export Project (release) to `build\windows\LightsBackOn.exe`.
     If templates are missing: Editor > Manage Export Templates > Download (record their version).
  3. (CI already proves the headless launch on Windows.) Double-click the exe: a window opens (Compatibility renderer, real GPU), no error dialog. For the log, run
     `build\windows\LightsBackOn.exe --log-file build\smoke.log` and check `Lights Back On boot | ... | build <build_id>` matches `build_manifest.json`.
  4. `certutil -hashfile build\windows\LightsBackOn.exe SHA256` (and `.pck`); paste both, GPU + driver version, and build_id into `docs/evidence/F01.md`.
  5. `py -3 tools/backlog.py set F01 DONE`
- [x] **G01, G02, G03** Windows rerun: done by CI (run 40838296362, 39/39 + MATCH). After F01 is DONE just run
  `set G01 DONE`, `set G02 DONE`, `set G03 DONE`. Optional local rerun in Git Bash:
  `GODOT_BIN="/c/path/Godot_v4.7.2-stable_win64_console.exe" PYTHON=py bash tools/run_tests.sh` -> must end `ALL CHECKS PASSED` and print `MATCH`.
  Add the output line to each evidence file, then `set G01 DONE`, `set G02 DONE`, `set G03 DONE` (in that order). G02's "host 10 Hz loop" and
  G03's "on-screen meter" notes stay open for G07 / V07; record them as follow-ups, they do not block DONE for the pure-logic acceptance.

## 2. Steam transport spike (F02, prompt P3) — the biggest open risk

Needs: Steam client on both PCs, two licensed Steam accounts, PC #2 on a **different network** (e.g. phone hotspot), Steamworks partner account.
Stop-and-ask items (Claude must ask you first): Steamworks app ID / depots, adding GodotSteam or any extension (license + version recorded first).
- [ ] Choose the extension candidate with Claude (HANDOFF issue 4), record source revision + binary hashes.
- [ ] Private friends-only lobby: create on PC #1, join from PC #2 on the other network, exchange reliable messages both ways, leave/rejoin.
- [ ] Record the tuple (engine, templates, extension, peer, Steamworks runtime) in the manifest and `docs/evidence/F02.md`.
  Localhost or same-network runs are smoke tests only and never satisfy F02.

## 2b. After F02: rerun the drafted network logic on the Steam peer (two PCs, separate networks)

All of these pass in cloud/CI on the ENet **development** transport or in-process; none is a network result yet.
- [ ] **F03** host authority: run `tests/unit/test_F03_*` logic over the Steam peer; NET01 (two real clients request the same lock at once), NET02 (resend a durable repair command).
- [ ] **F04** connection failures: start the exported build with Steam closed (REL02 -> offline solo offered), quit the host with a guest connected
      (NET07 -> guest sees HOST_LEFT), pull the guest's network for 5 s and restore it (NET06 -> one actor, no duplicate reward eligibility).
- [ ] **G07** two peers agree: host + guest compare the state hash after repair, trip, reset and reconnect (`session_host.state_hash()` vs the
      guest mirror's `state_hash()`; log both). Then **F06** gate, then **G08** grid-toy gate.
- [ ] **G04/G05** with real clients: NET05 (guest disconnects while carrying the generator -> it returns to the pad; lock clears).
- [ ] **G06** real kill: start a checkpoint write in the exported build and kill the process (Task Manager / `taskkill /F`), relaunch, confirm current
      or backup loads and the recovery is reported (SAVE01 on a real process).

## 3. Editor-side checks (when the matching task reaches CLOUD_VERIFIED)

- [ ] **F05** (art_ui, split): import the 4 m block kit at 1 unit = 1 m, check theme tokens render with WCAG AA contrast (ADR-004). Not started.
- [ ] **F06** foundation gate: export evidence + gate report; owner decision. Claude stops here for you.

## 4. Later local-only tasks (not yet unblocked)

G07/G08 (commands + grid on real peers, grid-toy gate), V01 graybox, V07 field/tablet UI, V09 slice gate, all art/audio/profiling (target GTX 1650 class,
report P95 frame time), controller-only run (UX01), studies with testers (A05, D07).
