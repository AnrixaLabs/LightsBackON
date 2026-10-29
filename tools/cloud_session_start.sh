#!/usr/bin/env bash
# SessionStart hook (wired in .claude/settings.json).
# Only acts inside Claude Code cloud sessions (CLAUDE_CODE_REMOTE=true); a no-op on your PC.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"
BIN="$(bash tools/setup_godot_linux.sh 2>/tmp/godot_setup.err)" || {
  echo "Godot setup FAILED (see /tmp/godot_setup.err). Tests that need Godot cannot run." >&2
  exit 0   # never block the session
}

# make `godot` available to later Bash tool calls
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GODOT_BIN=\"$BIN\"" >> "$CLAUDE_ENV_FILE"
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
echo "Godot ready: $("$BIN" --headless --version)"
python3 tools/backlog.py summary 2>/dev/null || true
