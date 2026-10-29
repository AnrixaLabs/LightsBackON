# ADR-012: Mission director rules (C01 and shared)

- Status: Accepted (V02, cloud, 29 Oct 2026, under ADR-011). Clarifies blueprint p.7 (C01 known solution) and p.18 (shared mission rules).

## Decision
1. **Content-driven** (`content/contracts/<c>/mission.json`): grid source, required consumers, excluded loads, access latches, final verification
   ticks, extraction zone and countdown, objectives. C01: required APT_E, APT_W, MARKET, PUB, WORKSHOP; excluded SIGN; latch LATCH_PUMP_DRAIN
   (PUMP supplied 120 continuous ticks -> access flag PUMP_HOUSE_DRAINED); verification 100 ticks; countdown 50 ticks in ZONE_VAN.
2. **Latches** count continuous supplied ticks and, once reached, stay latched for the contract (SIM13); a gap resets the count (SIM12).
3. **"Grid supply"** means supplied *and* the live path above the consumer roots at the grid source. A building lit by the temporary generator
   never counts toward verification or a restoration objective.
4. **Final verification** counts continuous ticks with every required consumer on grid supply; any loss resets it to 0 (SIM14). It is a continuous
   condition, not a latch: losing it later cancels a countdown.
5. **Extraction** (resolves HANDOFF issue 5 by supporting both rules): any connected player may start the countdown when verification holds, every
   portable item is stowed and every connected player is in the zone; any player may cancel; leaving the zone, losing verification or unstowing
   cancels it automatically (MIS04). Disconnected players are not required. A second "start" while running is an idempotent duplicate.
6. **Objectives** are evaluated from host state, ordered in content, and the first `max_visible_objectives` (3) not yet done are visible
   (blueprint p.11). Text keys never name the repair (pillar 1); the "stow equipment" row only counts as done once the site is verified, so a
   generator that never left the van does not tick it off at the start.
7. **Solution traces** (`solution.json`) are host intents replayed through `session_host.gd` with `pace_ticks_per_command` (1 tick per command:
   a human-speed upper bound that stays inside the per-sender rate limit). `tools/run_tests.sh` fails if any contract's trace does not complete.
8. Pause/time freeze in offline solo is not modelled yet; the host simply stops calling `tick()`.
