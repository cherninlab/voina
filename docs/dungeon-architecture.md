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
8. **Enclosed routes form one network.** Every stretch of an enclosed route outside the rooms is a passage. Where stretches meet at a route vertex:
   - a slight bend (under 25°) is mitred;
   - a real bend or a junction is a square bay with a groin vault, where solid sides are walls with a lunette and a narrower passage gets its own arch;
   - a route that ends where a bridge or ledge starts gets a portal, a face wall with the passage's arch.

   Two passages may not enter a bay through one side, a passage may not end in nothing, and two routes may not share a corridor. Each of these stops the build.
9. **Switchback stairs climb inside stair halls.** Legs 4 m apart can't each have a tunnel. Doorways sit at whatever height a route crosses a wall, with the sill under the ramp's lowest point in the wall. A passage's vault flattens to fit the tightest ceiling it passes under.
10. **Rooms are vaulted.** A cloister vault rises from every wall, about a third of the room's inradius, so the webs meet in groins from the corners and a ridge along long rooms. A vault never rises into a room or route above; where there's no room for one, the room keeps a flat lid. The game puts each room's roof over its vault (`tops` in index.json).
11. **No wall is ruler-straight.** Each wall bows out gently, leans a little and its courses wander along its length, as one smooth field so joints stay true. Plastered rooms keep their walls plumb under the render.
12. **Bays, plinths, cornices, thresholds.** Long facing walls are divided into bays by pilasters (plain rubble or dressed ashlar with a plinth block and a capital), placed clear of doorways and of walks along the wall. Under a vault, a transverse rib springs from each facing pair, following the vault's own curve a hand's breadth below it; the pilaster stands out exactly as far as the rib springs from the wall. Walls stand on a proud plinth course, carry a cornice course under the vault, and every doorway gets stone threshold slabs.
13. **Stairs, galleries and floors are stone.** A walk that climbs inside a room stands on masonry carried out to the wall beside it, with a stone face on the open side, a parapet over any drop of more than a metre, and stone treads (paving on the level). Passages and bays are paved wall to wall. The game keeps its smooth walking collision and hides the old flat floor strips there. A room's doorway onto a bridge or ledge right outside it is the mouth; no stub of tunnel is squeezed in between.
14. **Render over stone.** Rooms in `PLASTER` (the nave in red, the chapel and the restraint in lime) get a thin plaster skin a few centimetres proud of the stones. The game's peel mask cuts it away, so the masonry shows through in patches.

## Construction

The toolkit lives in `scripts/art/procgen/`:

- **`stones`** makes unique stones. Walls use `squared_rubble`: squared and fitted, rock-faced, worn round at the arrises. Arches use `voussoir` and quoins use `ashlar`.
- **`stonelib`** keeps a few hundred unique stones and fits one to each slot, by its body behind the worn front so joints close tight. Each placement gets its own turn, flip and tone.
- **`masonry`** builds walls course by course:
  - joints line up with sills and springing lines, and the courses run on round each room;
  - openings get alternating long and short jamb stones and an arch ring of voussoirs with a keystone (semicircular or segmental), all through the wall;
  - course stones are cut to the ring;
  - a mortar core sits a few centimetres behind the face, with true holes at the openings. The holes are set back too, so reveals show stone.
- **`vault`** builds cloister vaults course by course. Each stone's face is turned to the curve, the stones are clipped to their wall's region (nearer to it than to any other wall), and a mortar shell sits behind them.
- **`passage`** builds the network's pieces:
  - Runs have side walls with horizontal courses, cut to the floor and springing lines on ramps.
  - A run's barrel vault reuses a few sculpted ring variants per profile, mirrored, scaled to each ring's width and sheared to the slope.
  - A mortar mass surrounds each run, with the profile as its hole.
  - A bay's groin vault keeps each barrel's triangles over its own sides; its mass is the intersection of the two holed blocks.
  - Everything is clipped to whatever the piece meets: a room wall's outer face, a mitre or bay face, or a portal's back.

`--check` prints every doorway, stretch and node the layout implies, without building stones.

The bake:

1. Join each wall's stones and mortar.
2. Bake ambient occlusion for everything built together, so passages darken where they meet rooms.
3. Multiply by each stone's tone and store it in vertex colour. The shader multiplies albedo by `COLOR`.
4. Give each stone its own texture coordinates in its wall's frame (`map_stone`). UV gives each stone its own piece of the rock texture; UV2 runs continuously along the wall for the weathering masks. This matches `dungeon_surface.gdshader`'s projection convention, read through its `mapped` mode. Projecting from bumpy vertex normals smears the texture into swirls.
5. Collision is a copy of the mortar cores (`Collision_*-colonly`). Their holes are the real openings.

`index.json` has four parts:
- `rooms`: the stone-built rooms;
- `files`: one GLB per route's runs and one per bay or portal, each with the `layout_hash` of every route it serves;
- `passages`: the stretches covered;
- `nodes`: bay and portal centres with their radius.

The game loads a file only if all of its routes are unchanged since the bake. It skips old tunnel pieces covered by a stretch, a node or a stone room at any level it spans, and old shaft-wall arches at stone portals.

## Materials and dressing (T-185)

Everything the team made is picked up by `red_descent_geometry.gd`. Nothing is copied into the stone build.

**Stone kinds.** Each stone kind is baked into its own mesh, `Stone-<kind>_*`, and gets its own face material (`KIND_FACES`, T-183 sets with their anti-tiling shader):

| Kind | Material |
|---|---|
| walling | T-180 limestone |
| dressed ashlar | 01 chisel limestone |
| lacing slabs | 02 split bedded |
| quoins and piers | 03 drafted quoin |
| rough crypt walling | 08 salt-weathered |
| floor flags | 07 worn floor |
| arch and vault stones | 09 fine-tooled sandstone |

**Stand-ins replaced.** `integrate_materials()` swaps the old stand-ins for the team's sets. Each keeps its material's grade settings (T-181).

| Material | Set |
|---|---|
| red plaster | red_nave_v1 red lime plaster |
| plaster | bridge_well_v1 mineral plaster, greyed |
| iron | red_nave_v1 oxidized iron |
| wood and bridges | bridge_well_v1 bridge oak |
| props | red_nave_v1 aged oak |
| route floors | red_nave_v1 broken stone floor |
| shaft walls | bridge_well_v1 damp masonry |

**Per room**, loaded when the files exist:
- roots: `procedural_roots_v1/<id>.glb`, and per passage stretch `passages/<route>_<segment>_<t0×1000>.glb` (T-178);
- rubble, grit and grime: `procedural_rubble_v1/rooms/<id>.glb` (T-179); the grime uses the flagstone floor's dirt;
- props: the T-171 dressing sets at the places in `index.json` `props`, chosen by `build_architecture.py --props` or `--index-only`, with their backs to a wall and clear of doors, pilasters, stairs and walks.

**Rebuild in parallel**, then regrow the dressing:

```sh
blender ... build_architecture.py -- <layout> <out> --rooms a,b --export --no-index      # several processes
blender ... build_architecture.py -- <layout> <out> --rooms none --passages all --export --no-index
blender ... build_architecture.py -- <layout> <out> --index-only
blender ... build_roots.py -- --rooms ... ; blender ... build_room_rubble.py -- --rooms ...
```

Objects are discarded in one batch (`core.discard` / `flush_trash`). Removing them one by one from a scene of tens of thousands of stones is quadratic.

## Review

```sh
scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --stone-rooms --capture-dir=/abs/dir
```

Add `--review` for the fixed review set everyone compares: the shaft views plus each stone room's widest wall, its vault, its walks and the passages.

`--stone-rooms` captures, for every stone room:
- its four longest walls, from the middle and close up;
- a corner view looking up;
- views from the shaft of walls that face it.

For every passage it captures both directions inside, plus the approach from each end. `CAPTURE_CENTRE_HIT` names the body in the middle of each frame, to trace stray geometry back to its builder. Add `--no-stone-rooms` for the same frames of the old boxes.

## Open work

- **Shaft walls in stone:** the outline wall is still the old boxes. Its area (about 10,000 m²) needs instanced stones (one library, GPU instances with per-stone tone and texture offset) rather than merged unique meshes.
- **Stone kinds (T-182):** ashlar, thin slabs, small units, quoins, galleted rubble and floor flags, assigned by role: piers, arches, vault webs, paving.
- **Dressing:** roots (T-178), rubble at wall bases (T-179), stone surface textures (T-180).
