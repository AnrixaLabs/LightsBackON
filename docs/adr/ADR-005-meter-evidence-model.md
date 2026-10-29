# ADR-005: Meter readings and evidence model

- Status: Accepted (G03, cloud sprint A, 29 Oct 2026). Clarifies blueprint p.8 ("the meter shows source presence, continuity,
  branch demand, capacity, and breaker reason. Unknown data uses a question mark, not a false zero") and pillar 1. Changes no locked decision.

## Decision
1. **Panels** are content (`content/contracts/<contract>/meter.json`): an authored panel ID attached to a grid source or junction.
   `initial_breaker_reasons` explains breakers that start tripped (C01: JW = `fault`).
2. **Readings.** Junction panel: `source_present`, `feed_<EDGE>` per incoming edge (`closed` / `open` = broken / `switched_off` = disabled),
   `component` (`intact`/`open`), `isolator` (`closed`/`open`), `breaker` (`closed`/`tripped`), `breaker_reason` (`fault`/`overload`),
   `load_pu` (flow on the live feed), `capacity_pu` (that feed's capacity), `demand_pu` (what the branch would draw: enabled healthy
   consumers through active edges and unblocked downstream junctions, ignoring this junction's own block), `trip_load_pu` / `trip_capacity_pu`
   (recorded at the overload trip). Source panel: `online`, `load_pu`, `capacity_pu`.
3. **Unknown is the default.** Every field is `{"known": false, "display": "?"}` until `inspect`; an unknown never carries a value.
   An inspected 0 is `{"known": true, "value": 0, "display": "0"}`.
4. **Snapshots expire as a whole.** `inspect` stores a snapshot; if any measured value on that panel later differs from the live value,
   every field on the panel reverts to unknown with `needs_reinspect: true`. Expiring only the changed field would reveal a boolean's new value
   without a measurement. (This does tell the player that *something* on that panel changed; accepted as low information. A "meter stays
   clipped on" live mode can be added by the interaction layer, G04, without changing this model.)
5. **Breaker reason** is known only from evidence: `fault` from content, `overload` from a grid `trip` event (which carries flow and capacity at
   the trip). A breaker tripped any other way reads `?` (TRIPPED_UNKNOWN), never a guess. A breaker that closes forgets its reason.
6. **Findings** are observations from known readings only: NO_SOURCE, FEED_OPEN, FEED_SWITCHED_OFF, COMPONENT_OPEN, ISOLATED,
   TRIPPED_FAULT, TRIPPED_OVERLOAD, TRIPPED_UNKNOWN, DEMAND_OVER_CAPACITY, SOURCE_OFFLINE, SOURCE_OVERLOADED, each with the IDs to highlight
   and a localization key `meter.finding.<code>`. They never name a repair step.
7. **Display tokens**: `?`, a decimal PU number, or a localization key `meter.value.<state>`; units and wording belong to the UI (ADR-004:
   icon + text per state, one icon per real state; these value/finding codes are the state list the meter icons are drawn from).
8. Host-owned and crew-shared; pure like `power_grid.gd` (reads only `canonical_state()`). Distance, tool and lock checks for `inspect` belong to
   the interaction service (G04), not here.
