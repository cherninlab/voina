# Room rubble (T-179)

Broken stone, grit and grime at the wall bases of every stone-built room of Red
Descent. The material is dropped with Blender rigid-body physics against the real
stone builds and then baked. Nothing is simulated in the game.

The generator is `scripts/art/build_room_rubble.py`. It uses only original
procedural geometry and the shared `scripts/art/procgen/` toolkit: `stones`,
`fracture`, `rigid`, `disturb`, `bake`, `export` and `core`.

The older free-standing piles in the parent folder (`../rubble_*.glb`,
`../rubble.json`, T-163) are a separate generator. This folder does not touch them.

## Re-run

```sh
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_room_rubble.py -- \
    [--rooms antechamber,entry] [--seed 179] [--no-review] \
    [--arch content/environments/procedural_architecture_v1] \
    [--layout content/environments/procedural_bridge_v1/layout.json] \
    [--out content/environments/procedural_rubble_v1/rooms]
```

- **Rooms.** Without `--rooms`, every id in `<arch>/index.json` `"rooms"` is built. A
  new or rebuilt room is one command: `--rooms <id>`. Other rooms' files are left alone.
- **Time.** Each room takes 4-5 minutes on an M5 Max, including about 30 s of Metal
  renders. You can run several rooms as separate processes at the same time.
- **Reproducible.** The same machine reproduces the GLB byte for byte. The
  antechamber was checked twice: sha256 `9f97c21a…`.
- **Bullet differences.** Bullet is not guaranteed bit-identical across CPUs. The
  checks below still hold on another machine.
- **Stale inputs.** Each report records the sha256 of the room GLB and the layout it
  was built from. If T-177 rebuilds a room, re-run that room.

## Files

| File | Contents |
|---|---|
| `<id>.glb` | Visual meshes and Godot collision, in **Godot world coordinates** (same frame as `procedural_architecture_v1/rooms/<id>.glb`). Instance it at the origin. |
| `<id>.json` | The report (see below). |
| `review/<id>_view1..3.png` | Cycles frames at eye height (1.6 m) of the three biggest settled heaps. Warm point lights stand in for torches, with a cold fill. |
| `review/<id>_plan.png` | Orthographic top view. Image up is Godot −Z. The walking ribbons' clear zones are shown in red, and walls are cut at 1.6 m. |

The review folder has a `.gdignore`, so the frames are not imported as game assets.

### GLB nodes

- **`Rubble_<id>_0` … `_3`.** All stone pieces and grit, merged by quarter of the
  room so Godot can cull them. They have one surface and no material.
- **`Rubble_<id>_grime`.** The grime bed: dust and crushed mortar banked at the wall
  foot along the heaps.
  - It is up to 5.5 cm deep at the wall.
  - It dips 1.2 cm under the floor at its edge, so it meets the floor along a frayed
    contour instead of a seam.
- **`RubbleCollision_<id>_NN-convcolonly`.** One convex hull for every piece longer
  than 25 cm (37 and 42 hulls). Godot imports each one as a `StaticBody3D` with a
  `ConvexPolygonShape3D`. Smaller pieces and the grime bed have no collision.

Checked in Godot 4.7.2 headless:
- The antechamber has 5 meshes, 18,914 triangles, vertex colours, and 37 static bodies.
- The entry has 5 meshes, 18,637 triangles, and 42 static bodies.

### Suggested materials (integration, T-177)

- **`Rubble_<id>_0..3`.** Use the wall stone material, so the fragments read as the
  same stone as the walls. They carry metre box-projected UVs, but a world-projected
  material works too.
- **`Rubble_<id>_grime`.** Use the floor material, world-projected.
  - Its vertex grey fades to 1.0 at the edge, so only its relief and its darkening
    toward the wall show.
  - A different texture would show a seam where it meets the floor.
- **Vertex colour.** Both use `COLOR` as an albedo multiply. `dungeon_surface.gdshader`
  already does this.

## Vertex colour

`Color.rgb` is a neutral grey; alpha is 1:

- **Stone and grit:** baked AO (0.35 m, Cycles, walls and floor visible) × per-piece tone (0.7–1.15).
  - Fragments of one source stone share a tone within ±5 %, so a broken stone still reads as one stone.
  - Fresh break faces get ×1.07, a shade lighter than the weathered faces.
  - Grit is at the light end of the tone range (0.9–1.15), as freshly crushed stone.
- **Grime bed:** baked AO (floor hidden, so its thin edge is not darkened) × a grime tone. The tone goes from 0.5 deep at the wall to 1.0 at the edge.

glTF stores colours normalised, so values above 1 are clipped. That affects 1–4 % of vertices; the share is reported per mesh.

## How a room is made

1. **Wall foot.** The room build is imported (`Stone_*` and `Mortar_*`; the
   `Collision_*` boxes are dropped). Every 10 cm along the plan outline, rays at
   3–100 cm above the floor find the most protruding stone, which is the wall foot.
   Rays at 1.3 m and 1.8 m that pass through mark doorways.
2. **Where it falls.** A density along the wall foot decides where material has
   come down:
   - Corners hold heaps of three sizes, so not every corner caught the same amount.
   - Door jambs get heaps too.
   - One or two collapse spots are added.
   - A low base level covers the rest, broken up by noise along the wall.
   - Nothing is placed in doorways or in walking ribbons.
3. **Pieces.**
   - **Source stones.** About 32 wall-like stones (`procgen.stones`, squared rubble,
     ashlar or rubble, 26–46 cm) per 36 m of usable wall.
   - **Breaking.** Each is shattered by `procgen.fracture` Voronoi cells crowded around
     an impact corner, into 2–18 fragments. The result is a few big chunks and a spray
     of chips.
   - **Fragment detail.** Fragments over 10 cm lose one or two corners. Break faces are
     subdivided and displaced so they read rough rather than sawn.
   - **Size.** Fragments are 2–35 cm, measured as the longest chord.
   - **Rocks and grit.** Angular rocks (3.5–9 cm) and grit (about 1.5–5 cm) are
     low-poly hulls.
   - **Triangle budget.** Fragments share the triangle budget by surface, so the room
     total stays under 20k.
4. **Deposit.**
   - **Order.** Big pieces go first. Fragments of one stone land within about half a
     metre of each other.
   - **Placement.** Each piece is tried at several spots and lowered onto what is
     already there. The spot furthest below a 34° talus wedge wins.
   - **Result.** Big chunks end up at the wall foot, and grit runs out past the heap
     as a skirt (30 % of the grit trickles into the heap).
5. **Physics.** The physics is Blender Bullet, using these settings:
   - **Rate.** 30 fps, 40 substeps and 60 solver iterations.
   - **Colliders.**
     - The wall meshes below 1.6 m are MESH colliders with a 2 mm margin.
     - The floor is a BOX.
     - The grime bed is a set of convex 2×2-cell patches. The thin triangle shell let
       grit tunnel under it.
   - **Pieces.** Pieces are convex hulls with friction 0.95. Angular damping 0.95
     stands in for the rolling resistance of rough stone.
   - **Settling in runs.**
     - A free heap of Bullet hulls keeps creeping a few cm/s however long it runs. This
       was tested with 150 iterations, 80 substeps, heavier damping and higher friction.
     - So the drop runs in short segments: 90 frames, then 45-frame runs.
     - A piece whose net travel over the last 15 frames stayed under 1 cm/s is held
       still for the following runs. This acts as static friction.
     - Each piece's speed is the net travel of its fastest bound-box corner. Contact
       jitter therefore does not count, but creep does.
6. **Discards.** A piece is removed if:
   - it ends with any vertex above floor + 4 cm inside a walking ribbon. A ribbon is
     every layout route segment at the room's floor height (within 1 m), widened to
     width/2 + 0.3 m;
   - it ends outside the room (inset 0.3 m) or below the floor;
   - it never becomes still;
   - it is more than 1 cm from any support after the others are removed.
7. **Stability check.** The exported pose is tested by letting every piece go again
   for 1.5 s. The result is measured and not kept. If more than about 0.5 % of the
   pieces move more than 1 cm, or any moves more than 3 cm, the pose is settled again
   and re-checked, up to 4 times. The last check is reported.
8. **Bake and export.**
   - Pieces are merged per quarter of the room.
   - The grime bed's vertices are raised onto its physics patches, so pieces resting on
     the patches touch the visible surface.
   - AO is baked and the grey written.
   - Convex hulls are added for pieces over 25 cm.
   - Export goes through `procgen.export.glb`.

## This bake

The seed is 179, built from the T-177 builds on main (commit 525c070).

| Room | Pieces kept (big / medium / small / grit) | Triangles | Hulls | Tallest heap | Contact gap | Interpenetration | Highest point in a ribbon | Stability check (1.5 s re-release) |
|---|---|---|---|---|---|---|---|---|
| antechamber | 771 (151 / 134 / 111 / 375) | 18,914 | 37 | 0.38 m | ≤ 8.9 mm | 0 | 1.2 cm | max 3.1 cm; 4 pieces > 1 cm, 1 > 3 cm |
| entry | 965 (198 / 190 / 161 / 416) | 18,637 | 42 | 0.32 m | ≤ 9.8 mm | 0 | 4.0 cm | max 2.1 cm; 3 pieces > 1 cm |

The size classes are big ≥ 20 cm, medium 8–20 cm, small 3.5–8 cm, and grit smaller than that. Discards:

- **Antechamber.** None. Everything settled clear of the ribbons.
- **Entry.**
  - 6 pieces in a ribbon.
  - 2 pieces never still.
  - 2 with no spot to place.
  - 5 floating pieces, all grit and rocks.

## Report (`<id>.json`)

- **Inputs:** the source room GLB and layout, with their sha256. Also the seed and the command.
- **Pieces:** generated, kept and discarded, by reason.
- **Triangles:** per mesh, against the 20k budget.
- **Collision:** hull count and hull vertices.
- **`settle`:**
  - the rule;
  - the drop runs (active and stilled pieces per run);
  - the stability check: max move and turn, and pieces moved over 1 cm and over 3 cm;
  - max contact gap and max interpenetration. Interpenetration covers piece–piece (ray
    parity), piece–wall (behind the nearest wall face, since wall stones are open at
    the back), piece–grime bed (under its top) and piece–floor.
- **`routes`:** the ribbons used, and the highest piece point inside them.
- **`heaps`:**
  - corner, jamb and collapse-spot counts;
  - the target wedge heights;
  - the settled heaps: stone volume and top height per 1.6 m of wall.
- **AO and grey statistics** per mesh, including the clipped share.
- **Timings.**

## Known limits

- **Volume.** The heaps are 0.3–0.4 m high. A 20k triangle budget for a 45 m perimeter
  leaves about 800–1,000 pieces per room. Taller heaps would need a bigger budget or
  larger pieces.
- **Grit.** Grit is 1.5–5 cm. It reads as a skirt from 2–3 m, but the paving texture
  in the review frames hides much of it.
- **Small creep.** The stability numbers above are Bullet creep after the hold. A few
  pieces per room still move 1–3 cm when let go again. The final pose is the settled
  one; nothing is left mid-air (gap ≤ 1 cm).
- **Grime and floor material.** The grime bed only blends if it shares the floor's
  material. With another material its edge shows as a contour on the floor.
- **Wall texture in the review frames.** The review frames box-project the scanned
  rock, which stretches on the 45° chamfer walls. That is the review shader, not the
  stone build.
