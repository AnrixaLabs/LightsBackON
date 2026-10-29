#!/usr/bin/env bash
# Install the pinned Godot editor (win64 console exe) for headless use from Git Bash on Windows
# (GitHub Actions windows runners, or your PC). Idempotent. Verifies the official SHA512 sum.
# Prints the Windows-style path to the console exe (usable from bash and from Windows Python).
#
# Usage:  GODOT_BIN="$(bash tools/setup_godot_windows.sh)"
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/godot/${GODOT_VERSION}-win64}"
EXE="Godot_v${GODOT_VERSION}_win64_console.exe"
BIN="$INSTALL_DIR/$EXE"
WANT="${GODOT_VERSION%-stable}.stable"

winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }

if [ -f "$BIN" ] && "$BIN" --headless --version 2>/dev/null | grep -q "^${WANT}"; then
  winpath "$BIN"
  exit 0
fi

BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}"
ZIP="Godot_v${GODOT_VERSION}_win64.exe.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 -m 600 -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL --retry 3 -m 60  -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
( cd "$TMP" && grep " ${ZIP}\$" SHA512-SUMS.txt | sha512sum -c - >&2 )

mkdir -p "$INSTALL_DIR"
unzip -qo "$TMP/$ZIP" -d "$INSTALL_DIR"
"$BIN" --headless --version | grep -q "^${WANT}" || { echo "version check failed" >&2; exit 1; }
winpath "$BIN"
