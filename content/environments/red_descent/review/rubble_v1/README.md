# Rubble v1 review (T-163)

This folder is the evidence for `content/environments/procedural_rubble_v1/`: 12 rigid-body-settled
rubble piles (4 recipes × 3 seeds) baked by `scripts/art/build_rubble.py`.

## Images

- **Blender turntables.** `rubble_<recipe>_s<seed>_turntable.png`: four Cycles views per pile. The material is plain grey stone or brown wood multiplied by the baked vertex colour; the floor and wall proxies are dark grey.
- **Contact sheet.** `contact_sheet.png`: the first view of every pile. Columns are wall spill, corner heap, bridge debris and floor scatter; rows are seeds 1, 2 and 3.
- **In-engine frames.** `runtime/`: real Godot 4.7.2 Mobile/Metal frames from `procedural_rubble_v1/preview/preview.tscn`, captured through `scripts/godot_bg.sh`.
  - Setting: a torch-lit dungeon corner with the Red Descent environment and `dungeon_surface.gdshader` walls (Bricks089) and floor (Rocks025).
  - Rubble materials: Rocks025 stone, and Wood035 oak on the board UVs.
  - Frames: `01` is the overview for seed 1, `02`–`05` are close-ups of each recipe, and `06`/`07` are overviews for seeds 2 and 3.

## Logs

- `blender-bake.txt`: per-pile settle and check numbers.
- `editor-import.txt`: clean headless import.
- `rubble-check.txt`: headless import and standing test.
- `capture.txt`: the in-engine capture run.
- `main-smoke.txt`: the repository smoke test.

The leaked-RID and ObjectDB warnings at exit in `capture.txt` and `rubble-check.txt` also
appear for a trivial SceneTree script, and in the other review folders' captures. They come
from the project at exit, not from these assets.

## Measured

All values are from `procedural_rubble_v1/rubble.json`.

| Check | Result | Limit |
|---|---|---|
| Settle: max bound-box corner speed for 15 frames | residual 0.0044–0.0092 m/s after 104–1278 frames (3.5–42.6 s simulated) | < 0.01 m/s |
| Floating: gap from each piece to its nearest support | max 6.8 mm. This is the Bullet hull margin, 2 mm per hull. | ≤ 10 mm |
| Interpenetration: depth inside another closed mesh | 0 mm. No triangle pairs intersect. | ≤ 10 mm |
| LOD0 triangles | 3,984–7,538 | ≤ 8,000 |
| LOD1 / LOD2 triangles | 1,992–3,768 / 796–1,506 | |
| Godot collision | 10–25 convex `StaticBody3D` per pile, one per piece of 0.2 m or more | |
| Capsule test: r 0.4 m, h 1.8 m, the player's shape | stands on all 12 piles, feet at 0.22–0.65 m, rest speed 0 | must stand on the wall, corner and bridge piles |

No pieces escaped or were removed as floating in this bake.

## Honest visual assessment

**What works.**
- The Blender sheet reads as rubble.
  - Wall spills heap against the wall and thin out forwards.
  - Corner heaps lean into the corner.
  - Bridge debris is a convincing tangle of snapped planks and a beam with stones on and under it. The splintered ends read well in Godot.
- In engine, stone and wood sit on the floor without visible gaps or floating pieces.
- Contact darkening from the baked AO separates the stones.

**Weaknesses.**
- **Small piles.** The piles are modest: 0.26–0.65 m high, about 2.5 m wide. In the overview, from 7 m, they read as small debris rather than a collapse. Deposition builds 0.8–0.9 m heaps, but convex hulls have no rolling resistance, so the physics slumps them to about half.
- **Clean blocks.** Many fragments are recognisably clean chamfered blocks. Break faces are faceted rather than finely chipped, which is the price of the 8k triangle budget.
- **Texture.** The world-projected Rocks025 texture shows its cobble pattern on some block faces and streaks on steep faces.
- **Darkness.** The rubble is somewhat darker than the walls, because the baked AO multiplies albedo and so darkens torch light too. It is already softened to 80 %.
- **Floor scatter.** Low and sparse, 0.22 m. That is good as dressing, but the capsule only stands on its largest stones.
- **CL3D.** CL3D chunks from T-167 were not used, because their manifest does not exist yet.
