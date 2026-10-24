# Stone and brick material library v1 — T-183

Nine face-material candidates inspired by Theo's three supplied north-star dungeon images. Each has five matching files: **albedo, OpenGL tangent normal, roughness, 16-bit height, AO** (45 maps total), at native 1254 x 1254 resolution. All are available for material trials now; human visual approval is pending. The additional CL3D rubble batch is tracked separately as T-167 in `../cl3d_rubble_sources_v1/`.

T-182 (theo-claude-45) owns the six geometry kinds; T-177 owns masonry integration. This library complements their work and the three base procedural materials from T-180. The textures contain the **face of a material**, not a wall bond or block outlines: geometry supplies unit shapes, joints and silhouettes.

## Choose by number

Compare the raw albedo and normal images in [REVIEW.md](REVIEW.md). These are the same numbered candidates 01–09; approve all, select a subset, or describe changes. Approval of appearance does not imply room integration acceptance.

| Material | One repeat | Height range | Download/open maps |
| --- | --- | --- | --- |
| 01 Chisel-worn grey limestone | 1.8 m | 5.0 mm | [Albedo](materials/01-chisel-limestone/albedo.png) · [Normal](materials/01-chisel-limestone/normal_gl.png) · [Roughness](materials/01-chisel-limestone/roughness.png) · [Height](materials/01-chisel-limestone/height.png) · [AO](materials/01-chisel-limestone/ao.png) |
| 02 Split bedded stone | 1.8 m | 6.0 mm | [Albedo](materials/02-split-bedded-stone/albedo.png) · [Normal](materials/02-split-bedded-stone/normal_gl.png) · [Roughness](materials/02-split-bedded-stone/roughness.png) · [Height](materials/02-split-bedded-stone/height.png) · [AO](materials/02-split-bedded-stone/ao.png) |
| 03 Coarse dressed plinth stone | 1.8 m | 5.0 mm | [Albedo](materials/03-drafted-quoin-stone/albedo.png) · [Normal](materials/03-drafted-quoin-stone/normal_gl.png) · [Roughness](materials/03-drafted-quoin-stone/roughness.png) · [Height](materials/03-drafted-quoin-stone/height.png) · [AO](materials/03-drafted-quoin-stone/ao.png) |
| 04 Old terracotta brick face | 0.9 m | 2.5 mm | [Albedo](materials/04-old-terracotta-brick/albedo.png) · [Normal](materials/04-old-terracotta-brick/normal_gl.png) · [Roughness](materials/04-old-terracotta-brick/roughness.png) · [Height](materials/04-old-terracotta-brick/height.png) · [AO](materials/04-old-terracotta-brick/ao.png) |
| 05 Smoke-darkened brick face | 0.9 m | 2.0 mm | [Albedo](materials/05-smoke-darkened-brick/albedo.png) · [Normal](materials/05-smoke-darkened-brick/normal_gl.png) · [Roughness](materials/05-smoke-darkened-brick/roughness.png) · [Height](materials/05-smoke-darkened-brick/height.png) · [AO](materials/05-smoke-darkened-brick/ao.png) |
| 06 Eroded limewashed brick face | 0.9 m | 1.5 mm | [Albedo](materials/06-limewashed-brick/albedo.png) · [Normal](materials/06-limewashed-brick/normal_gl.png) · [Roughness](materials/06-limewashed-brick/roughness.png) · [Height](materials/06-limewashed-brick/height.png) · [AO](materials/06-limewashed-brick/ao.png) |
| 07 Foot-worn floor limestone | 1.8 m | 1.8 mm | [Albedo](materials/07-worn-floor-limestone/albedo.png) · [Normal](materials/07-worn-floor-limestone/normal_gl.png) · [Roughness](materials/07-worn-floor-limestone/roughness.png) · [Height](materials/07-worn-floor-limestone/height.png) · [AO](materials/07-worn-floor-limestone/ao.png) |
| 08 Salt-weathered crypt limestone | 1.8 m | 5.0 mm | [Albedo](materials/08-salt-weathered-limestone/albedo.png) · [Normal](materials/08-salt-weathered-limestone/normal_gl.png) · [Roughness](materials/08-salt-weathered-limestone/roughness.png) · [Height](materials/08-salt-weathered-limestone/height.png) · [AO](materials/08-salt-weathered-limestone/ao.png) |
| 09 Fine tooled vault sandstone | 1.8 m | 3.0 mm | [Albedo](materials/09-fine-tooled-sandstone/albedo.png) · [Normal](materials/09-fine-tooled-sandstone/normal_gl.png) · [Roughness](materials/09-fine-tooled-sandstone/roughness.png) · [Height](materials/09-fine-tooled-sandstone/height.png) · [AO](materials/09-fine-tooled-sandstone/ao.png) |

01/03 suit ashlar, piers, quoins and plinths. 02 suits thin coursed slabs and rubble. 04–06 offer three fired-clay finishes for brick-sized vault units. 07 is a worn floor face. 08 is a mineral/salt-weathered crypt face. 09 is fine tooled sandstone for smaller arch/vault units. Use these as restrained related variations, then inspect the actual placed stones.

## Use the corrected material resources

Theo rejected the initial visible tile repetition. Each folder now includes a ready-to-use `surface.tres` pointing to `stone_brick_stochastic.gdshader`. Use that resource to get the correction; loading the five PNGs into the old regular sampler retains the repetition. The production T-177 shader is unchanged. Example:

```gdscript
var stone: ShaderMaterial = load("res://content/environments/stone_brick_materials_v1/materials/01-chisel-limestone/surface.tres").duplicate() as ShaderMaterial
stone.set_shader_parameter("wetness", 0.3)
# Set mapped=true only when the receiving mesh has metre-space UVs/tangents.
# CL3D sources can use the default world projection.
```

- **Density** is `1 / tile_m`: 0.55556 for stone, 1.11111 for brick. `materials.json` records the exact values, height range and suggested relief for each.
- **Normal convention:** tangent-space OpenGL, green up; `normal_gl.png` is linear data, never sRGB. Godot imports explicitly enable normal-map mode and mipmaps without flipping green. Normals are calculated from the exact delivered quantised height field using T-180's wrapped central-difference normal encoder.
- **Height:** 16-bit linear PNG, black low/white high. The full range is 1.5–6 mm depending on material, listed above. The `relief_m` values in `materials.json` use metres. Geometry still supplies large chips and unit outlines.
- **Roughness:** linear grayscale, black smooth/white rough. The production dungeon shader remaps this input into its dry range (0.65–0.98 by default) and handles wetness separately; these are material variation inputs, not wet highlights painted into albedo.
- **AO:** linear grayscale, white unoccluded. It comes from a wrapped 16-direction horizon search on the same height field; let the existing shader consume it rather than multiplying it into the albedo again.
- All surfaces are non-metallic; no metallic map is needed. The candidate shader copies the recorded production shader interface and adds coherent triangular stochastic phase sampling. Albedo, normal, roughness, height and AO always share offsets and weights. It does not rotate UVs, so sediment bedding and normal axes remain consistent. `anti_tile=false` provides a direct regular-tiling control. This costs three texture reads per sampled map; scene-scale Mobile performance remains for the integration owner to measure.

## What was generated and what was computed

1. Built-in ImageGen created nine original face studies; `studies/` retains exact output bytes and receipts. The exact prompts are in `prompts/<id>.txt` and the [image manifest](image-manifest.json).
2. Built-in ImageGen edited each study into a separate grayscale relief interpretation, preserving its broad pits/tooling/framing while suppressing pigment. The unchanged outputs and exact edit prompts are in `height_inputs/` and `prompts/<id>-height.txt`.
3. `build_maps.py`, run in Blender 5.2.2, performs deterministic map encoding. It removes the smooth field responsible for opposite-edge discontinuity, keeps the mean, smooths the relief estimate at subpixel scale and quantises it to the delivered 16-bit height. The normal and AO encoding reuse `scripts/art/build_stone_surface.py`. Roughness follows restrained per-material defaults plus cavities/wear in the same height field. The original generated albedo/height images are never overwritten.
4. The output `materials/<id>/albedo.png` is the mechanically conditioned repeat tile, rather than a byte-identical original. Mean absolute albedo adjustment is about 0.006–0.012 on a 0–1 scale. All source/output hashes and dimensions are recorded.

**Limits:** the ImageGen height input is an artistic estimate, not measured relief. Some shaded-edge cues remain and fine grain can differ from the albedo, so use restrained strength and inspect the actual assets. Periodic correction reduces edge jumps but does not remove recognizable repetition on large uninterrupted planes. It makes wrap steps smoother than typical interior detail; the absolute seam-z scores in `materials.json` reflect that, while `wrap_step_max_ratio_to_interior_mean` gives the discontinuity check. These are review candidates, not scan-certified physical materials.

## Repetition correction

The rejected regular grid and the corrected stochastic material are compared in `review/stochastic/<id>-repeat.png` and `<id>-varied.png`. The same camera, lighting, maps and shader are used; only `anti_tile` changes. At a one-source-tile shift, luminance correlation fell from 0.76–0.94 to -0.041–0.058 across the nine materials (both axes). This measures the removal of the regular stamp pattern; it does not substitute for human acceptance.

`stone_brick_stochastic.gdshader` is a scoped candidate for the masonry owner, with the base source hash in `shader-provenance.json`. No active T-177 shader file was edited. All five maps remain available as editable source textures; the `.tres` preset is the corrected runtime sampling. The implementation uses explicit texture gradients for stable mip selection, following the [Godot shader function contract](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html#texturegrad).

## Actual engine review and verification

[Native Godot dry/normal overview](review/godot/all-materials-normal.png), [wet overview](review/godot/all-materials-wet.png), [normal-disabled control](review/godot/all-materials-flat.png). Each tile shows three by three texture repeats on a temporary flat review panel, using the original production shader in the first pass; corrected repeated/varied controls use the scoped stochastic candidate under a raking warm key and cool ambient fill. These are real Godot Mobile/Metal captures; labels identify each material. Full individual 960 x 960 captures are in `review/godot/`.

`review/map-audit.json` records:

- All 45 PNG hashes, bit depths, finite values and dimensions checked; all nine original albedo hashes preserved.
- Encoded normals agree with the slopes of the delivered 16-bit height to within one 8-bit quantisation step; blue remains positive. Maximum decoded normal-length error is below 0.0064 before shader renormalisation.
- All map wrap jumps are at most 0.974 times the average interior step; no hard seam was seen in the 3 x 3 native capture review. Some repetition remains visible.
- Nine normal-enabled controls and nine wetness controls measurably change the same central pixel area, with camera/light/material source held fixed.
- Godot 4.7.2 editor import, native shader rendering (45 imported maps, 27 captures), and the repository local ENet smoke passed. Logs are under `review/`. Existing ObjectDB cleanup warnings remain documented.

This task does not place materials in the dungeon or establish final in-dungeon human acceptance.

## Reproduce / provenance

```sh
blender --factory-startup -b --python-exit-code 1 --python content/environments/stone_brick_materials_v1/build_maps.py
"$GODOT" --headless --editor --path . --quit
GODOT="$GODOT" scripts/godot_bg.sh --path . --resolution 960x960 --script res://content/environments/stone_brick_materials_v1/preview_maps.gd
python3 scripts/smoke_test.py "$GODOT"
```

Godot-generated import settings and the preview script UID are committed. `build_maps.py` has runnable periodic-field and normal-polarity self-checks. It imports the shared T-180 bake functions without modifying them. Source prompts, source hashes, map hashes and controls are retained. `references/` contains the three user-provided inspiration images and provenance, excluded from engine import; they are not runtime textures or a claim of an external asset licence. Generated material pixels are AI-assisted, not CC0-by-construction procedural scans. Follow project release provenance policy when packaging.
