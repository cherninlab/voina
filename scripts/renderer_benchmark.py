#!/usr/bin/env python3
"""Run scripts/renderer_benchmark.gd windowed under Mobile and Forward+ and print a table.

Usage: python3 scripts/renderer_benchmark.py "$GODOT" [passes, default 20]
Refuses to start while another Godot process runs: other agents' tests and clients share the GPU,
which skews the numbers, and the benchmark's load breaks their timing-sensitive network tests.
Needs a logged-in desktop session (headless runs do not render); the window may be covered.
"""
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r"BENCH_RESULT config=(\S+) view=(\d+) frame_median_ms=([\d.]+) frame_p95_ms=([\d.]+)")


def run(godot: str, method: str, passes: str) -> dict[tuple[str, int], tuple[float, float]]:
    command = [godot, "--path", str(ROOT), "--rendering-method", method, "--script", "res://scripts/renderer_benchmark.gd", "--", f"--passes={passes}"]
    # A file instead of a pipe, so Godot never blocks on a full pipe while we poll.
    log = tempfile.TemporaryFile(mode="w+")
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.DEVNULL, text=True)
    while process.poll() is None:
        busy = other_godot_processes()
        if busy:
            # Stop at once: results would be skewed and the extra load breaks other agents' tests.
            process.kill()
            sys.exit(f"{method}: aborted, another Godot process started:\n" + "\n".join(line[:160] for line in busy))
        time.sleep(2)
    log.seek(0)
    output = log.read()
    results: dict[tuple[str, int], tuple[float, float]] = {}
    for line in output.splitlines():
        if line.startswith("BENCH_RENDERER"):
            print(line)
        match = PATTERN.search(line)
        if match:
            results[(match[1], int(match[2]))] = (float(match[3]), float(match[4]))
    if "BENCH_DONE" not in output:
        sys.exit(f"{method}: benchmark did not finish\n{output[-2000:]}")
    return results


def other_godot_processes() -> list[str]:
    # Match the executable name only; shells whose command line mentions the Godot path are not Godot.
    pids = subprocess.run(["pgrep", "-x", "Godot"], capture_output=True, text=True).stdout.split()
    if not pids:
        return []
    listing = subprocess.run(["ps", "-o", "pid=,command=", "-p", ",".join(pids)], capture_output=True, text=True).stdout
    return [line.strip() for line in listing.splitlines() if "renderer_benchmark" not in line]


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    busy = other_godot_processes()
    if busy:
        sys.exit("Other Godot processes are running; rerun when they finish:\n" + "\n".join(line[:160] for line in busy))
    passes = sys.argv[2] if len(sys.argv) == 3 else "20"
    tables = {method: run(sys.argv[1], method, passes) for method in ("mobile", "forward_plus")}
    print(f"ms per view ({passes} passes per frame), median / p95")
    print(f"{'config':16} {'view':>4} | {'mobile':>11} | {'forward+':>11}")
    for key, forward in tables["forward_plus"].items():
        mobile = tables["mobile"][key]
        cells = [f"{times[0] / int(passes):.2f} / {times[1] / int(passes):.2f}" for times in (mobile, forward)]
        print(f"{key[0]:16} {key[1]:>4} | {cells[0]:>11} | {cells[1]:>11}")


if __name__ == "__main__":
    main()
