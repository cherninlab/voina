#!/usr/bin/env python3
"""Run actual Godot dungeon explorers and turn telemetry into inspectable reports."""
import argparse
import collections
import hashlib
import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import time
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENE = "res://tests/dungeon_explorer.tscn"


def png(path, width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def summarize(directory):
    data = json.loads((directory / "telemetry.json").read_text())
    issues = sorted(data["issues"], key=lambda item: (item["severity"], item["kind"], item["id"]))
    (directory / "issues.json").write_text(json.dumps(issues, indent=2) + "\n")
    levels = collections.defaultdict(list)
    for cell in data["cells"]:
        levels[round(cell["position"][1] / 2) * 2].append(cell)
    for level, cells in sorted(levels.items()):
        pixels = bytearray([20, 23, 27] * 204 * 200)
        for cell in cells:
            x, z = cell["x"] + 102, cell["z"] + 92
            color = (65, 195, 130) if cell["reached"] else (218, 151, 61) if cell["walkable"] else (90, 93, 104)
            if 0 <= x < 204 and 0 <= z < 200:
                offset = (z * 204 + x) * 3
                pixels[offset:offset + 3] = bytes(color)
        for item in issues:
            if abs(item["position"][1] - level) <= 1.5:
                x, z = round(item["position"][0] / 0.5) + 102, round(item["position"][2] / 0.5) + 92
                if 0 <= x < 204 and 0 <= z < 200:
                    pixels[(z * 204 + x) * 3:(z * 204 + x) * 3 + 3] = b"\xff\x4a\x69"
        png(directory / f"level-{level:+03d}.png", 204, 200, pixels)
    coverage = data["coverage"]
    lines = ["# Dungeon explorer run", "", f"Build `{data['build']}`; seed {data['seed']}; mode {data['mode']}.", "",
             f"Actual capsule visits: {coverage['reached']} / {coverage['walkable']} sampled walkable cells.",
             f"Budget: {coverage['budget_ticks']} physics ticks per explorer; 3 explorers. Unvisited cells are untested, not proven unreachable.",
             "", "Heatmaps: green = visited, amber = sampled walkable but unvisited, grey = clearance blocked, red = issue location. Levels are 2 m height bins, not room IDs.", "", "## Capabilities", ""]
    lines += [f"- {key}: {value}" for key, value in data["capabilities"].items()]
    lines += ["", "## Findings", "", f"{len(issues)} issue locations; {coverage['suppressed_issue_locations']} additional locations suppressed by the report cap.", ""]
    for item in issues:
        lines.append(f"- **{item['id']} {item['kind']}** ({item['confidence']}), {item['area']} at {item['position']}; {item['occurrences']} occurrence(s). See issues.json for evidence.")
    (directory / "REPORT.md").write_text("\n".join(lines) + "\n")
    print(f"REPORT: {directory / 'REPORT.md'}")
    print(f"COVERAGE: {coverage['reached']}/{coverage['walkable']}; issues={len(issues)}")
    return data


def run_engine(args, capture=False):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    build = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    base = [str(ROOT / "scripts/godot_bg.sh")] if capture else [args.godot, "--headless", "--fixed-fps", "60"]
    command = base + ["--path", str(ROOT), SCENE, "--", "--host", "--dungeon", "--shading-ephemeral", f"--port={port}",
                      f"--explorer-output={args.output}", f"--explorer-mode={args.mode}", f"--explorer-seed={args.seed}", f"--explorer-build={build}"]
    if args.ticks is not None:
        command.append(f"--explorer-ticks={args.ticks}")
    if capture:
        command += ["--explorer-capture", f"--explorer-lenses={args.lenses}", f"--explorer-capture-workers={args.capture_workers}"]
    log_path = args.output / ("capture.log" if capture else "run.log")
    environment = dict(os.environ, GODOT=args.godot)
    with log_path.open("w") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=args.timeout)
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise
    output = log_path.read_text()
    print(output[-5000:], end="")
    if process.returncode or "ERROR" in output or (not capture and "EXPLORER_OK:" not in output):
        raise RuntimeError(f"Godot explorer failed; inspect {log_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", nargs="?", default=os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--mode", choices=("fast", "full"), default="fast")
    parser.add_argument("--seed", type=int, default=186)
    parser.add_argument("--ticks", type=int)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "content/environments/red_descent/review/explorer_v1/latest")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--capture", action="store_true", help="also capture real Mobile/Metal game frames through godot_bg.sh")
    parser.add_argument("--capture-only", action="store_true")
    parser.add_argument("--lenses", default="forward,back,left,right,up,down")
    parser.add_argument("--capture-workers", type=int, choices=(1, 2, 3), default=1)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.capture_only:
        run_engine(args)
        summarize(args.output)
    if args.capture or args.capture_only:
        run_engine(args, capture=True)


if __name__ == "__main__":
    main()
