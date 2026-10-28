"""Remove only two detached, thin full-height side planes from the RGB trial."""
import json
from pathlib import Path

import numpy as np
import trimesh

root = Path(__file__).resolve().parent / 'reconstruction_s42'
mesh = trimesh.load(root / 'review.glb', force='mesh', process=False)
labels = trimesh.graph.connected_component_labels(mesh.edges, node_count=len(mesh.vertices))
face_labels = labels[mesh.faces[:, 0]]
remove = []
records = []
for label in np.unique(labels):
    vertices = mesh.vertices[labels == label]
    extents = np.ptp(vertices, axis=0)
    center = (vertices.min(0) + vertices.max(0)) * .5
    if extents[0] < .020 and extents[1] > 1.2 and extents[2] > .60 and abs(center[0]) > .40:
        remove.append(label)
        records.append({'component': int(label), 'triangles': int((face_labels == label).sum()),
                        'extents': extents.tolist(), 'center': center.tolist()})
assert len(remove) == 2, 'Unexpected components; inspect before filtering'
keep = ~np.isin(face_labels, remove)
clean = mesh.submesh([keep], append=True)
assert len(clean.faces) == int(keep.sum())
out = root / 'clean'
out.mkdir(exist_ok=True)
clean.export(out / 'review.glb', include_normals=True)
(out / 'receipt.json').write_text(json.dumps({'method': 'Remove only two detached full-height side planes; retain every other component. No vertex displacement, smoothing or remeshing.',
    'removed': records, 'original_triangles': len(mesh.faces), 'triangles': len(clean.faces),
    'removed_triangles': int((~keep).sum()), 'source': '../review.glb'}, indent=2) + '\n')
print('DETACHED_PLANES_REMOVED', len(clean.faces), flush=True)
