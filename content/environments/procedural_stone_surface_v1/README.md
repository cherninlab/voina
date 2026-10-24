# Procedural stone surface v1 (T-180)

Tileable PBR maps for the faces of individual dressed stones in stone-built dungeon walls
(the stone-by-stone walls of T-177). The texture holds only the surface of one stone: rough,
pitted, slightly pillowed dressed stone with grit, small chips, darker grime in the cavities
and lighter worn high points. It has no joints, block outlines or crack veins, because the
wall geometry supplies the stones. This is the opposite of `dungeon_pbr_v2/marble_rock_03`,
whose dark crack veins read as cracked tiles.

## Variants

| folder | look | albedo, linear mean (p1-p99 luminance) | height range |
| --- | --- | --- | --- |
| `limestone/` | grey-beige; medium dressing scars, sharp pits, a few shallow solution pockets, shell flecks | 0.26 0.25 0.23 (0.15-0.34) | 10.1 mm |
| `sandstone/` | warm grey-brown; softer eroded relief, sand grain, honeycomb pit clusters, faint level bedding | 0.25 0.20 0.17 (0.12-0.28) | 8.7 mm |
| `granite/` | dark grey; crisp point-dressed facets and pocks, fine crystal speckle (feldspar, quartz, mica) | 0.14 0.14 0.14 (0.07-0.25) | 7.3 mm |

Each folder has the same five 2048 x 2048 maps as `dungeon_pbr_v2/<set>/`, so
`RedDescentDungeon.surface()` (crypt_dungeon.gd) loads it directly:

| file | format |
| --- | --- |
| `albedo.png` | 8-bit sRGB RGB. Physically plausible stone, low saturation; the shader multiplies it by vertex colour. |
| `normal_gl.png` | 8-bit RGB, OpenGL convention (green up). Encodes the true slopes of the height field. |
| `roughness.png` | 8-bit linear grey. The shader remaps it to 0.65-0.98 when dry. |
| `height.png` | 16-bit linear grey, white = high. 0..1 spans the height range in the table. |
| `ao.png` | 8-bit linear grey, cavity occlusion of the relief (pits are dark, the open face is near white). |

The `.png.import` files use the same settings as `dungeon_pbr_v2`: lossless, mipmaps, and the
normal-map flag only on `normal_gl.png`.

## Use in the game

```gdscript
var stone: ShaderMaterial = surface("res://content/environments/procedural_stone_surface_v1/limestone/", 0.555, 0.75, 0.3)
```

- **Density 0.555** (repeats per metre). One tile then covers 1.8 m of wall at 0.88 mm per
  pixel, which is the scale the maps were designed for: pits of 2-15 mm, dressing scars and
  undulations of 2-8 cm. Stay within about 0.45-0.7. Higher values shrink the pits below
  2 mm, and lower values make the scars read as large blotches.
- **Relief (normal_strength) 0.75.** `review/limestone_relief_study.png` compares 0.5, 0.75 and
  1.0. At 0.5 the face looks sanded flat. At 1.0 the scars start to look harsh under a raking
  torch. Use 0.6-0.85.
- **Parallax.** The height maps span 7-10 mm, so the shader's 12 mm parallax clamp (`relief_m`)
  suits them. Keep the default.
- **Wetness.** The paintovers' wet stone comes from the shader's `damp`/wet masks, which darken
  the albedo and lower the roughness in world-space patches. The maps contain no baked damp
  patches, because those would repeat every 1.8 m.
- Limestone is the recommended default for dungeon walls. Use sandstone or granite as a
  second family, for example per wall section, or for the darker lower courses (granite).

## How the maps were made

`scripts/art/build_stone_surface.py` runs in Blender 5.2.2's Python and synthesises every
layer with numpy on a periodic domain (the tile is a torus):

- **Noise:** Gaussian noise band-limited by FFT filters, given in millimetres. Domain warps and
  Gaussian blurs are periodic FFT or wrapped bilinear operations.
- **Dressing scars:** two generations, about 6 cm and 2 cm. Each is the rounded lower envelope
  (soft-min) of randomly oriented elliptical paraboloids on a jittered grid that wraps. This
  gives shallow dished facets with worn ridges where they meet: hand-dressed relief without
  outlines. Each scar also carries a slight tone of its own.
- **Undulation and roughness:** 2-9 cm undulation, plus broad-band 2.5-40 mm roughness with
  flattened highs.
- **Zones** of 10-30 cm vary how broken or worn the face is, so the surface is not uniform noise.
- **Pits** (radius 0.8-7.5 mm, power-law sizes), **pockets** and **chips** are stamped modulo the
  tile with irregular low-order outlines. Chips are shallow conchoidal scoops with a sharp
  break, and their fresh floors are lighter.
- **Grit, sand grains and pores:** fine relief at 1-3 mm and below.
- **Variant extras:** granite has warped Worley crystals (pale feldspar, grey quartz, clots of
  black mica, with relief from differential weathering). Sandstone has level bedding laminae.
  Limestone has sparse shell flecks.
- **Derived maps** all use wrapped neighbours:
  - normals: central differences in millimetres;
  - AO: a 16-direction horizon search (cosine-weighted, 24 mm reach);
  - grime: in small cavities and broad lows, broken up by noise;
  - wear: lightening on broad high ground;
  - roughness: rougher grime, smoother wear and fresh chips, glassier quartz.

Nothing is sampled from outside the tile, so the maps repeat exactly. `stone_surface.json`
records a seam score per map: how unusual the wrap-around step is among all row and column
steps, in standard deviations. All maps score below 2.1. For comparison, a tile shifted by one
pixel scores about 26 and an unrelated crop about 117. The `review/*_tile3x3.png` sheets show
5.4 x 5.4 m (3 x 3 tiles) under a raking light, with no seams or visible repetition.

## Provenance and licence

Procedural from Blender, so CC0 by construction. No external images, scans, HDRIs, node
assets or AI-generated pixels are read. All content comes from the script and seed **180**.
The maps are released under CC0 1.0. Generation is deterministic: running the script again
with the same seed reproduces the PNGs byte for byte. Their SHA-256 hashes are in
`stone_surface.json`.

Regenerate the maps, tiling sheets and review renders:

```
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_stone_surface.py -- \
    --seed 180 --samples 160 --study limestone
```

Add `--no-render` to write only the maps. Add `--preview DIR` for quick numpy-lit crops.

## Review renders (`review/`, Cycles)

- `<variant>_sphere.png`: a 1.15 m sphere whose UVs carry whole repeats at density 0.555,
  under a warm point torch from the upper left and a cool area fill from the right.
- `<variant>_wall.png`: about 3.6 x 1.45 m of separate box-ish stones with rounded arrises and
  10-16 mm joints in front of a dark bed. The torch rakes the wall, the cool fill comes from
  behind the camera, and each stone gets a -10 to +8 % tint (as the game's vertex colour would give).
  Damp patches and the bottom 40 cm use the shader's wet darkening and gloss.
- `<variant>_tile3x3.png`: the 3 x 3 tiling sheet described above.
- `limestone_relief_study.png`: relief 0.5, 0.75 and 1.0 side by side.

The render material copies `dungeon_surface.gdshader`:

- the same normal-xy scaling;
- roughness remapped to 0.65-0.98;
- 85 % saturation;
- specular 0.35;
- the wet tint and gloss;
- AO folded into the albedo at 35 %, standing in for the shader's indirect-only AO.

Review stones are box-mapped in the shader's orientation (horizontal tangent, V up, metres x
0.555). The game projects per vertex from smooth normals, which compresses the texture across
tightly rounded arrises. Stone meshes with strong bevels may look better with their own UVs.
