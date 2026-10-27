# Hunyuan3D-2.1 local oracle trial

Generated the supplied oracle reference on this Apple Silicon Mac using the official full Hunyuan3D-2.1 fp16 shape checkpoint and community MPS runtime compatibility patches. This is a shape-only comparison; texture synthesis and engine placement are separate work.

## Reproduce

Use the existing CherninLab3D Python environment and installed model/source paths recorded in `provenance.json`. Run from this repository worktree:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/hunyuan21_oracle_v1/generate.py --seed 42 --clean-black-background
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/hunyuan21_oracle_v1/prepare_review.py --seed 42 --clean-black-background
```

Existing receipts are protected from overwrite. Use another empty trial folder for an intentional rerun. The original U2Net-only attempts used `--seed 42` and `--seed 0` without the mask option.

The model, VAE and conditioner were each verified on `mps:0` in fp16. Unsupported operators and mesh extraction may use CPU. `PYTORCH_ENABLE_MPS_FALLBACK=1` and MPS memory high/low watermarks 1.0/0.8 apply only to the generation process. End-of-run memory values in receipts are not peak measurements. No hosted inference was used in these Hunyuan trials.

## Inputs and provenance

- Direct supplied `source.png`: SHA256 `528eac8ce3cabf3727872f169c834641eacf8eaadf3374152499a702c8263c41`.
- Official weights: [tencent/Hunyuan3D-2.1](https://huggingface.co/tencent/Hunyuan3D-2.1), revision `0b94677654c57bb9a6b6845cd7b704ccf551d327`.
- `model.fp16.ckpt`: 7,366,389,768 bytes; SHA256 matches official LFS object `6b519fc7242f78e9b5f47ea4d55668fe3d944a2d27332f4ca68d29a6ff603f5e`.
- [Official source](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1): `82920d643c0dc2f7bfd7255f45f62d386edfe60c`.
- [Mac compatibility wrapper](https://github.com/VladimirTalyzin/hunyuan3d-2.1-mac-rocm): `6f4b63bd6419406f40291bca23a7c849bcaae2a3`. Runtime-only patches; no core source edits.
- Reused CherninLab3D `.venv`; installed only `timm==1.0.30` for this trial. Runtime versions are in `checks/runtime.json`.
- Official model license/notice and compatibility license/notice are retained under `licenses/`; no unrestricted commercial-use claim is made.

## Settings and results

All three samples use 50 steps, guidance 5, octree resolution 384, chunk size 8,000 and fp16. This octree setting is not directly comparable to TRELLIS.2's 1536 geometry grid. The official pipeline resizes the conditioning image internally; a larger source image alone does not increase its feature resolution.

| Trial | Seed | Input mask | Inference | Triangles | Boundary edges | Non-manifold edges | Watertight |
|---|---:|---|---:|---:|---:|---:|---|
| 384_s42 | 42 | U2Net | 115.29 s | 528,006 | 0 | 0 | yes |
| 384_s0 | 0 | U2Net | 118.50 s | 535,078 | 0 | 0 | yes |
| 384_s42_maskfix | 42 | U2Net + black background removal | 122.49 s | 538,838 | 0 | 4 | no |

All meshes have finite coordinates, valid indices and consistent winding. Each raw export is retained. Review exports apply only uniform centering/scaling/grounding and a constant neutral PBR material; no repair, simplification, or geometry replacement was applied. Shape latents remain local and are excluded from Git and the review server copy.

## Mask diagnosis

U2Net retained the near-black background between the horns: pixel (343,30) was RGBA (1,1,1,254). Both initial samples reconstructed a filled-in crown. The corrected-mask trial reduces alpha for the supplied near-black backdrop (RGB maximum 12 to 24), giving that same gap pixel alpha 0. This is appropriate to this bright plastic reference with a black backdrop, not a general matting rule for dark assets. `checks/*_mask.jpg` shows both masks composited on grey.

## Review and validation

The review page offers all three local Hunyuan results plus the existing TRELLIS.2 and Hi3D full-statue candidates. Matching neutral material, camera presets and Blender studio lighting support comparison; full-body scale is 1.4 m. Fine anatomy and geometry quality still require visual review; closed topology does not establish fidelity.

`checks/godot_import.txt` and `checks/smoke.txt` retain repository import and networking/combat smoke checks. These are regression checks, not in-engine acceptance of the statue. Actual generation receipts, raw/review GLB hashes and per-trial topology checks are retained beside each export.

## Visual finding

The corrected mask restores the open horn silhouette, confirming the preprocessing cause of the large filled crown in both initial samples. The result retains the body pose and broad garment folds but still has a soft face, simplified hair and poor fine finger geometry. This trial does not improve the current face result and is not an accepted replacement for TRELLIS.2. The corrected export still has four non-manifold edges and requires cleanup before production use.
