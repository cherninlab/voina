# Hi3D oracle refinement trials

The existing TRELLIS.2 oracle and its unchanged supplied reference were passed to **Hi3D v1.0** for geometry refinement. This is a model comparison, not an approved replacement or a dungeon-integrated asset. Original TRELLIS.2 files remain unchanged.

| Trial | Grid | Updates per pass | Passes | Result triangles | GPU time | Peak allocated GPU memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Full statue | 1024 | 25 | 2 | 999,999 | 79.19s | 17.66GiB |
| Isolated head | 1024 | 15 | 2 | 999,999 | 126.48s | 23.37GiB |

Both runs used seed 42 on a reported NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 2g.48gb. Both achieved the requested 1024 output grid with no reported adaptive-grid warnings. These are per-request server receipts, not locally measured hardware timings. End-to-end client time also includes upload, queueing and download. Neither trial ran on the Mac's GPU.

The full-statue result has stronger facial contours but changes the mouth, retains eyelid artifacts and makes the horns rougher. The head-focused result resolves eyes and lips more clearly but produces raised eyebrow/eyelid shapes and frayed geometry at the cut neck. It is a separate head study and has not been merged into the body. It is not a controlled steps-only comparison: input framing, geometry scope and step count differ.

## Inputs and processing

- `source.png` is the exact supplied 687×1024 oracle reference, SHA256 `528eac8ce3cabf3727872f169c834641eacf8eaadf3374152499a702c8263c41`. No ImageGen reinterpretation was used.
- Full coarse geometry: `../oracle_resolution_v6/1536/remeshed/statue.glb`, SHA256 `1709ce2fb50629a0b07ded9b5893ec8c3d14de1a9014c583e42c4da58ee8a6e8`, 1,860,684 triangles. The demo accepted it directly and skipped Hunyuan coarse generation.
- Full reference background removal was performed by the demo's U2Net. Its returned segmented input is preserved as `1024/model_input.png`; the Hi3D conditioner subsequently applies its own white compositing and framing.
- `head_source.png` is a pixel crop `(190, 0, 505, 285)` of that returned segmented image. `head_coarse.glb` retains the largest connected component of whole coarse triangles above Y=1.03; this removes the separate raised hand. The cut neck is open. All coordinates and cropping details are in `head_request.json`.
- A 25-step head request was refused before inference because its reserved 220 GPU seconds exceeded the then-remaining 173 seconds of free allowance. The failure is retained under `head_1024_quota25/`. A separate 15-step request fit the allowance and completed. No subscription or paid GPU job was started. A 1536 trial was not run.
- Raw server outputs are `1024/hi3d.glb` and `head_1024/hi3d.glb`. The review GLBs apply only a uniform similarity transform and the same constant neutral material as the existing viewer. No local geometry repair or face replacement was applied. The head preview is aligned to its coarse crop's bounding box; the full result is centered and grounded with 1.4m maximum extent. Transform receipts are in each `validation.json`.

## Execution and reproducibility

Local machine: Apple Silicon macOS. The released Hi3D kernels require Linux/NVIDIA CUDA and have no supported local CPU/MPS path, so execution used the [townbox community ZeroGPU demo](https://huggingface.co/spaces/townbox/hi3d10-zerogpu), Space revision `0900d7b60cc443e50f1b3659046d9eb2975f2691`, through its `/refine` API. The demo is configured with the official `hi3d-official/Hi3Dv1.0` model at `705fc0901c5d896cdcbf1dbf1feaa173e62bdd3a` and official inference code at `23dcc684bc6e1fab86ecafb99ec5270edad122f9`.

`model_artifacts.json` records all eight runtime file identities at the demo's model revision and current Hub revision `d502e938cbedc6e87aba8884614c5ca6d177a4b6`: they match. The community demo's declared stack is Torch 2.8.0 / FlashAttention 2.8.3 / spconv-cu120 2.3.6 on Blackwell, differing from the authors' measured Torch 2.5 / CUDA 12.4 / H20 stack. No numerical parity claim is made. `remote_requirements.txt`, `provenance.json` and the Space app source snapshot retain this distinction. The locally inspected official source checkout is `CherninLab3D/vendor/Hi3Dv1.0` at `13657ad09afaa92e350b461a1cd66399e44a59c4`; it was not executed as a local inference runtime.

The runner uses the existing CherninLab3D Python environment and logged-in Hugging Face token without storing credentials in receipts. It refuses to overwrite an existing attempt receipt. For a fresh experiment, copy this folder and clear only that new copy's attempt outputs before using:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python run.py
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python run.py --attempt head_1024
```

Each request and receipt retains input hashes, settings, progress, output hash, GPU description, timing and warnings. Download-cache duplicates are ignored by Git. Code and model provenance/license notices are retained under `licenses/` and in the linked [official code](https://github.com/hi3d-official/Hi3Dv1.0) and [model repository](https://huggingface.co/hi3d-official/Hi3Dv1.0). The user-provided reference has separate provenance; no third-party ownership claim is made.

## Review and validation

`review/index.html` loads the actual full-refined, head-refined and original GLBs, with face/crown/back controls and matching mesh close-ups. Blender 5.2.2 renders use Cycles CPU, 24 samples, 800×800. `render_head.py` fixes the head lighting to the full TRELLIS.2 studio frame; otherwise scaling the studio down to the isolated head would overexpose it. Camera and material settings match the prior oracle review. These are geometry renders, not generated paintovers.

Both exports have finite coordinates, valid indices and consistent winding. Full refinement has 81 boundary and 22 non-manifold edges; the head has 135 boundary and 1,249 non-manifold edges. Neither is a watertight manifold. Boundary-edge counts are not counts of visible holes. Required Godot editor import and local two-process ENet smoke are recorded under `checks/`; these do not constitute in-game statue validation or art approval.
