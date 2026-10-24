# T-171: CL3D props and physics-scattered dressing

Ten image-approved source props, each with three LODs, and twelve independently baked static dressing sets. Shape generation used the local CL3D/2mini pipeline, then Blender 5.2.2 cleanup, decimation and rigid-body simulation. Final assets were imported and captured using Godot 4.7.2 Mobile/Metal. This pack is ready for placement/material work by the dungeon owners.

## Files to use

- `sources/<id>_lod0.glb`, `_lod1.glb`, `_lod2.glb`: table, bench, shelf, barrel, coffin body, coffin lid, skull, femur, pot and candle holder. `sources.json` records dimensions in Godot metres, triangle counts, hashes and source-image provenance. Total LOD0 budget: 59,500 triangles across ten props. Select LOD explicitly; the three source files are separate assets.
- `sets/<family>_v0.glb` through `_v2.glb`: `refectory`, `mortuary`, `ossuary` and `votive`. These are static baked compositions. Imported convex collision is included only for large props; bones, candles and small shards are decorative. `sets.json` records per-set bounds, seed, physics metrics, collision counts and SHA-256.
- `preview_sources.gd`: standalone native Godot audit/capture script, not gameplay code.
- `source_jobs.json`, `generation_jobs.json`, `conditioning.json`, `model-provenance.json`: generation and provenance records. `raw_cl3d/` and `conditioning/` have `.gdignore` and are reproduction inputs, not runtime assets.

## Placement handoff

Put the root at uniform scale `(1,1,1)`. Geometry is already scaled in metres, with source origin at ground centre. Never stretch a physics body. Sets preserve their baked local coordinates; their lowest point is approximately 1 mm above the offline support plane. Align that plane with the visible floor, then inspect actual room contacts.

`sets.json` gives each footprint as Godot min/max XYZ. Every standalone template reserves Blender Y -2.2 to -1.0 m, equivalent to Godot Z +1.0 to +2.2 m, as a 1.2 m route strip. The nearest retained geometry stays at least 0.3869 m away from this strip. This local template check does not prove room traversal. Avoid narrow doors and traversal chokepoints when placing it.

Suggested use: refectory beside wider landing walls; mortuary in crypt alcoves; ossuary against a tall wall; votive in chapel margins. v0 is the gravity-settled calm control, v1 a mild tremor, v2 a stronger tremor with an offline rolling stone. The rolling stone itself is not exported. Heavy ossuary/votive pots are split into three actual fracture cells. The shelf stays anchored during disturbance, allowing its loose contents to fall. Initial arrangements are gravity-settled before the calm/control comparison.

## Materials and acceptance

All GLBs currently use neutral `ReviewClay`. CL3D generated shape only: no final UV, wood, clay, metal or bone texture map is claimed. Assign suitable materials in a placement/material task. The new stone/brick work is T-183; existing stone-face PBR maps are T-180 and varied masonry geometry is T-182.

The approved image references and their exact prompts live in `../red_descent/review/props_aged_v1/references_v1/`. Approval was the user's “i think we can start with that”, recorded with image hashes in `approval.json`. Foreground masking is an internal conditioning step; the ten approved PNGs are byte-identical. A rejected unmasked pass fused ground shadows to a few props; its before-frames remain in `cl3d_v1/rejected_unmasked/`. Accepted sources were regenerated from foreground masks using the original fixed seeds. The open coffin and pot cavities were checked with actual mesh rays (`interior_probe` in `sources.json`).

## Review and checks

See `../red_descent/review/props_aged_v1/README.md` and `verification.json` there. The source and set contact sheets under `cl3d_v1/godot/` and `physics_v1/godot/` contain actual Godot screenshots. No dungeon scene is modified by this task; final human in-dungeon visual/traversal acceptance remains with placement.

The final twelve sets all pass the stored checks: calm maximum translation under 0.3 mm, maximum sampled support gap under 4 mm, sampled penetration 0, and local lane clearance over 0.386 m. Contact and penetration checks sample actual mesh surfaces and have finite tolerance; they are not a universal mathematical intersection proof.

Godot editor import, all thirty LOD/native twelve-set audits, twenty-two native captures and the repository ENet smoke passed on base 4489bea. Known ObjectDB cleanup warnings remain in shutdown logs; no final script/parse errors were found.

## Reproduce

Run at the repository root, with the recorded local CL3D environment/model available:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python /Users/theochernin/Projects/CherninLab3D/tests/dungeon_kit_01/generate_kit.py content/environments/procedural_props_aged_v1/generation_jobs.json
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_scattered_props.py
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_scattered_props.py -- --sets
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
scripts/godot_bg.sh --path . --script res://content/environments/procedural_props_aged_v1/preview_sources.gd
```

`generation_jobs.json` is the manifest for the external runner; its paths are resolved from the repository root. That runner is external to this repository and its SHA is recorded. The approved PNGs and masked conditioning inputs are retained. `--only`, `--variants` and `--no-render` permit scoped Blender reruns. The source preparation defaults to all ten props; `--sets` bakes all twelve compositions.

## Provenance

Image concepts: built-in ImageGen, exact prompts and generation receipts retained. Shape inference: local CL3D/2mini build of Tencent Hunyuan3D-2mini, 50 steps, octree 384, MPS float16; full checkpoint/config/code hashes and upstream community-model licence identity are in `model-provenance.json`. Follow the repository's CL3D provenance policy in `docs/procedural-generators.md`; public export/packaging review remains T-118. Blender procedural cleanup and physical placement add no external asset dependencies. The foreground extractor's installed rembg model identity is recorded explicitly; do not label the resulting pack CC0 by construction.
