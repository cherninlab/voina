# Eight poses of Temptation and Remorse — T-188

Theo approved the source design on 2026-10-25: “this one is good but we need more positions.” Eight new individual pose references were generated with the native built-in image_gen tool, each directly referencing that attached image. Source approval is recorded in `approval.json`; the new variants are pending selection.

![Eight new poses](review/all-8.png)

| Pose | Position | Native PNG | Exact prompt |
|---|---|---|---|
| P01 | Advancing | [Original](references/P01-advancing.png) | [Prompt](prompts/P01-advancing.txt) |
| P02 | Seated | [Original](references/P02-seated.png) | [Prompt](prompts/P02-seated.txt) |
| P03 | Kneeling | [Original](references/P03-kneeling.png) | [Prompt](prompts/P03-kneeling.txt) |
| P04 | Turning | [Original](references/P04-turning.png) | [Prompt](prompts/P04-turning.txt) |
| P05 | Foot on Step | [Original](references/P05-step-rest.png) | [Prompt](prompts/P05-step-rest.txt) |
| P06 | Leaning | [Original](references/P06-leaning.png) | [Prompt](prompts/P06-leaning.txt) |
| P07 | Ground Seated | [Original](references/P07-ground-seated.png) | [Prompt](prompts/P07-ground-seated.txt) |
| P08 | Raised Mirror | [Original](references/P08-raised-mirror.png) | [Prompt](prompts/P08-raised-mirror.txt) |

Larger review pages: [P01–P04](review/P01-P04.png), [P05–P08](review/P05-P08.png).

The variations preserve the approved adult female classical statue design, pale aged marble, plain drapery, mirror and loose serpent/broken mask symbolism. The body pose and drapery folds change. These are individual concept images, not alternate camera renders of a single existing mesh.

The original attachment is preserved byte for byte at `source/approved-reference.png`. All eight final PNGs are unchanged native generated files. `manifest.json`, `SHA256SUMS`, `receipts/` and `prompts/` record exact input/output hashes, save locations and sent prompts. Review sheets arrange reduced previews only; use the original single-image PNGs as future reconstruction inputs.

Visual inspection found eight distinct body poses, full integral bases and visible mirrors, with no new extra figures or Gothic patterned decoration. All originals are distinct RGBA images with alpha and no solid silhouette touching the canvas border at alpha >64. These checks do not prove the hidden anatomy or later mesh quality. Thin fingers, mirror stems and unseen surfaces remain for the CL3D review stage.

This directory inherits the parent `.gdignore` and does not alter game import/export or gameplay. No CL3D conversion or dungeon placement has been performed. Select P01–P08 for the next image-to-3D phase.

Godot 4.7.2 headless editor import passed without errors or warnings. The required smoke suite passed, including two-process ENet integration and build-mismatch rejection; existing ObjectDB shutdown warnings remain. [Verification](review/verification.json), [import log](review/editor-import.txt), [smoke log](review/smoke-test.txt).
