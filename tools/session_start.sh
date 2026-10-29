#!/usr/bin/env bash
# SessionStart hook (wired in .claude/settings.json).
# Cloud (CLAUDE_CODE_REMOTE=true): installs the pinned Godot. Local desktop/CLI: finds the installed Godot and Python.
# Either way it exports GODOT_BIN and PYTHON for later Bash tool calls and prints the backlog summary. Never blocks a session.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}"
source tools/find_tools.sh

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  BIN="$(bash tools/setup_godot_linux.sh 2>/tmp/godot_setup.err)" || {
    echo "Godot setup FAILED (see /tmp/godot_setup.err). Tests that need Godot cannot run." >&2
    exit 0
  }
  EXTRA_PATH='export PATH="$HOME/.local/bin:$PATH"'
else
  BIN="${GODOT_BIN:-$(find_godot)}"
  EXTRA_PATH=""
fi
PY="${PYTHON:-$(find_python)}"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  [ -n "$BIN" ] && echo "export GODOT_BIN=\"$BIN\"" >> "$CLAUDE_ENV_FILE"
  [ -n "$PY" ] && echo "export PYTHON=\"$PY\"" >> "$CLAUDE_ENV_FILE"
  [ -n "$EXTRA_PATH" ] && echo "$EXTRA_PATH" >> "$CLAUDE_ENV_FILE"
fi
if [ -n "$BIN" ]; then echo "Godot ready: $("$BIN" --headless --version 2>/dev/null)"; else echo "Godot 4.7.2 not found (set GODOT_BIN)"; fi
[ -n "$PY" ] && "$PY" tools/backlog.py summary 2>/dev/null || true
