# Oracle multicolored plastic source study

T-198, 2026-10-27. The user rejected the patched result and identified source-image ambiguity. This iteration returns to source-image quality before another mesh reconstruction.

## Deliverables

- [Source comparison](index.html)
- [Original marble reference](original_oracle.png)
- [A: material color study](oracle_plastic_a.png)
- [B: clearer construction](oracle_plastic_b.png), cleaner study, subsequently rejected
- [Exact prompts](prompts.json), built-in ImageGen
- [Image receipts](images.json)

A separates body, hair, horns, drapery and clasps by color. B also reduces six horns to four and untangles hair into larger swept locks. Both remain classical human sculptures with substantial drapery and no pedestal.

## State and next step

Both generated studies were rejected by the user for remaining artifacts. No TRELLIS.2 run, polygon reduction, maps, or game integration was performed from these images. The user instead supplied a simpler image for the separate [plastic warrior trial](../plastic_warrior_v4/README.md).

B was not selected for reconstruction. Color separation is a hypothesis for reducing visual ambiguity; improvement in generated geometry has not yet been measured. A closed-looking painted crown does not prove a closed 3D surface.

Plastic colors are conditioning/reference colors. A final marble material can be applied after an acceptable geometry result.

## Provenance

Original source copied unchanged from `../../trellis2_statues_v1/source/oracle.png`, the earlier ImageGen S06 Horned Oracle. A is a built-in ImageGen reference edit of that original. B is a built-in ImageGen reference edit of A. Exact prompts are retained. No external artist asset or new downloadable model was introduced.

Both output PNGs were copied unchanged from Codex generated images. RGBA is preserved, including the generated edge alpha. Their RGB buffers contain background colors in fully transparent pixels, so consumers must respect alpha before image encoding. No Python image editing, recoloring or matting was applied.
