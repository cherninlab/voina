# Occult cathedral sculpture concepts — T-187

Twenty-seven numbered individual image concepts, plus one alternate edit. All use native built-in ImageGen. Current direction: Greek/Renaissance anatomy and plain drapery, occult subjects and restrained Bosch influence, with only three caprine figures. Human visual approval is pending. No CL3D generation or dungeon placement has been performed.

![All 27 numbered concepts](review/all-27.png)

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
| 19 | The Condemned | hell | [PNG](references/19-the-condemned.png) | [Prompt](prompts/19-the-condemned.txt) |
| 20 | Dragged Below | hell | [PNG](references/20-dragged-below.png) | [Prompt](prompts/20-dragged-below.txt) |
| 21 | The Entombed | hell | [PNG](references/21-the-entombed.png) | [Prompt](prompts/21-the-entombed.txt) |
| 22 | The Entangled | hell | [PNG](references/22-the-entangled.png) | [Prompt](prompts/22-the-entangled.txt) |
| 23 | Ash Crawler | hell | [PNG](references/23-ash-crawler.png) | [Prompt](prompts/23-ash-crawler.txt) |
| 24 | The Unheard | hell | [PNG](references/24-the-unheard.png) | [Prompt](prompts/24-the-unheard.txt) |
| 25 | Burning Penitent | hell | [PNG](references/25-burning-penitent.png) | [Prompt](prompts/25-burning-penitent.txt) |
| 26 | Pillar of the Damned | hell | [PNG](references/26-pillar-of-damned.png) | [Prompt](prompts/26-pillar-of-damned.txt) |
| 27 | Temptation and Remorse | allegory | [PNG](references/27-temptation-and-remorse.png) | [Prompt](prompts/27-temptation-and-remorse.txt) |

## People in hell: 19–26

![Eight human damnation sculptures](review/19-26-people-in-hell.png)

Larger reviews: [19–22](review/19-22.png), [23–26](review/23-26.png).

## Temptation and Remorse: 27

A separate non-explicit classical allegory uses the mirror, serpent and broken mask to convey temptation, vanity and remorse.

![27 Temptation and Remorse](references/27-temptation-and-remorse.png)

## Earlier 01–18 references

![01–06](review/01-06.png)

![07–12](review/07-12.png)

![13–18](review/13-18.png)

## Alternate and provenance

[20 alternate edit](references/20-dragged-below-v2.png) refines the adult figure and drapery; the original remains the numbered 20 reference. [Exact edit prompt](prompts/20-dragged-below-v2.txt), input hash and receipt are retained.

`references/` holds 27 current original PNGs and one alternate, all byte-identical to their native generated files. `manifest.json` records hashes, dimensions, alpha checks and pending approval. `prompts/`, `prompts.json` and `receipts/` preserve exact generation instructions and output locations. Review sheets arrange reduced previews only; they are not CL3D inputs.

Six earlier goat studies with architectural ornament remain under `superseded_tracery_v1/`, excluded from the current selection. The root `.gdignore` keeps this whole image-only library out of Godot imports and exports.

Prompt heights are design intentions, not measured 3D sizes. Fingers, faces, negative spaces, flame curls, multiple figures, wings and unseen rear faces need later reconstruction review. These are concept images, not texture maps, meshes or engine captures. Image approval precedes CL3D and does not establish final 3D or in-game acceptance.

All 27 current candidates and the alternate pass native-byte and PNG checks; current assets are distinct RGBA images with transparency. Godot 4.7.2 headless editor import and the required smoke test passed on the initial image-only pack, including local two-process ENet integration and expected build-mismatch rejection. Existing ObjectDB shutdown warnings remain in the smoke log. The added images stay under the same `.gdignore`; no engine files changed. Audit: [verification](review/verification.json), [import log](review/editor-import.txt), [smoke log](review/smoke-test.txt).
