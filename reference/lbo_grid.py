"""Lights Back On - Python reference grid evaluator (RE-DERIVED, NOT THE ORIGINAL ORACLE).

The blueprint package's original reference model was not delivered. This module is re-derived from
blueprint section 5 (pp. 6-7), the C01 table in CLAUDE.md section 3 and ADR-003. It exists so the
GDScript port (res://scripts/simulation/power_grid.gd) can be checked against an independent
implementation byte for byte (tools/cross_check_reference.py). Agreement proves the two ports agree
with each other, not that either matches the lost original.

Scope: topology validation, evaluation steps 1-8 (static evaluation, integer overload counters, timed trips,
validated resets), the command path (refuse before mutation) and the canonical serialization. The original
blueprint reference covered steps 1-5 only; the timer rules here are re-derived from blueprint p.6 and ADR-003.

Model (ADR-003): integer PU, IDs ^[A-Z0-9_]+$, every traversal in ascending ID byte order.
"""
from __future__ import annotations

import copy
import hashlib
import re
from typing import Any

SCHEMA = 2
ID_RE = re.compile(r"^[A-Z0-9_]+$")
KINDS = ("source", "junction", "consumer")

# Fields a command may set, per node kind / edge. Everything else is content-authored and immutable at runtime.
SETTABLE = {
    "source": ("online",),
    "junction": ("isolated", "failed", "tripped"),
    "consumer": ("enabled", "healthy"),
    "edge": ("enabled", "healthy"),
}
NODE_FIELDS = {
    "source": {"capacity": int, "online": bool},
    "junction": {"isolated": bool, "failed": bool, "tripped": bool},
    "consumer": {"demand": int, "enabled": bool, "healthy": bool},
}
NODE_DEFAULTS = {
    "source": {"online": False},
    "junction": {"isolated": False, "failed": False, "tripped": False},
    "consumer": {"enabled": True, "healthy": True},
}
EDGE_FIELDS = {"from": str, "to": str, "capacity": int, "enabled": bool, "healthy": bool}
EDGE_DEFAULTS = {"enabled": True, "healthy": True}
PROTECTION_FIELDS = {"element": str, "breaker": str}


class GridError(Exception):
    def __init__(self, diagnostics: list[dict]):
        super().__init__("; ".join(d["code"] for d in diagnostics))
        self.diagnostics = diagnostics


def diag(code: str, message: str, ids: list[str]) -> dict:
    return {"code": code, "message": message, "ids": sorted(set(ids))}


def _typed(value: Any, want: type) -> bool:
    if want is int:
        return type(value) is int  # bool is not int here, floats are rejected (ADR-003)
    return type(value) is want


def _check_record(rec: Any, fields: dict, defaults: dict, where: str) -> tuple[dict | None, list[dict]]:
    if not isinstance(rec, dict):
        return None, [diag("BAD_RECORD", f"{where} is not an object", [])]
    rid = rec.get("id")
    if not isinstance(rid, str) or not ID_RE.match(rid):
        return None, [diag("INVALID_ID", f"{where} id {rid!r} must match ^[A-Z0-9_]+$", [])]
    out: dict = {"id": rid}
    errs: list[dict] = []
    for k, t in fields.items():
        v = rec.get(k, defaults.get(k))
        if v is None:
            errs.append(diag("MISSING_FIELD", f"{rid}: missing {k}", [rid]))
        elif not _typed(v, t):
            errs.append(diag("BAD_VALUE", f"{rid}: {k} must be {t.__name__}", [rid]))
        elif t is int and v < 0:
            errs.append(diag("BAD_VALUE", f"{rid}: {k} must be >= 0", [rid]))
        else:
            out[k] = v
    return (None if errs else out), errs


class Grid:
    """Authoritative grid state. Construct with Grid.load(definition); never holds an invalid topology."""

    def __init__(self) -> None:
        self.nodes: dict[str, dict] = {}
        self.edges: dict[str, dict] = {}
        self.protections: dict[str, dict] = {}
        self.overload_ticks: dict[str, int] = {}
        self.trip_ticks = 0
        self.tick = 0
        self.result: dict = {}

    # ---------- loading / validation ----------
    @classmethod
    def load(cls, definition: dict) -> "Grid":
        g = cls()
        errs: list[dict] = []
        for rec in definition.get("nodes", []):
            kind = rec.get("kind") if isinstance(rec, dict) else None
            if kind not in KINDS:
                errs.append(diag("BAD_KIND", f"node {rec.get('id') if isinstance(rec, dict) else rec!r}: kind must be one of {KINDS}", []))
                continue
            n, e = _check_record(rec, NODE_FIELDS[kind], NODE_DEFAULTS[kind], "node")
            errs += e
            if n is None:
                continue
            if n["id"] in g.nodes:
                errs.append(diag("DUPLICATE_ID", f"duplicate node id {n['id']}", [n["id"]]))
                continue
            n["kind"] = kind
            g.nodes[n["id"]] = n
        for rec in definition.get("edges", []):
            ed, e = _check_record(rec, EDGE_FIELDS, EDGE_DEFAULTS, "edge")
            errs += e
            if ed is None:
                continue
            if ed["id"] in g.edges or ed["id"] in g.nodes:
                errs.append(diag("DUPLICATE_ID", f"duplicate id {ed['id']}", [ed["id"]]))
                continue
            g.edges[ed["id"]] = ed
        for rec in definition.get("protections", []):
            pr, e = _check_record(rec, PROTECTION_FIELDS, {}, "protection")
            errs += e
            if pr is None:
                continue
            pid = pr["id"]
            if pid in g.protections or pid in g.edges or pid in g.nodes:
                errs.append(diag("DUPLICATE_ID", f"duplicate id {pid}", [pid]))
                continue
            g.protections[pid] = pr
            g.overload_ticks[pid] = 0
        if g.protections:
            trip = definition.get("trip_ticks")
            if type(trip) is not int or trip < 1:
                errs.append(diag("BAD_VALUE", "trip_ticks must be an int >= 1 when protections exist", []))
            else:
                g.trip_ticks = trip
        if errs:
            raise GridError(errs)
        errs = g.validate()
        if errs:
            raise GridError(errs)
        g.evaluate()
        return g

    def validate(self) -> list[dict]:
        errs = self._validate_structure()
        if errs:
            return errs
        return self._validate_energized()

    def _validate_structure(self) -> list[dict]:
        errs: list[dict] = []
        for eid in sorted(self.edges):
            e = self.edges[eid]
            a, b = e["from"], e["to"]
            if a not in self.nodes or b not in self.nodes:
                errs.append(diag("UNKNOWN_NODE", f"{eid}: endpoint {a if a not in self.nodes else b} does not exist", [eid]))
                continue
            if a == b:
                errs.append(diag("SELF_LOOP", f"{eid}: connects {a} to itself", [eid, a]))
            if self.nodes[b]["kind"] == "source":
                what = "source-to-source connection" if self.nodes[a]["kind"] == "source" else "backfeed into a source"
                errs.append(diag("SOURCE_BACKFEED", f"{eid}: {what} ({a} -> {b})", [eid, a, b]))
            if self.nodes[a]["kind"] == "consumer":
                errs.append(diag("CONSUMER_OUTPUT", f"{eid}: consumer {a} cannot supply other nodes", [eid, a]))
        for pid in sorted(self.protections):
            element, breaker = self.protections[pid]["element"], self.protections[pid]["breaker"]
            if element not in self.edges:
                errs.append(diag("PROTECTION_ELEMENT", f"{pid}: protected edge {element} does not exist", [pid]))
            elif self.edges[element]["to"] != breaker or breaker not in self.nodes or self.nodes[breaker]["kind"] != "junction":
                errs.append(diag("PROTECTION_BREAKER", f"{pid}: breaker {breaker} must be the junction fed by {element}", [pid, element]))
        if errs:
            return errs
        cyc = self._find_cycle()
        if cyc:
            errs.append(diag("CYCLE", "supply paths form a loop: " + " -> ".join(cyc), cyc))
        return errs

    def _out_edges(self, nid: str) -> list[str]:
        return [eid for eid in sorted(self.edges) if self.edges[eid]["from"] == nid]

    def _find_cycle(self) -> list[str]:
        """Directed cycle over all potential edges (enabled or not); returns node/edge IDs on the loop, or []."""
        state: dict[str, int] = {}
        stack: list[str] = []  # alternating node, edge, node, edge, ... along the current DFS path

        def visit(nid: str) -> list[str]:
            state[nid] = 1
            stack.append(nid)
            for eid in self._out_edges(nid):
                to = self.edges[eid]["to"]
                if state.get(to) == 1:
                    return stack[stack.index(to):] + [eid]
                if state.get(to) is None:
                    stack.append(eid)
                    r = visit(to)
                    if r:
                        return r
                    stack.pop()
            stack.pop()
            state[nid] = 2
            return []

        for nid in sorted(self.nodes):
            if state.get(nid) is None:
                r = visit(nid)
                if r:
                    return r
        return []

    def _passes(self, nid: str, energized: set[str]) -> bool:
        n = self.nodes[nid]
        if n["kind"] == "source":
            return n["online"]
        if n["kind"] == "junction":
            return nid in energized and not (n["isolated"] or n["failed"] or n["tripped"])
        return False

    def _energize(self) -> tuple[set[str], set[str]]:
        """Steps 2-3: drop inactive edges/blocked junctions, traverse out from online sources in ID order."""
        energized: set[str] = set()
        live_edges: set[str] = set()
        frontier = [nid for nid in sorted(self.nodes) if self._passes(nid, energized)]
        energized.update(frontier)
        while frontier:
            nxt: list[str] = []
            for nid in frontier:
                if not self._passes(nid, energized):
                    continue
                for eid in self._out_edges(nid):
                    e = self.edges[eid]
                    if not (e["enabled"] and e["healthy"]):
                        continue
                    live_edges.add(eid)
                    if e["to"] not in energized:
                        energized.add(e["to"])
                        nxt.append(e["to"])
            frontier = sorted(nxt)
        return energized, live_edges

    def _validate_energized(self) -> list[dict]:
        _, live = self._energize()
        incoming: dict[str, list[str]] = {}
        for eid in sorted(live):
            incoming.setdefault(self.edges[eid]["to"], []).append(eid)
        errs = []
        for nid in sorted(incoming):
            if len(incoming[nid]) > 1:
                errs.append(diag("DUAL_SUPPLY", f"{nid} would receive supply from {' and '.join(incoming[nid])} at once",
                                 [nid] + incoming[nid]))
        return errs

    # ---------- evaluation (steps 1-5) ----------
    def evaluate(self) -> dict:
        energized, live = self._energize()
        supplied = {nid for nid, n in self.nodes.items()
                    if n["kind"] == "consumer" and nid in energized and n["enabled"] and n["healthy"]}
        flow: dict[str, int] = {}

        def downstream(nid: str) -> int:
            n = self.nodes[nid]
            if n["kind"] == "consumer":
                return n["demand"] if nid in supplied else 0
            if not self._passes(nid, energized):
                return 0
            total = 0
            for eid in self._out_edges(nid):
                if eid in live:
                    flow[eid] = downstream(self.edges[eid]["to"])
                    total += flow[eid]
            return total

        load: dict[str, int] = {}
        for nid in sorted(self.nodes):
            if self.nodes[nid]["kind"] == "source":
                load[nid] = downstream(nid)
        self.result = {"energized": energized, "live": live, "supplied": supplied, "flow": flow, "load": load}
        return self.result

    # ---------- commands (refused before mutation) ----------
    def apply(self, cmd: dict) -> dict:
        trial = copy.deepcopy(self)
        resets = self._resetting_breaker(cmd)
        err = trial._mutate(cmd)
        if err is None:
            errs = trial.validate()
            err = errs[0] if errs else None
        if err is None:
            trial.evaluate()
            if resets:
                err = trial._reset_refusal(resets)
        if err is not None:
            return {"ok": False, "code": err["code"], "message": err["message"], "ids": err["ids"]}
        self.nodes, self.edges = trial.nodes, trial.edges
        self.evaluate()
        return {"ok": True}

    def step(self) -> list[dict]:
        """Step 6-8 for one 10 Hz tick: count, trip at trip_ticks, recompute; returns this tick's events."""
        self.tick += 1
        events: list[dict] = []
        for pid in sorted(self.protections):
            element = self.protections[pid]["element"]
            if self.result["flow"].get(element, 0) > self.edges[element]["capacity"]:
                self.overload_ticks[pid] += 1
            else:
                self.overload_ticks[pid] = 0
            if self.overload_ticks[pid] >= self.trip_ticks:
                breaker = self.protections[pid]["breaker"]
                self.nodes[breaker]["tripped"] = True
                self.overload_ticks[pid] = 0
                events.append({"type": "trip", "tick": self.tick, "protection": pid, "element": element, "breaker": breaker,
                               "flow": self.result["flow"][element], "capacity": self.edges[element]["capacity"]})
        if events:
            self.evaluate()
        return events

    def _resetting_breaker(self, cmd: dict) -> str:
        tid = cmd.get("id")
        if (cmd.get("op") == "set" and cmd.get("field") == "tripped" and cmd.get("value") is False
                and isinstance(tid, str) and tid in self.nodes and self.nodes[tid]["kind"] == "junction"
                and self.nodes[tid]["tripped"]):
            return tid
        return ""

    def _reset_refusal(self, breaker: str) -> dict | None:
        for pid in sorted(self.protections):
            element = self.protections[pid]["element"]
            f = self.result["flow"].get(element, 0)
            cap = self.edges[element]["capacity"]
            if self.protections[pid]["breaker"] == breaker and f > cap:
                return diag("RESET_OVERLOADED", f"{breaker} cannot reset: {element} would carry {f} PU over its {cap} PU limit",
                            [breaker, element])
        return None

    def _mutate(self, cmd: dict) -> dict | None:
        op = cmd.get("op")
        if op == "set":
            tid, field, value = cmd.get("id"), cmd.get("field"), cmd.get("value")
            if tid in self.nodes:
                rec, kind = self.nodes[tid], self.nodes[tid]["kind"]
            elif tid in self.edges:
                rec, kind = self.edges[tid], "edge"
            else:
                return diag("UNKNOWN_ID", f"no node or edge {tid!r}", [])
            if field not in SETTABLE[kind]:
                return diag("FIELD_NOT_SETTABLE", f"{tid}: {field!r} cannot be changed on a {kind}", [tid])
            if type(value) is not bool:
                return diag("BAD_VALUE", f"{tid}: {field} must be bool", [tid])
            rec[field] = value
            return None
        if op == "add_edge":
            ed, errs = _check_record(cmd.get("edge"), EDGE_FIELDS, EDGE_DEFAULTS, "edge")
            if errs:
                return errs[0]
            if ed["id"] in self.edges or ed["id"] in self.nodes:
                return diag("DUPLICATE_ID", f"duplicate id {ed['id']}", [ed["id"]])
            self.edges[ed["id"]] = ed
            return None
        if op == "remove_edge":
            tid = cmd.get("id")
            if tid not in self.edges:
                return diag("UNKNOWN_ID", f"no edge {tid!r}", [])
            del self.edges[tid]
            return None
        return diag("UNKNOWN_OP", f"unknown command {op!r}", [])

    # ---------- canonical state (ADR-003) ----------
    def canonical_state(self) -> dict:
        r = self.result
        nodes: dict[str, dict] = {}
        for nid, n in self.nodes.items():
            k = n["kind"]
            if k == "source":
                nodes[nid] = {"kind": k, "capacity": n["capacity"], "online": n["online"], "load": r["load"][nid],
                              "overloaded": r["load"][nid] > n["capacity"]}
            elif k == "junction":
                nodes[nid] = {"kind": k, "isolated": n["isolated"], "failed": n["failed"], "tripped": n["tripped"],
                              "energized": nid in r["energized"]}
            else:
                nodes[nid] = {"kind": k, "demand": n["demand"], "enabled": n["enabled"], "healthy": n["healthy"],
                              "supplied": nid in r["supplied"]}
        edges: dict[str, dict] = {}
        for eid, e in self.edges.items():
            f = r["flow"].get(eid, 0)
            edges[eid] = {"from": e["from"], "to": e["to"], "capacity": e["capacity"], "enabled": e["enabled"],
                          "healthy": e["healthy"], "energized": eid in r["live"], "flow": f, "overloaded": f > e["capacity"]}
        protections = {pid: {"element": p["element"], "breaker": p["breaker"], "overload_ticks": self.overload_ticks[pid]}
                       for pid, p in self.protections.items()}
        return {"schema": SCHEMA, "tick": self.tick, "trip_ticks": self.trip_ticks, "nodes": nodes, "edges": edges,
                "protections": protections}

    def canonical_string(self) -> str:
        return serialize(self.canonical_state())

    def canonical_hash(self) -> str:
        return hashlib.sha256(self.canonical_string().encode("ascii")).hexdigest()

    def overloads(self) -> list[str]:
        st = self.canonical_state()
        return sorted([i for i, n in st["nodes"].items() if n.get("overloaded")] +
                      [i for i, e in st["edges"].items() if e["overloaded"]])


def serialize(v: Any) -> str:
    """Hand-written canonical JSON (ADR-003): sorted keys, no whitespace, ints/bools/printable-ASCII strings only."""
    if v is True:
        return "true"
    if v is False:
        return "false"
    if type(v) is int:
        return str(v)
    if isinstance(v, str):
        for ch in v:
            if not (0x20 <= ord(ch) <= 0x7E):
                raise ValueError(f"canonical strings are printable ASCII only: {v!r}")
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "[" + ",".join(serialize(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(serialize(k) + ":" + serialize(v[k]) for k in sorted(v)) + "}"
    raise ValueError(f"type not allowed in canonical state: {type(v).__name__}")
