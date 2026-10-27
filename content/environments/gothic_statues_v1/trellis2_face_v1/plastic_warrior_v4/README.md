# Supplied multicolored plastic warrior: TRELLIS.2 trial

T-198, 2026-10-27. The user rejected the two generated plastic oracle images as still too ambiguous and supplied this simpler faceted warrior instead.

## Input and provenance

[source.png](source.png) is an unchanged copy of the user's supplied `codex-clipboard-aa5c6ed2-44b1-432e-bbe1-1cd779dd1792.png`: 687 × 1024 RGB, already on a black background. The source copy has no ImageGen reinterpretation, recoloring or anatomical edits. The reconstruction conditioning input uses the installed U2Net foreground segmentation. Provenance is user-supplied reference; this trial does not place the reference or derived model in game scenes.

The pipeline segments the foreground using its installed U2Net model, crops to the foreground bounds, adds black square margins and resizes to the standard 512² DINO conditioning image; [conditioning.png](conditioning.png) is retained. Geometry uses the 768 grid, not the input encoder dimensions.

## Reconstruction

- Existing Microsoft TRELLIS.2-4B model and official DINOv3 encoder, native MLX port.
- 24 sampling steps per stage, seed 42, 32768-token cap. A separate 512-grid trial uses the same segmented conditioning input and seed.
- The same 42 GiB MLX guideline used successfully for the prior Oracle 768 trial; not a measured memory-peak claim.
- [Generation script](generate.py) and [exact run/revision receipt](result.json).
- [Raw native GLB](raw.glb), [normalized raw preview](preview.glb), and [surface-cleaned GLB](clean_high.glb).
- Cleanup reuses `../../trellis2_statues_v1/finish_geometry.py`; it removes negligible debris, splits non-manifold edges and repairs confident exterior winding. It does not fill holes, remesh or decimate.
- The model stage stops after raw mesh. Review material is constant neutral stone. Input colors are not a generated texture.

## Rejected preprocessing attempt

The first RGB conditioning pass bypassed semantic segmentation and produced a backing slab. It is rejected; [receipts and the actual mesh render](rejected_backing_slab/README.md) are retained separately. The segmented rerun removes that slab, as shown in the raw mesh renders.

## Review and limits

[Rotatable review](review/index.html) includes source comparison, raw/cleanup selection, face/crown/back camera presets and actual exported-mesh renders.

Small-hole repair uses installed PyMeshLab to close boundary loops of at most 16 edges, with self-intersection checks and no refinement. All existing vertices are exactly unchanged and all existing triangles are retained; the pass only adds triangles. The original dense exports remain available for comparison.

| Trial | Original triangles | After small-hole filling | Boundary edges before / after |
| --- | ---: | ---: | ---: |
| 768 grid | 2,225,108 | 2,295,552 | 148,334 / 41,020 |
| 512 grid | 1,019,108 | 1,059,244 | 92,846 / 31,884 |

The 768 version better retains the supplied faceted face; 512 is visibly softer. Small-hole filling removes many pinholes but leaves some larger openings, cracks, surface bumps and uneven hair. Neither output is watertight or fully winding-consistent. These are review candidates.

No face substitution, crown patch, normal baking, PBR generation or dungeon integration has been applied. Geometry and visual acceptance remain separate. This is a fresh reconstruction from a different image and a different subject, not a controlled color-only comparison with the previous Oracle.

[768 repair measurements](pinholes.json) · [512 repair measurements](comparison_512/pinholes.json) · [validation](validation.json).

## Reproduce

From the repository root:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/generate.py
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python content/environments/gothic_statues_v1/trellis2_statues_v1/finish_geometry.py content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/fill_pinholes.py content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 4 --python-exit-code 1 --python content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/render_review.py -- --mesh content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/clean_high.glb --out content/environments/gothic_statues_v1/trellis2_face_v1/plastic_warrior_v4/review --prefix clean --size 800
```
