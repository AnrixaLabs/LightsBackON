#!/usr/bin/env bash
# Run every automated check that exists. Works on Linux (cloud) and Git Bash on Windows.
#   tools/run_tests.sh                 # all
#   tools/run_tests.sh --filter=grid   # only Godot test files/methods containing "grid"
# GODOT_BIN / PYTHON override discovery. Without them: `godot` on PATH, then the PC-RUNBOOK install path
# C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe; python3, python, then py -3, skipping the Windows Store stub.
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/find_tools.sh

GODOT_BIN="${GODOT_BIN:-$(find_godot)}"
PY="${PYTHON:-$(find_python)}"
FAIL=0

echo "== backlog =="
if [ -n "$PY" ]; then "$PY" tools/backlog.py validate || FAIL=1; else echo "no python found"; FAIL=1; fi

echo "== content (ADR-003 integer data) =="
if [ -n "$PY" ]; then "$PY" tools/validate_content.py || FAIL=1; fi

echo "== UI token contrast (WCAG 2.2 AA, ADR-004) =="
if [ -n "$PY" ]; then "$PY" tools/check_contrast.py | tail -1; [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1; fi

echo "== python reference model (re-derived, reference/tests) =="
if [ -d reference/tests ] && [ -n "$PY" ]; then
  ( cd reference && "$PY" -m unittest discover -s tests -v ) || FAIL=1
else
  echo "skipped: reference/tests not present"
fi

echo "== godot =="
if [ -f project.godot ] && [ -z "$GODOT_BIN" ]; then
  echo "FAIL: Godot 4.7.2 not found; set GODOT_BIN to the console exe (see docs/PC-RUNBOOK.md A.3)"; FAIL=1
elif [ -f project.godot ]; then
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true   # builds the class cache on a fresh clone
  GD_OUT="$(mktemp)"
  "$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$GD_OUT"
  [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  # GDScript cannot catch runtime errors, so a test that crashes mid-way could still report PASS: fail on any
  if grep -qE "SCRIPT ERROR|Parse Error" "$GD_OUT"; then echo "FAIL: Godot reported script errors (see above)"; FAIL=1; fi
  rm -f "$GD_OUT"
  echo "== solution traces: every contract with a solution.json must be solvable =="
  for sol in content/contracts/*/solution.json; do
    [ -f "$sol" ] || continue
    "$GODOT_BIN" --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --contract="res://$(dirname "$sol")" 2>&1 | grep -E "SOLVED|MISMATCH|CONTENT ERRORS"
    [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  done
  echo "== cross-check: python reference vs godot canonical hashes =="
  if [ -n "$PY" ]; then GODOT_BIN="$GODOT_BIN" "$PY" tools/cross_check_reference.py || FAIL=1; fi
else
  echo "skipped: no project.godot yet (task F01)"
fi

[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
exit "$FAIL"
