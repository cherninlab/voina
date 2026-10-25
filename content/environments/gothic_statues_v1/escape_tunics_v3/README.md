# Marble escape statue studies

T-190: five new original image concepts, generated with built-in ImageGen on 2026-10-25. Separate compositions for user selection before CL3D. No added pedestals. Short lightweight tunics were requested; E05 and E06 have heavier/longer drapery than intended.

| ID | Composition | Native image | Prompt and receipt |
| --- | --- | --- | --- |
| E01 | Crawling reach | [PNG](E01_crawling_reach.png) | [JSON](E01_crawling_reach.json) |
| E02 | Dragging escape | [PNG](E02_dragging_escape.png) | [JSON](E02_dragging_escape.json) |
| E03 | Reclining defiance | No output: ImageGen moderation blocked | [JSON](E03_reclining_defiance.json) |
| E04 | Fallen reaching | [PNG](E04_fallen_reaching.png) | [JSON](E04_fallen_reaching.json) |
| E05 | Kneeling ascent | [PNG](E05_kneeling_ascent.png) | [JSON](E05_kneeling_ascent.json) |
| E06 | Turning away | [PNG](E06_turning_away.png) | [JSON](E06_turning_away.json) |

## Provenance and review

All five PNGs are unchanged native ImageGen outputs. No external artwork was downloaded or used as an image input. Classical Roman/Renaissance sculpture was verbal style direction. Each sibling JSON records its exact prompt, native source/result metadata and visual inspection. The manifest records dimensions, real alpha extrema and file hashes.

The images are concepts, not production cutouts. E01/E04/E05 contain soft background halos; E02/E06 contain edge artifacts, especially E06. Margins are tighter than requested. Alpha cleanup and improved margins are required after selection and before CL3D. Inspect limb/finger geometry separately during reconstruction. Preserve these native files and create cleanup derivatives only after selection.

E03 was blocked by the image tool. Its failure receipt is preserved; no image is fabricated and the blocked prompt was not retried. Five of six planned compositions returned images. No meshes, material maps or game placement were created in this pass.

## Repository checks

Godot 4.7.2 headless editor import completed without reported errors. The broader smoke suite exited 1 at the projectile smoke check: `Exactly one host-confirmed bolt must hit (is cover parked between the spawns?)`. No gameplay or test files were changed in this image-only task; no full smoke pass is claimed. See [checks.json](checks.json). Three generated stone-kind review import sidecars outside this scope were left uncommitted.
