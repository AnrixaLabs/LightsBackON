#!/usr/bin/env bash
# Sourced by run_tests.sh and session_start.sh. Prints a usable interpreter/binary path, or nothing.

find_python() {
  local c
  # On Windows `python3` is often the Microsoft Store alias stub: it exists but cannot run code.
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  if command -v py >/dev/null 2>&1 && py -3 -c "import sys" >/dev/null 2>&1; then echo "py"; fi
}

find_godot() {
  local c
  for c in godot /c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
}
