# Supplied plastic oracle: TRELLIS.2 trial

T-198, 2026-10-27. Reconstruct the user's exact next reference, preserving prior trials separately.

## Input and provenance

[source.png](source.png) is an unchanged copy of user-supplied `codex-clipboard-25e9029b-9dfd-469e-8e14-5417a86fc5b2.png`, 687 × 1024 RGB. User-supplied reference provenance; this trial does not place the model in game scenes.

The source is not reinterpreted by ImageGen. Reconstruction preprocessing uses the installed U2Net foreground segmentation, foreground crop, 15% black margin, and standard 512² DINO conditioning. [Exact preprocessing receipt](preprocess.json), [conditioning image](conditioning.png).

## Reconstruction and review

- Existing Microsoft TRELLIS.2-4B and official DINOv3 encoder, native MLX port. Exact revisions and command are in [result.json](result.json).
- 768 geometry grid, 24 sampling steps, seed 42, 32768-token cap.
- 42 GiB MLX allocation guideline, not a measured memory-peak claim.
- Reuses the [previous generation runner](../plastic_warrior_v4/generate.py), now with an optional image path. Its previous default input is unchanged.
- Raw dense geometry, surface cleanup, and small-hole filling are retained separately.
- The [rotatable review](review/index.html) compares before and after small-hole filling with actual mesh close-ups of the face, crown, back, hands and legs.
- Neutral material exposes geometry. The reference colors are conditioning colors; this run stops after the raw mesh stage and does not generate PBR textures.

Small-hole filling reuses [the tested MeshLab pass](../plastic_warrior_v4/fill_pinholes.py): boundary loops of at most 16 edges, self-intersection checks, no refinement, and exact preservation checks for all existing vertices and triangles. Actual repair counts and remaining topology are in [pinholes.json](pinholes.json). Visual quality remains subject to review.

## Reproduce

From the repository root:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/generate.py --image content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5/source.png --out content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python content/environments/gothic_statues_v1/trellis2_statues_v1/finish_geometry.py content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/fill_pinholes.py content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 4 --python-exit-code 1 --python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5/render_review.py -- --mesh content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5/pinholes_filled.glb --out content/environments/gothic_statues_v1/trellis2_face_v1/plastic_oracle_v5/filled_review --prefix clean --size 800
```

## Observed quality

The silhouette, bent-leg pose and raised-arm composition survive. The reconstructed eyes, mouth and raised fingers remain visibly broken. Larger cracks and surface bumps persist in the hair, dress and body after small-hole filling. This trial falls below the art quality target.

The cleaned mesh contains 2,624,104 triangles; small-loop filling adds 161,909 triangles for 2,786,013 total. Boundary edges decrease from 500,290 to 253,289. Original vertices and triangles are retained. The result remains non-watertight and winding-inconsistent. No face replacement, anatomy substitution, remeshing, reduction, normal-map baking or game placement was applied.

Godot headless editor import and full smoke passed. [Export checks](validation.json) confirm structural export validity; they do not approve the art.
