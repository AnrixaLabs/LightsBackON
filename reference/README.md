# reference/: Python reference grid model (RE-DERIVED, NOT THE ORIGINAL ORACLE)

The blueprint package's Python reference (`reference/`, `reference/tests/`, `reference/data/first_shift.json`) was never
delivered (docs/BOOTSTRAP-REPORT.md). This directory is a **re-derivation** written in cloud sprint A (task G01) from:

- blueprint v1.0 section 5, pp. 6-7 (power rules, C01 starting network, known-valid solution),
- the C01 table in CLAUDE.md section 3,
- ADR-003 (integer PU, integer ticks, canonical serialization).

It is an independent second implementation used to cross-check the Godot port (`tools/cross_check_reference.py`).
Agreement shows the two ports agree with each other and with the scenario expectations in `tests/data/c01_grid_cases.json`;
it does **not** show agreement with the lost original. If the original package turns up, compare it with this one and
record any difference in an ADR.

| File | Purpose |
|---|---|
| `lbo_grid.py` | topology validation, evaluation steps 1-5, command path (refuse before mutation), canonical serialization |
| `cases.py` | replays `tests/data/c01_grid_cases.json` (shared with the Godot tests) |
| `tests/test_grid.py` | unittest suite named after the acceptance matrix (SIM01-SIM08, SIM11) |

C01 data lives in `content/contracts/c01_alder_street/grid.json` (single source for both implementations), not in `reference/data/`.
Timers and trips (G02) are implemented in Godot first; see the G02 evidence for whether this model covers them.

Run: `cd reference && python3 -m unittest discover -s tests -v` (also part of `bash tools/run_tests.sh`).
