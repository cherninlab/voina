# Bridge and well materials v1

Materials and shader maps from the selected close bridge/well concept. The
sculpted dungeon-kit screenshots supplied later are a geometry-quality reference:
thick broken edges, deep cavities, broad readable faces and varied silhouettes.
Textures provide surface detail; structural edges and openings require geometry.

## Delivered assets

- Three new surface families: `bridge_oak`, `mineral_plaster`, `damp_masonry`.
  Each has albedo, height, normal, roughness and ambient-occlusion PNGs, plus
  `material.tres` and `wet_material.tres`.
- `masks/wet_patches.png` and `masks/algae_coverage.png`: independent blend coverage.
- `water/ripple_height.png`, a corresponding normal and `foam_mask.png`.
- `wet_surface.gdshader`: selective darkening, damp roughness, biofilm tint and
  height-derived relief. `water.gdshader`: animated ripple normals, small vertex
  displacement, depth-dependent green absorption color and restrained shallow foam.
- Two cropped scanned wall fragments in `scan_fragments/`, preserving their
  original UVs and embedded photographic textures.

Total: **20 new native image maps**, plus two GLBs. Existing iron and limestone
materials are reused from `../red_nave_v1/`; this pack depends on that folder.
The source concept, extra references, exact prompts and inspection outputs are in
`review/`, which is excluded from Godot import/export by `.gdignore`.

## Mapping and shader use

Albedo is sRGB diffuse color without the concept's torch reflections. Scalar maps
use the linear red channel: height white raised, roughness white rough, AO white
open, blend masks white coverage. Native scalar PNGs have minor RGB differences.
Actual resolutions, hashes and diagnostic measurements are in `pack.json`.

Stone/plaster tiles start around2.5m wide; oak grain follows texture V. Model
individual boards and vary UV offset/width, rather than repeating one full plank
image on every board. The shader check uses separately rotated boards with offset
UVs and slight height/angle variation. Iron chains use actual link geometry.

Normals ending `_gl` use the OpenGL convention. Mineral plaster's `normal_dx.png`
and water's `ripple_normal_dx.png` have DirectX green polarity; their Godot import
recipes invert green. Import recipes explicitly mark normal data, enable mipmaps and
preserve source PNG bytes. Read each map's recorded convention when using another
engine; Godot receives OpenGL normals after import.

Generated normal/scalar maps are approximate, not calibrated scans or exact
derivatives. The wet shader therefore defaults to finite differences of its
height map for coherent surface-normal direction. Set `height_driven_normal`
false to use the imported native normal instead. `normal_strength` and
`height_gradient_gain` control visual relief. Height does not create wall
thickness, large cracks, collision or a walkable surface.

Oak roughness remains a limited native candidate after its correction attempt.
The wet shader clamps dry roughness to0.68–0.95 before applying the independent
wetness mask, preventing generated dark creases from becoming polished grooves.
The plain StandardMaterial presets are dry reference materials; use the wet
variant for the intended damp bridge treatment. Coverage masks are independent
of albedo damage and must be positioned/tiled for the actual mesh.

Water requires opaque geometry below/behind it so the depth texture can measure
water thickness. Its small height displacement needs a subdivided mesh. It uses
specular lighting and transparency; it does not implement SSR or refraction.
`review/water-wetness-0.png` and `-1.png` are real Mobile/Metal frames captured at
different times to check the animated response. This is a material test scene,
not an implementation of the complete concept or a gameplay traversal test.

## Scanned assets and attribution

The user supplied both folders and explicitly confirmed ownership or additional
reuse rights on2026-10-23. Their existing embedded credits are retained here and
in `review/scan_provenance.json`:

- **Scan001:** *Inishmaine Building*, Mayo3D. [Original model](https://sketchfab.com/3d-models/inishmaine-building-6c059f8dde0946ef9cc34cbd873469b4),
  [author](https://sketchfab.com/Mayo3D), [CC BY4.0](https://creativecommons.org/licenses/by/4.0/).
- **Scan002:** *Restos arqueológicos Bodega_Teruel_escáner3D*, CUADRANTE.
  [Original model](https://sketchfab.com/3d-models/restos-arqueologicos-bodega-teruel-escaner-3d-d9b2b5f52eac4d42acb5e258f5578e1e),
  [author](https://sketchfab.com/cuadrante.virtualizacion), embedded
  [CC BY-NC-ND4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/).
  Reuse of this modified fragment relies on the user's additional rights
  confirmation, not a claim that the embedded license permits unrestricted reuse.

Changes: crop existing vertical wall faces, remove loose vertices, weld0.5mm,
reorient locally and decimate where needed. Final triangle counts are725 and12000.
No collision is supplied. The three embedded JPEGs are byte-identical to their
source scan textures; hashes are verified in `review/scan_texture_verification.json`.
Godot extracts these three JPEGs beside the GLBs on import; those copies are also
included through Git LFS so their texture import settings and UIDs stay stable.
These photographic textures may retain capture lighting and are not new calibrated
PBR albedos. Original downloads were not modified.

The native-generated texture maps are separate from these scan derivatives.
Exact ImageGen prompts, ordered inputs, attempts and candid QA are recorded in
the three `review/*_generation.json` files. Native output sizes are reported
without upscaling. Large areas still need tile-join inspection and broad material
variation; the repeat capture exposes repeated landmarks.

## Reproduce and validate

`review/prepare_pack.py` reuses the nave inspector, reads images for measurements
and writes resource/metadata text. It never changes bitmap pixels. Run it, run
the headless editor import, run preparation again to configure newly created
import recipes, then import once more. Windowed checks must use:

```sh
GODOT="$GODOT" scripts/godot_bg.sh --path . --script content/environments/bridge_well_v1/review/capture_materials.gd
GODOT="$GODOT" scripts/godot_bg.sh --path . --script content/environments/bridge_well_v1/review/capture_shader_check.gd
```

Blender inspection/extraction scripts retain the source paths and crop criterion.
They use Blender's native geometry tools; their intermediate `.blend` files stay
local. Validation outcomes and practical limitations are in `review/validation.md`.
