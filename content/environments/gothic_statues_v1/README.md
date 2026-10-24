# Occult cathedral sculpture concepts — T-187

Eighteen separate native ImageGen references, numbered 01–18. Current direction: classical Greek/Renaissance anatomy and drapery, occult subjects, a restrained Bosch influence, three caprine sculptures. No Gothic ornamental patterns were requested in the revised direction.

These are concept images for approval. No CL3D generation or dungeon placement has been performed. Numbers in this review refer only to the current revision.

![All eighteen current candidates](review/all-18.png)

| No. | Sculpture | Family | Original | Exact prompt |
|---|---|---|---|---|
| 01 | Veiled Oracle | human | [PNG](references/01-veiled-oracle.png) | [Prompt](prompts/01-veiled-oracle.txt) |
| 02 | Bound Titan | human | [PNG](references/02-bound-titan.png) | [Prompt](prompts/02-bound-titan.txt) |
| 03 | Kneeling Mourner | human | [PNG](references/03-kneeling-mourner.png) | [Prompt](prompts/03-kneeling-mourner.txt) |
| 04 | Blind Seer | human | [PNG](references/04-blind-seer.png) | [Prompt](prompts/04-blind-seer.txt) |
| 05 | Sorrowing Angel | human | [PNG](references/05-sorrowing-angel.png) | [Prompt](prompts/05-sorrowing-angel.txt) |
| 06 | Vessel Bearer | human | [PNG](references/06-vessel-bearer.png) | [Prompt](prompts/06-vessel-bearer.txt) |
| 07 | Chained Philosopher | human | [PNG](references/07-chained-philosopher.png) | [Prompt](prompts/07-chained-philosopher.txt) |
| 08 | Silent Sibyl | human | [PNG](references/08-silent-sibyl.png) | [Prompt](prompts/08-silent-sibyl.txt) |
| 09 | Vessel-Headed Pilgrim | bosch | [PNG](references/09-vessel-headed-pilgrim.png) | [Prompt](prompts/09-vessel-headed-pilgrim.txt) |
| 10 | Bird-Masked Confessor | bosch | [PNG](references/10-bird-masked-confessor.png) | [Prompt](prompts/10-bird-masked-confessor.txt) |
| 11 | Owl Judge | bosch | [PNG](references/11-owl-judge.png) | [Prompt](prompts/11-owl-judge.txt) |
| 12 | Double-Faced Listener | bosch | [PNG](references/12-double-faced-listener.png) | [Prompt](prompts/12-double-faced-listener.txt) |
| 13 | Goat Philosopher | goat | [PNG](references/13-goat-philosopher.png) | [Prompt](prompts/13-goat-philosopher.txt) |
| 14 | Ram Offerer | goat | [PNG](references/14-ram-offerer.png) | [Prompt](prompts/14-ram-offerer.txt) |
| 15 | Sleeping Caprine | goat | [PNG](references/15-sleeping-caprine.png) | [Prompt](prompts/15-sleeping-caprine.txt) |
| 16 | Headless Martyr | human | [PNG](references/16-headless-martyr.png) | [Prompt](prompts/16-headless-martyr.txt) |
| 17 | Burdened Caryatid | human | [PNG](references/17-burdened-caryatid.png) | [Prompt](prompts/17-burdened-caryatid.txt) |
| 18 | Twinned Penitents | human | [PNG](references/18-twinned-penitents.png) | [Prompt](prompts/18-twinned-penitents.txt) |

## Larger reviews

![01–06](review/01-06.png)

![07–12](review/07-12.png)

![13–18](review/13-18.png)

## Files and approval

`references/` contains the unmodified native RGBA PNGs. `manifest.json` records hashes, dimensions, alpha checks and pending approval for every candidate. `prompts/` and `prompts.json` contain exact sent prompts; `receipts/` preserves the native save locations. Review sheets only arrange reduced previews; they are not generation inputs.

The artist-specified heights in prompts are design intentions, not measured 3D dimensions. Alpha and subject silhouette will need conditioning and mesh review after approval. Fine fingers, wings, double faces, vessel openings and rear surfaces remain reconstruction risks to inspect in the later 3D stage. The images are not texture maps or engine captures.

Six earlier goat studies with architectural ornament are retained under `superseded_tracery_v1/` as history. They are excluded from this numbered selection. The root `.gdignore` keeps this image-only library out of game imports and exports.

Built-in image_gen was used throughout. All current originals are byte-identical to their native generated files. Approval of selected images will authorize the next CL3D phase; it does not establish final mesh or in-game acceptance.

Godot 4.7.2 headless editor import passed without errors or warnings. The required repository smoke test passed, including local two-process ENet integration and expected build-mismatch rejection. Existing ObjectDB shutdown leak warnings remain in the smoke log. These regression checks do not validate statues in-game because this is an image-only pack. Logs and file audit: `review/verification.json`.
