# PC runbook: everything to do on your Windows PC, step by step

Written 29 Oct 2026 at the end of cloud sprint B. State on `main`: F01, F03, F04, F05, G01-G07 are CLOUD_VERIFIED; nothing is DONE.
Everything below needs real hardware, Steam, a second PC or you. Work top to bottom; each part says what to record and when to stop.
`docs/PC-WORK.md` is the short checklist version; this file is the long one.

Conventions: commands in **Git Bash** unless marked *PowerShell*. Repo at `C:\LightsBackOn` (`/c/LightsBackOn` in Git Bash).
Replace `<...>` with your values. Never commit `private/`, `steam_appid.txt`, Steamworks SDK files or tokens (they are gitignored).

---

## Part 0. What you need before starting

| Item | Needed for | Notes |
|---|---|---|
| Windows 10/11 x64 PC, GPU driver up to date | Parts 1-4 | GTX 1650 class is the performance target; any GPU is fine for F01 |
| A second Windows PC (laptop is fine) | Part 5-6 | Must be on a **different network** for the real test (phone hotspot works) |
| Two Steam accounts, each logged in on one PC | Part 5-6 | Both must be able to run Spacewar (app 480), which every Steam account can |
| A gamepad (Xbox-style) | Part 4 optional check | Not required for F01 DONE |
| About 2 h for Parts 1-4, 4-6 h for Part 5 | | Part 5 can be split over days |

---

## Part 1. One-time PC setup (about 30-45 min)

1. **Git for Windows** (includes Git Bash): https://git-scm.com/download/win. Defaults are fine. Then in Git Bash:
   ```
   git config --global core.autocrlf false
   git lfs install
   ```
   (The repo forces LF line endings itself; `autocrlf false` stops Git from fighting it.)
2. **Python 3.12 or newer**: https://www.python.org/downloads/windows/ - tick "Add python.exe to PATH". Check in Git Bash: `py -3 --version`.
3. **Godot 4.7.2 standard (not .NET)**:
   - Download `Godot_v4.7.2-stable_win64.exe.zip` from https://godotengine.org/download/archive/4.7.2-stable/ (or the GitHub release
     `godotengine/godot-builds`, tag `4.7.2-stable`).
   - Verify it (*PowerShell*): `certutil -hashfile Godot_v4.7.2-stable_win64.exe.zip SHA512` and compare with the line in that release's
     `SHA512-SUMS.txt`. Expected: `83decd58fdf67b9d…2259993` (full value in SHA512-SUMS.txt).
   - Unzip to `C:\Tools\Godot\`. You get `Godot_v4.7.2-stable_win64.exe` (editor) and `Godot_v4.7.2-stable_win64_console.exe` (same, with a console).
   - Check (Git Bash): `"/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --version` prints `4.7.2.stable.official.ed1daf0bf`.
4. **Export templates 4.7.2**: open the editor once (any project), Editor menu > *Manage Export Templates* > *Download and Install*.
   They land in `%APPDATA%\Godot\export_templates\4.7.2.stable\`. Expected hash of `windows_release_x86_64.exe` (*PowerShell*):
   `certutil -hashfile "$env:APPDATA\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe" SHA256` ->
   `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` (the same file CI used). If it differs, stop and tell Claude.
5. **Steam client** on both PCs, each logged into its own account.
6. **Claude Code CLI** (optional but recommended for Part 5): install per https://code.claude.com/docs, sign in with the **same claude.ai
   account** as the cloud sessions.
7. Make Godot easy to call. Add to `~/.bashrc` in Git Bash:
   ```
   export GODOT_BIN="/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
   export PYTHON=py
   ```
   then `source ~/.bashrc`.

---

## Part 2. Get the latest code (2 min)

If `C:\LightsBackOn` already exists:
```
cd /c/LightsBackOn
git status                     # must say "nothing to commit"; if not, tell Claude before continuing
git switch main
git pull origin main
git log --oneline -1           # should be at or after f1dc3f1 "Merge pull request #14"
```
If it does not exist: `git clone https://github.com/AnrixaLabs/LightsBackON.git /c/LightsBackOn && cd /c/LightsBackOn`.

---

## Part 3. Run every automated check on your PC (5 min)

```
cd /c/LightsBackOn
bash tools/run_tests.sh 2>&1 | tee build/pc_tests.log
```
(`mkdir -p build` first if it says the folder is missing.)

Expected last lines:
```
contrast: 44 checks, 0 failures
Ran 19 tests ... OK
tests: 114 passed, 0 failed, ...
MATCH: 32 case runs (fwd+rev), 246 command hashes, 10 definition rejections identical ...
ALL CHECKS PASSED
```
Windows Firewall may ask about Godot during the ENet test: choose **Private networks** and Allow (it only uses 127.0.0.1).
If anything fails: stop, keep `build/pc_tests.log`, and paste its end into Claude (cloud or local).

---

## Part 4. F01: export and launch on real hardware, then promote F01 and G01-G03 to DONE (20-30 min)

### 4.1 Build the manifest and export
```
cd /c/LightsBackOn
py -3 tools/build_manifest.py --godot "$GODOT_BIN"
"$GODOT_BIN" --headless --path . --import
mkdir -p build/windows
"$GODOT_BIN" --headless --path . --export-release "Windows Desktop" build/windows/LightsBackOn.exe
```
(Same result through the editor: Project > Export > Windows Desktop > Export Project, untick "Export With Debug".)

### 4.2 Launch it
1. Double-click `C:\LightsBackOn\build\windows\LightsBackOn.exe`. Expected: a window opens (it is a blank boot scene; black or grey is
   correct), no error dialog. Close it with Alt+F4.
2. Launch again with a log (*Git Bash*):
   ```
   ./build/windows/LightsBackOn.exe --log-file "$PWD/build/smoke.log" --quit-after 300
   grep "Lights Back On boot" build/smoke.log
   grep build_id build_manifest.json
   ```
   The boot line must end with the same `build_id` as the manifest.
3. Optional: plug in the gamepad; nothing to test yet beyond "no crash".

### 4.3 Record
```
sha256sum build/windows/LightsBackOn.exe build/windows/LightsBackOn.pck
```
Find your GPU and driver: *PowerShell* `Get-CimInstance Win32_VideoController | Select Name, DriverVersion`.

Open `docs/evidence/F01.md` and add a section (copy the format):
```
## Local Windows launch (<date>)
- PC: <CPU>, <GPU> driver <version>, Windows <version>
- Commit: <git rev-parse --short HEAD>; build_id: <from manifest>
- Window opened with the Compatibility renderer: yes/no; errors: none/<text>
- exe sha256 <...>, pck sha256 <...>; boot line: <paste>
```

### 4.4 Promote and push
```
py -3 tools/backlog.py set F01 DONE
py -3 tools/backlog.py set G01 DONE
py -3 tools/backlog.py set G02 DONE
py -3 tools/backlog.py set G03 DONE
py -3 tools/backlog.py validate
git switch -c task/F01-local-launch
git add docs/evidence/F01.md docs/backlog.json
git commit -m "F01: local Windows launch evidence; F01, G01-G03 DONE"
git push -u origin task/F01-local-launch
```
Then open a PR on GitHub (or tell Claude to). G02 and G03 keep their notes about the host loop (G07) and on-screen meter (V07) as follow-ups.
**Do not** set G04-G07 or F03-F05 DONE: they depend on F02/F06 or on editor work.

---

## Part 5. F02: Steam transport spike on two real PCs (the biggest open risk; 4-6 h)

### 5.1 Decisions only you can make (stop-and-ask items)
1. **Which extension to try first.** Recommended order (HANDOFF issue 4): **A** = current GodotSteam GDExtension with its built-in
   multiplayer peer; **B** = ExpressoBits SteamMultiplayerPeer + GodotSteam 4.16.2 or earlier; **C** = the peer named in the blueprint.
   Approve A (or another) and say so to Claude. Claude must record source URL, version, commit and license (GodotSteam is MIT) before adding it.
2. **App ID.** For the spike use Valve's public test app **480 (Spacewar)** in a gitignored `steam_appid.txt`; no Steamworks account action
   is needed. Creating your own app ID/depots is a separate stop-and-ask decision for later (D08).

### 5.2 Let local Claude build the spike
```
cd /c/LightsBackOn && git switch main && git pull
claude
```
Paste the HANDOFF prompt **P3** (docs/HANDOFF.md section 4) and add: "I approve candidate A. Use app 480 in steam_appid.txt (gitignored)."
Claude prepares a minimal private-lobby create/join spike, an export, and a checklist for PC #2. It records extension hashes.

### 5.3 Run the two-network test
1. Copy the exported spike folder (exe, pck, extension DLLs, `steam_api64.dll`, `steam_appid.txt`) to PC #2 via USB or a private share.
   Do not upload it anywhere public.
2. Put PC #2 on a **different network** (phone hotspot). Confirm: on each PC open https://ifconfig.me (or similar) and note the two public IPs
   are different. Write only "different: yes" in evidence, never the IPs.
3. Both PCs: Steam running and logged in; the two accounts are Steam friends.
4. PC #1: start the spike, create a friends-only lobby. PC #2: join via the friend invite or lobby list.
5. Follow Claude's checklist: messages both ways, leave and rejoin, close the host (guest sees a clear end), pull PC #2's network for ~5 s.
6. Record for each step: pass/fail, time, any error text. Screenshots go to `docs/evidence/F02/` (crop out names/IDs).
7. A same-network or localhost run is only a smoke test; label it that way. If A fails on the real test, tell Claude to try B, then C.

### 5.4 Record and pin
Claude writes `docs/evidence/F02.md`, pins the tuple (engine, templates, extension revision + binary hashes, peer, Steamworks runtime) in
`build_manifest.json` fields, and sets F02 DONE only after the two-network pass. Commit on a `task/F02-...` branch and PR.

---

## Part 6. After F02: rerun the drafted network logic on the Steam peer

Ask local Claude: "Run docs/PC-WORK.md section 2b on the Steam peer." What you will do by hand, with Claude preparing the builds:
1. **NET01**: both players press Interact on the same repair panel at the same moment. Exactly one gets the lock; the other sees who is working.
2. **NET02**: Claude adds a debug "resend last command" key; press it during a repair. The part is used once.
3. **NET05**: guest carries the generator, then you pull the guest's network. The generator appears back on its pad; the lock clears.
4. **NET06**: guest drops for ~5 s and comes back. One actor, correct state, no duplicate reward eligibility.
5. **NET07**: host quits while the guest is connected. The guest sees "host left" with a Back option, no hang.
6. **G07 agreement**: after a repair, a trip (sign on), a reset and a reconnect, both PCs log their state hash; they must match.
7. **REL02**: quit Steam completely, start the exported build. It must offer offline solo and not corrupt the profile.
8. **G06 / SAVE01 real kill**: start a checkpoint write and kill the process (*PowerShell* `taskkill /F /IM LightsBackOn.exe`), relaunch. The
   current or backup save loads and the recovery is shown.
Claude updates the evidence files and promotes F03, F04, G04-G07 when their dependencies are DONE.

---

## Part 7. Gates (you decide)

1. **F06 Foundation gate**: Claude writes the gate report (HANDOFF prompt P5). You read it and accept or reject. Accepted -> tag `gate-F`.
2. **G08 Grid toy gate**: same, after G07 runs on real peers. Accepted -> tag `gate-G`. This unblocks V01 (graybox) and the V phase.
A failed gate moves the schedule; it is not rounded up.

---

## Part 8. Editor and art work (F05 local part; can run in parallel with Part 5)

1. Decide the font (Noto Sans recommended, SIL Open Font License). Tell Claude to record source/version/license and add it.
2. In the editor, block out the 4 m kit (walls, floor, door 1.1 m clear, panels at 1.2-1.6 m) at 1 unit = 1 m, using
   `content/world/kit_dimensions.json`. Keep source files in `art_source/` (Git LFS).
3. Draw the icon set from `content/ui/status_states.json` (one icon per listed state, 24 px grid, icon + text always).
4. Decide the HUD panel question in the ADR-004 addendum: opaque text panels (current) or translucent panels with muted `?` text.

---

## Part 9. Coming back to the cloud

1. Make sure everything you did is pushed and merged into `main` (the cloud only sees GitHub).
2. Start a cloud session and paste:
   ```
   Continue Lights Back On after the PC pass. Read docs/PC-RUNBOOK.md, docs/PC-WORK.md and the evidence files changed since f1dc3f1.
   Follow CLAUDE.md section 6: run `python3 tools/backlog.py next --env cloud`, finalize what the PC results unblock, and stop at the first
   stop condition. Results from my PC: <one line per part: done / failed + where the evidence is>.
   ```
3. If something failed on the PC, paste the failing output instead; the cloud session fixes code, CI re-runs on Linux and Windows, and you
   rerun only the failed step.
