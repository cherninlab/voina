# Church and graveyard content

Shaders for `gameplay/environment/church_grounds.gd` (task T-085). All geometry is generated
procedurally at load time by that script; this folder holds only original shader code written
for the task. No new external assets are added here.

| Shader | Use |
| --- | --- |
| `church_stone.gdshader` | World-triplanar weathered stone with grime streaks, moss and a light ash dusting |
| `church_slate.gdshader` | Procedural wet slate shingles (roofs, spires) |
| `church_glass.gdshader` | Leaded glass: dim uneven flicker, dark, broken or boarded states |
| `church_flame.gdshader` | Y-billboarded candle, torch and grave-fire flames (one MultiMesh) |
| `church_mist.gdshader` | Thin terrain-following ground mist layers, depth-softened |
| `church_embers.gdshader` | Smouldering Voronoi ground cracks |
| `church_pit.gdshader` | Open grave: ray-marched earthen pit on a flat quad |
| `church_grass.gdshader` | Dead grass, reeds and hanging moss strands with wind sway |
| `church_ground.gdshader` | Dark trampled graveyard earth laid over the landscape |

## Reused repository assets

Textures (already in the repository; provenance in their own folders):

- `content/environments/valhalla/textures/KB3D_VHL_StoneGeneric_*`, `StoneFloor_*` (stone, walls,
  headstones, terrace), `MetalHammeredDark_*` (railing, gate, bell, cross), `WoodPlanksSeededDark_*`
  (door, boards, wooden crosses), `LogBark_*` (dead trees) — user-authorized KitBash Valhalla
  textures, see `content/environments/valhalla/provenance.json`.
- `content/environments/village_generated/soil_gravel.png`, `mineral_earth.png` (graves, yard
  earth) — original generated textures, prompts beside them.

Sounds (played, not copied; see `content/audio/catalog.json` and `docs/audio.md`, Sonniss GDC 2026
bundle licence): `content/audio/clips/ambience/church_bells_01.ogg` (occasional distant toll),
`forest_dark_synth_01.ogg` (low drone over the yard), `chimney_wind_01.ogg` (wind at the door).
None are verified loops; beds crossfade at their ends. Levels are not listening-tested.
