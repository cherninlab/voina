#!/usr/bin/env python3
"""Run actual Godot dungeon explorers and turn telemetry into inspectable reports."""
import argparse
import collections
import hashlib
import heapq
import json
import os
import pathlib
import shlex
import socket
import struct
import subprocess
import sys
import time
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENE = "res://tests/dungeon_explorer.tscn"


def identity():
    game_files = ["project.godot", "gameplay/match_world.gd", "gameplay/mobs/mob_system.gd",
                  "gameplay/environment/red_descent_layout.gd", "gameplay/environment/red_descent_geometry.gd",
                  "gameplay/environment/crypt_dungeon.gd", "gameplay/environment/dungeon_dressing.gd",
                  "gameplay/mobs/hostile_mob.gd", "gameplay/mobs/raider_mob.gd", "gameplay/mobs/mob_navigation.gd",
                  "gameplay/mobs/dungeon_mobs.gd", "gameplay/player/player_character.gd",
                  "content/environments/procedural_architecture_v1/index.json"]
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in game_files}
    harness = hashlib.sha256((ROOT / "tests/dungeon_explorer.gd").read_bytes() + pathlib.Path(__file__).read_bytes()).hexdigest()
    return {"game_files": hashes, "game_sha256": hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
            "harness_sha256": harness,
            "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "dirty_tracked_paths": subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).splitlines()}


def travel_times(data):
    cells = data["cells"]
    graph = collections.defaultdict(list)
    groups = collections.defaultdict(list)
    for cell in cells:
        if cell["reached"]:
            groups[cell["area"]].append(cell["id"])
    for key, seconds in data.get("walked_edges", {}).items():
        start, end = map(int, key.split(":"))
        graph[start].append((end, seconds))
    representatives = {}
    for area, ids in groups.items():
        centre = [sum(cells[i]["position"][axis] for i in ids) / len(ids) for axis in range(3)]
        representatives[area] = min(ids, key=lambda i: sum((cells[i]["position"][axis] - centre[axis]) ** 2 for axis in range(3)))
    rows = []
    for pair in sorted(data.get("adjacent_areas", [])):
        a, b = pair.split("|")
        for source, target in [(a, b), (b, a)]:
            seconds = None
            if source in representatives and target in representatives:
                start, goal = representatives[source], representatives[target]
                queue, best = [(0.0, start)], {start: 0.0}
                while queue:
                    cost, node = heapq.heappop(queue)
                    if cost > best[node]:
                        continue
                    if node == goal:
                        seconds = cost
                        break
                    for neighbour, weight in graph[node]:
                        candidate = cost + weight
                        if candidate < best.get(neighbour, float("inf")):
                            best[neighbour] = candidate
                            heapq.heappush(queue, (candidate, neighbour))
            rows.append({"from": source, "to": target, "seconds": seconds,
                         "status": "sum of fastest physically observed directed edge times" if seconds is not None else "unchecked: observed edges do not connect these representatives"})
    return {"method": "Dijkstra between visited area representatives; simulated time assembled from actual successful capsule steps, not a single timed trip", "rows": rows}


def png(path, width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def summarize(directory):
    data = json.loads((directory / "telemetry.json").read_text())
    data["identity"] = json.loads((directory / "identity.json").read_text())
    timings = travel_times(data)
    (directory / "travel-times.json").write_text(json.dumps(timings, indent=2) + "\n")
    issues = sorted(data["issues"], key=lambda item: (item["severity"], item["kind"], item["id"]))
    for item in issues:
        item["replay_command"] = shlex.join([sys.executable, str(ROOT / "scripts/dungeon_explorer.py"), "--replay-from", str(directory), "--output", str(directory.parent / (directory.name + "-replay"))])
        item["identity"] = {"game_sha256": data["identity"]["game_sha256"], "harness_sha256": data["identity"]["harness_sha256"]}
    (directory / "telemetry.json").write_text(json.dumps(data, separators=(",", ":")) + "\n")
    (directory / "issues.json").write_text(json.dumps(issues, indent=2) + "\n")
    levels = collections.defaultdict(list)
    for cell in data["cells"]:
        levels[round(cell["position"][1] / 2) * 2].append(cell)
    for level, cells in sorted(levels.items()):
        pixels = bytearray([20, 23, 27] * 204 * 200)
        for cell in sorted(cells, key=lambda item: (item["reached"], item["walkable"])):
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
    areas = collections.defaultdict(lambda: [0, 0])
    for cell in data["cells"]:
        if cell["walkable"]:
            areas[cell["area"]][0] += 1
            areas[cell["area"]][1] += int(cell["reached"])
    lines += ["", "## Area coverage", "", "Independent starts and every recovery are logged; these visits do not establish entrance connectivity.", "", "| Area | Visited | Sampled walkable |", "| --- | ---: | ---: |"]
    lines += [f"| {area} | {visited} | {sampled} |" for area, (sampled, visited) in sorted(areas.items())]
    lines += ["", "## Gameplay bot scenarios", "", "| Scenario | Arrived | False arrival | Longest stuck (s) |", "| --- | --- | --- | ---: |"]
    lines += [f"| {run['scenario']} | {run.get('arrived', 'see trace')} | {run.get('false_arrival', 'see trace')} | {run.get('max_stuck_seconds', 'see trace')} |" for run in data["enemy_runs"]]
    lines += ["", f"Detector controls: {sum(check['passed'] for check in data['checks'])}/{len(data['checks'])} passed.", "", "Travel estimates and unchecked directions are in travel-times.json. They sum observed edge times and are not single-trip timings."]
    lines += ["", "## Findings", "", f"{len(issues)} issue locations; {coverage['suppressed_issue_locations']} additional locations suppressed by the report cap.", ""]
    for item in issues:
        lines.append(f"- **{item['id']} {item['kind']}** ({item['confidence']}), {item['area']} at {item['position']}; {item['occurrences']} occurrence(s). See issues.json for evidence.")
    (directory / "REPORT.md").write_text("\n".join(lines) + "\n")
    print(f"REPORT: {directory / 'REPORT.md'}")
    print(f"COVERAGE: {coverage['reached']}/{coverage['walkable']}; issues={len(issues)}")
    return data


def compare(directory, baseline):
    current = json.loads((directory / "telemetry.json").read_text())
    prior = json.loads((baseline / "telemetry.json").read_text())
    paired = all(current[key] == prior[key] for key in ("seed", "mode")) and current["coverage"]["budget_ticks"] == prior["coverage"]["budget_ticks"]
    same_harness = current["identity"]["harness_sha256"] == prior.get("identity", {}).get("harness_sha256")
    before = {row["scenario"]: row for row in prior["enemy_runs"]}
    after = {row["scenario"]: row for row in current["enemy_runs"]}
    keys = ("arrived", "false_arrival", "max_stuck_seconds", "distance_m", "seconds")
    result = {"paired_configuration": paired, "same_harness": same_harness,
              "interpretation": "paired outcomes; no quality score" if paired and same_harness else "unpaired differences; do not claim improvement",
              "scenarios": {name: {key: {"before": before.get(name, {}).get(key), "after": after[name].get(key)} for key in keys} for name in after}}
    (directory / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
    print("COMPARISON:", result["interpretation"])


def capture_index(directory):
    captures = json.loads((directory / "captures.json").read_text())
    groups = collections.defaultdict(dict)
    for frame in captures["views"]:
        path = directory / frame["frame"]
        header = path.read_bytes()[:24]
        if header[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", header[16:24]) != (1152, 720):
            raise RuntimeError(f"Invalid or missing rendered frame: {path}")
        groups[frame["view"]["name"]][frame["pass"]] = frame["frame"]
    columns = ("color", "objects", "depth", "normals", "intersections", "collision", "clearance")
    lines = ["<!-- capture-index -->", "## Diagnostic cameras", "", "Static architecture; actors hidden in every pass. See captures.json for source poses, ticks and legends; objects.json maps colors to actual render objects.", "", "| View | " + " | ".join(columns) + " |", "| --- | " + " | ".join("---" for _ in columns) + " |"]
    lines += ["| " + name + " | " + " | ".join(f"[{kind}]({frames[kind]})" if kind in frames else "unchecked" for kind in columns) + " |" for name, frames in groups.items()]
    lines += ["", "<!-- /capture-index -->", ""]
    report = (directory / "REPORT.md").read_text()
    if "<!-- capture-index -->" in report:
        start, rest = report.split("<!-- capture-index -->", 1)
        report = start + rest.split("<!-- /capture-index -->", 1)[1]
    report = report.replace("## Findings", "\n".join(lines) + "\n## Findings", 1)
    (directory / "REPORT.md").write_text(report)
    print(f"CAPTURES_VERIFIED: {len(captures['views'])} rendered frames, {len(groups)} camera views")


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
    parser.add_argument("--replay-from", type=pathlib.Path, help="repeat a saved run's seed, mode and physics budget; also compare its enemy outcomes")
    parser.add_argument("--compare", type=pathlib.Path, help="write comparison.json against an earlier run")
    args = parser.parse_args()
    args.output = args.output.resolve()
    if args.ticks is not None and args.ticks < 1:
        parser.error("--ticks must be positive")
    if args.replay_from:
        baseline = args.replay_from.resolve()
        if baseline == args.output:
            parser.error("replay output must differ from its baseline")
        prior = json.loads((baseline / "telemetry.json").read_text())
        args.mode, args.seed, args.ticks = prior["mode"], prior["seed"], prior["coverage"]["budget_ticks"]
        args.compare = baseline
    if args.compare and args.compare.resolve() == args.output:
        parser.error("comparison output must differ from its baseline")
    if args.capture_only and not (args.output / "telemetry.json").is_file():
        parser.error("--capture-only needs telemetry.json in --output")
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.capture_only:
        (args.output / "identity.json").write_text(json.dumps(identity(), indent=2) + "\n")
        run_engine(args)
        summarize(args.output)
        if args.compare:
            compare(args.output, args.compare.resolve())
    if args.capture or args.capture_only:
        original = json.loads((args.output / "identity.json").read_text())
        current = identity()
        if current["game_sha256"] != original["game_sha256"]:
            raise RuntimeError("Gameplay/layout source changed after exploration; rerun before capturing")
        (args.output / "capture-identity.json").write_text(json.dumps(current, indent=2) + "\n")
        run_engine(args, capture=True)
        capture_index(args.output)


if __name__ == "__main__":
    main()
