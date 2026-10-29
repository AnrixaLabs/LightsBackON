#!/usr/bin/env python3
"""Lights Back On - backlog helper.

The backlog (docs/backlog.json) is transcribed from the Development Blueprint v1.0.
This tool exists so that cloud sessions and local sessions share one source of truth
in git, and so that "DONE" cannot be set without evidence.

Commands
  validate                      check schema, dependencies, cycles, status/evidence rules
  next [--env cloud|local|any]  print the next task(s) to work on
  list [--milestone M] [--status S]
  show ID
  set ID STATUS [--pending-local TEXT] [--blocked-reason TEXT]
  summary

Status rules (see CLAUDE.md section 6)
  * A task can be WORKED when every dependency is DONE or CLOUD_VERIFIED
    (or listed in its prep_ok_without).
  * A task can be set DONE only when every dependency is DONE and docs/evidence/<ID>.md exists.
  * CLOUD_VERIFIED = automated checks pass in a headless/cloud session, but acceptance still
    needs real hardware, a real network, a person, or a dependency that is only CLOUD_VERIFIED.
    It requires an evidence file and a non-empty --pending-local.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKLOG = ROOT / "docs" / "backlog.json"
STATUSES = ("NOT_STARTED", "IN_PROGRESS", "CLOUD_VERIFIED", "BLOCKED", "DONE")
ENV_CLOUD = ("cloud", "split")
ENV_LOCAL = ("local", "split", "human")


def load() -> dict:
    with open(BACKLOG, encoding="utf-8") as f:
        return json.load(f)


def save(doc: dict) -> None:
    with open(BACKLOG, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


def index(doc: dict) -> dict[str, dict]:
    return {t["id"]: t for t in doc["tasks"]}


def order_key(doc: dict, t: dict, pos: int) -> tuple[int, int]:
    return (doc["milestone_order"].index(t["milestone"]), pos)


def evidence_exists(t: dict) -> bool:
    p = ROOT / t["evidence_file"]
    return p.is_file() and p.stat().st_size > 0


def deps_for_work(t: dict, idx: dict[str, dict]) -> bool:
    skip = set(t.get("prep_ok_without", []))
    return all(d in skip or idx[d]["status"] in ("DONE", "CLOUD_VERIFIED") for d in t["depends_on"])


def deps_for_done(t: dict, idx: dict[str, dict]) -> bool:
    return all(idx[d]["status"] == "DONE" for d in t["depends_on"])


def validate(doc: dict) -> list[str]:
    errs: list[str] = []
    idx = index(doc)
    if len(idx) != len(doc["tasks"]):
        errs.append("duplicate task ids")
    for t in doc["tasks"]:
        i = t["id"]
        if t["status"] not in STATUSES:
            errs.append(f"{i}: bad status {t['status']}")
        for d in t["depends_on"]:
            if d not in idx:
                errs.append(f"{i}: unknown dependency {d}")
        if t["status"] in ("DONE", "CLOUD_VERIFIED") and not evidence_exists(t):
            errs.append(f"{i}: status {t['status']} but {t['evidence_file']} is missing or empty")
        if t["status"] == "DONE" and not deps_for_done(t, idx):
            errs.append(f"{i}: DONE but a dependency is not DONE")
        if t["status"] == "CLOUD_VERIFIED" and not t.get("pending_local"):
            errs.append(f"{i}: CLOUD_VERIFIED needs pending_local")
        if t["status"] == "BLOCKED" and not t.get("blocked_reason"):
            errs.append(f"{i}: BLOCKED needs blocked_reason")
    # cycle check
    state: dict[str, int] = {}

    def visit(n: str, path: list[str]) -> None:
        if state.get(n) == 2:
            return
        if state.get(n) == 1:
            errs.append("dependency cycle: " + " -> ".join(path + [n]))
            return
        state[n] = 1
        for d in idx[n]["depends_on"]:
            if d in idx:
                visit(d, path + [n])
        state[n] = 2

    for n in idx:
        visit(n, [])
    return errs


def fmt(t: dict, note: str = "") -> str:
    s = f"{t['id']:5} [{t['status']}] {t['title']}  ({t['role']}, {t['hours']} h, env={t['env']})"
    if note:
        s += f"\n      {note}"
    return s


def cmd_next(doc: dict, env: str, limit: int) -> int:
    idx = index(doc)
    out: list[tuple[tuple[int, int, int, int], dict, str]] = []
    for pos, t in enumerate(doc["tasks"]):
        st = t["status"]
        if env == "local" and st == "CLOUD_VERIFIED":
            out.append(((0, 0, *order_key(doc, t, pos)), t, "verify locally: " + "; ".join(t.get("pending_local", []))))
            continue
        if st not in ("NOT_STARTED", "IN_PROGRESS"):
            continue
        if env == "cloud" and t["env"] not in ENV_CLOUD:
            continue
        if env == "local" and t["env"] not in ENV_LOCAL:
            continue
        if not deps_for_work(t, idx):
            continue
        skip = set(t.get("prep_ok_without", []))
        override = any(d in skip and idx[d]["status"] not in ("DONE", "CLOUD_VERIFIED") for d in t["depends_on"])
        note = t["env_note"]
        if override:
            note = ("OVERRIDE: starts before " + ", ".join(sorted(skip)) + " is DONE (prep_ok_without: blueprint s12 for the grid toy, ADR-011 for V02); "
                    "ceiling is CLOUD_VERIFIED. " + note).strip()
        elif not deps_for_done(t, idx):
            note = ("ceiling CLOUD_VERIFIED until dependencies are DONE. " + note).strip()
        prio = 1 if st == "IN_PROGRESS" else 2
        out.append(((prio, 1 if override else 0, *order_key(doc, t, pos)), t, note))
    out.sort(key=lambda x: x[0])
    if not out:
        print(f"No unblocked {env} tasks. Run `list --status NOT_STARTED` to see what is waiting on what.")
        return 0
    for _, t, note in out[:limit]:
        print(fmt(t, note))
    return 0


def cmd_list(doc: dict, milestone: str | None, status: str | None) -> int:
    idx = index(doc)
    for t in doc["tasks"]:
        if milestone and t["milestone"] != milestone:
            continue
        if status and t["status"] != status:
            continue
        waiting = [d for d in t["depends_on"] if idx[d]["status"] != "DONE"]
        note = ("waiting on: " + ", ".join(f"{d}({idx[d]['status']})" for d in waiting)) if waiting else ""
        print(fmt(t, note))
    return 0


def cmd_show(doc: dict, tid: str) -> int:
    t = index(doc).get(tid)
    if not t:
        print(f"unknown task {tid}", file=sys.stderr)
        return 1
    print(json.dumps(t, indent=2, ensure_ascii=False))
    return 0


def cmd_set(doc: dict, tid: str, status: str, pending: str | None, reason: str | None) -> int:
    idx = index(doc)
    t = idx.get(tid)
    if not t:
        print(f"unknown task {tid}", file=sys.stderr)
        return 1
    if status not in STATUSES:
        print(f"status must be one of {STATUSES}", file=sys.stderr)
        return 1
    if status == "DONE":
        if not deps_for_done(t, idx):
            bad = [d for d in t["depends_on"] if idx[d]["status"] != "DONE"]
            print(f"refused: dependencies not DONE: {bad}", file=sys.stderr)
            return 1
        if not evidence_exists(t):
            print(f"refused: {t['evidence_file']} missing or empty", file=sys.stderr)
            return 1
        t.pop("pending_local", None)
        t.pop("blocked_reason", None)
    elif status == "CLOUD_VERIFIED":
        if not deps_for_work(t, idx):
            print("refused: dependencies are neither DONE nor CLOUD_VERIFIED", file=sys.stderr)
            return 1
        if not evidence_exists(t):
            print(f"refused: {t['evidence_file']} missing or empty", file=sys.stderr)
            return 1
        if not pending:
            print("refused: CLOUD_VERIFIED needs --pending-local (what still requires real hardware/network/people)", file=sys.stderr)
            return 1
        t["pending_local"] = [p.strip() for p in pending.split(";") if p.strip()]
    elif status == "BLOCKED":
        if not reason:
            print("refused: BLOCKED needs --blocked-reason", file=sys.stderr)
            return 1
        t["blocked_reason"] = reason
    t["status"] = status
    errs = validate(doc)
    if errs:
        print("refused, backlog would be invalid:\n  " + "\n  ".join(errs), file=sys.stderr)
        return 1
    save(doc)
    print(f"{tid} -> {status}")
    return 0


def cmd_summary(doc: dict) -> int:
    per: dict[str, dict[str, int]] = {}
    for t in doc["tasks"]:
        m = per.setdefault(t["milestone"], {"n": 0, "done": 0, "cv": 0, "h": 0, "hd": 0})
        m["n"] += 1
        m["h"] += t["hours"]
        if t["status"] == "DONE":
            m["done"] += 1
            m["hd"] += t["hours"]
        if t["status"] == "CLOUD_VERIFIED":
            m["cv"] += 1
    print("milestone  tasks  done  cloud_verified  est_hours (done)")
    for k in doc["milestone_order"]:
        m = per[k]
        print(f"{k:9}  {m['n']:5}  {m['done']:4}  {m['cv']:14}  {m['h']:5} ({m['hd']})")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate")
    sub.add_parser("summary")
    p = sub.add_parser("next")
    p.add_argument("--env", choices=("cloud", "local", "any"), default="any")
    p.add_argument("--limit", type=int, default=3)
    p = sub.add_parser("list")
    p.add_argument("--milestone")
    p.add_argument("--status")
    p = sub.add_parser("show")
    p.add_argument("id")
    p = sub.add_parser("set")
    p.add_argument("id")
    p.add_argument("status")
    p.add_argument("--pending-local")
    p.add_argument("--blocked-reason")
    a = ap.parse_args()

    doc = load()
    if a.cmd == "validate":
        errs = validate(doc)
        if errs:
            print("INVALID\n  " + "\n  ".join(errs))
            return 1
        print(f"OK: {len(doc['tasks'])} tasks")
        return 0
    if a.cmd == "next":
        return cmd_next(doc, a.env, a.limit)
    if a.cmd == "list":
        return cmd_list(doc, a.milestone, a.status)
    if a.cmd == "show":
        return cmd_show(doc, a.id)
    if a.cmd == "set":
        return cmd_set(doc, a.id, a.status, a.pending_local, a.blocked_reason)
    if a.cmd == "summary":
        return cmd_summary(doc)
    return 2


if __name__ == "__main__":
    sys.exit(main())
