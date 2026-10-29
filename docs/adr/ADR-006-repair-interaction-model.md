# ADR-006: Repair interaction model

- Status: Accepted (G04, cloud sprint B, 29 Oct 2026). Clarifies blueprint p.8 and CLAUDE.md section 3 "Repair state machine". Changes no locked decision.

## Decision
1. **One state machine for every repair**: undiagnosed -> diagnosed -> isolated -> opened -> component_removed -> replacement_installed -> closed
   -> tested -> restored, driven by the steps diagnose, isolate, open, remove, install, close, test, restore. Each step is one discrete
   `repair_step` intention and one atomic durable transition. Cancel (`release`) only drops the lock.
2. **Preconditions, checked by the host on every step**: sender is the lock owner, the host's range check passes, the step is the next one
   (an earlier step is an idempotent duplicate: `ok`, `duplicate: true`, no change; a later one is WRONG_STEP naming the next step),
   diagnose needs a current meter snapshot of the repair's panel (NOT_INSPECTED), open/remove/install/close/test need the panel's junction
   isolated **right now** (ISOLATE_FIRST, so re-energizing mid-repair is caught), and the step's tool must be equipped (MISSING_TOOL).
3. **Side effects**: isolate sets the junction isolated; install checks and consumes exactly one component from the crew supply and applies
   the repair's grid fix in the same transition; restore clears isolation and, if tripped, resets the breaker. If either grid command is
   refused (DUAL_SUPPLY, RESET_OVERLOADED), restore is undone (junction re-isolated) and refused as GRID_REFUSED with the grid code and
   conflicting IDs. A restored repair releases its lock (`completed`).
4. **Locks**: one owner per repair; a second requester gets LOCKED_BY_OTHER with the owner ID (others see who is working). Released on cancel,
   `left_range`, `disconnect_player`, or when `now - last_seen >= lock_heartbeat_timeout_ticks` (20 = 2 s at 10 Hz). Any valid repair
   request or `heartbeat` refreshes `last_seen`.
5. **Access**: a repair may name an access flag set by the mission director (C01 east trunk: PUMP_HOUSE_DRAINED, SIM12). Without it the lock is refused (NO_ACCESS).
6. **Holds**: content `hold_ticks` per step is presentation for the client; the loader rejects any hold above `max_hold_ticks` (12 = 1.2 s).
   The host does not time holds in this version (anti-cheat timing is out of scope; revisit in F03 if needed).
7. **Supplies** are an interim crew stock (`supplies` in repairs.json) until carried inventory exists; tools are a per-player loadout with one
   equipped tool, since all essential tools are available from the start.
8. **Selection**: `target_selector.gd` picks the target from a 2.3 m center ray (ray hit first) plus a 6 degree aim-assist cone (design choice),
   with ties broken by angle, distance and ID, so the host can re-run it to validate a client's claimed target.
9. Every refusal carries `code`, a localization key `interaction.refused.<code>`, a message and the IDs to highlight (prompt "object | verb | missing condition").
   Sequence-number dedupe across the network is F03, not this service.
