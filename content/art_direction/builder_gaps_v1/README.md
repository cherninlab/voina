# Builder gaps v1 (H-021)

Actual-game frames of what looks most primitive in Red Descent on 2026-11-08 (main at `0d0d4a9`). Mobile/Metal, captured with `scripts/godot_bg.sh` using `capture_dungeon.gd --dungeon --shading-ephemeral --review` and `capture_bridges.gd --dungeon --shading-ephemeral`, then reduced to 1280 px JPEG. The folder has a `.gdignore` so Godot does not import these frames or ship them.

The ranked gap list and the rules that answer each gap are in [docs/builder-design.md](../../../docs/builder-design.md).

| Frame | What is wrong |
| --- | --- |
| `01-bridge-floats-beside-tower` | The low bridge is a thin flat deck hanging beside a tower. Nothing visibly carries it, and the tower is a flat box with a tiling texture and small decals. Compare Theo's paintover 4, where the deck rests on brackets and struts let into ragged masonry. |
| `02-bridge-underside-no-structure` | Seen from below, the bridge is a thin plank sheet on a few black sticks, with no bearers, bracing or bearings into the wall. |
| `03-bridge-missing-boards-grey-plates` | Missing boards show flat pale plates instead of the drop below. Diagnose these before building on them. |
| `04-bridge-straight-uniform` | Ruler-straight deck, identical boards, evenly spaced identical posts, and the same post-and-box torch repeated. The bake report says the chosen ageing moved boards 1.8 cm at most, leaned no post, and left the deck within 7 mm of flat: invisible. |
| `05-shaft-boxes-and-repeated-torch` | The shaft is old boxes: flat brick-textured slabs floating in the dark, the torch prop repeated. |
| `06-upper-crossing-slabs-thin-beams` | The upper crossing reads as flat tiled slabs on thin black beams, a plain cylinder column, and blank plaster faces. |
| `07-tunnel-uniform-clean` | Real stonework, but every stone is the same size and tone, nothing is dirty or broken, and there is no rubble, damp or growth at the base. The torch is the same prop again. |
| `08-junction-flat-arch-slabs` | Arches between passages and rooms read as thin flat-sided slabs, not deep rings through a wall. |
| `09-stair-hall-box-parapet` | The stair hall's parapet is a plain box, and the walls are uniform with nothing that explains the space. |
| `10-nave-empty-dark` | The biggest room is a dark empty floor with flat red plaster and a few sconces: no composition, focal point or furniture. |
| `11-ossuary-props-in-a-row` | The ossuary shows no bones. Three identical crates and pots are lined up against the wall under one lamp post. |
