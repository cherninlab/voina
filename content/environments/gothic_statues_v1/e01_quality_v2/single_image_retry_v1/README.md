# E01: return to one-image reconstruction

The user rejected the four-image fingers and requested a single-image retry and a larger model. Both new baselines use exactly one image: the front panel of the approved statue sheet, with its existing U2Net mask. No second view is passed to either model.

| Attempt | Checkpoint | Sampling | Cleaned preview |
| --- | --- | --- | --- |
| `triposg_seed42` | VAST-AI/TripoSG, 1.5B | Seed 42, 75 steps, 2048 tokens; published conditioning size | 1,165,180 triangles; selected for comparison |
| `trellis_seed42` | Microsoft/TRELLIS-image-large, original generation | Seed 42, 75 structure + 75 shape steps; native image crop | 616,952 triangles |

TripoSG gives a cleaner separated hand silhouette than the TRELLIS retries, but the fingertips are rounded and the hand proportions remain imperfect. Face detail is soft, and the back and hidden limbs are inferred. The dense original geometry is retained. Preview cleanup removes only detached components and applies a neutral material; no hand replacement, smoothing or texture bake was applied. These remain review candidates, with no dungeon integration.

[Interactive comparison](review/index.html) includes both single-image models and the previous four-image result. [Actual TripoSG hand close-up](triposg_seed42/review/single_hand_front.png). Each candidate's `result.json` records the single source hash, parameters and checks.

## Larger model installation

TRELLIS.2-4B is a different Microsoft model family from the original TRELLIS-image-large used so far. The official model card lists four billion parameters and 512–1536 voxel output resolutions. The shape weights required for 512 generation and 1024/cascade generation have now been downloaded to `/Users/theochernin/Projects/CherninLab3D/models/TRELLIS.2-4B/`, pinned to `af44b45f2e35a493886929c6d786e563ec68364d`. Texture-generation weights were not downloaded for this geometry experiment.

The Apple Silicon runtime is installed separately at `/Users/theochernin/Projects/CherninLab3D/.venv-trellis2/`, using MLX 0.32.4 and `lyonsno/trellis2mlx` revision `449bfbc011401fe03d684a01f0b1068bfe8f6ceb`. Import and CLI help checks passed. The existing Shape Studio environment and server code are unchanged.

The remaining dependency is the official `facebook/dinov3-vitl16-pretrain-lvd1689m` encoder. Hugging Face CLI authentication works, but the repository returns HTTP 403 because the user's access request is awaiting review by Meta. TRELLIS.2 inference has not run. No alternate weight mirror, substituted encoder or random conditioning was used. [Installed files/status receipt](trellis2_install_status.json).

Once access is approved, use the prepared launcher from the game repo:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/e01_quality_v2/single_image_trellis2.py --check-only
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/gothic_statues_v1/e01_quality_v2/single_image_trellis2.py --resolution 512 --steps 12
```

This launcher checks official encoder access before running anything, saves native intermediate geometry, and stops before texture generation. Its complete inference path remains unverified until encoder access is granted. Higher-resolution requests are available through `--resolution 768` or `1024`; memory and quality must be measured on the actual run.

Official sources: [TRELLIS.2-4B model card](https://huggingface.co/microsoft/TRELLIS.2-4B), [DINOv3 access page](https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m), [Mac runtime source](https://github.com/lyonsno/trellis2mlx).
