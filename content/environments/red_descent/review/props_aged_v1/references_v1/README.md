# T-171: movable dungeon props - image review

Ten isolated ImageGen references for approval. These are generated design images, not Godot screenshots or finished 3D assets. The user approved all ten references for CL3D generation; see `approval.json`. CL3D work is proceeding in the sibling `cl3d_v1` review and `procedural_props_aged_v1` output folders. These images remain unmodified.

The user explicitly requested image approval before CL3D work. All ten images are now approved for that next step; image approval does not establish the quality of a resulting mesh.

## Review images

Compare the silhouette, construction, wear and material direction. Each original is a separate single-object input candidate on an off-white background. Numbers are stable for feedback.

| 01 - Refectory table | 02 - Trestle bench |
| --- | --- |
| ![Refectory table](01-table.png) | ![Trestle bench](02-bench.png) |

| 03 - Empty timber shelf | 04 - Iron-hooped barrel |
| --- | --- |
| ![Empty timber shelf](03-shelf.png) | ![Iron-hooped barrel](04-barrel.png) |

| 05 - Open wooden coffin | 06 - Separate coffin lid |
| --- | --- |
| ![Open wooden coffin](05-coffin-body.png) | ![Separate coffin lid](06-coffin-lid.png) |

| 07 - Dry ossuary skull | 08 - Dry long bone |
| --- | --- |
| ![Dry ossuary skull](07-skull.png) | ![Dry long bone](08-femur.png) |

| 09 - Unglazed storage pot | 10 - Wax and iron candle tray |
| --- | --- |
| ![Unglazed storage pot](09-pot.png) | ![Wax and iron candle tray](10-candle-holder.png) |

## Later set proposals

After image approval, the selected source objects can feed four physics-dressed set families: a refectory corner (table, bench, barrel); a mortuary corner (coffin body and independently moving lid); an ossuary store (shelf, bones, pot); and a votive corner (candle tray and vessels). The T-171 target remains at least three variants per family, with a calm control and measured contacts and route clearances. No set has been generated or placed yet.

## Provenance and handoff

- Built-in ImageGen, one distinct call per asset, ten images in total. Every first output passed visual review; no image retries or post-generation image edits.
- Exact supplied prompts are saved beside each image as `.prompt.txt`; `prompts.json` indexes prompts, titles, families and approximate target dimensions. The dimensions are design targets, not measurements extracted from the images.
- `image-manifest.json` records SHA-256 hashes and pixel dimensions. Each `.receipt.json` records the native artifact identifier, original image hash and user approval status. Model version and seed are not exposed by the built-in tool.
- The references have not been altered, cropped or composited. Each standalone original remains suitable for its own review and possible later CL3D input.
- Coffin body and lid share an intended outline, but exact dimensional fit must be established in 3D. Furniture gaps, pot interiors, skull cavities and candle separations must be inspected in the resulting meshes after approval.
- Source frames read for style context were existing project art/runtime images; they were not edit targets and were not passed as conditioning images.
- No gameplay files, shared procedural toolkit, masonry, roots or rubble assets were changed.

## Verification

All ten PNG signatures, minimum dimensions, prompt identity and file hashes were checked. Each image was visually inspected for one complete object, legible structure, no extra props, no unwanted text and full framing. The candle tray is unlit and the open coffin is empty. Repository import and smoke results are recorded in `checks/` and `verification.json`.
