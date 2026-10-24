# Procedural rubble v1 (T-163)

Static rubble and debris piles for Red Descent, baked from a Blender 5.2.2 rigid-body
drop. Nothing is simulated in the game. Original procedural geometry: no external
meshes or textures are used by the generator.

Generator: `scripts/art/build_rubble.py`. The physics helpers are in
`scripts/art/procgen/rigid.py`. Everything else uses the shared `scripts/art/procgen/` toolkit.

```sh
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_rubble.py -- \
    content/environments/procedural_rubble_v1 --review content/environments/red_descent/review/rubble_v1
```

Options: `--seed N` or `--seeds 1,2,3` (default), `--recipes wall_spill,corner_heap,bridge_debris,floor_scatter`.
The default command takes about 80 s on an M-series Mac. The same machine reproduces the GLB
hashes in `rubble.json` byte for byte.

## Files

- `rubble_<recipe>_s<seed>.glb`: LOD0 with Godot collision. This is the file you place.
- `lod/rubble_<recipe>_s<seed>_lod1.glb` and `_lod2.glb`: decimated to 50 % and 20 %, visual only. Use them only if you want manual `visibility_range` LODs. Godot also generates automatic LODs for every GLB on import (`meshes/generate_lods=true`).
- `rubble.json`: the report. Per pile it lists:
  - seed and pieces by kind
  - settle frames and residual speed
  - maximum contact gap and maximum interpenetration
  - triangles and path per LOD
  - hull count
  - footprint, height, Godot bounds and wall planes
  - AO statistics
  - sha256 of every GLB (relative paths)
- `preview/preview.tscn` with `preview.gd`: a torch-lit dungeon corner showing one pile per recipe in the game's materials. It also captures frames (see the review folder).
- `preview/rubble_check.gd`: the headless import and standing test.

## Recipes (3 seeds each, 12 piles)

| Recipe | Walls | Contents | Footprint (x by z) | Height |
|---|---|---|---|---|
| `wall_spill` | back wall | 38 stones: ashlar fragments, rocks, bricks, brick clumps | about 2.5 × 1.2 m | 0.48–0.65 m |
| `corner_heap` | back and side walls | 33–34 stones | about 1.6 × 1.8 m | 0.37–0.51 m |
| `bridge_debris` | none | 8–10 broken planks, 1–2 snapped beams, about 20 stones | about 2.6–3.1 × 1.7 m | 0.26–0.35 m |
| `floor_scatter` | none | 35–36 mostly small stones in loose clusters | about 2.4 × 2.5 m | 0.22 m |

### Stone sources (0.1–0.8 m, all closed meshes)

- **Fractured ashlar.** A chamfered block is cut by one large break and up to two corner chips. Break faces are roughened with noise and shaded as crisp facets.
- **Rough rock.** The convex hull of 12–22 points on a squashed ellipsoid, then roughened.
- **Brick.** Often a broken bat.
- **Brick clump.** Two or three courses, one or two bricks wide, with recessed mortar, broken through.

### Boards

- **Planks:** `shapes.plank` cut 0.45–1.35 m long.
- **Beams:** `shapes.timber`, 0.15–0.2 m square.
- **Splintered ends:** one end is always splintered, and 40 % of boards have both. The end ring is subdivided, staggered back along the grain with two splinters pushed out, and the cap is poked.
- **UVs:** boards keep the along-grain metre UVs from `shapes.prism`.

## How a pile is made

1. **Pieces.** Pieces are generated under the 8k triangle budget. If the first pass is over budget, the tessellation is coarsened (`tessellation_scale` in the report).
2. **Deposition.** Pieces are deposited one by one, mostly big ones first and blocks mostly bedded flat. For each piece, 12 random spots are tried. At each spot the piece is lowered by downward ray casts until it rests on the floor or on the meshes already there. The spot furthest below the recipe's target heap profile wins: a wedge against the wall, a quarter cone in the corner, a low mound along the fallen span. The winner is lifted 1–3 cm, and a BVH overlap test guarantees no mesh overlap.
3. **Physics.** Blender's Bullet world runs at 30 fps with 20 substeps and 40 iterations. Pieces use convex-hull shapes with a 2 mm margin, friction 0.9 for stone and 0.75 for wood, and density 2300 or 650 kg/m³. The floor and walls are passive boxes. The world steps until the fastest bound-box corner of any piece moves slower than 1 cm/s for 15 consecutive frames, measured from per-frame position deltas. The residual speed is recorded.
4. **Freezing and checks.** The settled transforms are applied to the meshes. Pieces that rolled out of the recipe area are removed, and so is any piece left more than 1 cm from all support (none were in this bake). Then the final meshes are measured with BVH trees:
   - **Contact gap:** for every piece, the distance to its nearest neighbour, floor or wall. Maximum 6.8 mm, limit 1 cm.
   - **Interpenetration:** the depth of sample points inside other closed meshes. 0 mm, limit 1 cm. No triangle of one piece intersects another, because Bullet keeps the hulls a margin apart.
5. **Origin.** Everything is shifted so the origin is at the ground centre of the footprint.
6. **Collision hulls.** Every piece at least 0.2 m long gets a convex hull node named `<Piece>-convcolonly`. Godot imports each as a `StaticBody3D` with a `ConvexPolygonShape3D`; there are 10–25 per pile. Smaller pebbles have no collision.
7. **Merging and AO.** Pieces are merged into `Stone` and `Wood` meshes. AO is baked against each other and the floor and wall proxies, which are not exported, using `procgen.bake.ao_to_color` with a 0.3 m distance.
8. **Export.** Export goes through `procgen.export.glb`. The Blender turntables (Cycles, 4 views) are rendered from the same scene.

## Vertex colour (`COLOR_0`): a deliberate deviation

The toolkit convention is R = AO, G = variation, B = wear. These piles instead store a
neutral grey:

`Color.rgb = (1 − 0.8 × (1 − AO)) × tone`, with alpha 1.

- `tone` is a per-piece value: 0.84–1.0 for stone and 0.8–1.0 for wood. It separates neighbouring stones.
- **Why grey:** `dungeon_surface.gdshader` multiplies albedo by `COLOR.rgb`, so a G or B channel holding data would tint the stone.
- **Why AO is at 80 %:** the albedo multiply also darkens direct torch light, and full-strength AO made the piles read much darker than the walls.

If the AO is needed separately, R, G and B are all equal, so any one channel holds it.

## Placing a pile (integration, T-162)

- **Origin and walls.** The origin is on the ground at the footprint centre. `walls_godot` in `rubble.json` gives each pile's wall planes in pile-local Godot coordinates:
  - The back wall has normal +Z and passes through `point`. Its z is negative, and the pile spills toward +Z.
  - The corner's side wall has normal +X.
  - To seat a pile, rotate it so the normal faces out of the real wall, then translate it so that plane lies on the wall face. `preview.gd` `show_seed()` does this for axis-aligned walls.
- **Scaling.** Never scale piles non-uniformly. Uniform scaling also scales the convex shapes, so prefer the unscaled pile.
- **Suggested materials:**
  - Stone: `MeshInstance3D` named `Stone` with `material_override` set to a `dungeon_surface.gdshader` material on `dungeon_pbr_v2/Rocks025` (density 0.526, normal 0.8, wetness 0.3). The existing `rock` material (marble_rock_03) turned the rubble chocolate-brown with marble veins.
  - Wood: `Wood` with a `StandardMaterial3D` using `Wood035` on UV1 (`uv1_scale` 0.6) and `vertex_color_use_as_albedo`. The world-projected timber mode cannot follow boards lying at random angles.
- **Cost.** LOD0 is 4.0k–7.5k triangles per pile. There are two draw calls per pile at most: Stone, and Wood for bridge debris.

## Optional CL3D sources

T-167's CL3D chunk manifest did not exist when this was baked. Only the procedural sources
are used. Adding them later means:

- loading the listed GLBs as additional `make_stone` kinds;
- keeping them closed;
- recentring them on their bound-box centre.

## Known limits

- The piles are modest: 0.26–0.65 m high. Deposition builds 0.8–0.9 m heaps, but Bullet's convex hulls have no rolling resistance, so they slump. Higher piles need more volume than the 8k triangle budget allows at this tessellation.
- Blocks read as clean dressed ashlar. Break faces are faceted rather than finely chipped, which is a triangle budget trade-off.
- The world-projected stone texture shows the floor's cobble pattern on some block faces.
- Settled poses are reproducible on this machine. Bullet is not guaranteed bit-identical across CPUs, so rerunning elsewhere may give slightly different piles. The checks still apply.
