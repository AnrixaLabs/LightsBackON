#!/usr/bin/env python3
"""Write build_manifest.json with the version fields from blueprint p.41.

    python3 tools/build_manifest.py [--godot PATH] [--templates DIR] [--out build_manifest.json]

Fields: engine_version, engine_hash, export_templates_hash, steam_wrapper_revision,
multiplayer_peer_revision, extension_binary_hashes, steamworks_runtime_version, protocol_version,
save_schema_version, content_revision, git_commit, build_id. Extra fields (prefixed by what they
describe) make the manifest auditable for REL04.

The default output is res://build_manifest.json, which the Windows export preset includes and the
Boot scene logs. It is gitignored: a manifest describes one build, not the source tree.
Values that do not exist yet are the string "none" (never null, never a guess).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NONE = "none"
TEMPLATE_FILES = ("windows_release_x86_64.exe", "windows_debug_x86_64.exe")
EXTENSION_SUFFIXES = (".dll", ".so", ".dylib")


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git(*args: str) -> str:
    try:
        return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def find_godot(explicit: str | None) -> Path | None:
    cand = explicit or os.environ.get("GODOT_BIN") or shutil.which("godot")
    return Path(cand) if cand and Path(cand).is_file() else None


def engine_info(godot: Path | None) -> dict:
    if godot is None:
        return {"engine_version": NONE, "engine_hash": NONE, "engine_binary_sha256": NONE}
    out = subprocess.run([str(godot), "--headless", "--version"], capture_output=True, text=True).stdout.strip()
    version = out.splitlines()[-1] if out else NONE
    # "4.7.2.stable.official.ed1daf0bf": the last component is the engine source commit
    m = re.search(r"\.([0-9a-f]{7,40})$", version)
    return {
        "engine_version": version,
        "engine_hash": m.group(1) if m else NONE,
        "engine_binary_sha256": sha256_file(godot),
    }


def templates_info(version: str, explicit: str | None) -> dict:
    short = ".".join(version.split(".")[:4]) if version != NONE else ""  # 4.7.2.stable
    if explicit:
        d = Path(explicit)
    elif os.name == "nt":
        d = Path(os.environ.get("APPDATA", "")) / "Godot" / "export_templates" / short
    else:
        d = Path.home() / ".local" / "share" / "godot" / "export_templates" / short
    files = {f: sha256_file(d / f) for f in TEMPLATE_FILES if (d / f).is_file()}
    if not files:
        return {"export_templates_hash": NONE, "export_templates_files": {}}
    combined = hashlib.sha256("".join(f"{k}:{v}\n" for k, v in sorted(files.items())).encode()).hexdigest()
    return {"export_templates_hash": combined, "export_templates_files": files}


def content_revision() -> str:
    """SHA-256 over sorted (relative path, bytes) of everything under content/."""
    h = hashlib.sha256()
    base = ROOT / "content"
    for p in sorted(x for x in base.rglob("*") if x.is_file()):
        rel = p.relative_to(ROOT).as_posix()
        h.update(rel.encode() + b"\0")
        h.update(p.read_bytes() + b"\0")
    return h.hexdigest()


def extension_hashes() -> dict:
    out: dict[str, str] = {}
    for d in (ROOT / "addons", ROOT / "bin"):
        if d.is_dir():
            for p in sorted(d.rglob("*")):
                if p.is_file() and p.suffix.lower() in EXTENSION_SUFFIXES:
                    out[p.relative_to(ROOT).as_posix()] = sha256_file(p)
    return out


def build(args: argparse.Namespace) -> dict:
    versions = json.loads((ROOT / "content" / "versions.json").read_text(encoding="utf-8"))
    eng = engine_info(find_godot(args.godot))
    tpl = templates_info(eng["engine_version"], args.templates)
    commit = git("rev-parse", "HEAD") or NONE
    dirty = bool(git("status", "--porcelain"))
    now = datetime.now(timezone.utc)
    build_id = f"{now.strftime('%Y%m%dT%H%M%SZ')}-{commit[:10]}{'-dirty' if dirty else ''}"
    return {
        "engine_version": eng["engine_version"],
        "engine_hash": eng["engine_hash"],
        "engine_binary_sha256": eng["engine_binary_sha256"],
        "export_templates_hash": tpl["export_templates_hash"],
        "export_templates_files": tpl["export_templates_files"],
        "steam_wrapper_revision": NONE,       # GodotSteam not integrated yet (F02)
        "multiplayer_peer_revision": NONE,    # Steam multiplayer peer not integrated yet (F02)
        "extension_binary_hashes": extension_hashes(),
        "steamworks_runtime_version": NONE,   # never committed; recorded only by local Steam builds
        "protocol_version": int(versions["protocol_version"]),
        "save_schema_version": int(versions["save_schema_version"]),
        "content_revision": content_revision(),
        "git_commit": commit,
        "git_dirty": dirty,
        "build_id": build_id,
        "built_at_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", help="Godot binary (default: $GODOT_BIN or godot on PATH)")
    ap.add_argument("--templates", help="export template directory (default: Godot's per-user directory)")
    ap.add_argument("--out", default=str(ROOT / "build_manifest.json"))
    a = ap.parse_args()
    manifest = build(a)
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
