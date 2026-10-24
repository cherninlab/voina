# Red Descent architecture

Red Descent's rooms and passages are built from real stones in Blender, one stone at a time, then baked. This replaces boxes with textures painted on them. The generator is `scripts/art/build_architecture.py`. It reads the real layout exported from the game (`scripts/art/export_dungeon_layout.gd` → `content/environments/procedural_bridge_v1/layout.json`) and writes `content/environments/procedural_architecture_v1/`.

```sh
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_architecture.py -- \
    content/environments/procedural_bridge_v1/layout.json content/environments/procedural_architecture_v1 \
    --rooms entry,antechamber --passages entry --export
```

## Rules

Every element has a structural reason. A rule that can't be met stops the build; it is never papered over.

1. **An opening exists only where a route really crosses a wall** at that height. This is a segment intersection, not a nearness test. The opening is centred on the crossing.
2. **One generator per element.** An enclosed route is one passage with one cross-section, its *profile*. The doorways where it crosses room walls and the barrel vault between the rooms are the same arch, built together, so nothing stands inside an arch. The lowest room the passage serves decides how flat the vault is. Where a semicircle would hit that room's ceiling, the vault goes segmental.
3. **A doorway onto an open crossing is sized by that crossing.** When an enclosed route leaves a room on its last segment and hands over to a bridge or ledge, the door matches the bridge, not the corridor.
4. **A doorway must fit its wall.** If a route crosses too near a corner for its door plus jambs, the build prints `DOOR_DOES_NOT_FIT` and refuses to export. The fix is to change the room outline in `RedDescentLayout.rooms()`, never to shrink the door. Example: the entry room's east wall was turned square to its passage.
5. **A stone build replaces everything it stands for.** A room with `rooms/<id>.glb` skips its old wall boxes, niches, pilasters and proximity arches. A stretch of route inside a passage, or within 1.6 m of a stone room, skips its old tunnel walls and lid (`stone_enclosed`).
6. **The shaft's outline wall stops at rooms.** Rooms are cut into the rock at the shaft's edge. Where one stands in the outline, its own walls are the shaft wall over the room's height (`room_cuts`). Routes that pass beside the room still get their doorway.
7. **Walls seen from the shaft are faced on both sides.** Their through-stones (jambs and voussoirs) serve both faces.

## Construction

The toolkit lives in `scripts/art/procgen/`:

- **`stones`** makes unique stones. Walls use `squared_rubble`: squared and fitted, rock-faced, worn round at the arrises. Arches use `voussoir` and quoins use `ashlar`.
- **`stonelib`** keeps a few hundred unique stones and fits one to each slot, by its body behind the worn front so joints close tight. Each placement gets its own turn, flip and tone.
- **`masonry`** builds walls course by course:
  - joints line up with sills and springing lines, and the courses run on round each room;
  - openings get alternating long and short jamb stones and an arch ring of voussoirs with a keystone (semicircular or segmental), all through the wall;
  - course stones are cut to the ring;
  - a mortar core sits a few centimetres behind the face, with true holes at the openings. The holes are set back too, so reveals show stone.
- **Passages** have side walls to the springing, staggered voussoir rings for the barrel vault, and a mortar mass with the profile as its hole. All of it is clipped to the outer faces of the room walls at both ends.

The bake:

1. Join each wall's stones and mortar.
2. Bake ambient occlusion for everything built together, so passages darken where they meet rooms.
3. Multiply by each stone's tone and store it in vertex colour. The shader multiplies albedo by `COLOR`.
4. Give each stone its own texture coordinates in its wall's frame (`map_stone`). UV gives each stone its own piece of the rock texture; UV2 runs continuously along the wall for the weathering masks. This matches `dungeon_surface.gdshader`'s projection convention, read through its `mapped` mode. Projecting from bumpy vertex normals smears the texture into swirls.
5. Collision is a copy of the mortar cores (`Collision_*-colonly`). Their holes are the real openings.

`index.json` lists the built rooms and passages. Each passage carries its route's `layout_hash`; the game ignores a passage whose route has changed since it was baked.

## Review

```sh
scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --stone-rooms --capture-dir=/abs/dir
```

This captures, for every stone room:
- its four longest walls, from the middle and close up;
- a corner view looking up;
- views from the shaft of walls that face it.

For every passage it captures both directions inside, plus the approach from each end. `CAPTURE_CENTRE_HIT` names the body in the middle of each frame, to trace stray geometry back to its builder. Add `--no-stone-rooms` for the same frames of the old boxes.

## Open work

- **Rooms:** the remaining rooms. Several have crossings too near corners and need their outlines squared first; the build lists them.
- **Passages:** stairs and sloped passages; passage bends and junctions.
- **Rooms' upper parts:** vaults over rooms instead of flat lids.
- **Dressing:** roots (T-178), rubble at wall bases (T-179), stone surface textures (T-180).
