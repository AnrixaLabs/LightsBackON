# ADR-011: Cloud work continues while the Steam spike (F02) is deferred

- Status: Accepted by the owner (Levon), 29 Oct 2026. Revisit when a second Steam account is available and F02 starts.

## Context
The local PC pass (docs/PC-RUNBOOK.md) ran on 29 Oct 2026 on the owner's GTX 1650 laptop:
- Session A (tools): done. Session B (all checks on Windows): PASS. Session C (F01 windowed launch): PASS. F01 and G01-G03 are DONE (PR #17).
- Sessions D/E (F02 Steam spike, Steam reruns): **not started**. There is no second Steam account yet, so the two-PC, two-network test cannot run.
  The owner has not yet approved the GodotSteam extension or test app 480 (both stop-and-ask items).
- Session F decisions (font, HUD panel style, repo visibility) are still open.

With F02 not started, `backlog.py next --env cloud` returned nothing: every remaining task waits on F02 directly or through F06/G08, or on the
local graybox V01. The owner asked that the cloud keep developing everything that does not need Steam, a second PC or the editor.

## Decision
1. **F02 is BLOCKED** (reason recorded in the backlog). F02, F06, G08 and every Steam/two-PC/editor acceptance stay open; nothing here counts as
   network qualification (CLAUDE.md sections 4 and 8 still apply in full).
2. **V02 gets `prep_ok_without: ["V01"]`.** C01 mission logic (pump latch, access predicates, 10 s final verification, extraction readiness and
   cancel, replayable solution trace) is pure host logic over content data and the existing grid, interaction and equipment services; it does not
   need graybox geometry. Positions and zones are authored content IDs with placeholder coordinates until V01 places them.
   This unblocks, in order, the cloud-capable parts of V02, then V03, V06, V08, V04 and V05.
3. **Ceiling CLOUD_VERIFIED** for all of them until their dependencies are DONE. Each evidence file lists in `pending_local` what still needs V01
   geometry, real peers on the F02 tuple, or people (for example V06's two-tester pings-only run).
4. Network-facing work (V04 snapshot flow, V05 movement sync, V06 pings/chat) is built against `transport_adapter.gd` on the offline/ENet
   development transport only; the Steam path keeps refusing with STEAM_NOT_QUALIFIED. No GodotSteam, Steamworks SDK, `steam_appid.txt`
   or app ID is added.
5. Still not allowed from the cloud: art, models, fonts, sounds or other third-party assets; editor scene work for V01/V07; any task-status claim
   that needs Windows hardware, Steam or people.

## Consequences
- Later Steam results may force changes to V04/V05/V06 (channel layout, packet sizes, reconnect timing). That rework risk is accepted; keep the
  transport behind the adapter and test against the single-reliable-channel baseline.
- When F02 starts, resume docs/PC-RUNBOOK.md at session D. Remove V02's `prep_ok_without` once V01 is DONE.
