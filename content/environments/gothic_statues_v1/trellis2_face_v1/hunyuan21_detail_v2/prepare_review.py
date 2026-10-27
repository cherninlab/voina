"""Preserve raw geometry and place crop studies near their original body regions."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import trimesh

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('job')
args = parser.parse_args()
folder = root / args.job
receipt = json.loads((folder / 'receipt.json').read_text())
assert receipt['status'] == 'complete'
mesh = trimesh.load(folder / 'raw.glb', force='mesh', process=False)
assert len(mesh.faces) and np.isfinite(mesh.vertices).all()
assert mesh.faces.min() >= 0 and mesh.faces.max() < len(mesh.vertices)
if args.job == 'body512':
    transform = json.loads((root.parent / 'hunyuan21_oracle_v1/384_s42_maskfix/validation.json').read_text())['transform']
    center = np.array(transform['input_bbox_center'])
    scale = transform['uniform_scale']
    target = np.array(transform['translation'])
else:
    if args.job == 'head384':
        span, target = .23, [-.065, 1.15, .025]
    elif args.job.startswith('head_context'):
        span, target = .34, [-.072, 1.115, .025]
    elif args.job.startswith('raised'):
        span, target = .21, [.19, 1.01, .07]
    elif args.job.startswith('hip'):
        span, target = .18, [-.20, .80, .07]
    elif args.job.startswith('upper_body'):
        span, target = .72, [0., 1.04, .025]
    else:
        raise ValueError(args.job)
    center = mesh.bounds.mean(0)
    scale = span / max(mesh.extents)
    target = np.array(target)
mesh.vertices = (mesh.vertices - center) * scale + target
mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral comparison', baseColorFactor=[180, 169, 149, 255], roughnessFactor=.78,
    doubleSided=False))
mesh.export(folder / 'review.glb', include_normals=True)
edges = np.sort(np.asarray(mesh.edges, dtype=np.uint64), axis=1)
_, counts = np.unique((edges[:, 0] << np.uint64(32)) | edges[:, 1], return_counts=True)
result = {'vertices': len(mesh.vertices), 'triangles': len(mesh.faces),
          'finite_and_indices_valid': True, 'boundary_edges': int((counts == 1).sum()),
          'non_manifold_edges': int((counts > 2).sum()), 'watertight': bool(mesh.is_watertight),
          'winding_consistent': bool(mesh.is_winding_consistent),
          'transform': {'center': center.tolist(), 'scale': scale, 'target': target.tolist()},
          'raw_sha256': hashlib.sha256((folder / 'raw.glb').read_bytes()).hexdigest(),
          'review_sha256': hashlib.sha256((folder / 'review.glb').read_bytes()).hexdigest(),
          'method': 'Uniform transform and neutral material only. Crop studies are separate geometry, not merged.'}
(folder / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
print('DETAIL_REVIEW_READY', args.job, result['triangles'], flush=True)
