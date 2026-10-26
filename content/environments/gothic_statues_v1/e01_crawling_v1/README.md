# E01 crawling reach — first 3D pass

The selected E01 image is now a real, static marble sculpture with no added plinth. This is ready for model review; it does **not** match the source's fine facial, finger or hair detail yet.

- [80,000-triangle GLB](asset/e01_crawling_lod0.glb), with embedded 2K albedo, roughness, OpenGL tangent normal and AO.
- [30,000-triangle GLB](asset/e01_crawling_lod1.glb), sharing the same maps for distant use.
- [Blender source](asset/e01_crawling.blend), with the 722,974-triangle high mesh, LODs and packed textures.
- [Separate PNG maps](asset/textures/), [technical validation](review/asset_validation.json), [Godot validation](review/statue_probe.txt).
- [Actual Godot Mobile capture](review/godot_mobile.png), [Blender hero](review/final_hero.png), and six additional actual mesh views under `review/final_*.png`.

The GLBs are Y-up, about 2.2 m long × 1.2 m wide × 1.2 m tall, with the origin centered horizontally at floor level (within 1 mm after decimation). They have UVs, normals and tangents. No rig, animation or collider is supplied. Check contacts and collision during placement.

## Reconstruction and limits

The supplied approved PNG is unchanged in `source/approved.png`. This uses **one source view**: the earlier generated side/back candidates drifted and were not used as calibrated views. Hidden surfaces are inferred.

The selected reconstruction is TripoSG, seed 42, 75 steps, 2,048 latent tokens, guidance 7, 512-grid hierarchical extraction on Apple MPS. Fourteen disconnected scraps (316 triangles) were removed; the retained shell is closed. Quadric decimation produces both LODs. The normal map bakes actual high-to-low geometric detail; the warm marble albedo and roughness are procedural, and AO is baked. These maps do not recover missing source anatomy.

The face remains generic and soft; hair forms are chunky, fingers and toes are simplified, and rear folds differ from the reference. Treat this as an environment asset candidate, not a finished close-up sculpture. Image approval does not approve this reconstruction. No dungeon placement or traversal acceptance is claimed. The parent `.gdignore` deliberately keeps this review library out of the game's imports; copy the selected `asset/` files into a claimed runtime asset scope when integrating.

Two MIT TripoSG candidates and a local CL3D candidate were compared in actual geometry renders. The CL3D checkpoint's published territorial restrictions were found during provenance review; its experiment was preserved locally outside this game deliverable. [TripoSG's model card declares MIT](https://huggingface.co/VAST-AI/TripoSG); the [license](source/TripoSG-LICENSE.txt), exact revisions, weight hashes and narrow MPS patch are recorded here. No external sculpture mesh or texture artwork was downloaded.

## Reproduce

Use the existing `/Users/theochernin/Projects/CherninLab3D/.venv`, pinned TripoSG checkout and model snapshot recorded in `provenance.json`. The portable decoder patch is `source/triposg-mps.patch`; it makes the CUDA-only decoder import lazy, allocates the edge grid on the selected device and reduces decoder chunks to 8,000. No CUDA renderer or background-removal model is used.

From the game worktree, with `p=content/environments/gothic_statues_v1/e01_crawling_v1`:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python "$p/generate_triposg.py" --cl3d-root /Users/theochernin/Projects/CherninLab3D --seed 42 --steps 75 --name triposg_42
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python "$p/cleanup.py"
/Applications/Blender.app/Contents/MacOS/Blender --background --python "$p/finish_asset.py" -- --mesh "$p/mesh/clean_high.glb" --out "$p/asset"
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python "$p/validate_asset.py"
```

Both GLBs were imported and instantiated in a separate Godot 4.7.2 project to verify UV/tangent/normal arrays and all four material inputs, then rendered using Mobile/Metal through `scripts/godot_bg.sh`. Game headless import and full smoke passed; the smoke still emits existing ObjectDB shutdown warnings. See `review/checks.json` and adjacent logs. Browser orbit/zoom review is available locally at [the E01 preview](http://127.0.0.1:7865/static/e01-review/review/index.html) while the existing local server runs.
