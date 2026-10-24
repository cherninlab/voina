# Separate-agent integration — 2026-10-24

This is the first combined masonry/shader review. It retains the rejected wooden bridge geometry for comparison; T-159 is owned by the user's parallel bridge builder, theo-claude-14. Do not describe this set as completed dungeon art.

## Inputs

- Construction baseline: ec6150d — connected support placements, pitched nave trusses, local CL3D bearing capital and static Blender cloth bake.
- Masonry: 9c42bd9 + 92f1ad7 — deep blind arched reveals instead of whole pasted window panels; continuous chamfered/tapered/rebated shafts; shaped projecting voussoirs with mortar joints. No bridge-generator changes.
- Material shader: feedb45, SHA256 `452a50039f38045204ce4243fe6a15b901fcc21e26845db632bdbfcef131a729` — projected normal orientation, separate plaster/substrate colour, broad/medium variation, restrained relief, dry/damp roughness and per-timber scan variation. All existing uniform names retained.
- Integration caller change: `stone` and `wall` Bricks089 density 0.22 -> 0.16 repeats/m to match the coarser exposed substrate art scale. This is an art-direction adjustment, not a claim about scan-scale calibration.

## Current actual evidence

All eight `runtime/` PNGs are actual Godot 4.7.2 Mobile/Metal frames, source fingerprint `8fc6d62ccd76` on fc4c82f plus the two caller changes. The earlier ImageGen targets remain separately labelled in `../paintover_v3/`; they are not runtime evidence.

- Editor import: no script/shader errors.
- Main smoke: PASS, including real local ENet pair and disconnect cleanup.
- Character traversal: PASS, 1,276 m through descent, return, egress, optional loops, both bridge lanes and deep-floor recovery.
- Captures: all eight nonblank views saved. Pre-existing capture-exit cleanup warnings (seven Texture RIDs and one ObjectDB instance) remain recorded.
- Stronger construction audit: **FAIL**, two individual bridge-brace anchors lack a sufficiently close masonry intersection. The older center-of-support check passed; it did not cover these laterally offset endpoints. The new audit also checks all six roof-tie ends against actual wall collision and retains route/pier/brace intrusion checks. It is not weakened to hide the bridge defects.

Flagged anchor coordinates (metres, world coordinates):

```
(3.142679, -18.2, 2.070459)
(11.44105, -31.5075, -0.732803)
```

These belong to the bridge-support helper owned under T-159. The bridge owner also measured guard gaps around route bends and is changing that protected `build_path` guard branch. That new bridge/guard candidate is not included in these captures or test results. The independent review additionally flags the high-span pier's 57.25 m height and 5.12 m offset bearing as visually unconvincing; foundation contact alone does not validate that design.

## Ownership / next integration gate

- T-159: user's bridge agent — procedural baked decks, rails, joints, guard gaps and support follow-up. No competing bridge edits are made here.
- T-160: masonry agent — shipped and done.
- T-161: material agent — shipped and done.
- T-162: integration — this combined snapshot is saved; final acceptance waits for bridge corrections and later generator outputs.
- T-163..T-167 are separately scoped asset-generator tasks created by the user's bridge coordinator. Their outputs are not claimed as implemented or placed here.

The shader improvement is modest relative to the references. Broad plaster fields, repetitive wall texture and limited mid-scale wear still need further art work. The bridge geometry is explicitly rejected. Use the new actual captures for the next review; preserve the irregular routes, grades and layered crossings.
