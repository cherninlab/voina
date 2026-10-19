# Haunted forest (T-092)

Original SECHA shaders and procedural geometry for the forest along the north trail to the church, written for this project by theo-claude-12 on 2026-10-19. Used by `gameplay/environment/haunted_forest.gd`; see `docs/haunted-forest.md`.

References: two user-supplied mood images (a misty dead swamp forest and a dark forest understorey with light shafts) plus two church/graveyard mood images, shared in chat only. They are inspiration, not shipped, and no pixels were copied.

## Shaders here (all original)

| File | Use |
| --- | --- |
| `dead_bark.gdshader` | dead trees, logs, stumps, spruce trunks: reused LogBark maps pulled to cold grey, moss on top faces and around the base |
| `hanging_moss.gdshader` | beard moss ribbons frayed into strings by discard; slight sway |
| `spruce_needles.gdshader` | opaque near-black spruce fronds |
| `dry_grass.gdshader` | reeds, dead grass tufts, and the village trail-shoulder grass beyond the palisade |
| `mossy_rock.gdshader` | boulders: triplanar schist with moss |
| `bog_water.gdshader` | terrain-hugging bog patches: wet mud and still black water, opaque with discarded edges, fresnel fog-sky sheen |
| `light_shaft.gdshader` | additive, depth-faded, camera-facing god-ray cards |
| `ground_mist.gdshader` | soft, depth-faded, camera-facing low mist cards |

## Reused textures (no new external assets)

- `content/environments/valhalla/textures/KB3D_VHL_LogBark_basecolor.png`, `_normal.png`, `_roughness.png`: KitBash3D Valhalla, user-authorized; provenance in `content/environments/valhalla/provenance.json`.
- `content/environments/village_generated/schist_rock.png`: original generated schist albedo; provenance in `content/environments/village_generated/provenance.json`.

All tree, spruce, reed, log, stump, rock, pool, shaft and mist geometry is generated at runtime from code. Nothing is imported.
