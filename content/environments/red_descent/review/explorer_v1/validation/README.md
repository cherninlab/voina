# Delivery validation

Godot 4.7.2 Standard, built-in Jolt. All scripts ran against the actual project. Final commands:

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/dungeon_explorer.py "$GODOT" --mode full --output content/environments/red_descent/review/explorer_v1/20261027-full-v2 --capture --capture-workers 3 --timeout 1200
python3 scripts/dungeon_explorer.py "$GODOT" --ticks 1800 --output /tmp/dungeon-explorer-delivery-baseline
python3 scripts/dungeon_explorer.py "$GODOT" --replay-from /tmp/dungeon-explorer-delivery-baseline --output /tmp/dungeon-explorer-delivery-replay
python3 scripts/smoke_test.py "$GODOT"
python3 scripts/mob_smoke_test.py "$GODOT"
```

The full run, fast baseline and fast replay have the same harness SHA-256. All 22 detector/control checks pass. [fast-replay-comparison.json](fast-replay-comparison.json) records identical outcomes, distances, durations and longest-stuck times in all ten enemy scenarios. [baseline-enemy-runs.json](baseline-enemy-runs.json) and [replay-enemy-runs.json](replay-enemy-runs.json) retain source identity, configuration, controls and full enemy traces. This establishes repeatability of these cases; it does not establish better gameplay enemies.

[import-output.txt](import-output.txt), [baseline-output.txt](baseline-output.txt), [replay-output.txt](replay-output.txt), [smoke-output.txt](smoke-output.txt) and [mobs-output.txt](mobs-output.txt) retain output with terminal color escapes removed. No script/error lines or failed controls occur. Existing material-remapping/ObjectDB warnings and the rendered run's seven texture-RID shutdown warning remain visible. The full run's [run-output.txt](../20261027-full-v2/run-output.txt) and [capture-output.txt](../20261027-full-v2/capture-output.txt) are retained separately. Its 147 frames were checked for file validity, dimensions and matching capture-manifest entries; selected game, object-color, depth, normal and failure-location frames were also visually inspected.

No production enemy/level code was changed. Fixes should run the same saved full configuration with the unchanged harness and compare actual scenario outcomes. Headless exploration and inspection captures do not establish human input/camera acceptance, WAN latency or thermal performance.
