# Hillside church and graveyard

`gameplay/environment/church_grounds.gd` (node `ChurchGrounds`, added by `MatchWorld.build_arena` after the village) builds the haunted church yard at the end of the north trail. It is cosmetic scenery plus static collision: no network state and no gameplay logic. Positions come from `ChurchSite`.

## What is there

- **Church**: the imported "Collapsed Gothic Chapel Ruin" (Pigcraft, CC-BY-4.0; processing and attribution in `content/environments/chapel_ruin/`, T-094), unscaled, front arch on `ChurchSite.DOOR` facing the village. Its flat base sits 0.35 m below the slope behind it (about 6.0 m), so a stone terrace carries the front 2.6 m above the yard and is buried into the hill at the back. The model brings its own trimesh collision. A runtime shader (`church_ruin.gdshader`) darkens, greys and moss-stains its pale source texture. Cold pale light glows behind the back tracery window, the one bright opening seen through the arch; a cold lamp washes the inner walls and candles stand on the threshold.
- **Terrace and steps**: 3 m wide steps (0.27 m risers, 27 degrees) with sloping cheek walls run down to the yard. Collision is one ramp under the step nosings plus a short invisible ramp over the 0.25 m lip into the ruin, so the real player walks straight in.
- **Graveyard**: a waist-high mossy wall topped by a spiked iron railing encloses x -20.5…12.5, z -87.5…-111, with two collapsed, crossable bays (west z -99.5, east z -102). Two stone pillars with balls and burning pitch torches flank an open, arched iron gate across the road at z -87.5 (3.5 m clear), under an iron overthrow with a cross.
- **Graves**: over thirty tilted round, pointed, shouldered, broken, cross, obelisk and wooden markers in rows with lanes between them, kerbs and old mounds, a crooked cross and a crow (idle head turns) by the path, a stepped obelisk monument, and a faceless hooded figure just inside the gate. The six villager spawn points (`MobSystem.SPAWN_SPOTS`) carry three open graves (ray-marched pits, spoil heaps, a shovel; one ringed by candles) and three freshly broken mounds, each kept free of collision within a metre.
- **Dressing**: six tall, thin dead trees with broken limbs and hanging moss (two gnarled ones frame the gate), dead grass and reeds, a small grave fire (torches and fire share the road torches' noise-torn flame, halo, sparks and smoke shaders from `content/environments/church_road/`; candles keep a tiny billboard flame), four smouldering ember-crack patches with sparks, dark trampled earth over the landscape, thin drifting ground mist layers and slow ash flakes.
- **Ground**: the yard earth (`church_ground.gdshader`) is the village's gravel-and-mineral dirt trodden dark, with textured dead turf, matte wet hollows and ash. It lies 3 cm above the landscape on sheets with the landscape's own triangles and smooth normals, reaching about 7 m outside the walls (x -29…20, z -119…-76, in eight pieces for Mobile's per-mesh light limit). Over its outer 6 m it fades in ragged tongues into exactly what the landscape shader draws there (a copy of `make_landscape_material`; keep the two in step), so the forest floor runs into the yard without a seam; it hands the torch-road mud strip's shoulders back to the landscape the same way. The terrace, steps and their coping use the ruin's weathering (its tint, greying and the grime that darkens stone near its floor), so the terrace meets the ruin floor in kind. Ground mist thins when seen edge-on, so it does not read as a pale floor over the earth.
- **Blood**: blood marks are placed on collision but drawn 5 cm nearer the camera along their view ray (same screen position), so they show on the yard earth and other overlays laid just above the collision; the road mud (transparent) draws first.
- **Sound**: an occasional distant bell toll from `church_bells_01`, a low `forest_dark_synth_01` drone over the yard and `chimney_wind_01` at the arch, as `AudioStreamPlayer3D`s; beds crossfade because no clip is a verified loop. Skipped headless and with `--server`. Levels are not listening-tested.

Village plants and rocks inside the church and yard areas are hidden from this script (tree-pack meshes hidden, instanced grass, ferns and saplings collapsed); the village files are untouched. The global environment, sky and fog are not changed.

## Collision and the villagers

Static collision: terrace, steps ramp, threshold ramp, cheek walls, wall bays with railing height, gate pillars and open leaves, monument, boulders, tree trunks and the figure (unscaled boxes and cylinders), plus the ruin's own trimesh. Grave markers have none, so the villagers' leaps and grid stay open. It is built synchronously after the village, and the capture confirms it within two physics frames.

`MobNavigation` takes the lowest surface under each cell, so any collider standing above the terrain (terrace, steps, ruin) counts as solid: villagers cannot path up into the ruin unless that rule changes. Players can.

## Lights

Six non-shadowing OmniLights with distance fade: two gate torches, the grave fire, the candle-ringed open grave, the ember patch at the terrace and the cold lamp in the ruin. Godot's Mobile renderer applies at most 8 omni + 8 spot lights per mesh ([lights and shadows](https://docs.godotengine.org/en/latest/tutorials/3d/lights_and_shadows.html)), so yard meshes are split into four chunks and the yard earth reaches past the gate to catch the torch pools; the single huge landscape mesh still spends its slots on whichever lights it is paired with.

## Captures and checks

```sh
"$GODOT" --path . --script scripts/capture_church.gd -- --host --capture-dir=/absolute/folder [--fog] [--bright] [--hide=NodePattern]
```

Run without `--headless`. The script checks the terrace floor within two physics frames, terrace/ruin/yard-wall collision, the player capsule through the open gate, real player landings on the path, steps and terrace, the real player walking up the steps into the ruin, the spawn graves clear of church collision and the light count; then it saves Metal frames: trail (from the village gate), gate, path, facade, slope, door, crow, grave, overview, seam-west, seam-east (forest floor into the yard earth), terrace, and blood-yard and blood-road (stains placed on the yard earth, the road mud and bare landscape). `--fog` raises capture-only blue-grey fog; `--bright` holds the forest grade still and adds flat ambient light so ground textures and seams can be judged; `--hide=Pattern` (repeatable) hides church meshes by node name, e.g. `--hide='GroundMist*'`.

## Not done

- From the village end of the trail the church is hidden by trees and the haunted-forest fog; it appears from the gate onward.
- No bell tower: the ruin stands alone, and the bell is heard but not seen.
- Villagers do not climb the terrace (see above). Landscape lighting near the yard depends on Mobile's per-mesh light pairing.
- Sound mix, M2 frame cost and temporal stability are not measured.
