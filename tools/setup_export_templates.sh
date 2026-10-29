#!/usr/bin/env bash
# Install the pinned Godot export templates (Windows x86_64 only) for headless exports
# on Linux (cloud sessions, CI). Idempotent. Verifies the official SHA512 of the .tpz.
# The .tpz is ~1.3 GB; only the Windows templates are kept (~200 MB).
#
# Source: GitHub release assets of godotengine/godot-builds (same as setup_godot_linux.sh).
# On Windows use the editor's Export Template Manager instead and record the hash in the evidence file.
#
# Usage:  tools/setup_export_templates.sh      # prints the template directory
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
WANT="${GODOT_VERSION%-stable}.stable"   # e.g. 4.7.2.stable
DEST="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/$WANT}"
KEEP=(windows_release_x86_64.exe windows_debug_x86_64.exe version.txt)

if [ -f "$DEST/windows_release_x86_64.exe" ] && [ -f "$DEST/version.txt" ] && grep -q "^${WANT}$" "$DEST/version.txt"; then
  echo "$DEST"
  exit 0
fi

BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}"
TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 -m 1800 -o "$TMP/$TPZ" "$BASE/$TPZ"
curl -fsSL --retry 3 -m 60   -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
( cd "$TMP" && grep " ${TPZ}\$" SHA512-SUMS.txt | sha512sum -c - >&2 )

mkdir -p "$DEST"
for f in "${KEEP[@]}"; do
  unzip -qo -j "$TMP/$TPZ" "templates/$f" -d "$DEST"
done
grep -q "^${WANT}$" "$DEST/version.txt" || { echo "template version mismatch" >&2; exit 1; }
echo "$DEST"
