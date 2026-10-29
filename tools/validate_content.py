#!/usr/bin/env python3
"""Reject content JSON that breaks ADR-003: any non-integer number (Godot's JSON parser turns every number into
a float, so 12.0 would load there; it must never reach content/). Also loads every contract grid with the
reference model when reference/ is present.

    python3 tools/validate_content.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class FloatInContent(ValueError):
    pass


def no_float(token: str) -> float:
    raise FloatInContent(token)


def main() -> int:
    errs: list[str] = []
    files = sorted((ROOT / "content").rglob("*.json"))
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        try:
            json.loads(p.read_text(encoding="utf-8"), parse_float=no_float)
        except FloatInContent as e:
            errs.append(f"{rel}: non-integer number {e} (PU and ticks are integers, ADR-003)")
        except json.JSONDecodeError as e:
            errs.append(f"{rel}: invalid JSON: {e}")
    if (ROOT / "reference" / "lbo_grid.py").is_file():
        sys.path.insert(0, str(ROOT / "reference"))
        from lbo_grid import Grid, GridError  # noqa: E402
        for p in sorted((ROOT / "content" / "contracts").glob("*/grid.json")):
            try:
                Grid.load(json.loads(p.read_text(encoding="utf-8")))
            except GridError as e:
                errs.append(f"{p.relative_to(ROOT).as_posix()}: " + "; ".join(d["message"] for d in e.diagnostics))
    for e in errs:
        print("CONTENT ERROR:", e)
    print(f"content: {len(files)} JSON files, {len(errs)} errors")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
