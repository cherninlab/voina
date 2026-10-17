#!/usr/bin/env python3
"""Run scripts/renderer_benchmark.gd windowed under Mobile and Forward+ and print a table.

Usage: python3 scripts/renderer_benchmark.py "$GODOT" [passes, default 20]
Needs a visible desktop session; headless runs do not render.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r"BENCH_RESULT config=(\S+) view=(\d+) frame_median_ms=([\d.]+) frame_p95_ms=([\d.]+) cpu_median_ms=([\d.]+) drawn=([\d.]+)")


def run(godot: str, method: str, passes: str) -> dict[tuple[str, int], tuple[float, float, float, float]]:
    command = [godot, "--path", str(ROOT), "--rendering-method", method, "--script", "res://scripts/renderer_benchmark.gd", "--", f"--passes={passes}"]
    if sys.platform == "darwin":
        # A sleeping display stops macOS drawing the window, which voids samples.
        command = ["caffeinate", "-dimu", *command]
    output = subprocess.run(command, capture_output=True, text=True, timeout=900).stdout
    results: dict[tuple[str, int], tuple[float, float, float, float]] = {}
    for line in output.splitlines():
        if line.startswith("BENCH_RENDERER"):
            print(line)
        match = PATTERN.search(line)
        if match:
            results[(match[1], int(match[2]))] = (float(match[3]), float(match[4]), float(match[5]), float(match[6]))
    if "BENCH_DONE" not in output:
        sys.exit(f"{method}: benchmark did not finish\n{output[-2000:]}")
    return results


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    passes = sys.argv[2] if len(sys.argv) == 3 else "20"
    tables = {method: run(sys.argv[1], method, passes) for method in ("mobile", "forward_plus")}
    print(f"ms per pass ({passes} passes per frame, median); '-' = OS skipped drawing, so no measurement")
    print(f"{'config':16} {'view':>4} | {'mobile':>7} | {'forward+':>8}")
    for key in tables["forward_plus"]:
        cells = []
        for method in ("mobile", "forward_plus"):
            median, _p95, _cpu, drawn = tables[method][key]
            cells.append(f"{median / int(passes):.2f}" if drawn >= 0.95 else "-")
        print(f"{key[0]:16} {key[1]:>4} | {cells[0]:>7} | {cells[1]:>8}")


if __name__ == "__main__":
    main()
