# Crown and surrounding-hair cleanup

The user approved the v1 face, then requested cleanup around the head and closure of the large hole in the crown. This version retains the approved facial features and body, repairs the scalp beneath the hair, and replaces the damaged surrounding head surface.

## Deliverables

- `statue.glb`: **185,279 triangles**, two materials. The retained source primitive still uses its original 4K normal/AO maps. The new head-surround primitive uses separate **2K normal/AO maps**. No face-generation model was rerun.
- `patch_baked/normal.png`, `ao.png`: new OpenGL tangent normal and AO maps for the repaired hair/scalp. `patch_baked/bake.json` records the bake.
- `surround_patch_high.glb`: dense local repair source for rebaking.
- `review/index.html`: before/after mesh selector and crown/face/back/full views.
- `review/before/`, `review/after/`: actual geometry renders at matching camera settings.
- `validation.json`: geometry/image preservation checks and physical crown coverage.

## Repair

`clean_surround.py` extracts only the upper head and horn area from the existing reduced model. Blender repairs the thin broken sheets, adds a fitted cranial surface with swept S-shaped hair relief beneath the hair, closes the asymmetric frontal join, and unites/smooths the local geometry with OpenVDB. The altered hairline is above Y=1.252 m in this asset's coordinates; the facial features below it are protected.

`compose.py` retains original face/body vertex, normal, UV, tangent and embedded-image buffers **byte-for-byte**. It removes only the selected old head-surround triangles, and appends the local replacement as another primitive. A rasterized facial depth buffer keeps that replacement behind the approved facial skin. The damaged hairline and temple boundary are trimmed, while the protected facial triangles remain at their exact original positions with the same material data.

The local repair is reduced to roughly 60k triangles using the existing MeshLab quadric reduction, then receives a separate Blender normal/AO bake. This increases total triangles from 147,628 to 185,279 while remaining about 93.4% below the initial 2,805,322-triangle reconstruction. It is a triangle-count comparison, not a measured frame-rate result.

## Checks

- The entire original binary vertex/image payload is preserved as an exact prefix of the new GLB; the original materials and attribute accessors are unchanged.
- All selected protected-face triangles remain unchanged. The source body below the head-repair region remains unchanged.
- 202 front-facing probes of the facial features have **zero depth change**.
- All **253 probes** over the crown and frontal join hit the reconstructed crown above Y=1.24 m. The previous model had 139 low/missing samples in the same area.
- Matching face, crown, top, back, profile and full-body renders are retained for inspection. Small pits and unevenness remain in the generated stone/horn surfaces; this pass does not claim to remove every imperfection in the statue.

## Reproduce

From the worktree root, with the existing CherninLab3D Python environments:

```sh
PY=/Users/theochernin/Projects/CherninLab3D/.venv/bin/python
TASK=content/environments/gothic_statues_v1/trellis2_face_v1
PATCH=$TASK/head_cleanup_v2
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER --background --factory-startup --python-exit-code 1 --python "$PATCH/clean_surround.py"
$PY "$PATCH/compose.py"
$PY "$TASK/reduce_geometry.py" "$PATCH/surround_patch_high.glb" "$PATCH/surround_60k.glb" --triangles 60000
$BLENDER --background --factory-startup --python-exit-code 1 --python "$TASK/bake_asset.py" -- --high "$PATCH/surround_patch_high.glb" --low "$PATCH/surround_60k.glb" --out "$PATCH/patch_baked" --size 2048
$PY "$PATCH/compose.py" "$PATCH/patch_baked/statue.glb" --prepared
$BLENDER --background --factory-startup --python-exit-code 1 --python "$PATCH/validate.py"
```

The previous approved asset remains at `../baked_150k/statue.glb`. This is a local asset-library update; dungeon placement and game-camera visual acceptance are separate.

Godot headless import and the repository smoke suite passed after this repair. Both browser comparison modes and the face/crown views were inspected. These checks validate this asset-library repair, not dungeon placement or game-camera acceptance.
