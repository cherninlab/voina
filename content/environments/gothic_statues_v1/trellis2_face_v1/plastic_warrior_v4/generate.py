"""Reconstruct the user's exact colored warrior image with the installed TRELLIS.2."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import numpy as np
from PIL import Image
import trimesh

base_root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--resolution", type=int, choices=[512, 768], default=768)
parser.add_argument("--out", type=Path, default=base_root)
args = parser.parse_args()
root = args.out.resolve()
root.mkdir(parents=True, exist_ok=True)
cl3d = Path("/Users/theochernin/Projects/CherninLab3D")
image_path = base_root / "source.png"
image = Image.open(image_path).convert("RGB")
os.environ.setdefault("U2NET_HOME", str(cl3d / "models/matting/models/u2net"))
sys.path.insert(0, str(cl3d / "vendor/trellis2mlx"))
from trellmlx.preprocess import preprocess_image_with_provenance

# Use the model pipeline's semantic foreground segmentation before conditioning.
# The original RGB image is retained byte-for-byte; black RGB is not an alpha mask.
preprocessed = preprocess_image_with_provenance(image_path)
(root / "preprocess.json").write_text(json.dumps(preprocessed.provenance, indent=2) + "\n")
foreground = preprocessed.image
side = round(max(foreground.size) * 1.15)
canvas = Image.new("RGB", (side, side))
canvas.paste(foreground, ((side - foreground.width) // 2, (side - foreground.height) // 2))
canvas.resize((512, 512), Image.Resampling.LANCZOS).save(root / "conditioning.png")
native = cl3d / "vendor/trellis2mlx/generate.py"
bootstrap = "import mlx.core as mx,runpy,sys;mx.set_memory_limit(42*1024**3);sys.argv=[sys.argv[1],*sys.argv[2:]];runpy.run_path(sys.argv[0],run_name='__main__')"
command = [
    str(cl3d / ".venv-trellis2/bin/python"), "-u", "-c", bootstrap, str(native),
    "--image", str(root / "conditioning.png"), "--output", str(root / "raw.glb"),
    "--resolution", str(args.resolution), "--steps", "24", "--seed", "42",
    "--max-tokens", "32768", "--no-rembg", "--target-faces", "0",
    "--no-cleanup", "--no-hole-fill", "--save-checkpoints", str(root / "checkpoints"),
    "--stop-after-stage", "mesh_raw",
]
if args.resolution == 512:
    command.append("--no-cascade")
started = time.monotonic()
subprocess.run(command, cwd=native.parent, check=True)
data = np.load(root / "checkpoints/mesh_raw.npz")
vertices = data["vertices"][:, [0, 2, 1]] * np.array([1, 1, -1])
faces = data["faces"]
assert len(faces) and np.isfinite(vertices).all()
mesh = trimesh.Trimesh(vertices, faces, process=False)
mesh.export(root / "raw.glb", include_normals=True)
mesh.vertices -= mesh.bounds.mean(axis=0)
mesh.vertices *= 1.4 / max(mesh.extents)
mesh.vertices[:, 1] -= mesh.bounds[0, 1]
mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name="Neutral geometry inspection", baseColorFactor=[180, 169, 149, 255],
    metallicFactor=0, roughnessFactor=.78, doubleSided=True))
mesh.export(root / "preview.glb", include_normals=True)
native_meta = json.loads((root / "checkpoints/mesh_raw.json").read_text())
base = json.loads((base_root.parent.parent / "trellis2_statues_v1/oracle_768/result.json").read_text())
base.update(
    source="Exact user-supplied colored warrior; U2Net pipeline foreground segmentation; no ImageGen edits",
    source_sha256=hashlib.sha256(image_path.read_bytes()).hexdigest(),
    source_dimensions=list(image.size), source_mode=image.mode,
    conditioning_sha256=hashlib.sha256((root / "conditioning.png").read_bytes()).hexdigest(),
    conditioning_dimensions=[512, 512], preprocessing=preprocessed.provenance, input_count=1,
    resolution_requested=args.resolution, resolution_actual=native_meta["mesh_grid_size"],
    steps=24, seed=42, max_tokens=32768, memory_limit_guideline_gib=42,
    triangles=len(faces), vertices=len(vertices), cleanup="none",
    seconds=time.monotonic()-started, command=command)
(root / "result.json").write_text(json.dumps(base, indent=2) + "\n")
print("USER_PLASTIC_WARRIOR_OK", len(faces), native_meta["mesh_grid_size"], flush=True)
