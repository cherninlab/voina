# Hanging dressing review v1 (T-164), 2026-10-24

Evidence for `content/environments/procedural_hanging_v1/` (18 GLBs: banner, tapestry, drape,
web_corner, web_sheet, rope, three variants each). Nothing here is placed in the game; T-162
integrates.

## Files

- `turntable_<type>.png`: Blender Cycles, four views (0/90/180/270 degrees) of the three
  variants, re-imported from the exported GLBs (UVs, COLOR_0 and socket nodes asserted). Red dots
  are the socket nodes; brown boxes are unexported context (beam proxies, posts, wall arrises).
  The review material is AO x a dye picked by Color.G; webs are drawn as translucent sheets to
  judge their shape, not with the Godot strand shader.
- `engine/01..05`: Godot 4.7.2 Mobile/Metal frames of `preview/hanging_preview.tscn`: dungeon
  hewn timber with the crypt's wood material, crypt brick and floor materials, the crypt
  environment and one warm torch OmniLight3D. Every asset is placed only from bake.json sockets;
  the GLB socket nodes agree with bake.json to 0.000000 m.
- `engine/11-12`: the real Red Descent (`--dungeon --shading-ephemeral`), dressing hung at runtime
  on the middle nave roof tie (0.42 x 0.55 m, from (-14.3, -0.3, 38.5) to (14.3, -0.3, 38.5)):
  banner_1, drape_1 (baked for exactly that section), tapestry_1, banner_0 and web_corner_2 at the
  king post. The nave roof is about 18 m above its torches and is black without light, so two
  capture-only warm lamps were added; they are not part of the assets.
- `blender-bake.txt`, `capture.txt`, `editor-import.txt`, `smoke.txt`: logs of the runs.

## Measured (bake.json)

| | Limit | Worst |
|---|---|---|
| Pin error, settled pin to socket | 2 mm | 2e-7 m (rope end ring); cloth 0 |
| Edge stretch, settled / rest | 1.05 | 1.0162 (drape_1); banners 1.004-1.007, webs <= 1.0008 |
| Last-frame motion after 300 frames | 1 mm | 0.85 mm (tapestry_1, cloth touching the beam); banner_0/2 and tapestry_0 < 0.003 mm, drapes 0.15-0.64 mm, webs <= 0.06 mm |
| Cloth triangles | 6,000 | 4,740 (tapestry_0) |

Exported cloth is a 4 mm shell centred on the simulated surface, so its faces are 2 mm from each
socket. Editor import: no errors or warnings. Smoke suite: PASS. Capture exit warnings (one
ObjectDB, seven Texture RIDs in the dungeon run) match the pre-existing ones in
`../structure_v1/README.md`.

## Honest assessment

- Banners and tapestries are the strongest result: gathered tops scallop between the nails, the
  lost-nail variants (banner_1, tapestry_1) droop diagonally, holes, notches and the swallowtail
  read clearly. Below the top third they hang fairly flat; some torn strips end in rounded
  "fingers" from the outline smoothing rather than sharp frayed points. The weave is invisible
  beyond about a metre, and dark gradients band on the Mobile renderer (all materials do).
- Drapes bunch convincingly on the beam with uneven sides, but from below and in front drape_0
  reads as a lumpy sack, and the undyed `cloth_ash` looks brown under torch light.
- The corner web (05) reads as a cobweb in the beam-post corner, but it is stylised: a regular
  fan of radials, and near the anchored edges the capture threads look like ladder rungs.
  The two ceiling-corner webs (web_corner_0/1) are nearly flat (7-12 cm sag) and were not shown
  in engine.
- The sheet web (04) sags correctly between the two bearers, but at 1-2 m its strands look more
  like coarse netting than gauze.
- Rope: clean catenaries and a plausible tail; the end bindings are too small to read at distance.
- In the dungeon (11-12) the dressing sits correctly on the real tie, but it is small and dark
  from below; banners there need nearby light to be seen.

Not done: wind or other runtime motion, shadows from webs (alpha-blended), web-specific LODs
(Godot's default import LODs apply), placement in Red Descent (T-162).

## Reproduce

```sh
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_hanging.py -- \
    content/environments/procedural_hanging_v1 --review content/environments/red_descent/review/hanging_v1
"$GODOT" --headless --editor --path . --quit
scripts/godot_bg.sh --path . --script res://content/environments/procedural_hanging_v1/preview/capture.gd -- --capture-dir=$PWD/content/environments/red_descent/review/hanging_v1/engine
scripts/godot_bg.sh --path . --script res://content/environments/procedural_hanging_v1/preview/capture_in_dungeon.gd -- --dungeon --shading-ephemeral --capture-dir=$PWD/content/environments/red_descent/review/hanging_v1/engine
python3 scripts/smoke_test.py "$GODOT"
```
