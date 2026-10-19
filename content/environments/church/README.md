# Church and graveyard content

Shaders for `gameplay/environment/church_grounds.gd` (task T-085). The church building is the
imported "Collapsed Gothic Chapel Ruin" by Pigcraft (CC-BY-4.0), processed and documented in
`content/environments/chapel_ruin/` (task T-094; attribution in its `provenance.json`). Everything
else (terrace, steps, walls, gate, graves, trees, props) is generated procedurally at load time.
This folder holds only original shader code written for the task; no new external assets.

| Shader | Use |
| --- | --- |
| `church_ruin.gdshader` | Runtime weathering of the chapel ruin's own PBR maps: greyer, darker, grime, moss |
| `church_stone.gdshader` | World-triplanar weathered stone with grime streaks, moss and a light ash dusting |
| `church_flame.gdshader` | Y-billboarded candle, torch and grave-fire flames (one MultiMesh) |
| `church_mist.gdshader` | Thin terrain-following ground mist layers, depth-softened |
| `church_embers.gdshader` | Smouldering Voronoi ground cracks |
| `church_pit.gdshader` | Open grave: ray-marched earthen pit on a flat quad |
| `church_grass.gdshader` | Dead grass, reeds and hanging moss strands with wind sway |
| `church_ground.gdshader` | Dark trampled graveyard earth laid over the landscape |

## Reused repository assets

Textures (already in the repository; provenance in their own folders):

- `content/environments/valhalla/textures/KB3D_VHL_StoneGeneric_*`, `StoneFloor_*` (yard wall,
  headstones, terrace, steps), `MetalHammeredDark_*` (railing, gate, torch brackets),
  `WoodPlanksSeededDark_*` (wooden crosses, torch shafts, shovel), `LogBark_*` (dead trees) — user-authorized KitBash Valhalla
  textures, see `content/environments/valhalla/provenance.json`.
- `content/environments/village_generated/soil_gravel.png`, `mineral_earth.png` (graves, yard
  earth) — original generated textures, prompts beside them.

Sounds (played, not copied; see `content/audio/catalog.json` and `docs/audio.md`, Sonniss GDC 2026
bundle licence): `content/audio/clips/ambience/church_bells_01.ogg` (occasional distant toll),
`forest_dark_synth_01.ogg` (low drone over the yard), `chimney_wind_01.ogg` (wind at the door).
None are verified loops; beds crossfade at their ends. Levels are not listening-tested.
