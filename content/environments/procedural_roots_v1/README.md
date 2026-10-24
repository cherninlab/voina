# Procedural roots v1 (T-178)

Dark blood-red roots and veins grown in Blender over the Red Descent stone
builds (`procedural_architecture_v1`, T-177), baked for the game.

Generator: `scripts/art/build_roots.py` (driver) and `scripts/art/procgen/roots.py`
(growth, settling and skinning; reusable for other surfaces).

## Re-run

```
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 \
    --python scripts/art/build_roots.py -- \
    [--rooms entry,antechamber] [--passages entry_0_0] [--seed 178] [--budget 15000] \
    [--headroom 2.7] [--samples 96] [--no-render] \
    [--arch content/environments/procedural_architecture_v1] \
    [--layout content/environments/procedural_bridge_v1/layout.json] \
    [--out content/environments/procedural_roots_v1]
```

With no `--rooms`, it builds every room in `<arch>/index.json` "rooms" and every
passage in "passages". Pass `--rooms ,` or `--passages none` to skip either group.
Rooms whose stone GLB is missing are skipped (`ROOTS_SKIPPED`). The output is
deterministic for a given seed and stone build. Run it again whenever T-177
regenerates a room. All three outputs take about a minute with renders on an M5
Max.

## Output

| File | Contents |
| --- | --- |
| `<room>.glb` | `Roots_<room>_<wall>` meshes, one per wall of the room outline (walls without roots have none) |
| `passages/<route>_<segment>_<n>.glb` | `Roots_<label>_0` for a vaulted passage |
| `<room>.json`, `passages/*.json` | Report: seed, triangles, root counts, diameters, AO stats, QA audit, source GLB hashes, layout hash |
| `review/*.png` | Cycles renders under warm point lights, with the stone included (3 per room or passage) |

The meshes are in world space: the same frame as the stone GLBs (the glTF
exporter turns Blender z-up back into Godot y-up). Instance them at the origin,
next to the room's stone build. They have no collision and no `-colonly` nodes.
Roots never enter walking corridors, so traversal is unaffected.

### Vertex data
- `COLOR_0` (Blender attribute `Color`) is grey: baked AO against the room's
  stone, mortar and floor, multiplied by a per-root tone of 0.75 to 1.15.
  Undersides pressed on stone go dark (down to about 0.15), exposed tops stay
  near 1.
- `TEXCOORD_0` (`UVMap`): u runs along the root in metres from where it
  emerges; v goes once round the tube (0 to 1). A fibre or bark texture with
  repeat on u follows every root's length.
- Normals are smooth and point outward. Triangles wind outward, so backface
  culling is safe.

### Godot material
Use one material for all `Roots_*` meshes:
- `albedo = root_albedo.rgb * COLOR.rgb`, as with the dungeon stone (the
  dungeon shader already multiplies albedo by `COLOR`). Use a dark blood-red
  albedo of roughly sRGB (90, 12, 18) to (55, 6, 10), with fibre streaks
  stretched along u (for example a noise texture with `uv1_scale` about
  (1, 5)).
- Roughness 0.25 to 0.6. Use the low end in the grooves so the roots look wet.
  A normal map of fine wrinkles across u adds bark. Leave the mesh AO in
  `COLOR`; do not add a separate AO texture.
- Cull back. Shadow casting is optional: thick trunks benefit, but veins cost
  shadow-map draws for little gain.

The review renders use a stand-in Cycles material (`root_material()` in the
generator) with these values.

## How it grows

1. **Surface.** A `BVHTree` of the room's `Stone_*` and `Mortar_*` meshes (Collision
   meshes dropped), plus any passage that touches the room and a floor plane
   at the room's floor height. Every face knows whether it is stone, mortar or
   floor, so roots start in joints and thin roots prefer to run along them.
2. **Rules.** A root may only grow inside the room outline (plus the wall
   thickness) and below the ceiling. It may not grow anywhere within a route's
   `width / 2 + 0.3 m` of the route centre line between 3 cm above the walking
   surface and `--headroom` (default 2.7 m) above it.
3. **Seeds.** At each doorway (found by ray-casting the wall faces):
   - a trunk and a medium root from joints above the crown;
   - sagging loops under the arch: a root crawls from a joint near the crown
     along the soffit, hangs in a catenary and catches the soffit again;
   - a loop across the opening, bowed out over the arch stones.

   Then a base layer of trunks and medium roots round the perimeter. A slow
   noise "heat" along the walls leaves some stretches bare. Clusters of
   trunks go at two or three hot spots. Thin vein bunches are seeded beside
   existing roots until the triangle budget is spent. Trunks start from the
   wall head under the ceiling or from a mortar joint high on the wall, and
   only where they can reach the floor beside a walkway.
4. **Crawl.** Each step turns the heading towards gravity projected on the
   stone, adds slow meander and fine jitter (noise), and caps the turn per step.
   The tip then moves and snaps back to `radius * flatness + 3 mm` off the
   nearest surface.
   - A surface ahead is climbed onto.
   - Edges are wrapped round.
   - Every move is ray-tested, so no centre line passes through stone.
   - Thick roots never climb back up a wall.
   - On the floor, a root runs out from the wall foot and never climbs back
     onto it.
   - A root stops where it meets a thicker one, runs out on the floor, or is
     blocked. A thick root that stops mid-wall dives back into the nearest
     joint.
5. **Branching.** Breadth first, capped per system:
   - near-even forks, side branches and veins;
   - a fan of 1 to 3 roots where a trunk reaches the floor;
   - small bunches of hanging rootlets under soffits.
6. **Radii.** A pipe model: a point's radius follows the root length downstream
   of it, so trunks are 8 to 15 cm across where they leave the joint and
   taper as branches leave. Every tip ends at 5 mm. Lumps along the length and
   knots where branches leave add swelling.
7. **Settle.** Smooth, then Douglas-Peucker decimation. Spacing scales with
   radius, and the wobble perpendicular to the stone counts less. Re-cling with
   the final radii, then push every ring out of the stone: rays go from the
   centre to the flattened, ridged section, and the push follows the stone's
   normal. Any ring that settling nudged into a corridor ends its root there.
8. **Skin.** Elliptical tubes, wider across the stone than off it. Ring
   vertices concentrate on the visible front. Raised ridges spiral along the
   length (bark twist), and each root ends in a point. There are 3 to 6 sides by
   radius.
9. **Bake.** `procgen.bake.ao_to_color` (Cycles, 64 samples, 0.5 m) against everything
   loaded, then `Color = AO * tone`. Export with `procgen.export.glb`.

## QA in the report (`qa`)
- `audit.in_walking_corridor` counts final tube vertices inside a route
  corridor. It must be 0, and it is 0 for every output.
- `audit.cut_into_stone` counts vertices whose ray from the ring centre
  crosses stone (the skin dips into masonry). `cut_deeper_than_1cm` counts
  the ones deeper than 1 cm.
  - Current builds are at 0.3 to 0.9 % of vertices (at most 11 vertices deeper
    than 1 cm per file).
  - These are almost all where a flattened root crosses a proud stone
    edge or a corner.
- `audit.emerging_from_joint` counts vertices of the ring where a root leaves
  its joint. They are expected.
- `cling_gap_m` is the skin-to-stone distance under clinging rings. The median
  is about 6 mm, p95 about 1.5 cm. Nothing clinging floats more than 6 cm.

## Known limits
- Rooms have no stone ceiling yet: a proxy plane at `floor + height` stands in
  for the game's ceiling slab. Roots start at the wall head under it rather
  than from a vault.
- The floor is a proxy plane at the room's floor height. Flagstones a few
  millimetres proud of it can overlap thin floor veins slightly.
- The antechamber budget is 12.9k of 15k because its noise heat leaves two
  walls bare. That is intentional variety. Change `--seed` for another
  arrangement.
