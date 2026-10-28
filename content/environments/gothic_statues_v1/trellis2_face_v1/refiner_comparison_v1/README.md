# Statue refinement comparison

The user supplied two new images and requested independent single-image reconstruction, then asked for Hi3D MLX, prioritized UltraShape first, and added UniForge3D for consideration. Sources are preserved byte-for-byte in `tunic/source.jpg` and `pillar/source.jpg`; manifests record their original paths, dimensions and SHA256.

## Completed speed trials

Both coarse meshes use the official full Hunyuan3D-2.1 checkpoint locally through the previously verified MPS wrapper: 50 steps, guidance 5, seed 42, octree 384. They retain original RGB images and their black backdrops. No texture generation is claimed.

| Case | Coarse triangles | Coarse wall seconds | UltraShape triangles | UltraShape wall seconds |
|---|---:|---:|---:|---:|
| Tunic | 435,636 | 134.12 | 1,227,538 | 50.65 |
| Pillar | 361,924 | See receipt | 1,036,264 | 54.26 |

UltraShape uses the unmodified released `infinith/UltraShape` checkpoint at revision `5aeb21a7185d39f042d02b2695802f125a6f5159`, SHA256 `c96ae010c4169597fd0006dcb08056bf6104a1fca249b10fed7ddded324c3f0f`, 7,366,231,254 bytes. The official source is pinned at `5e8dcef05df101ab00ab6cd5fdd0ed0c74fbca66`. The community Mac implementation is pinned at `2724fd7b5496f3c90789da3217d0ad6021ea939e`; source changes are retained in `mps_port_changes.patch`.

The speed trials use 12 Euler steps, 8192 latent tokens, 512 extraction resolution, guidance 5, chunks 4096 and seed 42. These reduced settings are not the released quality defaults. VAE, DiT and DINO weights all load strictly on MPS fp16. Unsupported operations may fall back to CPU; marching cubes uses the port's scikit-image implementation. One image and its matching coarse mesh enter each independent refinement.

Only border-connected near-black pixels (maxRGB<=24) are made transparent for refinement. No body-part segmentation is used. Exact prepared inputs and their hashes remain with each run. The conditioner's released 1022px image path is unchanged. The runner imports inference modules directly to avoid unrelated training/UI dependencies, uses MPS float16 autocast, and performs coordinate selection on CPU. Model architecture and checkpoint weights are unchanged.

The successful preflight loaded every component and executed a real finite denoiser forward pass on MPS. Earlier runner errors (watermark, argument shape and missing autocast) are retained separately. Preflight success is not mesh acceptance.

The first visual comparison shows stronger eyes and mouth after refinement, with distorted creases and finger detail remaining. All geometry is experimental. Higher triangle counts and zero boundary edges do not establish correct anatomy. Raw outputs and uniformly centered/scaled neutral review GLBs are kept separately, without smoothing, repair or decimation.

## Further tests in progress

A full-default UltraShape quality attempt uses 50 steps, 32768 latent tokens and 1024 extraction resolution on the tunic case. Do not treat its loading/sampling receipt as a completed mesh. Hi3D MLX code and an isolated MLX environment have been prepared; its weights are being downloaded and no Hi3D geometry is claimed yet.

## UniForge3D audit

[UniForge3D](https://github.com/xibushu/UniForge3D) is a sparse, unposed multiview reconstruction/generation pipeline based on TRELLIS.2 and VGGT. Source revision `8b6094780e202b8a6b1d239e0997552e18547026` was inspected. Its published sparse convolution backend explicitly permits only `flex_gemm`; setup installs CUDA PyTorch, FlashAttention, CuMesh and nvdiffrast. There is no published MPS backend in this source. The local import also fails because this existing environment lacks the required DINOv3 transformers class. Resolving that version issue alone would not provide the missing CUDA kernels. No UniForge weights were downloaded and no UniForge mesh was generated. `uniforge_audit/` retains the actual preflight and backend/setup evidence. The model repository currently totals about 26.96 GB and marks its weights CC-BY-NC-4.0; the source MIT license does not replace those model terms.

## Review and reproduce

Use `generate_coarse.py --case tunic` or `--case pillar` with the existing CherninLab3D `.venv/bin/python`. `run_ultrashape.py --case tunic --preflight` verifies the inference path; omit `--preflight` for the speed trial, or pass `--steps 50 --latents 32768 --resolution 1024` with spaces between options and values for the quality trial. Existing receipts are protected from overwrite. `prepare_review.py FOLDER` preserves the raw mesh and writes a neutral review GLB and topology/hash measurements. `render_review.py` uses the existing shared Blender background studio. `build_comparison.py` includes only completed, validated meshes and verifies their SHA256 values.

Licenses/notices, pinned versions, original/prepared inputs, settings and wall times are retained with the outputs. No game integration or finished-asset acceptance is claimed.
