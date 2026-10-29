"""Reference tests for the re-derived grid model (NOT the original oracle). Names follow the acceptance matrix."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cases import load_cases, run_case  # noqa: E402
from lbo_grid import Grid, GridError, serialize  # noqa: E402

DOC = load_cases()


class GridCases(unittest.TestCase):
    def check_case(self, case: dict) -> None:
        g, log = run_case(DOC, case)
        for rec in log:
            cmd, res = rec["cmd"], rec["result"]
            want = cmd["expect"]
            if want == "ok":
                self.assertTrue(res["ok"], f"{case['name']}: {cmd} refused: {res}")
            else:
                self.assertFalse(res["ok"], f"{case['name']}: {cmd} should be refused")
                self.assertEqual(res["code"], want, f"{case['name']}: {cmd}")
                self.assertEqual(res["ids"], sorted(cmd.get("expect_ids", [])), f"{case['name']}: {cmd}")
                self.assertTrue(res["message"])
                self.assertEqual(rec["hash_before"], rec["hash_after"], "refused command mutated state")
        st = g.canonical_state()
        exp = case["expect"]
        supplied = sorted(i for i, n in st["nodes"].items() if n.get("supplied"))
        self.assertEqual(supplied, exp["supplied"], case["name"])
        self.assertEqual(g.overloads(), exp["overloaded"], case["name"])
        for nid, v in exp.get("load", {}).items():
            self.assertEqual(st["nodes"][nid]["load"], v, f"{case['name']} load {nid}")
        for eid, v in exp.get("flow", {}).items():
            self.assertEqual(st["edges"][eid]["flow"], v, f"{case['name']} flow {eid}")
        # SIM11: reversed input order gives identical canonical bytes
        g_rev, _ = run_case(DOC, case, reverse=True)
        self.assertEqual(g_rev.canonical_string(), g.canonical_string(), f"{case['name']} SIM11")


def _make(case: dict):
    return lambda self: self.check_case(case)


for _c in DOC["cases"]:
    setattr(GridCases, f"test_{_c['name']}", _make(_c))


class DefinitionCases(unittest.TestCase):
    def test_SIM07_SIM06_definitions_rejected(self) -> None:
        for case in DOC["definition_cases"]:
            with self.subTest(case["name"]):
                with self.assertRaises(GridError) as cm:
                    Grid.load(case["definition"])
                self.assertIn(case["expect"], [d["code"] for d in cm.exception.diagnostics])


class Serializer(unittest.TestCase):
    def test_golden_bytes(self) -> None:
        self.assertEqual(serialize({"b": [1, True, "x\"y\\"], "a": {"Z": False, "A": -3}, "_": 0}),
                         '{"_":0,"a":{"A":-3,"Z":false},"b":[1,true,"x\\"y\\\\"]}')

    def test_rejects_float_null_non_ascii(self) -> None:
        for bad in (1.0, None, "é", "\n"):
            with self.assertRaises(ValueError):
                serialize(bad)


if __name__ == "__main__":
    unittest.main()
