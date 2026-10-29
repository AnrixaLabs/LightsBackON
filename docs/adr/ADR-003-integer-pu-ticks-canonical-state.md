# ADR-003: Integer PU, integer ticks, canonical state serialization

- Status: Accepted (bootstrap, 29 Oct 2026); the exact state field list is fixed by G01 and appended here
- Resolves: HANDOFF section 2, issue 3; CLAUDE.md section 3 "implementation interpretations"

## Context
The blueprint states capacities in PU, a 10 Hz grid evaluation and a trip at "1.5 continuous seconds" of overload. Accumulating float
seconds drifts and can make the GDScript port and the Python reference disagree on the trip tick. The host must emit one authoritative
state that clients and the reference model can compare.

## Decision
1. **PU are integers** everywhere in simulation, content and saves (capacities, demands, flows). Floats are rejected by the content loader.
2. **Time is integer ticks.** The grid ticks at 10 Hz. Each protected branch keeps an integer `overload_ticks` counter.
   Per tick: overloaded (value strictly greater than capacity) -> counter += 1; not overloaded -> counter = 0.
   The designated upstream breaker trips on the tick where the counter **reaches 15** (= 1.5 s). Equality is not overload (SIM08).
   Content stores durations in ticks (`trip_ticks: 15`); designer-facing seconds are converted once, at authoring time.
   Other continuous-time rules use the same pattern: pump drain 12 s = 120 ticks, final hold 10 s = 100 ticks, extraction countdown 5 s = 50 ticks.
3. **Determinism.** Every traversal iterates IDs in ascending byte order of the ASCII ID string. IDs match `^[A-Z0-9_]+$`.
   Input order of nodes and edges must not change output (SIM11).
4. **Canonical serialization** of authoritative grid state (shared by GDScript and Python, byte-for-byte):
   - UTF-8 JSON, keys sorted ascending, no whitespace (`separators=(",", ":")` in Python), no trailing newline.
   - Values are only integers, booleans, ASCII strings, arrays and objects. No floats, no null, no positions or visual data.
   - Collections keyed by stable ID are objects (so key sorting orders them); arrays only where order is semantic.
   - Top level holds a `schema` integer and the `tick` integer.
   - Both implementations use a hand-written serializer (not engine JSON defaults) so number and escape formatting cannot diverge.
5. **Hash** = lowercase hex SHA-256 of the canonical bytes. `tools/cross_check_reference.py` (G01) compares the hashes from Python and Godot
   for every C01 case and fails on the first difference, printing both canonical strings.

## Consequences
- A golden-bytes test exists on both sides (same input -> identical string), not only a hash comparison.
- If the original Python reference is absent, G01 re-derives it from the C01 table and labels it "re-derived, not the original oracle".
- Changing the serialization bumps `schema` and is recorded here.
