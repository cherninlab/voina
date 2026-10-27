# Hunyuan3D-2.1 face and hand detail experiments

## Current findings

Hunyuan3D-2.1 can accept an ordinary RGB image without a background-removal stage. Transparency is optional. Its official [preprocessor](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/blob/82920d643c0dc2f7bfd7255f45f62d386edfe60c/hy3dshape/hy3dshape/preprocessors.py) converts PIL images to RGBA, uses alpha for recentering, and composites transparent pixels onto white. The image encoder then receives RGB features. Acceptance of RGB input does not establish equal quality for every background.

The direct rectangular head crop with its original black background produced a more defined face than the earlier whole-statue reconstruction. The identical crop with the earlier background-only alpha mask produced a bad planar reconstruction. Repeating that transparent input in a freshly loaded process gave the exact same GLB SHA256, so this failure was reproducible. This establishes a result for this crop, checkpoint, seed and settings, not a general claim that black is always better than transparency.

The early tight head/hand masks were too aggressive: color thresholds and traced part boundaries removed useful neighboring material/anatomy and left edge artifacts. Those inputs are retained as diagnostics. The later contextual crops are plain rectangles retaining hair/neck/shoulders or wrist/forearm/clothing. No tight part segmentation is applied to the contextual crops.

Increasing the whole-body surface extraction from 384 to 512 using the identical final shape latents changed 538,838 triangles into 958,360. It barely changed the face. More polygons alone did not recover missing facial information. The model's normal preprocessing reduces a complete statue to 512px and the conditioner to 518px, leaving roughly 40px for the face. Close-ups allocate more image features and shape capacity to it.

The successful head crop reconstructs a volumetric head with hair on the back, but still has excessive eyelid folds and other surface artifacts. Narrow hand crops remain unreliable and can produce duplicate fingers/hands or flat fragments. The wider RGB upper-body crop retained arm/wrist context but still produced rounded fingers and unwanted broad backing geometry; it did not solve the hands. These trials are not approved game assets.

## Inputs and reproducibility

- All inputs derive from the same user-supplied oracle source stored in `../hunyuan21_oracle_v1/source.png`.
- `inputs/crops.json` records source paths, crop boxes, any early polygon/color masks and exact input hashes.
- Contextual black inputs are direct RGB rectangular crops of the supplied image. Contextual alpha inputs crop the earlier background-only alpha image; they retain neighboring body parts.
- All sampling trials use the official `tencent/Hunyuan3D-2.1` full fp16 checkpoint, seed42, 50 steps, guidance5, octree384 and query chunks8000.
- `body512` reuses the saved corrected-mask final shape latents from the preceding trial and only re-decodes them at512. It performs no diffusion resampling.
- Model source revisions, checkpoint hash, license copies and Mac wrapper provenance are retained in `../hunyuan21_oracle_v1/provenance.json` and `../hunyuan21_oracle_v1/licenses/`.
- All inference is local Apple MPS. CPU fallback and CPU mesh extraction may occur. No hosted generation, texture generation or engine placement took place.

Use the existing CherninLab3D Python environment:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/hunyuan21_detail_v2/generate.py --jobs head_context_black384
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/trellis2_face_v1/hunyuan21_detail_v2/prepare_review.py head_context_black384
```

The runner preserves existing receipts rather than overwriting completed attempts. Reproduction should use a fresh output folder. Shape latents remain local and ignored by Git. Per-trial receipts preserve model/input/output identity, component devices, settings and elapsed times.

## Experimental face transfer

`compose_face.py` tries transferring the new facial depth onto the denser whole-body mesh with conforming local subdivision and a feathered boundary. It keeps the body silhouette and hands. This is a separate experiment from model generation. Seams and eyelid artifacts remain visible, so the composition is a comparison candidate rather than an accepted replacement.

## Review

The viewer offers the previous body, denser decode, isolated crop reconstructions and face-transfer experiment. Isolated crop studies are uniformly placed near the corresponding body region for camera inspection; they are not merged into the statue. Matching neutral material and fixed studio lighting are used. Validation checks finite coordinates, indices, topology, asset hashes, HTTP availability and actual browser loading. Repository import/smoke checks remain separate from art acceptance.

## Trial measurements

| Trial | Seconds | Triangles | Boundary edges | Non-manifold edges |
|---|---:|---:|---:|---:|
| body512 | 152.68 | 958,360 | 0 | 4 |
| head384 | 163.88 | 1,243,156 | 0 | 16 |
| head_context_alpha384 | 181.74 | 515,212 | 0 | 4 |
| head_context_alpha_fresh384 | 167.07 | 515,212 | 0 | 4 |
| head_context_black384 | 176.37 | 1,296,330 | 0 | 10 |
| hip_context384 | 169.82 | 764,232 | 0 | 4 |
| raised_context384 | 172.12 | 170,316 | 0 | 2 |
| raised_context_black384 | 196.30 | 139,452 | 0 | 0 |
| upper_body_black384 | 174.16 | 1,308,720 | 0 | 9 |
