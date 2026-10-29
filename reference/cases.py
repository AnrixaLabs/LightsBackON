"""Shared scenario runner for the reference model (used by reference/tests and tools/cross_check_reference.py)."""
from __future__ import annotations

import copy
import json
from pathlib import Path

from lbo_grid import Grid

ROOT = Path(__file__).resolve().parent.parent
CASES_PATH = ROOT / "tests" / "data" / "c01_grid_cases.json"


def res_path(p: str) -> Path:
    return ROOT / p.removeprefix("res://")


def load_cases() -> dict:
    return json.loads(CASES_PATH.read_text(encoding="utf-8"))


def expand(steps: list, macros: dict) -> list[dict]:
    out: list[dict] = []
    for s in steps:
        out += expand(macros[s[1:]], macros) if isinstance(s, str) else [s]
    return out


def definition_for(doc: dict, case: dict, reverse: bool = False) -> dict:
    d = copy.deepcopy(json.loads(res_path(doc["definition"]).read_text(encoding="utf-8")))
    for rec in d["nodes"] + d["edges"]:
        rec.update(case.get("patch", {}).get(rec["id"], {}))
    if reverse:
        d["nodes"].reverse()
        d["edges"].reverse()
    return d


def run_case(doc: dict, case: dict, reverse: bool = False) -> tuple[Grid, list[dict]]:
    """Returns the final grid and one record per step: {cmd, result, hash_before, hash_after}. Tick steps report trips."""
    g = Grid.load(definition_for(doc, case, reverse))
    log: list[dict] = []
    for cmd in expand(case["steps"], doc["macros"]):
        before = g.canonical_hash()
        if cmd["op"] == "tick":
            events: list[dict] = []
            for _ in range(cmd["count"]):
                events += g.step()
            res = {"ok": True, "trips": [e["breaker"] for e in events], "overload_ticks": dict(g.overload_ticks)}
        else:
            res = g.apply({k: v for k, v in cmd.items() if not k.startswith("expect")})
        log.append({"cmd": cmd, "result": res, "hash_before": before, "hash_after": g.canonical_hash()})
    return g, log
