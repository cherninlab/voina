# Haunted forest

The woods along the north trail, between the village gate and the church graveyard, are a damp, foggy dead forest (`gameplay/environment/haunted_forest.gd`, node `HauntedForest`, built by `MatchWorld.build_arena` after the village and the church road). It follows two user mood references: a misty dead swamp forest (cold blue-grey fog swallowing layered silhouettes, thin dead trees, dark conifers, dry reeds, still black water) and a dark understorey (mossy trunks, hanging growth, crowded undergrowth, pale light shafts). Two later church references added gnarled bare branches arching over the path, hanging moss, rolling ground mist, ash and ember patches as the only warm colour besides torches. Cosmetic only: it owns no gameplay or network state. All placement is seeded, so every peer builds the same scenery and the same trunk collision.

## Fog zone

Each peer blends its own copy of the shared `Environment` and the sun by where its active camera (`get_viewport().get_camera_3d()`) is:

- weight 0 inside the palisade outline; rising with `smoothstep` from 1 m to 14 m outside it, so walking out of the north gate eases in over about 13 m with no pop;
- times a height fade: cameras 9–16 m above the ground fall back to 0, so the main-menu lobby view at (34, 26, 38) keeps today's grade;
- eased in time (rate 2.5/s) so teleports and camera switches do not snap.

The blend is a layer over whatever grade is active, not a replacement. Every frame the zone reads each property it drives; a value that differs from what it last wrote (the grim grade's deferred build, a shading theme, a later grade change on main) becomes the new base. At weight 0 the base is written back exactly, and then nothing is touched until the camera leaves again.

| Property | Village base on main today | Forest grade (weight 1) |
| --- | --- | --- |
| `fog_density` (exponential depth fog) | 0.006 | max(base, 0.044) |
| `fog_light_color` | `303c40` | `65757f` |
| `fog_sky_affect` | 0.08 | max(base, 0.8): the sky hazes over too |
| `fog_aerial_perspective` | 0.0 | 0.1 |
| `fog_sun_scatter` | base | 0 |
| `ambient_light_energy` / colour | 0.40 / `829698` | × 0.8 / `5a6a74` |
| `tonemap_exposure` | base | × 0.95 |
| sun `light_energy` / colour | base | × 0.45 / toward `aebdcc` |

The Mobile renderer has no volumetric fog. At 0.044 exponential density, 10 m is about 36 % fog, 25 m about 67 % and 40 m about 83 %: near trunks stay dark while the next rows fade into grey silhouettes. The church road's additive torch glows read the live fog density, so they sink into the forest fog with distance.

## Dressing

All geometry is original and generated at runtime; textures are reused from the repository (see `content/environments/haunted_forest/README.md`). Repeats are MultiMesh batches, one draw call per mesh surface.

- **Dead trees**, three procedural kinds with three variants each, built from parallel-transported bark tubes: gnarled trees (twisting trunk, root flares, four branch levels down to fine twigs, broken limbs with splintered ends), tall thin snags (some snapped, some leaning) and leaning arch trees whose long crooked limb reaches over the road above head height. Nine arches alternate sides from z -55 to -86, so the walk ends in a tunnel of bare limbs that opens onto the graveyard gate. 72 more trees line the trail and 26 ring the graveyard just outside its wall.
- **Hanging moss**: crossed ribbons on the limbs, frayed by the shader into strings of uneven length, with a slight sway.
- **Spruces**: 45 near-black procedural conifers in loose groups 10–34 m from the road, layering as dark masses in the fog.
- **Deadfall**: 16 logs laid along the terrain slope, 18 stumps, 20 triplanar schist boulders with moss on top.
- **Bog pools**: two terrain-hugging patches on the flattest ground 9–16 m from the road (z -48 to -84): wet mud and still black water with a fresnel sheen of the fog colour (Mobile has no screen-space reflections), ringed and dotted with reeds. Opaque, with discarded edges.
- **Reeds and dead grass**: 191 reed clumps and about 1,500 straw tufts in noise patches outside the walking strip.
- **Light shafts**: eight pale additive cards slanting through the canopy along the sun's azimuth at 62°, turning about their axis to face the camera and fading against geometry, with distance, end-on and outside the forest grade.
- **Ground mist**: 80 low camera-facing cards beside and across the trail, depth-faded into the ground, tinted with the live fog colour.
- **Embers**: seven small smouldering patches beside the trail, emissive, no lights.
- **Ash**: a sparse CPU particle drift (240 flakes) that follows the camera while it is well into the forest.

Existing village scenery outside the palisade is adjusted at runtime from this script only: near the trail most broadleaf crowns are hidden, leaving bare trunks and branches, the rest are darkened and desaturated; the trail-shoulder grass fades to straw; grass and ferns are cleared from the two pools; and one village boulder that spilled across the walking strip at z -73 (no collision) is hidden.

## Clearances, collision and cost

- Nothing solid or tall stands within 3.9 m of the road centre (`ChurchSite.road_x`), and nothing at all within 2.9 m (the walking strip; the torches are at 2.5 m). Logs keep both ends 3.4 m away.
- Nothing is placed inside theo-claude-7's church ground (T-085): the graveyard ring (`YARD_RADIUS` + 1.5 m), the walled rectangle x -21..13, z -112..-87 and the church footprint x -11..3, z -132..-106, each with a metre of margin. Nothing stands inside the palisade line (z > -31).
- 33 static cylinder colliders on the thicker trunks within 16 m of the road; snags, spruces, deadfall and plants have none.
- No new lights. Trees cast shadows; spruces and all small dressing do not. The batches hold about 0.6 M triangles. Measured in the real renderer at four fixed views (village gate, mid-trail, church approach, lobby), removing the node saves 32–36 draw calls and 0.8–1.6 M rendered primitives per frame including shadow passes, against a village that already renders 13–18 M. Frame time and thermals on M2 have not been measured (runs hit the game's 60 fps cap on an M5 Max).

## Captures

```sh
"$GODOT" --path . --script scripts/capture_haunted_forest.gd -- --host --port=7797 --capture-dir=/absolute/output/folder
```

Run it without `--headless`. It fails if the node is missing or a player-sized capsule collides anywhere along 31 samples of the walking strip from z -30 to -90. It then saves real Metal frames through the game's lens: inside the village facing the gate (base grade), just past the gate, mid-trail north, west and east, the arch tunnel, the church approach, looking back toward the village, a bog pool, and the lobby view. Each line prints the zone weight, the fog values it applied and the frame's draw calls and primitives. `--only=tunnel,bog` limits the views.

## Limitations

- Fog is non-volumetric depth fog plus cards; there is no light scattering through real volumes, and the light shafts are faked.
- Shading themes that set their own fog colour see the forest's absolute fog colour in the forest.
- The procedural trees are stylised, not botanical; moss strings and fine twigs alias a little in motion at a distance.
- Existing village conifers and distant tree-pack meshes are only darkened, not replaced.
- Collision is cylinders at trunk bases; arch limbs and branches have none.
