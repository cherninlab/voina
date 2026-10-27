# TRELLIS.2: two different Gothic sculptures

T-197 uses the previously selected S02 Hooded Reaper and S06 Horned Oracle concepts from `../compositions_v2/`. Each reconstruction uses one image. This is the actual larger Microsoft TRELLIS.2-4B family running through native MLX, not the original TRELLIS-image-large checkpoint and not a four-image conditioning run.

| Trial | Requested / actual grid | Sampling | Cleaned triangles |
| --- | --- | --- | --- |
| Hooded reaper | 512 / 512 | Seed 42, 12 steps per stage | 1,444,206 |
| Horned oracle | 512 / 512 | Seed 42, 12 steps per stage | 1,303,598 |
| Horned oracle, higher resolution | 768 / 768 | Same input and seed, 12 steps per stage; 32,768-token cap | 2,805,322 |

[Rotatable review](review/index.html), [input receipts](sources.json). The review offers dense cleaned GLBs and raw generated geometry. Neutral marble is a constant PBR material for inspecting shape; texture-generation weights and PBR baking were not used. Fine pockmarks, rough patches, thin-surface gaps and some winding inconsistencies remain. These are reconstruction candidates for visual review, not accepted or dungeon-integrated assets.

## Provenance and processing

- Model: `microsoft/TRELLIS.2-4B`, weight revision `af44b45f2e35a493886929c6d786e563ec68364d`.
- Image encoder: the official, access-granted `facebook/dinov3-vitl16-pretrain-lvd1689m`, revision `ea8dc2863c51be0a264bab82070e3e8836b02d51`.
- Runtime: MLX 0.32.4, native Apple Silicon port `lyonsno/trellis2mlx`, revision `449bfbc011401fe03d684a01f0b1068bfe8f6ceb`; isolated environment `/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/`.
- Input: original source RGB and alpha, threshold-based foreground crop with 20% margin, black alpha composite, 512-square DINO conditioning. No image generation or repainted content was introduced in this step.
- Native `mesh_raw` checkpoints are saved locally; `checkpoints/` is excluded from Git. Raw and cleaned GLBs, actual mesh renders and JSON receipts are retained for sharing.
- Cleanup uses the port's `cleanup_mesh` and `repair_exterior_surface`. It filters negligible debris before splitting non-manifold edges, preserves attached detail, and repairs confident exterior orientation. No decimation, smoothing, anatomical replacement or hole filling was applied. Open/non-manifold surfaces are allowed by the model; structural validity is separate from visual acceptance.

`result.json` records the actual source hash, command, model revisions and generation time. `finish.json` records cleanup and orientation changes. The 768 run records its actual decoder grid and a 42 GiB MLX memory guideline; the guideline is not a measured peak-memory claim.

## Reproduce

From the game repository, using the installed CherninLab3D environment:

```sh
python content/environments/gothic_statues_v1/e01_quality_v2/single_image_trellis2.py --image content/environments/gothic_statues_v1/compositions_v2/references/S02-hooded-reaper.png --out content/environments/gothic_statues_v1/trellis2_statues_v1/reaper_512 --resolution 512 --steps 12
python content/environments/gothic_statues_v1/e01_quality_v2/single_image_trellis2.py --image content/environments/gothic_statues_v1/compositions_v2/references/S06-horned-oracle.png --out content/environments/gothic_statues_v1/trellis2_statues_v1/oracle_512 --resolution 512 --steps 12
python content/environments/gothic_statues_v1/trellis2_statues_v1/higher_resolution.py
```

Run `finish_geometry.py FOLDER` with `.venv-trellis2/bin/python` after each raw generation. It reuses saved native geometry and does not rerun the model. The higher-resolution script uses the same saved conditioning image as the 512 oracle. Official source and runtime license copies are in `licenses/`; model weights remain outside the game repository.
