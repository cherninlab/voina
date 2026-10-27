# Oracle face and reduction trial

This is a review candidate, not a finished or dungeon-integrated asset. The original TRELLIS.2 statue files are unchanged. The face is more readable, but the hair, neck transition and larger surface defects still need art cleanup.

## Deliverables

- `baked_150k/statue.glb`: **147,628 triangles**, embedded 4096² OpenGL tangent normal and ambient-occlusion maps. About **94.7% fewer triangles** than the original 2,805,322-triangle Oracle. This is a geometry reduction measurement, not an FPS or memory benchmark.
- `baked_150k/geometry_only.glb`: identical positions, indices and vertex normals, with the normal/AO material channels disabled for comparison. The unused image payload is retained in this comparison file.
- `baked_150k/normal.png`, `ao.png`: separate maps for further work.
- `oracle_repaired_high.glb`: dense surface-repair source for baking. VDB makes it denser than the original; it is an offline intermediate.
- `review/index.html`: original/repaired comparison, face camera, map links and downloads.
- `review/before/`, `review/final_high/`, `review/baked/`: actual Blender geometry renders, not image-generated previews.

## Method and provenance

1. Crop the head/neck from the **same approved S06 image**, without making a new face image. `generate_head.py` records the source hash, crop polygon and conditioning hash. The background is masked for conditioning; cropped horns are not included as the intended head geometry.
2. Run **Microsoft TRELLIS.2-4B**, revision `af44b45f2e35a493886929c6d786e563ec68364d`, native MLX port revision `449bfbc011401fe03d684a01f0b1068bfe8f6ceb`, one image / 512 grid / 12 steps / seed 42. Official DINOv3 conditioning is used. See `head_512/result.json`; runtime and licenses are documented in the parent statue trial.
3. Use the native port's surface-preserving cleanup for the reconstructed head. `head_512/clean_high.glb` is retained. Register it to the original head with trimmed ICP (`refine_geometry.py`, `head_alignment.json`).
4. Replace the original facial shell while retaining the original crown, horns and long hair (`swap_head.py`). Give the generated open sheets **2.4 mm symmetric thickness** and unite them using **Blender OpenVDB**, 1 mm voxels, adaptivity .025 and two bounded smooth iterations (`voxel_repair.py`). This repairs many fine cracks, but also softens/thickens thin features. It does not recover missing reference detail or remove every visual defect.
5. Use installed **MeshLab / PyMeshLab quadric error reduction**, target 150k, normal/boundary preservation, face importance ×30 and hands ×8 (`reduce_geometry.py`). This protects important regions more than uniform reduction. It is not hand-authored quad retopology.
6. Use **Blender 5.2.2 Cycles** to unwrap the reduced mesh and bake the dense surface onto it, with selected-to-active tangent normal baking, a 0.5 mm cage and 4 mm maximum ray distance. Valid back-facing normal samples are flipped into the tangent hemisphere; invalid normal vectors use the neutral tangent normal. Bake AO separately. Degenerate triangles discarded on Blender import bring the exported count to 147,628. The GLB includes normals, tangents, UVs, normal texture and occlusion texture (material AO strength .35). Each stage retains a receipt.

No texture image is claimed to fix silhouettes or missing anatomy. No displacement map is included: the present Godot Mobile target benefits from the normal-map export without requiring extra tessellation.

## Rejected experiments and remaining limits

`rejected_attempts.json` records the failed face depth transfer, direct VDB on open sheets, and whole-object MeshFix trial. None is the default reviewed asset. The rejected MeshFix output was a closed head with most of the body discarded, demonstrating why watertightness alone is insufficient.

The reduced export has consistent indexed winding but still contains non-manifold geometry. Geometric welding reveals remaining singularities. **It is not claimed fully watertight or print-ready.** Larger cloth/hair gaps, remaining pockmarks, blocky hair and the neck transition need further selective repair/sculpting. Normal maps preserve the current dense source's shading, including its residual imperfections. Visual acceptance remains open.

Useful established tools:

- [MeshLab](https://www.meshlab.net/): cleaning, reconstruction and simplification.
- [Open3D surface reconstruction](https://www.open3d.org/docs/release/tutorial/geometry/surface_reconstruction.html): Poisson reconstruction from consistently oriented surface samples. Not run for this candidate.
- [MeshFix](https://pymeshfix.pyvista.org/): digitized-mesh repair, with a single closed-solid assumption. PyMeshFix 0.18.1 was tested in the isolated TRELLIS environment and rejected for the whole object.
- [Blender baking](https://docs.blender.org/manual/en/5.4/render/cycles/baking.html): high-to-low map transfer.
- [Simplygon](https://documentation.simplygon.com/SimplygonSDK_10.2.10100.0/api/): integrated reduction, repair and material casting. Researched, not installed or run.

## Reproduce

From the agent worktree, use CherninLab3D's existing Python environments; model weights stay outside Git:

```sh
CL3D_PY=/Users/theochernin/Projects/CherninLab3D/.venv/bin/python
TRELLIS_PY=/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python
TASK=content/environments/gothic_statues_v1/trellis2_face_v1
$CL3D_PY "$TASK/generate_head.py"
$TRELLIS_PY content/environments/gothic_statues_v1/trellis2_statues_v1/finish_geometry.py "$TASK/head_512"
$CL3D_PY "$TASK/refine_geometry.py"
$CL3D_PY "$TASK/swap_head.py"
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python "$TASK/voxel_repair.py"
$CL3D_PY "$TASK/reduce_geometry.py" "$TASK/oracle_repaired_high.glb" "$TASK/oracle_150k.glb"
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python "$TASK/bake_asset.py" -- --high "$TASK/oracle_repaired_high.glb" --low "$TASK/oracle_150k.glb" --out "$TASK/baked_150k"
$CL3D_PY "$TASK/validate_asset.py"
```

The optional `meshfix_low.py` reproduces a **rejected** whole-object trial and is not a finishing stage. Required Godot import and smoke tests are recorded in the board task; they do not constitute art approval or dungeon placement.

## Verified in this trial

- Saved head registration reproduced exactly.
- Export validation checks finite geometry, indices, triangle count, UVs/tangents and both embedded images.
- Normal/AO maps are 4096² with spatial variation. The comparison GLB retains identical binary geometry.
- All three browser modes loaded; face/full cameras and download links were checked. The shortened cage and hemisphere filter removed black-triangle normal-bake artifacts.
- Godot headless import and the repository smoke suite passed; the final smoke marker was `PASS: local two-process ENet integration and disconnect cleanup`.
- Remaining geometry singularities are recorded in `validation.json`; none of these technical checks means final art acceptance.
