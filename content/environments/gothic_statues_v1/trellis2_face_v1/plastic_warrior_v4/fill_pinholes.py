"""Close small boundary loops with MeshLab while preserving existing geometry."""
import argparse
import json
from pathlib import Path
import time

import numpy as np
import pymeshlab as ml
import trimesh

parser = argparse.ArgumentParser()
parser.add_argument("folder", type=Path)
args = parser.parse_args()
folder = args.folder.resolve()
source = trimesh.load(folder / "clean_high.glb", force="mesh", process=False)
v = np.array(source.vertices)
f = np.array(source.faces)
before_boundary = int(np.count_nonzero(np.bincount(source.edges_unique_inverse) == 1))
started = time.monotonic()
ms = ml.MeshSet()
ms.add_mesh(ml.Mesh(vertex_matrix=v, face_matrix=f.astype(np.int32)))
ms.apply_filter("meshing_close_holes", maxholesize=16, selected=False,
                newfaceselected=True, selfintersection=True, refinehole=False)
result = ms.current_mesh()
out_v = result.vertex_matrix()
out_f = result.face_matrix()
assert len(out_v) == len(v), "Hole fill unexpectedly changed vertex count"
assert np.array_equal(out_v, v), "Existing vertex positions changed"
assert len(out_f) >= len(f) and np.array_equal(out_f[:len(f)], f), "Existing triangles changed"
mesh = trimesh.Trimesh(out_v, out_f, process=False)
mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name="Neutral geometry inspection", baseColorFactor=[180, 169, 149, 255],
    metallicFactor=0, roughnessFactor=.78, doubleSided=True))
mesh.export(folder / "pinholes_filled.glb", include_normals=True)
boundary_after = int(np.count_nonzero(np.bincount(mesh.edges_unique_inverse) == 1))
report = {
    "method": "PyMeshLab meshing_close_holes",
    "max_boundary_loop_edges": 16,
    "self_intersection_checks": True,
    "refinement": False,
    "existing_vertices_byte_identical": True,
    "existing_triangles_retained": True,
    "source_triangles": len(f),
    "result_triangles": len(out_f),
    "added_triangles": len(out_f)-len(f),
    "boundary_edges_before": before_boundary,
    "boundary_edges_after": boundary_after,
    "watertight": bool(mesh.is_watertight),
    "winding_consistent": bool(mesh.is_winding_consistent),
    "seconds": time.monotonic()-started,
}
(folder / "pinholes.json").write_text(json.dumps(report, indent=2)+"\n")
print("PINHOLE_FILL_OK", json.dumps(report), flush=True)
