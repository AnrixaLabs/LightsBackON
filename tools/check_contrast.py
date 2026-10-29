#!/usr/bin/env python3
"""WCAG 2.2 contrast check of the design tokens (ADR-004): every rule in content/ui/tokens.json must meet
4.5:1 for body text or 3:1 for icons/large text, on each opaque background and on the HUD panel composited
at its overlay alpha over the worst and best case backdrops. Exit 1 on any failure.

    python3 tools/check_contrast.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {"body": 4.5, "icon_or_large": 3.0}


def rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def lum(c: tuple[float, float, float]) -> float:
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ratio(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def over(fg: tuple[float, float, float], alpha: float, bg: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(alpha * f + (1 - alpha) * b for f, b in zip(fg, bg))  # type: ignore[return-value]


def main() -> int:
    t = json.loads((ROOT / "content" / "ui" / "tokens.json").read_text(encoding="utf-8"))
    colors = {k: rgb(v) for k, v in t["colors"].items()}
    alpha = t["overlay"]["panel_alpha_percent"] / 100
    backdrops = {"worst": rgb(t["overlay"]["worst_backdrop"]), "best": rgb(t["overlay"]["best_backdrop"])}
    fails = 0
    checks = 0
    for rule in t["contrast_rules"]:
        need = REQUIRED[rule["use"]]
        for bg_name in rule["on"]:
            surfaces = {bg_name: colors[bg_name]}
            if bg_name in ("panel", "elevated"):
                for bd_name, bd in backdrops.items():
                    surfaces[f"{bg_name}@{int(alpha * 100)}%/{bd_name}"] = over(colors[bg_name], alpha, bd)
            for s_name, s in surfaces.items():
                r = ratio(colors[rule["fg"]], s)
                checks += 1
                ok = r >= need
                fails += 0 if ok else 1
                print(f"{'ok  ' if ok else 'FAIL'} {rule['fg']:>11} on {s_name:<24} {r:5.2f}:1 (needs {need}:1, {rule['use']})")
    print(f"contrast: {checks} checks, {fails} failures")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
