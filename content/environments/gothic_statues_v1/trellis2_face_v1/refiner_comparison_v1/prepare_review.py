"""Keep the raw mesh and produce a uniformly aligned neutral comparison."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import trimesh

parser = argparse.ArgumentParser()
parser.add_argument('folder', type=Path)
args = parser.parse_args()
folder = args.folder
mesh = trimesh.load(folder / 'raw.glb', force='mesh', process=False)
assert len(mesh.faces) and np.isfinite(mesh.vertices).all()
assert mesh.faces.min() >= 0 and mesh.faces.max() < len(mesh.vertices)
bounds = mesh.bounds.copy()
scale = 1.4 / max(mesh.extents)
translation = [0., .7, 0.]
mesh.vertices = (mesh.vertices - bounds.mean(axis=0)) * scale + np.array(translation)
mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral comparison', baseColorFactor=[180, 169, 149, 255], roughnessFactor=.78,
    doubleSided=False))
mesh.export(folder / 'review.glb', include_normals=True)
edges = np.sort(np.asarray(mesh.edges, dtype=np.uint64), axis=1)
_, counts = np.unique((edges[:, 0] << np.uint64(32)) | edges[:, 1], return_counts=True)
result = {'vertices': len(mesh.vertices), 'triangles': len(mesh.faces),
          'boundary_edges': int((counts == 1).sum()), 'non_manifold_edges': int((counts > 2).sum()),
          'finite_and_indices_valid': True, 'watertight': bool(mesh.is_watertight),
          'winding_consistent': bool(mesh.is_winding_consistent),
          'transform': {'input_bbox_center': bounds.mean(axis=0).tolist(), 'uniform_scale': scale,
                        'translation': translation},
          'changes': 'Uniform centering, scale and neutral material only; no repair or simplification',
          'raw_sha256': hashlib.sha256((folder / 'raw.glb').read_bytes()).hexdigest(),
          'review_sha256': hashlib.sha256((folder / 'review.glb').read_bytes()).hexdigest()}
(folder / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
print('HUNYUAN21_REVIEW_READY', json.dumps(result), flush=True)
