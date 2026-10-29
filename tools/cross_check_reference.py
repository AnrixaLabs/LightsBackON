#!/usr/bin/env python3
"""Compare the Python reference grid model with the Godot port on every C01 case (ADR-003 point 5).

    python3 tools/cross_check_reference.py [--godot PATH]

Both sides replay tests/data/c01_grid_cases.json forwards and with reversed node/edge order, and emit the
outcome and canonical SHA-256 after every command plus the final canonical string. The first difference
fails the check and prints both canonical strings. Exit 0 = identical, 1 = mismatch, 2 = could not run.

reference/ here is RE-DERIVED from the blueprint, not the original oracle (see reference/README.md).
If reference/ is absent the check is skipped with exit 0 and a clear message.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "reference"


def python_records() -> list[list[str]]:
    sys.path.insert(0, str(REF))
    from cases import load_cases, run_case  # noqa: E402
    from lbo_grid import Grid, GridError  # noqa: E402

    doc = load_cases()
    out: list[list[str]] = []
    for c in doc["cases"]:
        for direction, rev in (("fwd", False), ("rev", True)):
            g, log = run_case(doc, c, rev)
            for i, rec in enumerate(log):
                res = rec["result"]
                outcome = "ok" if res["ok"] else res["code"]
                if "trips" in res:
                    outcome = "trips:" + ",".join(res["trips"])
                out.append(["STEP", c["name"], direction, str(i), outcome, rec["hash_after"]])
            out.append(["CASE", c["name"], direction, g.canonical_hash(), g.canonical_string()])
    for c in doc["definition_cases"]:
        try:
            Grid.load(c["definition"])
            codes: list[str] = []
        except GridError as e:
            codes = sorted({d["code"] for d in e.diagnostics})
        out.append(["DEF", c["name"], ",".join(codes)])
    return out


def godot_records(godot: str) -> list[list[str]]:
    script = str(ROOT / "tools" / "godot" / "dump_grid_cases.gd")
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], capture_output=True)
    p = subprocess.run([godot, "--headless", "--path", str(ROOT), "-s", script], capture_output=True, text=True)
    if p.returncode != 0:
        print(p.stdout + p.stderr, file=sys.stderr)
        raise SystemExit(2)
    return [line.split("\t") for line in p.stdout.splitlines() if line.split("\t")[0] in ("STEP", "CASE", "DEF")]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    a = ap.parse_args()
    if not (REF / "lbo_grid.py").is_file():
        print("SKIPPED: reference/ is absent; nothing to cross-check against.")
        return 0
    if not a.godot:
        print("cannot run: no Godot binary (set GODOT_BIN or pass --godot)", file=sys.stderr)
        return 2
    py, gd = python_records(), godot_records(a.godot)
    if len(py) != len(gd):
        print(f"MISMATCH: python emitted {len(py)} records, godot {len(gd)}")
    for i, (x, y) in enumerate(zip(py, gd)):
        if x != y:
            print(f"MISMATCH at record {i}:\n  python: {x}\n  godot:  {y}")
            return 1
    if len(py) != len(gd):
        return 1
    cases = sum(1 for r in py if r[0] == "CASE")
    steps = sum(1 for r in py if r[0] == "STEP")
    defs = sum(1 for r in py if r[0] == "DEF")
    print(f"MATCH: {cases} case runs (fwd+rev), {steps} command hashes, {defs} definition rejections identical "
          "(reference is re-derived, not the original oracle)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
