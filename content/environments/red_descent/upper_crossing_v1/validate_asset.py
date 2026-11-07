"""Check the exported meshes, including their topology after welding split normals."""
import hashlib
import json
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parents[1] / "procedural_architecture_v1/passages/return_gallery.glb"


def topology(filename):
    scene = trimesh.load(ROOT / filename, force="scene")
    results = {}
    for node in scene.graph.nodes_geometry:
        transform, name = scene.graph[node]
        mesh = scene.geometry[name].copy()
        mesh.apply_transform(transform)
        assert np.isfinite(mesh.vertices).all(), node
        normal_alignment = np.einsum("ij,ij->i", mesh.vertex_normals[mesh.faces].mean(axis=1), mesh.face_normals)
        assert (normal_alignment > 0).all(), (filename, node, "Inward shading normals")
        mesh.merge_vertices(merge_tex=True, merge_norm=True)
        incident = np.bincount(mesh.edges_unique_inverse)
        results[node] = {
            "triangles": len(mesh.faces),
            "boundary_edges": int((incident == 1).sum()),
            "nonmanifold_edges": int((incident > 2).sum()),
            "winding_consistent": bool(mesh.is_winding_consistent),
            "euler_number": mesh.euler_number,
            "volume": float(mesh.volume),
        }
        assert results[node]["boundary_edges"] == 0, (filename, node, results[node])
        assert results[node]["nonmanifold_edges"] == 0, (filename, node, results[node])
        assert mesh.is_winding_consistent, (filename, node)
    return results


def collision_vertices(scene):
    result = {}
    for node in scene.graph.nodes_geometry:
        if not node.startswith("Collision"):
            continue
        transform, name = scene.graph[node]
        mesh = scene.geometry[name].copy()
        mesh.apply_transform(transform)
        result[node] = sorted(set(tuple(point) for point in np.round(mesh.vertices, 5)))
    return result


report = {}
for filename in ["rock_lod0.glb", "rock_lod1.glb", "rock_cliff.glb"]:
    report[filename] = topology(filename)
source = trimesh.load(SOURCE, force="scene")
gallery = trimesh.load(ROOT / "gallery.glb", force="scene")
before = collision_vertices(source)
after = collision_vertices(gallery)
assert len(before) == 5 and before == after, "Collision geometry changed during export"
report["gallery_collision"] = {"meshes": len(before), "vertex_positions_unchanged": True}
roof = {}
for node in gallery.graph.nodes_geometry:
    if node.startswith("Stone-stone_upper_gallery_roof") or node.startswith("Mortar_return_gallery") or node.startswith("Stone-stone_gallery_exterior"):
        transform, name = gallery.graph[node]
        mesh = gallery.geometry[name].copy()
        mesh.merge_vertices(merge_tex=True, merge_norm=True)
        incident = np.bincount(mesh.edges_unique_inverse)
        roof[node] = {"triangles": len(mesh.faces), "boundary_edges": int((incident == 1).sum()),
                      "nonmanifold_edges": int((incident > 2).sum())}
        assert not (incident == 1).any() and not (incident > 2).any(), roof[node]
report["roof_and_mortar"] = roof
assert len(roof) == 7, "Missing exterior roof, facing or mortar mass"
report["sha256"] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ["gallery.glb", "rock_lod0.glb", "rock_lod1.glb", "rock_cliff.glb"]}
(ROOT / "mesh-validation.json").write_text(json.dumps(report, indent=2) + "\n")
print("UPPER_ASSETS_VALID", json.dumps(report), flush=True)
