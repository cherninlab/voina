# Long Grass

A night map for a long walk: a trodden road winds through a field of grass taller than a person, opening every so often into a campfire clearing. Hooded cultists at each fire wake when a player comes near. Pick **Long Grass** under Host game → Map, or `python3 scripts/playtest.py host --map long_grass`.

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
| | `grass_view_distance` | Grass beyond this is not drawn. |
| | `grass_root`, `grass_tip`, `wind` | Blade colours and sway. |
| Camps | `first_camp`, `camp_spacing`, `camp_jitter` | Where clearings fall along the road. The road's end is always a camp. |
| | `camp_radius` | Clearing size. |
| | `cultists_first`, `camp_growth`, `cultists_max` | Cultists per camp, growing along the road; the last camp holds the most. |
| | `wake_distance` | How close a player gets to a fire before its cultists wake. |
| Night | `moon_yaw`, `moon_height`, `moon_size`, `moonlight` | Moon position, size and light. |
| | `fog_density` | Night haze. |

Keep `turn` modest: a very tight bend can bring the inner fence closer than `field_half_width` to the road. The host prints the result on load, for example `LONG_GRASS_READY: 900 m road, 6 camps (2,2,3,3,4,5 cultists), 34431 grass clumps, seed 1337`.

## How it plays

- Players start at the south end of the road. The corner label shows camps cleared and either the distance to the road's end or the cultists at the live fire.
- One camp is live at a time. Its cultists use the existing host-owned raider AI on a navigation grid centred on the clearing. Walk on past a camp and its survivors give up and vanish when the next camp wakes; only camps whose cultists all fell count as cleared. Camps do not respawn. Leave and host again for a fresh road.
- The grass has no collision and does not hide players from cultists. The fence keeps everyone within `field_half_width` of the road.

## Scenery and cost

Flat ground, one road ribbon, one clearing disc and a stone ring with logs per camp, and grass in 30 m multimesh chunks culled past `grass_view_distance` with no shadows. Headless servers and tests skip the grass. The sky reuses the village's storm panorama (`content/environments/grim/storm_sky.png`), darkened, with an original procedural full moon (`gameplay/environment/moon_sky.gdshader`). Campfires reuse the church road's flame shader. No new external assets.

Verification: `python3 scripts/dungeon_smoke_test.py "$GODOT"` runs `tests/long_grass_test.tscn` over ENet: determinism, fence, planting, wake/clear/abandon, rehost and a joiner adopting the map.
