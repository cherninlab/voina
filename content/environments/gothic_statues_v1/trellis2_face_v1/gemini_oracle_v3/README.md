# Gemini reference: single-image and approved four-view reconstruction

The supplied image is retained byte-for-byte as `source.jpg` (1696×2528). `source.json` records its origin and SHA256. This trial uses the original RGB image and black backdrop without segmentation or color masks.

## Single image

`generate_single.py` runs the official full Hunyuan3D-2.1 fp16 shape checkpoint locally on Apple MPS: 50 steps, guidance 5, seed 42, octree 384 and query chunks 8000. It produced 797,192 triangles in 142.95 seconds wall time including loading. This is new shape geometry, not a texture-only operation.

Model, VAE and conditioner devices/dtypes, source/checkpoint hashes and timings are in `hunyuan21_single_s42/receipt.json`. Model licenses, pinned source revisions and model hashes are retained at `../hunyuan21_oracle_v1/provenance.json` and its `licenses/` folder.

## Approved multiview images

Built-in imagegen created a draft 2×2 turnaround from the supplied reference. That sheet returned at 1254×1254 rather than the requested 4096×4096. To avoid using 627px quadrants, four separate native 1024×1536 views were generated using the original image and draft sheet as references. Exact prompts are in `multiview/*_prompt.txt`.

Each original generated image is retained as `*_original.png`. Prepared `front.png`, `left.png`, `back.png` and `right.png` use uniform framing on a 1024×1536 black canvas. No input was upscaled or subjected to a part mask. Native dimensions, uniform scales, crop bounds and SHA256 values are recorded in `multiview/inputs.json`.

The user explicitly approved all four images with “Approve these four views” on 2026-10-28 before multiview reconstruction. Approval is recorded in the input manifest. Side/back surfaces remain AI-inferred observations; small trim, fold and finger differences remain between images. These are not four measured photographs of one physical object.

## Dedicated multiview geometry model

The actual multiview geometry model is [tencent/Hunyuan3D-2mv](https://huggingface.co/tencent/Hunyuan3D-2mv), a dedicated multiview checkpoint from the Hunyuan3D-2 family. The single-image 2.1 checkpoint is not being relabeled as multiview.

- Model revision: `3a761b539b29fe4ff64714813aa9560fd66f5de0`.
- Full regular fp16 checkpoint: 4,928,151,562 bytes, SHA256 `d36f5881bcdc56726b73e517cd444c13c60732431622da7268145355c8d38e9c` verified against the official LFS object.
- Official 2.1 code provides the older denoiser, VAE and multiview conditioner classes. The derived config changes only the import namespace `hy3dgen.shapegen` to `hy3dshape`; all model parameters remain unchanged. Original/derived config hashes and runtime revisions are in `multiview/model.json`.
- All active model, decoder and conditioner weights are present with matching shapes. The inference checkpoint intentionally omits 144 VAE point-cloud-encoder/pre_kl keys; those modules are unused by image-to-shape inference. An initial overstrict audit failure is preserved in `multiview/preflight_strict_audit/`; the corrected audit explicitly checks all active weights.
- A geometry-free preflight on dummy color discs verified MPS fp16 devices, prepared shape `[1,4,3,512,512]`, camera slots `[0,1,2,3]`, joint CFG conditioning `[2,5480,1536]`, and finite denoiser output `[2,3072,64]`.
- Actual reconstruction processes the approved front/left/back/right images jointly through one diffusion trajectory and exports one mesh. It does not concatenate four independent reconstructions.
- Sampling settings: 50 steps, guidance 5, seed 42, octree 384, query chunks 8000. Exact input/output hashes and elapsed time are in `multiview/reconstruction_s42/receipt.json`.

All inference is local on this Apple Silicon Mac. Unsupported operations and geometry extraction can use CPU. No hosted 3D inference, texture generation or game placement was performed.

## Reproduce

Use the existing CherninLab3D Python environment and the installed paths recorded in the manifests. Existing receipts are protected from overwrite, so rerun in a fresh output folder.

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/gemini_oracle_v3/generate_single.py --seed 42
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/gemini_oracle_v3/multiview/run.py --preflight
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/gemini_oracle_v3/multiview/run.py --reconstruct
```

Shape latents remain local and ignored by Git. `prepare_review.py` uniformly centers/scales meshes to a maximum span of 1.4 m and assigns the same neutral material; it performs no repair or simplification. Both raw and review GLBs are retained.

## Interpretation

The comparison changes both the model and the input images: original supplied image with 2.1 versus generated cardinal views with 2mv. It does not isolate view count as the only cause of a quality difference. A higher triangle count or closed surface does not establish correct anatomy or visual acceptance. User approval of the reference images is separate from acceptance of either resulting mesh.

## Background control and detached-plane cleanup

A second joint-view run uses the exact approved images, checkpoint, seed, camera labels and sampling settings, while making only border-connected near-black pixels transparent. Interior dark details remain intact; no skin, hair, garment or hand mask is used. Its prepared input hashes and exact matting rule are in its receipt.

The raw RGB multiview run generated two detached full-height side planes. `remove_detached_planes.py` removes only those two geometrically identified connected components, totaling 670,652 triangles, and preserves every other component without displacement or smoothing. Raw and filtered outputs remain available separately. The alpha-background trial is a new inference, not this component filtering.

## Current visual findings

The supplied single-image trial retains its pose and main cloth/hair shapes but has a soft face and fingers. The raw RGB multiview run adds two detached side planes. Background-only transparency eliminates those planes, while facial and finger detail remains insufficient. Removing the two detached RGB components cleans that output without improving its remaining anatomy. No result has been accepted as a finished game asset.

A focused head-and-shoulders run crops the same approved four views at the identical pixel rectangle (220, 60, 804, 610), retaining the native 584×550 pixels. It tests allocating more conditioning pixels and shape capacity to the head. This is a new reconstruction of the cropped subject; it is kept separate from the whole statue.

The head crop restores more recognizable eyes, nose and mouth than the full-statue reconstruction, but adds distorted creases around the eyelids and mouth. This is evidence that allocating more image pixels and geometry capacity helps recover features, while remaining insufficient for this asset. It does not isolate source resolution from model capacity or view consistency. The bust remains separate and is not a replacement head attached to the body.

## Measured outputs

| Reconstruction | Triangles | Wall time including load | Visual finding |
|---|---:|---:|---|
| Original supplied RGB, Hunyuan3D-2.1 | 797,192 | 142.95 s | Overall pose retained; soft face and fingers |
| Approved four-view RGB, Hunyuan3D-2mv | 1,334,488 | 170.21 s | Two detached side planes; soft features |
| Same RGB mesh, two detached planes removed | 663,836 | Postprocessing only | Body vertices unchanged; soft features remain |
| Approved four views with background alpha | 635,960 | 177.50 s | Detached planes absent; soft features remain |
| Four-view head and shoulders with alpha | 1,300,094 | 171.31 s | More facial structure, but distorted creases remain |

All four raw reconstructions have zero boundary edges but retain 2–12 non-manifold edges. Zero boundary edges does not establish watertightness or correct anatomy. These are local shape trials with a neutral review material; no generated PBR texture maps, low-poly bake or game integration is claimed.

The browser comparison exposes all five outputs, the approved inputs, actual mesh close-ups, raw run receipts and downloadable GLBs. Required Godot import and two-process networking smoke checks passed; those checks do not establish statue art acceptance.
