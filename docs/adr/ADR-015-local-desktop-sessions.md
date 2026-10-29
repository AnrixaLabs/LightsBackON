# ADR-015: Local desktop sessions take over; editor work continues while F02 is blocked

- Status: Accepted, 30 Oct 2026, on the owner's instruction to continue in local Claude Code desktop sessions and fix the workflow.
  Revisit when F02 starts (second Steam account available) or if the owner wants V01 to wait for G08.
- Extends ADR-011 (cloud logic work while F02 is deferred) to local editor work.

## Context
All cloud-capable tasks are done (`backlog.py next --env cloud` returns nothing). F02 is BLOCKED (no second Steam account), and every
remaining engineering acceptance runs through F02 -> F03 -> F04 -> F06 -> G07 -> G08. `next --env local` still listed F03, F04, G04, G05
and F06 as "next" although none of them could run, and V01 (graybox) waited on G08, a two-player network gate that says nothing about geometry.
Work now happens in Claude Code desktop sessions on the owner's Windows PC (GTX 1650 laptop), each in its own git worktree.

## Decision
1. **V01 gets `prep_ok_without: ["G08"]`.** Graybox geometry, routes, pads and collision are editor work over authored content IDs; they do
   not need the network gate. Ceiling CLOUD_VERIFIED (here: "automated checks and local checks pass, acceptance still waits on a dependency")
   until G08 is DONE. V07 follows V01 through its normal dependency.
2. **`backlog.py next --env local` parks** tasks whose acceptance needs a BLOCKED task (transitively) or a task in their new `verify_after`
   list that is not DONE (G04/G05 need G07 and the V01 scene). Parked tasks are printed separately, never as "next".
3. **Local session order while F02 is blocked:** F05 local part (block kit at 1 unit = 1 m, worker silhouette, icon art, rendered contrast),
   G06 real-process kill test on the exported build, then V01 graybox, then V07 UI. F05's font stays an owner decision (stop-and-ask).
4. **Branches:** each desktop session works in a worktree on `claude/<slug>`; one backlog task per branch, cut from `origin/main`, one PR.
   No stacked task branches (V04 -> V05 -> V08 needed five cross-merges); if a task needs unmerged work, wait for that PR to merge.
   The owner merges PRs. (Superseded 30 Oct 2026: Claude merges; see the amendment below.)
5. **Tooling finds the local toolchain itself:** `tools/run_tests.sh` skips the Windows Store `python3` stub and finds Godot at
   `C:\Tools\Godot` (PC-RUNBOOK A.3); the SessionStart hook exports `GODOT_BIN`/`PYTHON` for desktop sessions as it already did in the cloud.

## Consequences
- The status name CLOUD_VERIFIED now also covers local work whose acceptance waits on a dependency; the evidence file says where it ran.
- V01 geometry may need changes after the G08 two-player toy (reach, sync, collision); accepted, as in ADR-011.
- Nothing here counts as network qualification. CLAUDE.md sections 4 and 8 apply unchanged.

## Amendment (30 Oct 2026): Claude runs the git/GitHub process
The owner said: "Merge pull push commit tag CI all should be handled by you. I approve all the meaningful processes." Waiting on the owner
to merge had stalled V07 behind PR #29.
- Claude commits, pushes, opens PRs and **merges them into `main` with a merge commit once the `linux` and `windows` CI jobs pass**. Claude also fixes CI,
  creates tags and manages issues.
- Still binding: no direct pushes to `main`, no force-push, one task per branch (decision 4), and the CLAUDE.md section 6 stop-and-ask list
  (Steam/publishing, locked decisions, third-party assets, secrets, money, save deletion, the game name).
- A branch that is behind `main` and overlaps it gets `main` merged in and the full suite rerun before it merges. CI on `main` is the backstop.
- Branch protection with required checks on `main` was not applied: changing repository protection needs the owner's explicit action. The owner can
  enable it in the repository settings (require `linux` and `windows`) if wanted.
