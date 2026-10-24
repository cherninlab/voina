# Generated dungeon kit, first integrated revision

17 distinct mesh sources reconstructed locally with the supplied CL3D/2mini pipeline on MPS float16. Native OpenAI ImageGen produced the isolated transparent references. The final window bay was generated from a paintover of the actual `kit-first/06-descent-overlook` runtime capture, then reconstructed and put back into the level. The model weights are not included.

The kit contains pointed and round arches, narrow and twin-lancet windows, three different wall fragments, a window wall bay, square buttress, octagonal column, stairs, timber bracket, timber deck, stone arch span, natural outcrop, rubble and carved corbel. Sixteen source types are placed in the dungeon. The stair block remains a reviewed source asset; the existing tested ramps provide the playable stair routes.

Each source has three authored mesh LODs: 18,000–35,000 triangles near the camera, roughly one third at medium distance, and about 2,500 far away. Runtime spatial MultiMeshes switch at 20 and 50 metres and stop at 140 metres. Large source meshes (roughly 0.3–1.6 million triangles) remain outside the game repository. `preparation.json` records output triangle counts and SHA256 hashes.

The meshes are uniformly converted to physical metre units and grounded before export. Duplicate/degenerate geometry and tiny extraction islands are removed; normals are recalculated before decimation. Native triplanar PBR uses the documented CC0 detail textures in `../dungeon_pbr_v2/`. Subtle per-vertex macro colour comes from each source reference. This is not a complete multi-view texture bake. A naive full colour projection was rejected because it projected studio highlights and false edges onto the reconstructed shapes. The window wall bay instead uses a matched-view UV projection, with an opaque ImageGen-extended colour plate and a separate world-triplanar UV2 detail normal. Filling the plate outside the source silhouette avoids transparent black/red fringes; the actual mesh supplies the opening. Unseen faces still need a future multi-view art pass. Sculpted relief, material normals and roughness supply separate scales of detail.

Wall relief and cave rocks contribute transformed LOD2 triangle faces to the unscaled static collision body. Existing ribbon collision remains authoritative for the inclined bridge decks; their sculpted tops vary by a few centimetres. Timber brackets and stone bridge supports follow each route's slope and direction. Cave dressing respects joining passages. Pier modules are stacked in sections rather than stretching one short column over a whole hall.

`sources.json` records exact reference prompts, original pixel hashes, raw-mesh hashes and local generation parameters. `review/references/` contains unchanged native outputs; `review/paintover-01.png` is an AI target, not a game screenshot. `review/final/` contains real Godot material previews. The review folder is excluded from engine import/export. No supplied 3D scans were needed for this revision.

Reconstruct with the existing local `CherninLab3D/tests/dungeon_kit_01/generate_kit.py` runner and manifest. Then prepare in this checkout:

```sh
blender --factory-startup --background --python-exit-code 1 --python scripts/art/prepare_dungeon_kit.py -- /absolute/manifest.json content/environments/generated_dungeon_kit_v1/meshes
# Refresh broad colour only, without changing geometry:
blender --factory-startup --background --python-exit-code 1 --python scripts/art/prepare_dungeon_kit.py -- /absolute/manifest.json content/environments/generated_dungeon_kit_v1/meshes --paint-only
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script content/environments/generated_dungeon_kit_v1/review_kit.gd
```

For material previews, run the same review script through `scripts/godot_bg.sh` with `-- --capture-dir=/absolute/folder`. The runnable check verifies all 51 GLBs, grounded bounds, normals, non-uniform reference colours and the three triangle budgets. The whole-level capsule check is `tests/dungeon_traversal_test.tscn`; real level captures use `scripts/capture_dungeon.gd`. See `../red_descent/review/rerender_v2/` for validation evidence and remaining art limits.
