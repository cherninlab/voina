# E01: reconstruction from the four approved statue images

The user approved `../statue_from_rig_v1/` for a 3D attempt. Every generation here uses all four images together. None is a single-image reconstruction. [Interactive review](review/index.html), [comparison of actual raw-mesh renders](comparison.png), [masked/registered input review](input_review.png).

## Three completed attempts

| Folder | Model and conditioning | Extraction / sampling | Review |
| --- | --- | --- | --- |
| `instantmesh_256` | TencentARC/InstantMesh `instant_nerf_large`, four jointly encoded images with explicit cameras | 256 density grid, iso threshold 10; local MPS extraction adapter | Lumpy surfaces and weak anatomy; diagnostic |
| `trellis_multi42` | Microsoft TRELLIS-image-large, four-image multidiffusion; every view contributes at every step | Seed 42, 50 structure + 50 shape steps, shared rig framing | Better pose and support hand; thin-surface defects |
| `trellis_multi42_stochastic_native` | Same published TRELLIS image checkpoint, four-image stochastic conditioning; the sampler cycles through all four views | Seed 42, 76 structure + 76 shape steps, standard foreground crops | Strongest of these three trials; still rough face, fingers and cloth |

The selected review mesh is [`trellis_multi42_stochastic_native/preview.glb`](trellis_multi42_stochastic_native/preview.glb): 560,216 triangles, one connected watertight component. It retains 97.24% of the raw surface area and removes 32,794 detached triangles. Watertightness does not prove correct anatomy: holes through thin features, fused fingers and misplaced surfaces can still be watertight. No smoothing, anatomical replacement, hole filling, retopology or texture bake was applied. Neutral marble is a constant PBR material; original decoder vertex color is retained in `raw.glb`. Raw meshes and generation receipts are preserved for all three attempts.

These are review candidates, not final game-ready statues. The face and raised fingers remain much softer than the approved images. Fine cloth and back surfaces have defects. No new model has been integrated into the dungeon, and the earlier E01 asset remains unchanged.

## Inputs and framing

`inputs/*_masked.png` preserves each supplied crop's original RGB with a U2Net alpha mask. The source sheet's gray background is removed without generating or repainting content. `inputs/front.png`, `left.png`, `back.png`, `right.png` additionally register uniform scale and translation against the matching real rig render, using silhouette overlap. No nonuniform stretching, limb warping or rotation is used. Exact hashes, mask boxes, registration scales and placements are in [inputs.json](inputs.json).

InstantMesh and the first TRELLIS trial use those registered 900-square inputs. The second TRELLIS trial uses the unregistered masked crops with the pipeline's normal foreground-crop preprocessing. This is appropriate to its camera-free image conditioning, but is not a controlled camera-calibrated comparison. The input images themselves still have view-to-view pose/projection differences introduced by ImageGen. InstantMesh camera angles are nominal 90/180/270/0 degrees from +X, 20-degree elevation, matching the rig's +Y front; generated artwork is not an exact calibrated scan.

## Reproduce

Run with `/Users/theochernin/Projects/CherninLab3D/.venv/bin/python` from the game repository:

```sh
python content/environments/gothic_statues_v1/e01_quality_v2/reconstruct_four_views.py --method prepare
python content/environments/gothic_statues_v1/e01_quality_v2/reconstruct_four_views.py --method instantmesh --resolution 256
python content/environments/gothic_statues_v1/e01_quality_v2/reconstruct_four_views.py --method trellis --seed 42 --steps 50
python content/environments/gothic_statues_v1/e01_quality_v2/reconstruct_four_views.py --method trellis --seed 42 --steps 76 --trellis-mode stochastic --trellis-native-crop
```

Installed checkpoints only; no new model downloads. `result.json` in each candidate records the actual four input hashes, checkpoint revision, method, timing and geometry checks. TRELLIS is the published image model used through its multi-image inference API, not a separately trained camera-conditioned multi-view checkpoint. The CL3D multi-view checkpoint was not used.

Model attribution and supplied license copies are in `licenses/`. TRELLIS weights: `microsoft/TRELLIS-image-large`, revision `25e0d31ffbebe4b5a97464dd851910efc3002d96`; native-MPS port `f7c175a8620c2c23923d5b6fca3bf7f53604335f`. InstantMesh weights: `TencentARC/InstantMesh`, revision `b785b4ecfb6636ef34a08c748f96f6a5686244d0`; the existing MPS adapter uses its encoder and transformer and independently queries density, without importing the upstream NVIDIA renderer.
