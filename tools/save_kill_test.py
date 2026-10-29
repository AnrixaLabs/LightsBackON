#!/usr/bin/env python3
"""G06 / SAVE01 on a real process: hard-kill the exported internal build while it rewrites a checkpoint, then check a save loads.

    py -3 tools/save_kill_test.py --exe build/windows-internal/LightsBackOn.exe --cycles 60 --seed 1

Each cycle: start `<exe> --headless -- --save-soak`, wait until it logs `SOAK start`, sleep a random time, kill it
(TerminateProcess on Windows: no shutdown code runs, same as Task Manager "End task" or `taskkill /F`), then run
`<exe> --headless -- --save-verify`. A cycle passes when a valid copy loads and its sequence number never goes backwards.
The soak continues from the loaded save, so the next write also exercises write_record's post-crash recovery.
Needs the "Windows Desktop (internal)" export: release builds refuse the soak arguments.
Exit 0 = every cycle passed, 1 = a failure, 2 = setup problem.
"""
from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path

VERIFY_RE = re.compile(r"VERIFY ok=(true|false) (.*)")
START_TIMEOUT_S = 30.0
POLL_S = 0.02


def read_log(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def soak_and_kill(exe: Path, log: Path, delay_s: float) -> tuple[bool, float]:
    log.unlink(missing_ok=True)
    proc = subprocess.Popen([str(exe), "--headless", "--log-file", str(log), "--", "--save-soak"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.monotonic()
    while "SOAK start" not in read_log(log):
        if proc.poll() is not None or time.monotonic() - t0 > START_TIMEOUT_S:
            proc.kill()
            proc.wait()
            return False, 0.0
        time.sleep(POLL_S)
    time.sleep(delay_s)
    proc.kill()
    proc.wait()
    return True, time.monotonic() - t0


def verify(exe: Path, log: Path) -> tuple[int, str]:
    log.unlink(missing_ok=True)
    rc = subprocess.run([str(exe), "--headless", "--log-file", str(log), "--", "--save-verify"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60).returncode
    lines = [ln for ln in read_log(log).splitlines() if ln.startswith("VERIFY ")]
    return rc, (lines[-1] if lines else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exe", default="build/windows-internal/LightsBackOn.exe")
    ap.add_argument("--cycles", type=int, default=60)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--min-delay", type=float, default=0.0, help="seconds after SOAK start before the kill")
    ap.add_argument("--max-delay", type=float, default=1.5)
    a = ap.parse_args()
    exe = Path(a.exe).resolve()
    if not exe.is_file():
        print(f"setup: {exe} not found (export the 'Windows Desktop (internal)' preset first)")
        return 2
    rng = random.Random(a.seed)
    work = Path(tempfile.mkdtemp(prefix="lbo_kill_"))
    soak_log, verify_log = work / "soak.log", work / "verify.log"

    rc, line = verify(exe, verify_log)
    if "not available" in read_log(verify_log):
        print("setup: this build refuses the soak (release export?); use the internal preset")
        return 2
    print(f"before: {line or '(no VERIFY line)'}")
    m = re.search(r"seq=(\d+)", line)
    last_seq = int(m.group(1)) if m else 0

    states: Counter[str] = Counter()
    sources: Counter[str] = Counter()
    failures: list[str] = []
    advanced = 0
    for i in range(1, a.cycles + 1):
        delay = rng.uniform(a.min_delay, a.max_delay)
        started, alive = soak_and_kill(exe, soak_log, delay)
        if not started:
            failures.append(f"cycle {i}: soak never logged SOAK start")
            print(f"{i:3} FAIL soak did not start")
            continue
        rc, line = verify(exe, verify_log)
        vm = VERIFY_RE.search(line)
        seq_m = re.search(r"seq=(\d+)", line)
        files_m = re.search(r"files=(\S+)", line)
        src_m = re.search(r"source=(\w+)", line)
        if files_m:
            states[files_m.group(1)] += 1
        ok = rc == 0 and vm is not None and vm.group(1) == "true" and seq_m is not None
        seq = int(seq_m.group(1)) if seq_m else -1
        if ok and seq < last_seq:
            ok = False
            line += f"  (seq went back from {last_seq})"
        if ok:
            sources[src_m.group(1) if src_m else "?"] += 1
            advanced += 1 if seq > last_seq else 0
            last_seq = seq
        else:
            failures.append(f"cycle {i}: {line or 'no VERIFY line, exit %d' % rc}")
        print(f"{i:3} {'PASS' if ok else 'FAIL'} kill after {alive:5.2f}s  {line}")

    print(f"\nfile states right after the kill: {dict(states)}")
    print(f"loaded from: {dict(sources)}; seq advanced in {advanced}/{a.cycles} cycles; final seq {last_seq}")
    print(f"{'PASS' if not failures else 'FAIL'}: {a.cycles - len(failures)}/{a.cycles} cycles, seed {a.seed}, exe {exe.name}")
    for f in failures:
        print("  " + f)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
