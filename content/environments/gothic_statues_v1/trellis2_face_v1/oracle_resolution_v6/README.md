# Oracle resolution comparison v6

Same supplied female oracle, seed 42, 24 sampling steps, and identical segmented input in both trials. The 1536 reconstruction retains more recognizable eye, nose, lip and hair shapes than 768 after remeshing. Both are preserved for review alongside the previous v5 base. The 1536 result still has eyelid fins/slits, inaccurate fingers and some cavities around accessories. It is a comparison candidate, not an approved game asset.

## Measured result

| Geometry grid | Raw triangles | Remeshed triangles | Boundary edges, raw → remeshed | Non-manifold edges after remeshing |
| --- | ---: | ---: | ---: | ---: |
| 768 | 2,235,318 | 1,865,922 | 39,636 → 0 | 2,905 |
| 1536 | 9,528,562 | 1,860,684 | 123,210 → 0 | 8,442 |

Both remeshed outputs have consistent winding. Neither is a watertight manifold: edges shared by more than two triangles remain. A boundary edge has one incident triangle; the count is not a count of visible holes. Remeshing substantially removes the dotted surface breakup, and the inspected crown is closed, but increased grid resolution alone does not correct inferred anatomy. Raw meshes are retained before any remeshing or reduction. Dense intermediate remesh arrays remain locally under `remeshed/rebuilt_full.npz` and are ignored by Git.

## Generation and geometry method

- Exact source: `source.png`, 687×1024 RGB; SHA256 `528eac8ce3cabf3727872f169c834641eacf8eaadf3374152499a702c8263c41`. Supplied by the user; no new image synthesis or pose changes.
- Model: `microsoft/TRELLIS.2-4B`, revision `af44b45f2e35a493886929c6d786e563ec68364d`; DINOv3 ViT-L/16 revision `ea8dc2863c51be0a264bab82070e3e8836b02d51`. Existing local weights and granted access were reused.
- Native MLX port: `CherninLab3D/vendor/trellis2mlx`, revision `449bfbc011401fe03d684a01f0b1068bfe8f6ceb`. The wrapper patches the generator in memory, leaving that checkout unchanged. Its receipt records source and patched hashes and verifies the actual decoded grid; no silent 1536→768 fallback occurred.
- The low-resolution cascade uses 512px image features. The high-resolution cascade now re-encodes at 1024px, matching the official pipeline's division. Saved high-resolution feature arrays are `(1, 4101, 1024)` for both trials. The 1536 setting is a geometry grid, not a 1536px image encoder or a larger checkpoint.
- Background segmentation uses existing U2Net, square crop, 15% margin and a 1024×1024 RGB conditioning image. Both runs' conditioning SHA256 is `bbff0204ec5175df06b9154b70b2e593f71997b6f01956481b46ae2d2acde84d`. This segmentation model differs from upstream RMBG2; numerical CUDA parity is not asserted.
- Geometry export follows the upstream stage order through the port's `rebuild_surface`: small-hole prefill, original-surface BVH, narrow-band dual contouring (band 1), projection back (0.9), and reduction directly toward 2,000,000 faces. Actual triangle counts are approximate. This run uses the Torch-facing Metal geometry backend, not the appearance/UV/PBR baking branch.
- GLBs are normalized with the same raw-source transform to 1.4m maximum extent, Y-up, centered and grounded. Neutral material exposes geometry; remeshed materials render one-sided. No texture or normal-map bake is included in this comparison.

Native generation took approximately 167s at 768 and 301s at 1536. Remeshing took 18s and 89s respectively. Peak MLX allocations were 8.65GiB and 11.81GiB; these are allocator measurements, not total process/system memory.

## Reproduction and dependencies

Run from this folder with the existing CherninLab3D environments. Scripts preserve completed trial folders and refuse overwrites; use a copied empty attempt folder for reruns.

```sh
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python generate.py --resolution 768
/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/bin/python generate.py --resolution 1536
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python remesh.py --smoke
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python remesh.py --resolution 768
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python remesh.py --resolution 1536
```

Optional dependencies installed into `.venv`: [mtlmesh](https://github.com/pedronaugusto/mtlmesh) at `5e6749356ba39b15489c99487f55840d49923da7` (package `cumesh` 0.1.0), and [mtlbvh](https://github.com/pedronaugusto/mtlbvh) at `fe6660bdb7de5a12ea00bd96df2e21bdcbdd40b1` (0.1.0). Both MIT licenses are copied under `licenses/`. `dependency_build.patch` records the C++17→C++20 setup-only adjustment required by installed Torch 2.14.1. Builds used Xcode 27.1 and its Metal Toolchain 27A266a via per-command `DEVELOPER_DIR`; the global developer-tools selection was unchanged. No additional texture model was installed.

Backend identity hashes are retained in the smoke and natural-run remeshing receipts. The 498,002-triangle deep-BVH regression witness passed all 2,000 sampled source-vertex distance queries, and the small cube remesh was watertight with consistent winding. This targeted check does not certify arbitrary BVH queries. Finite geometry/index validation passed for the output GLBs. Godot headless editor import and the local two-process ENet smoke test passed; these do not establish in-game statue appearance or multiplayer human acceptance.

Actual geometry was rendered with the existing `../plastic_oracle_v5/render_review.py`, Blender 5.2.2 Cycles CPU, 24 samples, 800×800, matching cameras and lighting. `review/index.html` loads the real GLBs, including raw and previous-base options. `comparison.json`, run receipts and `validation.json` retain the numerical evidence and file hashes.

Upstream references: [pipeline conditioning](https://github.com/microsoft/TRELLIS.2/blob/main/trellis2/pipelines/trellis2_image_to_3d.py), [export geometry stages](https://github.com/microsoft/TRELLIS.2/blob/main/o-voxel/o_voxel/postprocess.py). Generation and dependency licenses apply independently of the user-provided reference. No new claim about third-party reference ownership is made.
