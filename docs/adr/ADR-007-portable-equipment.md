# ADR-007: Portable equipment (generator) model

- Status: Accepted (G05, cloud sprint B, 29 Oct 2026). Clarifies blueprint p.7 (C01 generator) and p.8 (carry, recovery). Changes no locked decision.

## Decision
1. Content `equipment.json` lists portable items bound to a grid source and its breaker junction (C01: GEN_PORTABLE -> GEN 6 PU, breaker TEMP),
   authored **anchors** (storage anchors such as VAN_BAY, and work pads such as PAD_PUMP) and, per anchor, the **route edges** a placed item can be
   cabled into. Cables are authored curves between sockets for presentation only; the host only tracks which route edges are enabled.
2. **Invariant**: an item that is carried or stored is stopped with no connected routes. pickup is refused while running (STOP_FIRST) or cabled
   (DISCONNECT_FIRST); start/stop/connect need the item placed at a work pad (PLACE_FIRST); a pad only offers its own sockets (NO_SOCKET); one
   carrier at a time (CARRIED_BY_OTHER / NOT_CARRIER); a work pad holds one item (ANCHOR_OCCUPIED).
3. Route toggles, start/stop and breaker reset are grid commands, so an unsafe source tie (e.g. generator -> pub while the pub is on grid) is refused
   by `power_grid.gd` before any mutation and reported as GRID_REFUSED with grid_code DUAL_SUPPLY and the conflicting IDs; a reset while still
   overloaded is RESET_OVERLOADED (G02).
4. **Recovery** (van menu) works from anywhere: stop, disconnect every route, return the item to `recovery_anchor`. It never touches repairs or supplies.
5. **Carrier disconnect** returns the item to the last anchor it stood on (NET05 logic). Movement while carrying (2.8 m/s) is presentation/player-controller work.
6. **Stowed** = every portable item at a storage anchor (C01 extraction precondition). No fuel model in C01.
