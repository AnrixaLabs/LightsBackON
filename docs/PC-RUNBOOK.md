# PC runbook: exact steps on your Windows PC

Every step has three parts: **Do** (exactly what to click or type), **You should see** (how you know it worked),
**If not** (what to do instead). Do the steps in order and do not skip any. If a step fails and the "If not" line does not help,
stop, copy what is on the screen, and paste it into Claude (cloud or local). Nothing you do here can break the project:
everything is in Git and can be undone.

How to read the commands:
- A grey box with commands = type it **exactly**, one line at a time, then press **Enter** after each line.
- Text in `<angle brackets>` = replace it with your own value, without the brackets.
- "Git Bash" = the black terminal window installed in step 1.1. "PowerShell" = the blue Windows terminal. They are different; each step says which.
- To paste into Git Bash: right-click inside the window and choose **Paste** (Ctrl+V may not work there).

| Session | What | Time | Needs |
|---|---|---|---|
| A | Install tools (once) | 45 min | this PC, internet |
| B | Get the code and run the tests | 15 min | session A |
| C | F01: export, launch, record, mark DONE | 30 min | session B |
| D | F02: Steam test on two PCs | 3-6 h, can split | session C, second PC, two Steam accounts, phone hotspot |
| E | Steam reruns of the network features | 2-3 h | session D passed |
| F | Gates and art decisions | your time | sessions C-E |
| G | Hand back to the cloud | 5 min | whatever you finished |

You can stop after any session and continue another day. Sessions A-C need only this PC.

---

## Session A: install the tools (once, about 45 minutes)

### A.1 Install Git for Windows (includes Git Bash)
1. **Do:** open https://git-scm.com/download/win in your browser. Click **Click here to download** (64-bit Git for Windows Setup).
   **You should see:** a file like `Git-2.xx.x-64-bit.exe` in your Downloads folder.
2. **Do:** double-click that file. If Windows asks "Do you want to allow this app to make changes", click **Yes**.
3. **Do:** click **Next** on every screen, **except** these three, where you pick the option named here:
   - "Choosing the default editor used by Git": pick **Use Notepad as Git's default editor** (easier than Vim).
   - "Adjusting the name of the initial branch": leave **Let Git decide**.
   - "Configuring the line ending conversions": pick **Checkout as-is, commit as-is**.
   Then click **Install**, wait, untick "View Release Notes", click **Finish**.
4. **Do:** press the Windows key, type `Git Bash`, press Enter.
   **You should see:** a black window with a line ending in `$`.
5. **Do:** in Git Bash, type:
   ```
   git --version
   git lfs install
   git config --global core.autocrlf false
   ```
   **You should see:** `git version 2.xx...`, then `Git LFS initialized.`, then nothing for the last line (nothing = success).
   **If not:** if `git lfs` is unknown, reinstall Git and make sure "Git LFS" is ticked on the "Select Components" screen.
6. **Do:** tell Git who you are (used in commit history; use the email of your GitHub account):
   ```
   git config --global user.name "Levon"
   git config --global user.email "<your GitHub email>"
   ```

### A.2 Install Python
1. **Do:** open https://www.python.org/downloads/windows/ and click the newest **Python 3.13.x** (or 3.12.x) "Windows installer (64-bit)".
2. **Do:** run the installer. On the **first** screen tick **Add python.exe to PATH** (bottom of the window), then click **Install Now**.
   Click **Close** at the end.
3. **Do:** **close Git Bash and open it again** (so it sees Python), then type:
   ```
   py -3 --version
   ```
   **You should see:** `Python 3.13.x` (or 3.12.x).
   **If not:** if it says "command not found", reboot the PC and try again; if it opens the Microsoft Store, run the installer again and tick "Add python.exe to PATH".

### A.3 Install Godot 4.7.2 (the exact engine version the project uses)
1. **Do:** open https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable. Scroll to **Assets** (click "Show all assets" if needed).
   Download two files: `Godot_v4.7.2-stable_win64.exe.zip` and `SHA512-SUMS.txt`.
2. **Do:** in File Explorer create the folder `C:\Tools\Godot`. Right-click the zip > **Extract All...** > type `C:\Tools\Godot` as the destination > **Extract**.
   **You should see:** in `C:\Tools\Godot`: `Godot_v4.7.2-stable_win64.exe` and `Godot_v4.7.2-stable_win64_console.exe`.
3. **Do (check the download is genuine):** press the Windows key, type `PowerShell`, press Enter. In the blue window type:
   ```
   certutil -hashfile "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe.zip" SHA512
   ```
   **You should see:** a long hex value starting `83decd58fdf67b9d` and ending `2259993`. Open `SHA512-SUMS.txt` in Notepad, find the line that ends
   with `Godot_v4.7.2-stable_win64.exe.zip`: its value must be the same (certutil may print it with spaces; ignore spaces).
   **If not:** delete the zip and download it again. If it still differs, stop and tell Claude.
4. **Do:** in Git Bash:
   ```
   "/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --version
   ```
   **You should see:** `4.7.2.stable.official.ed1daf0bf`.

### A.4 Install the Windows export templates
1. **Do:** double-click `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe` (the one **without** `_console`).
   **You should see:** the Godot Project Manager window.
   **If not:** if Windows SmartScreen says "Windows protected your PC", click **More info** > **Run anyway**.
2. **Do:** click **Create** (top left). Project Name: `scratch`. Project Path: click **Browse** and pick `C:\Tools\Godot\scratch`
   (make the folder if needed). Leave the renderer as it is. Click **Create & Edit**. In the editor that opens, use the top menu
   **Editor** > **Manage Export Templates...**. (The scratch project is only needed to reach this dialog; you can delete it afterwards.)
3. **Do:** in the dialog, choose **Download and Install** (pick the official mirror if asked).
   **You should see:** a progress bar (about 1.3 GB), then "Current Version: 4.7.2.stable" with **Installed**.
4. **Do:** close Godot. In PowerShell:
   ```
   certutil -hashfile "$env:APPDATA\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe" SHA256
   ```
   **You should see:** `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` (spaces don't matter).
   **If not:** stop and tell Claude; the build would not match the one CI produced.

### A.5 Make the commands short
1. **Do:** in Git Bash type (two separate lines):
   ```
   echo 'export GODOT_BIN="/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"' >> ~/.bashrc
   echo 'export PYTHON=py' >> ~/.bashrc
   ```
2. **Do:** close Git Bash, open it again, type `echo $GODOT_BIN`.
   **You should see:** `/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`.

### A.6 Install Steam (needed from session D on; do it now on this PC)
1. **Do:** install Steam from https://store.steampowered.com/about/ and sign in with your **first** Steam account. Leave it running.

### A.7 Install Claude Code locally (needed from session D on)
1. **Do:** follow the Windows install steps at https://code.claude.com/docs (Setup page). Sign in with the **same claude.ai account** you use here.
2. **Do:** in Git Bash type `claude --version`.
   **You should see:** a version number. **If not:** reopen Git Bash; if still missing, follow the docs' troubleshooting section.

**End of session A.** Nothing to commit.

---

## Session B: get the code and run every test (about 15 minutes)

### B.1 Get the project
1. **Do:** in Git Bash, check whether you already have the project:
   ```
   ls /c/LightsBackOn
   ```
   - If it lists files (`CLAUDE.md`, `docs`, ...), go to step 2.
   - If it says "No such file or directory", type:
     ```
     git clone https://github.com/AnrixaLabs/LightsBackON.git /c/LightsBackOn
     ```
     (A browser window may ask you to sign in to GitHub: sign in and allow access.) Then skip to step 3.
2. **Do:** update it:
   ```
   cd /c/LightsBackOn
   git status
   ```
   **You should see:** `nothing to commit, working tree clean`.
   **If not:** you have local changes. Type `git stash` to put them aside (they are kept, `git stash pop` brings them back), then continue.
   ```
   git switch main
   git pull origin main
   ```
3. **Do:**
   ```
   cd /c/LightsBackOn
   git log --oneline -1
   ```
   **You should see:** a line containing `Merge pull request #16` or later (the PR that added this file), or a newer one.

### B.2 Run all checks
1. **Do:**
   ```
   cd /c/LightsBackOn
   mkdir -p build
   bash tools/run_tests.sh 2>&1 | tee build/pc_tests.log
   ```
   This takes 1-2 minutes. A Windows Firewall popup may appear for Godot: tick **Private networks** only and click **Allow**
   (the test only talks to this PC itself, 127.0.0.1).
2. **You should see**, near the end:
   ```
   contrast: 44 checks, 0 failures
   Ran 19 tests in ...  OK
   tests: 114 passed, 0 failed, ...
   MATCH: 32 case runs (fwd+rev), 246 command hashes, 10 definition rejections identical ...
   ALL CHECKS PASSED
   ```
   (The number of tests can be higher if more were added; "0 failed" and "ALL CHECKS PASSED" are what matter.)
3. **If not:** the file `C:\LightsBackOn\build\pc_tests.log` has the full output. Stop here and send its last 50 lines to Claude
   (`tail -50 build/pc_tests.log` shows them).

**End of session B.** Nothing to commit.

---

## Session C: F01, export and launch the game on this PC (about 30 minutes)

### C.1 Write the build manifest
1. **Do:**
   ```
   cd /c/LightsBackOn
   py -3 tools/build_manifest.py --godot "$GODOT_BIN"
   ```
   **You should see:** a block of text in `{ ... }` with `"engine_version": "4.7.2.stable.official.ed1daf0bf"` and an
   `"export_templates_hash"` that is **not** `"none"`.
   **If not:** if `export_templates_hash` is `"none"`, the templates from A.4 are missing; redo A.4.

### C.2 Export the Windows build
1. **Do:**
   ```
   "$GODOT_BIN" --headless --path . --import
   mkdir -p build/windows
   "$GODOT_BIN" --headless --path . --export-release "Windows Desktop" build/windows/LightsBackOn.exe
   ls -l build/windows
   ```
   **You should see:** `LightsBackOn.exe` (about 109 MB) and `LightsBackOn.pck` (small).
   **If not:** copy the output and send it to Claude.

### C.3 Launch it (real window, real GPU)
1. **Do:** in File Explorer open `C:\LightsBackOn\build\windows` and double-click `LightsBackOn.exe`.
   If SmartScreen appears: **More info** > **Run anyway** (the exe is not signed yet; that is expected).
   **You should see:** a window opens and stays open with a plain black or grey screen. **That is correct**: the boot scene is empty on purpose.
   No error popup.
   **If not:** if an error popup appears, take a screenshot (Win+Shift+S) and send it to Claude. Note the message exactly.
2. **Do:** close the window (click X, or Alt+F4).
3. **Do:** launch it again with a log file, from Git Bash:
   ```
   ./build/windows/LightsBackOn.exe --log-file "$PWD/build/smoke.log" --quit-after 300
   ```
   The window opens and closes by itself after a few seconds.
4. **Do:**
   ```
   grep "Lights Back On boot" build/smoke.log
   grep build_id build_manifest.json
   ```
   **You should see:** the first line ends with `build <something>`; the second shows `"build_id": "<the same something>"`. They must match.
   **If not:** if the first grep prints nothing, run `cat build/smoke.log` and send it to Claude.

### C.4 Collect the values for the evidence file
1. **Do:**
   ```
   sha256sum build/windows/LightsBackOn.exe build/windows/LightsBackOn.pck
   git rev-parse --short HEAD
   ```
   Copy the output into Notepad for the next step.
2. **Do (GPU and driver):** in PowerShell:
   ```
   Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
   Get-CimInstance Win32_Processor | Select-Object Name
   (Get-CimInstance Win32_OperatingSystem).Caption
   ```
   Copy these too.

### C.5 Write the evidence
1. **Do:** open `C:\LightsBackOn\docs\evidence\F01.md` in Notepad (right-click > Open with > Notepad).
2. **Do:** find the line that starts with `## Not verified / pending_local`. **Above** it, paste this block and fill in the `<...>` from C.4:
   ```
   ## Local Windows launch (<today's date>)
   - PC: <CPU name>, <GPU name> driver <DriverVersion>, <Windows caption>
   - Commit: <short hash>; build_id: <build_id>
   - Double-click launch: window opened, no error (Compatibility renderer on a real GPU): yes
   - Log launch boot line: <paste the line from C.3 step 4>
   - exe sha256 <hash>; pck sha256 <hash>
   - Result: PASS
   ```
   Save (Ctrl+S) and close Notepad.

### C.6 Mark the tasks DONE
1. **Do:** in Git Bash, one line at a time:
   ```
   cd /c/LightsBackOn
   py -3 tools/backlog.py set F01 DONE
   py -3 tools/backlog.py set G01 DONE
   py -3 tools/backlog.py set G02 DONE
   py -3 tools/backlog.py set G03 DONE
   py -3 tools/backlog.py validate
   ```
   **You should see:** `F01 -> DONE`, `G01 -> DONE`, `G02 -> DONE`, `G03 -> DONE`, then `OK: 66 tasks`.
   **If not:** a "refused" message names the reason (for example a missing evidence file). Send it to Claude. Do not edit backlog.json by hand.
   Do **not** set any other task DONE: G04-G07 and F03-F05 still need Steam or editor work.

### C.7 Save it to GitHub
1. **Do:**
   ```
   git switch -c task/F01-local-launch
   git add docs/evidence/F01.md docs/backlog.json
   git commit -m "F01: local Windows launch evidence; F01, G01-G03 DONE"
   git push -u origin task/F01-local-launch
   ```
   **You should see:** the last command prints a link like `https://github.com/AnrixaLabs/LightsBackON/pull/new/task/F01-local-launch`.
2. **Do:** open that link in your browser. Click **Create pull request**, then **Create pull request** again.
3. **Do:** wait about 2 minutes. On the PR page, the checks **linux** and **windows** turn into green ticks.
4. **Do:** click **Merge pull request** > **Confirm merge**.
   **If a check is red:** don't merge; send the PR link to Claude.
5. **Do:** back in Git Bash:
   ```
   git switch main
   git pull origin main
   ```

**End of session C.** F01, G01, G02 and G03 are DONE.

---

## Session D: F02, prove Steam multiplayer works between two PCs on different networks (3-6 hours)

This is the most important test in the whole plan. You need:
- **PC 1** = this PC (it will host). **PC 2** = a second Windows PC or laptop (it will join).
- Two **different** Steam accounts, one per PC, that are **Steam friends** with each other.
- A **phone with a mobile hotspot**, so PC 2 is on a different network from PC 1.
- A USB stick (or another private way to copy a folder to PC 2).

### D.1 Prepare PC 2 (about 15 minutes)
1. **Do (on PC 2):** install Steam and sign in with the **second** Steam account.
2. **Do (on both PCs):** in Steam click **Friends** > **Add a Friend**, and add the other account. Accept the request on the other PC.
   **You should see:** each account in the other's friends list, shown as Online.
3. **Do (on PC 2):** nothing else; PC 2 does not need Git, Python or Godot.

### D.2 Make the two decisions only you can make
Write down your answers; you will paste them into Claude in D.3.
1. **Which Steam add-on to use.** Recommended: **"Candidate A: GodotSteam (GDExtension for Godot 4.7) with its built-in multiplayer peer, MIT license."**
   Alternatives B and C exist (docs/HANDOFF.md, section 2, issue 4); only pick them if Claude reports that A failed.
2. **Steam App ID for testing.** Recommended: **"Use Valve's test app 480 (Spacewar) in steam_appid.txt; do not create anything in Steamworks."**

### D.3 Let local Claude build the test program (PC 1)
1. **Do:** in Git Bash:
   ```
   cd /c/LightsBackOn
   git switch main
   git pull origin main
   claude
   ```
   **You should see:** the Claude Code prompt inside Git Bash.
2. **Do:** open `C:\LightsBackOn\docs\HANDOFF.md` in Notepad, find **"P3: Local Steam spike"**, and copy the text inside its grey box.
   Paste it into Claude, and add this sentence at the end, then press Enter:
   ```
   I approve candidate A (GodotSteam GDExtension, MIT) and Steam app 480 (Spacewar) in a gitignored steam_appid.txt.
   Give me numbered steps for each PC, and tell me exactly which folder to copy to PC 2.
   ```
3. **Do:** when Claude asks for permission to run commands or download the add-on, read what it wants to do and click/answer **Yes**
   if it matches the plan (downloading GodotSteam from its official GitHub release, building, exporting). Say **No** to anything about
   creating Steamworks apps, depots or uploading builds.
4. **You should see:** at the end, Claude says where the exported spike is (for example `C:\LightsBackOn\build\steam_spike\`) and gives you
   a numbered checklist. Keep that checklist open.

### D.4 First, a quick smoke test on one network (both PCs on the same Wi-Fi)
This only checks that the program starts; it does **not** count as the real test.
1. **Do:** copy the whole spike folder from PC 1 to the USB stick, then to PC 2 (for example to `C:\steam_spike\` on PC 2).
2. **Do:** with both PCs on the same Wi-Fi: on PC 1 run the spike and choose **Host** (or what Claude's checklist says). On PC 2 run the
   spike and join (via the friend invite in the Steam overlay, Shift+Tab, or the lobby list, per the checklist).
3. **You should see:** PC 2 shows it joined; messages appear on both sides as the checklist describes.
4. **If not:** write down the exact message on each screen and give it to Claude on PC 1. Do not move on until this works.

### D.5 The real test: two different networks
1. **Do (PC 2):** turn on your phone's hotspot. On PC 2 click the Wi-Fi icon and connect to the phone hotspot instead of your home Wi-Fi.
   Leave PC 1 on your home network.
2. **Do (check they are different):** on **each** PC open https://ifconfig.me in a browser. The two numbers shown must be **different**.
   Don't write the numbers anywhere; just note "different: yes".
3. **Do:** run through **every item** in Claude's checklist. It will include at least:
   - PC 1 creates a friends-only lobby; PC 2 joins it.
   - Messages go both ways (PC 1 to PC 2 and PC 2 to PC 1).
   - PC 2 leaves and joins again.
   - PC 2 loses network for about 5 seconds (turn off the hotspot, count to 5, turn it on) and comes back.
   - PC 1 (the host) quits while PC 2 is connected: PC 2 must show a clear message, not freeze.
4. **Do:** for each item write in Notepad: item, PASS or FAIL, the time, and any message shown. For screenshots use Win+Shift+S; save them,
   but crop out Steam names and avatars.
5. **If an item fails:** tell Claude on PC 1 exactly which item and what happened. Claude may fix it or switch to candidate B; then repeat D.4 and D.5.

### D.6 Record and save (PC 1)
1. **Do:** paste your Notepad results into the Claude session and say:
   ```
   Here are the two-network results. Write docs/evidence/F02.md, pin the tuple in the manifest, set F02 DONE only if every item passed,
   and open a PR. Do not commit steam_appid.txt or Steamworks SDK files.
   ```
2. **Do:** open the PR link Claude gives you. Wait for the green **linux** and **windows** checks, then **Merge pull request** > **Confirm merge**.
3. **Do:** in Git Bash: `git switch main && git pull origin main`.

**End of session D.** F02 is DONE only if every two-network item passed.

---

## Session E: rerun the network features over Steam (2-3 hours, after D passed)

1. **Do:** in the Claude session on PC 1 say:
   ```
   F02 passed. Now do docs/PC-WORK.md section 2b on the Steam peer. Build what is needed and give me a numbered two-PC checklist
   for NET01, NET02, NET05, NET06, NET07, the G07 state-hash comparison, REL02 (Steam closed) and the SAVE01 real kill test.
   ```
2. **Do:** copy the new build to PC 2 as in D.4 step 1. Keep PC 2 on the phone hotspot.
3. **Do:** run every checklist item and note PASS/FAIL like in D.5 step 4. These are what you will be checking (Claude's list has the exact keys):
   - **NET01:** both players press Interact on the same repair panel at the same moment. **Expect:** only one gets it; the other sees who is working.
   - **NET02:** press the debug "resend last command" key during a repair. **Expect:** the replacement part is used once.
   - **NET05:** PC 2 picks up the generator, then turn off the hotspot. **Expect:** on PC 1 the generator goes back to its pad; the lock clears.
   - **NET06:** turn the hotspot off for 5 s and on again. **Expect:** PC 2 rejoins as one player, with the right state.
   - **NET07:** close the game on PC 1 while PC 2 is connected. **Expect:** PC 2 shows "host left" with a Back button, no freeze.
   - **G07:** after a repair, a trip (sign on), a reset and a reconnect, both PCs show a state hash. **Expect:** identical on both.
   - **REL02:** fully quit Steam (system tray > right-click Steam > Exit), then start the game. **Expect:** it offers offline solo and works.
   - **SAVE01:** while a checkpoint is saving (Claude tells you when), in PowerShell type `taskkill /F /IM LightsBackOn.exe`, then start the
     game again. **Expect:** the save loads, or it says it recovered the backup. Never an empty or reset game without a message.
4. **Do:** paste the results into Claude: "Write the evidence, promote what is now allowed, open a PR." Merge it once the checks are green.

---

## Session F: gates and decisions (your time)

1. **Do:** in Claude (local or cloud) say: `Write the F06 gate report (HANDOFF prompt P5) and stop for my decision.`
   Read the report. Reply **"F gate accepted"** or **"F gate rejected because ..."**. Claude then tags `gate-F` (only if accepted).
2. **Do:** the same for **G08**: `Write the G08 grid-toy gate report and stop for my decision.` Accepting it unblocks the graybox (V01).
3. **Decisions to give Claude whenever you are ready** (one line each is enough):
   - Font: "Use Noto Sans (SIL Open Font License)" or another font you own a license for.
   - HUD panels: "Keep text panels opaque" (current) or "Translucent panels, draw `?` in the muted text color".
   - Repo visibility: keep public or make private (docs/BOOTSTRAP-REPORT.md, owner action 2).
4. **Art/editor work (F05 local part):** when you want to start it, open the project in the Godot editor
   (`C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe` > **Import** > select `C:\LightsBackOn\project.godot` > **Import & Edit**) and ask local Claude
   to guide you through blocking out the 4 m kit with `content/world/kit_dimensions.json`.

---

## Session G: hand back to the cloud (5 minutes)

1. **Do:** make sure every PR you opened is merged (on GitHub, **Pull requests** tab shows 0 open).
2. **Do:** start a new cloud session at https://claude.ai/code on the LightsBackON repo and paste:
   ```
   Continue Lights Back On after the PC pass. Read docs/PC-RUNBOOK.md, docs/PC-WORK.md and every evidence file changed since 3af92a8.
   Follow CLAUDE.md section 6: run `python3 tools/backlog.py next --env cloud`, finalize what the PC results unblock, and stop at the
   first stop condition. My results: A done; B <pass/fail>; C <pass/fail>; D <pass/fail/not done>; E <pass/fail/not done>; F <decisions>.
   ```
3. **If something failed** in any session: paste the failing output instead of "fail". The cloud session fixes the code; GitHub re-runs the
   Linux and Windows checks; you only repeat the step that failed.
