"""Uniformly align the remote result and apply the existing neutral review material."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import trimesh

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--attempt", choices=["1024", "head_1024"], default="1024")
args = parser.parse_args()
folder = root / args.attempt
mesh = trimesh.load(folder / "hi3d.glb", force="mesh", process=False)
assert len(mesh.faces) and np.isfinite(mesh.vertices).all()
assert mesh.faces.min() >= 0 and mesh.faces.max() < len(mesh.vertices)
bounds = mesh.bounds.copy()
if args.attempt == "head_1024":
    target = np.asarray(json.loads((root / "head_request.json").read_text())["coarse_crop"]["bounds"])
    scale = max(np.ptp(target, axis=0)) / max(mesh.extents)
    translation = target.mean(axis=0)
    mesh.vertices = (mesh.vertices - bounds.mean(axis=0)) * scale + translation
else:
    scale = 1.4 / max(mesh.extents)
    translation = np.array([0., .7, 0.])
    mesh.vertices = (mesh.vertices - bounds.mean(axis=0)) * scale + translation
mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name="Neutral remeshed inspection", baseColorFactor=[180, 169, 149, 255],
    roughnessFactor=.78, doubleSided=False))
mesh.export(folder / "review.glb", include_normals=True)
edges = np.sort(np.asarray(mesh.edges, dtype=np.uint64), axis=1)
packed = (edges[:, 0] << np.uint64(32)) | edges[:, 1]
_, counts = np.unique(packed, return_counts=True)
report = {
    "vertices": len(mesh.vertices), "triangles": len(mesh.faces),
    "finite_and_indices_valid": True,
    "boundary_edges": int((counts == 1).sum()),
    "non_manifold_edges": int((counts > 2).sum()),
    "winding_consistent": bool(mesh.is_winding_consistent),
    "watertight": bool(mesh.is_watertight),
    "preview_transform": {"input_bbox_center": bounds.mean(axis=0).tolist(),
                          "uniform_scale": scale, "translation": translation.tolist()},
    "changes": "Uniform centering/scale/grounding and constant material only; no geometry repair",
    "raw_sha256": hashlib.sha256((folder / "hi3d.glb").read_bytes()).hexdigest(),
    "review_sha256": hashlib.sha256((folder / "review.glb").read_bytes()).hexdigest(),
}
(folder / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
print("HI3D_REVIEW_GEOMETRY_OK", json.dumps(report), flush=True)
