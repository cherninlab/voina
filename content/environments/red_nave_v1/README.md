# Red nave material pack v1

Generated from the selected red-plaster nave concept with built-in ImageGen.
Six separate surface families keep the plaster fields, structural stone, floor,
timber and iron visually distinct. This is a material library, not an updated
gameplay-level render.

## Contents

| Folder | Surface | Starting tile width |
| --- | --- | --- |
| `red_lime_plaster` | Matte iron-oxide lime plaster, fissures and sparse spalls | 2.5 m |
| `rubble_masonry` | Dark structural rubble with recessed mortar | 2.5 m |
| `pale_limestone` | Continuous pale stone for individual arch blocks and exposed substrate | 1 m |
| `broken_stone_floor` | Broad worn slabs with grit-filled joints | 3 m |
| `aged_oak` | Dark hand-hewn beams; grain follows texture V | 2.5 m |
| `oxidized_iron` | Forged torch hardware, oxide/rust and sparse worn metal | 0.5 m |

Each family contains `albedo.png`, `normal_gl.png`, `roughness.png`, `height.png`,
`ao.png` and a Godot `material.tres`. Iron additionally has `metallic.png`.
`masks/plaster_peel.png` and `masks/damp_grime.png` provide independent blend
coverage. Total: **33 image maps**, excluding the source concept and review renders.

Tile widths are initial art settings, not measured dimensions from a scan. Adjust
UV density to the mesh. Use limestone on individually modeled arch blocks rather
than expecting the texture to create an arch. Reserve rubble for pilasters and
broken substrate; keep the tall red plaster planes comparatively quiet.

## Channels and Godot use

- **Albedo:** sRGB base color. Torch color and illumination belong to the lights.
- **Normal:** OpenGL tangent space, X+ Y+ Z+; Godot normal slot, not albedo.
- **Roughness:** linear grayscale, white rough and black smooth; red channel.
- **AO:** linear grayscale, white open and black occluded; red channel. Presets
  apply AO to ambient illumination, with `ao_light_affect = 0`.
- **Height:** white raised and black recessed. This is also the bump/displacement
  source; a second independent bump map would duplicate it. Native 8-bit data is
  intended for shallow surface relief. Presets assign the texture but leave
  parallax disabled; start at `heightmap_scale = 1.0` if enabling it.
- **Metallic:** iron only; white exposed metal, black rust/oxide. Other families
  use constant zero metallic and need no redundant black maps.
- **Blend masks:** white coverage, black no coverage. They are independent masks,
  not pixel-registered damage maps for the plaster albedo. Use broad peel zones
  to reveal limestone/rubble; damp coverage can darken albedo and lower roughness
  selectively. They require a mesh/material blend and are not automatically
  applied by the single-surface presets.

Scalar PNGs are near-grayscale RGB native outputs with small residual channel
differences. Consume their red channel as a single linear value; do not average
them as sRGB color. Per-channel measurements are preserved in `pack.json`.
Godot import recipes use lossless compression and mipmaps, with explicit normal
handling and no green-channel inversion. This preserves the delivered sources;
GPU packing/compression can be tuned when the materials enter the level.

Normal and height maps affect apparent surface relief; they do not repair mesh
silhouettes, wall openings, collision or unsupported bridge geometry. Scene
lightmaps must be baked from the actual level geometry and lights.

Godot's [StandardMaterial3D documentation](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html)
describes the OpenGL normal convention, height/parallax and AO behavior. Preset
properties were also checked against the installed **Godot 4.7.2** binary.

## Provenance and reproducibility

The source is our generated concept, preserved at `review/selected_nave.png`.
The user supplied that selection explicitly for texture generation. No external
texture downloads or scan libraries are included. Each output was generated
separately through built-in ImageGen; no bitmap maps were fabricated by a local
script. Derived map prompts reference the corresponding albedo/height with fixed
crop, layout and dimensions.

Exact prompts, ordered reference roles/paths, native output paths, attempts and
per-image observations are in `review/furnace_generation.json`,
`review/ossuary_generation.json` and `review/reliquary_generation.json`.
`pack.json` records delivered dimensions, hashes, channel statistics, border
differences and normal/height slope diagnostics. Native dimensions are reported
as generated, without upscaling or an unsupported 2K/4K claim.

`review/prepare_pack.py` only reads bitmap data for checks and writes metadata and
Godot resource text. It never edits image pixels. `review/.gdignore` excludes the
concept, generation records and preview tooling from Godot imports/exports.

## Review

`review/materials-neutral.png` shows the six actual Godot materials under the
same neutral light, with a small sphere for curved-surface response.
`review/materials-repeat.png` repeats each texture 2 × 2 to expose tile joins.
These are engine renders, not generated concept paintovers.

The maps are generated approximations, not a calibrated material scan. Macro
feature alignment, dimensions and normal direction are checked; fine detail can
drift between maps. Requested seamless tiling is inspected rather than guaranteed.
Use the repeat view before covering a large uninterrupted wall, and break repeats
with the supplied broad masks, mesh divisions and changes in UV offset.

Run from the worktree root:

```sh
python3 content/environments/red_nave_v1/review/prepare_pack.py
"$GODOT" --headless --editor --path . --quit
python3 content/environments/red_nave_v1/review/prepare_pack.py
"$GODOT" --headless --editor --path . --quit
GODOT="$GODOT" scripts/godot_bg.sh --path . --script content/environments/red_nave_v1/review/capture_materials.gd
```

The first import creates Godot's recipes; the second preparation configures those
recipes and the second import applies them.

Validation outcomes are recorded in `review/validation.md`.
