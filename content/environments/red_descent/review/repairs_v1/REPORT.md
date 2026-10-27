# First crawler repair batch — 2026-10-27

This batch fixes paving backing, floating doorway chips in four rooms, and shared enemy movement. It does not clear the dungeon's remaining findings. Theo's direction is to prioritize other parts of the map over further polish of the best room.

## Shipped changes

| Repair | Commit | Observed result |
| --- | --- | --- |
| Continuous recessed mortar beneath stone-built route paving | `f85421d` | Root-tunnel E0266 no longer shows the void through a joint; the probe hits upward-facing mortar 4 cm under the walking ribbon. No collision was added. |
| Truthful arrival and blocked-route recovery | `0c6dbbb` | Both false-arrival cases stopped claiming success; added-wall and enemy-body obstruction cases reached their goals. |
| Remove floating gallet chips from cells, ossuary, bones and window openings | `fb93515` | 644 disconnected chips / 44,865 render triangles removed across eight openings. Fixed-camera Mobile captures show the chips gone. Generator filtering prevents the same wholly unsupported fillers on future builds. |

## Evidence across different areas

The rough-room repair removes only disconnected components under 9 cm wholly inside the authored arch void, with a 2 cm boundary margin. Collision, every original vertex attribute, and all other mesh primitives remain byte-for-byte unchanged. The GLBs retain unused original vertex/index storage; this is a render-triangle reduction, not a claim of complete asset compaction, hidden-face removal or measured GPU savings.

`gallet-removal.json` lists all removed component centres and before/after asset hashes. `gallet-openings.json` records the authored opening masks. `gallet-removal-method.py.txt` preserves the one-off raw-GLB repair method; it used those masks and the pre-repair assets, without regenerating rooms or rebaking their lighting. A second component scan found zero remaining components meeting that conservative removal rule. Valid joint fillers were retained.

| Room | Removed chips | Removed render triangles |
| --- | ---: | ---: |
| Ossuary | 160 | 11,129 |
| Bones | 148 | 10,289 |
| Window | 141 | 9,799 |
| Cells | 195 | 13,648 |

Eight camera definitions are in `opening-views.json`; their actual game captures are in `opening-chips-before/` and `opening-chips-after/`. For example:

| Bones doorway before | Same camera after |
| --- | --- |
| ![Before](opening-chips-before/bones-door-0-0-game.png) | ![After](opening-chips-after/bones-door-0-0-game.png) |

Paving E0266 is shown in `diagnosis/E0266-game.png` and `paving-bed-confirmed/E0266-game.png`, with mesh hits in the corresponding `probe.json` files. The original paving emitted individual stones while hiding the old floor ribbon; it had no continuous backing. The new bedding follows the existing mitred ribbon and uses the existing mortar shader without peeling.

## Enemy verification

The original explorer harness was unchanged. `combined-full/` is paired with `../explorer_v1/20261027-full-v2/`: seed 186, full mode, 36,000 ticks per crawler. These are scenario outcomes, not a general enemy-quality score.

| Scenario | Before | After |
| --- | --- | --- |
| Same X/Z, goal on another floor | False arrival | No arrival |
| Partial path to an unreachable goal | False arrival | No arrival; horizontal movement stops |
| Another actual enemy blocks the route | Did not arrive; 2 s stationary cutoff | Arrived; longest stationary interval 0.65 s |
| Wall added after the navigation snapshot | Did not arrive; 2 s stationary cutoff | Arrived; longest stationary interval 0.58 s |
| Clear movement and both real dungeon hall routes | Arrived | Arrived |
| Cover, memory, reacquisition and returning home | Controls passed | Controls passed |

The scenarios run sequentially, so an earlier successful movement can change a later scenario's start. Do not interpret every timing difference as an isolated speed improvement. Permanently unreachable goals remain unarrived, and one corresponding enemy-stuck finding remains in the final report.

The windowed navigation probe (`opening-chips-after/navigation.json`) also checks both actual, vertically separated dungeon grids: scratch queries preserve the shared AStar object, original height bytes, origin and original path, while the fresh path stays on the intended floor. This is bounded collision resampling after a stall, not continuous crowd steering or inter-floor navigation.

## Traversal and remaining defects

- Full crawler: **17,190 / 21,402 sampled walkable cells**, unchanged by these repairs; all **22 detector/control checks passed**. All 30 room/route areas were sampled. Independent starts and recoveries do not prove entrance connectivity or complete coverage.
- The floor-gap report went from **100 (capped)** to **52** flags. Negative floor/collision height mismatch flags went from **15 to 0**. The capped baseline prevents an exact count of holes fixed.
- **37 physical crawler snag locations remain.** `snags-confirmed/` replays E0437–E0439 against the actual map and records their collision contacts. They are not marked fixed.
- `stair-centrelines/stairs.json` records the production player capsule traversing first stair, second stair and return stair in both directions: **6/6 complete**. This checks route centres, not every edge or parapet approach. It does not resolve the 37 snag findings.
- **17 ceiling-gap candidates remain.** Actual upward views in `outer-route-ceilings/` confirm large openings to the void at E0275/E0277 in the root tunnel and E0334/E0336 in the cave bypass. T-196 tracks these joins as the next priority outside the polished rooms. Skew passage-to-square-bay clipping is a hypothesis to investigate, not an established root cause. E0330's render looks different and needs separate diagnosis.
- Many other visual candidates remain untriaged; repeated object counts do not by themselves prove poor batching or measured GPU cost.

## Iterations and checks

`paving-crawler/` preserves the full run after the paving change. `arrival-iteration1/` preserves the first arrival-only run; its comparison against a full baseline is explicitly **unpaired** and is not used for before/after quality claims. `recovery-iteration1/` preserves the matching fast seed/tick comparison for the subsequent recovery change. `combined-full/` is the final full comparison with all three fixes.

Godot 4.7.2 editor import, core smoke/real ENet checks, and mob smoke passed with no script or engine `ERROR` lines. Clean output is in `validation/` and each capture directory. The known imported-material `specular` warning and seven texture-RID shutdown warning remain in windowed capture output; mob smoke also reports its existing one-object shutdown warning. No manual two-Mac input, WAN, performance or human visual acceptance is claimed.

The earliest probe attempts had shutdown resource errors and were excluded from this evidence; those invalid debug runs are archived under `/tmp/secha-repairs-invalid-debug-20261027/` on the working Mac.

All windowed commands used `scripts/godot_bg.sh`. Reproduce focused captures with:

```sh
scripts/godot_bg.sh --path . --script scripts/dungeon_issue_probe.gd -- \
  --host --dungeon --shading-ephemeral --port=FREE_UDP_PORT \
  --probe-output=/absolute/output \
  --probe-views=res://content/environments/red_descent/review/repairs_v1/opening-views.json \
  --probe-modes=game --probe-navigation
```

Use `--probe-stairs --probe-ids=none` for both directions of all three stair routes, or `--probe-ids=E0437,E0438,E0439` for the saved incidents. Each stair/incident trial starts independently; it does not teleport during the attempted route. `--probe-doorways` is only a ray-based candidate scan: bay walls, arch contacts and sloped floors can be intentional hits and require inspection.
