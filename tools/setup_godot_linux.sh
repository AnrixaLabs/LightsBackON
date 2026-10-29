#!/usr/bin/env bash
# Install the pinned Godot editor binary for headless use on Linux x86_64
# (cloud sessions, CI). Idempotent. Verifies the official SHA512 sum.
#
# Source: GitHub release assets of godotengine/godot-builds (reachable from
# Claude Code cloud "Trusted" network access; downloads.godotengine.org is not).
#
# Usage:  tools/setup_godot_linux.sh            # prints the path to the binary
#         GODOT_VERSION=4.7.2-stable tools/setup_godot_linux.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/godot/$GODOT_VERSION}"
BIN="$INSTALL_DIR/godot"
WANT="${GODOT_VERSION%-stable}.stable"   # e.g. 4.7.2.stable

if [ -x "$BIN" ] && "$BIN" --headless --version 2>/dev/null | grep -q "^${WANT}"; then
  echo "$BIN"
  exit 0
fi

BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}"
ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 -m 300 -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL --retry 3 -m 60  -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
( cd "$TMP" && grep " ${ZIP}\$" SHA512-SUMS.txt | sha512sum -c - >&2 )

mkdir -p "$INSTALL_DIR"
unzip -qo "$TMP/$ZIP" -d "$TMP/x"
mv "$TMP/x/Godot_v${GODOT_VERSION}_linux.x86_64" "$BIN"
chmod +x "$BIN"

mkdir -p "$HOME/.local/bin"
ln -sf "$BIN" "$HOME/.local/bin/godot"

"$BIN" --headless --version | grep -q "^${WANT}" || { echo "version check failed" >&2; exit 1; }
echo "$BIN"
