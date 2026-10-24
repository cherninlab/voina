# Procedural flagstone floors (T-165)

Original procedural geometry, no external meshes. Regenerate with Blender 5.2.2:

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_flagstones.py -- \
        [outdir] [--seed 165] [--samples 96] [--render content/environments/red_descent/review/flagstone_v1]

Tiling helpers live in `scripts/art/procgen/tiles.py`. `flagstones.json` records the seed,
triangles per LOD, height ranges, seam errors and file hashes.

## Modules

| family | ids | size | layout |
| --- | --- | --- | --- |
| laid | laid_a, laid_b, laid_c | 4 x 4 m | irregular flags (periodic Voronoi) |
| coursed | coursed_a, coursed_b, coursed_c | 4 x 4 m | random rectangular flags in courses |
| border | border_a, border_b | 4 x 0.5 m | kerb course, periodic along X, finished long sides |

Variant a is sound, b cracked, c broken (more cracks, knocked corners, missing stones with
dirt fill and loose shards). All variants of one family share every stone that crosses a
module border, so any variant tiles with any other; mix them per cell to hide repetition.

Each GLB holds `<id>_stones_lod{0,1,2}` and `<id>_dirt_lod{0,1,2}`. LOD0 is at most 20k
triangles; suggested visibility ranges are 0-14, 14-32 and 32-90 m (`FlagstoneFloor.LOD_RANGES`).
Godot's automatic mesh LODs are off in the `.import` files so border vertices never move.

## Contract

- A module spans +X and +Z from its corner, walking plane at y = 0. Every vertex stays within
  -0.021..+0.02 m of it: keep the existing flat collision, the floor is visual only.
- Vertex colour (data, linear): R = baked AO, G = per-stone variation, B = edge wear.
- UV = metres, rotated and offset per stone (dirt and bedding: plain module metres).
- `flagstone.gdshader` samples UVs (the world-projected `dungeon_surface.gdshader` ignores them):
  Concrete012 for stones and Rocks025 for dirt from `dungeon_pbr_v2` (CC0, see its README),
  0.5 repeats/m = 1024 px/m, whole repeats per module.
- `FlagstoneFloor.module(id)` builds one module with LODs; `FlagstoneFloor.tile()` lays a grid.

`preview/flagstone_preview.tscn` shows a 3 x 3 grid under a low torch;
`preview/capture_flagstones.gd` re-checks the imported meshes and writes the review captures.
