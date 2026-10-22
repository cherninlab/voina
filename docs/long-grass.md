# Long Grass

A night map for a long walk: a trodden road winds through a field of grass taller than a person, opening every so often into a campfire clearing. Hooded cultists at each fire wake when a player comes near, and midway between every two fires a small trampled space hides an ambush in the grass. The road ends in a last clearing around its final fire, where the corner label reads "The road ends here." Pick **Long Grass** under Host game → Map, or `python3 scripts/playtest.py host --map long_grass`.

## Tweaking the generation

Every knob lives in [`gameplay/environment/long_grass.tres`](../gameplay/environment/long_grass.tres). Open it in the Godot inspector (each field has a tooltip) or edit the text, then host. The same file gives every peer the same road. It is part of the build fingerprint, so ship the change before playing with someone else.

| Group | Setting | What it does |
| --- | --- | --- |
| Road | `road_seed` | Same seed, same road. Change it for a new layout with the same feel. |
| | `length` | Walking length in metres (default 900). |
| | `step` | Distance between road points; the road bends only there. |
| | `turn` | Largest random change of direction per point, in degrees. |
| | `straighten` | Pull back toward the overall direction (0 wanders freely, 1 stays straight). |
| | `max_heading` | The road never points further than this from straight ahead. |
| | `path_width` | Width of the trodden path. |
| Field | `field_half_width` | Grass and the invisible fence sit this far from the road's centre line. |
| | `grass_height_min`, `grass_height_max` | Clump heights in metres. |
| | `grass_density` | Clumps per square metre; each clump is 11 blades. |
| | `grass_beyond_fence` | Grass carries on this far past the fence, so the field never visibly stops where walking does. |
| | `grass_view_distance` | Grass beyond this is not drawn. |
| | `grass_root`, `grass_tip`, `wind` | Blade colours and sway. |
| Treeline | `trees_near`, `trees_far` | Spruce silhouettes stand this near and far from the road, beyond both ends too. |
| | `tree_spacing`, `tree_gaps` | Road metres between rows of three trees per side; the share of horizon left open between stands. |
| | `tree_height_min`, `tree_height_max` | Tree heights in metres. |
| | `tree_tint` | Multiplies the pine sprites' colours; low keeps the wood dark against the night sky. |
| Camps | `first_camp`, `camp_spacing`, `camp_jitter` | Where clearings fall along the road. The road always ends in a clearing around the last fire. |
| | `camp_radius` | Clearing size. |
| | `cultists_first`, `camp_growth`, `cultists_max` | Cultists per camp, growing along the road; the last camp holds the most. |
| | `wake_distance` | How close a player gets to a fire before its cultists wake. |
| Ambushes | `ambushes` | A trampled space midway between each pair of fires, with cultists in the grass around it. |
| | `ambush_cultists`, `ambush_radius` | How many rise, and the size of the space. |
| | `ambush_wake` | How close to the middle of the space a player gets before they rise. |
| Night | `moon_yaw`, `moon_height`, `moon_size`, `moonlight` | Moon position, size and light. |
| | `fog_density` | Night haze. |

Keep `turn` modest: a very tight bend can bring the inner fence closer than `field_half_width` to the road. The host prints the result on load, for example `LONG_GRASS_READY: 900 m road, 6 camps (2,2,3,3,4,5 cultists), 5 ambushes, 66213 grass clumps, 840 trees, seed 1337`. Planting that much grass takes about half a second at load..

## How it plays

- Players start at the south end of the road. The corner label shows fights won (camps and ambushes) and either the distance to the last fire or the cultists still standing.
- Encounters come in road order: camp, ambush, camp ... A camp wakes at `wake_distance` from its fire; an ambush springs at `ambush_wake` from the middle of its space, its cultists rising just inside the grass around it.
- One site is live at a time. Its cultists use the existing host-owned raider AI on a navigation grid centred on the clearing. Walk on past a site and its survivors give up and vanish when the next one wakes; only sites whose cultists all fell count as won. Nothing respawns. Leave and host again for a fresh road.
- Under the Risograph theme this map brightens the image by 1.4 stops, so the night falls across the inks instead of onto black (`GameMaps.SHADING_ADJUST`, see docs/shading.md). Other maps and themes are untouched.
- The grass has no collision and does not hide players from cultists. The fence keeps everyone within `field_half_width` of the road; the grass runs `grass_beyond_fence` further.

## Scenery and cost

Flat ground, one road ribbon, one clearing disc and a stone ring with logs per camp, and grass in 30 m multimesh chunks culled past `grass_view_distance` with no shadows. The road, clearings and soil use the village's generated dirt albedos (`compacted_path`, `soil_gravel`, `mineral_earth` in `content/environments/village_generated/`), projected from above in world metres. The treeline is one multimesh of about 850 pines, each three crossed quads (6 triangles) showing one of three sprites from `content/environments/long_grass/horizon_pines.png`, unlit, darkened by `tree_tint` and unfogged so they hold against the sky. The atlas comes from a sprite sheet the project owner supplied; its licence is still to be confirmed (see that folder's README). Headless servers and tests skip the grass. The sky reuses the village's storm panorama (`content/environments/grim/storm_sky.png`), darkened, with an original procedural full moon (`gameplay/environment/moon_sky.gdshader`). Campfires reuse the church road's flame shader. No other new external assets.

Verification: `python3 scripts/dungeon_smoke_test.py "$GODOT"` runs `tests/long_grass_test.tscn` over ENet: determinism, fence, planting, wake/clear/abandon, rehost and a joiner adopting the map.
