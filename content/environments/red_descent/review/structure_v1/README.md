# Construction review — 2026-10-24

Fresh actual Godot 4.7.2 Mobile/Metal frames are in `runtime/`. They show source fingerprint `3c83cc837bad`. ImageGen paintovers in the separate `../paintover_v3/` folder are future art targets, never runtime evidence.

The pass removes world-axis floating braces and substitutes explicit deck/stringer/transom/support connections. Stone bearing capitals were reconstructed locally from a generated reference. Existing generic stone-bridge fragments hanging below ledges were removed. Nave rafters now form joined trusses seated into the walls beneath a pitched timber roof. Bell supports reach the floor. Loose cloth triangles were replaced with gravity-settled, pinned Blender cloth exported statically.

## Verification

- Editor import: no script or shader errors.
- Construction audit: 23 required exposed-route bearings present; wall anchors intersect actual masonry collision; foundation piers reach the existing base at -60 m; independent sampling checks lower routes against piers and diagonal timber members; six roof rafters share their end nodes with ties/king posts.
- Actual character capsule: 1,276 m walking through descent, return, egress, four optional loops, both wooden bridge lanes at +/-0.75 m and deep-floor recovery. No mouse/camera or two-Mac human acceptance is claimed.
- Main smoke suite: combat and real local ENet pair passed. Logs retained adjacent.
- Eight runtime captures passed the nonblank checks. Capture timing is recorded in `runtime/render-metrics.json`, not a gameplay performance benchmark.
- Capture shutdown still reports the pre-existing seven Texture RID / one ObjectDB cleanup warnings. The structure-only process reports one ObjectDB cleanup warning. These are not counted as shader errors or hidden from the record.

## Remaining visual defects

The wooden bridge is explicitly rejected as a visual result: over-repeated carved edge profiles, narrow alternating bright gaps and shading create visible board artifacts. The separate procedural-bridge workstream owns its replacement. The wall tiling, flat plaster panels, repetitive windows and skinny stacked pilasters also remain well below the art references. This pass establishes connected support placements, not the desired material or architectural finish.

The baked cloth is a small verified example of offline simulation. We did not run finite-element bridge analysis or claim real structural certification. The candidate load paths are a game-art construction model.

## Reproduce

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script scripts/dungeon_structure_test.gd -- --report=/tmp/construction-audit.json
python3 scripts/dungeon_traversal_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
GODOT="$GODOT" scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --capture-dir=/tmp/dungeon-review
```
