"""Close reconstruction perforations volumetrically before Blender LOD reduction.

Run with the existing CherninLab3D Python environment (trimesh/scipy/skimage).
"""
import json
from pathlib import Path

import numpy as np
from scipy import ndimage
import trimesh

ROOT = Path(__file__).resolve().parent
source = trimesh.load(ROOT / "mesh/rock_raw.glb", force="mesh")
# The inference output is Y-up. Normalize before choosing the voxel resolution.
height = source.extents[1]
source.vertices -= [(source.bounds[0, 0] + source.bounds[1, 0]) / 2,
                    source.bounds[0, 1], (source.bounds[0, 2] + source.bounds[1, 2]) / 2]
source.vertices /= height
pitch = 0.0125
voxels = source.voxelized(pitch)
# Pad before closing so silhouette faces at the grid boundary are retained.
for closing in range(3, 9):
    occupancy = np.pad(voxels.matrix, closing + 2)
    occupancy = ndimage.binary_closing(occupancy, iterations=closing)
    # Fill between the outer surfaces along each voxel axis. This keeps the
    # stepped silhouette but removes inferred tunnels inside the monolith.
    for axis in (2, 0, 1):
        forward = np.maximum.accumulate(occupancy, axis=axis)
        backward = np.flip(np.maximum.accumulate(np.flip(occupancy, axis=axis), axis=axis), axis=axis)
        occupancy |= forward & backward
    occupancy = ndimage.binary_fill_holes(occupancy)
    labels, count = ndimage.label(occupancy)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    occupancy = labels == sizes.argmax()
    solid = trimesh.voxel.ops.matrix_to_marching_cubes(occupancy, pitch=pitch)
    solid.apply_translation(voxels.translation - pitch * (closing + 2))
    if solid.euler_number == 2:
        break
assert solid.is_watertight and solid.is_winding_consistent and solid.euler_number == 2
solid.vertex_normals = trimesh.geometry.mean_vertex_normals(len(solid.vertices), solid.faces, solid.face_normals)
solid.export(ROOT / "mesh/rock_solid.glb")
report = {"voxel_size_unit_height": pitch, "closing_radius_voxels": closing,
          "triangles": len(solid.faces), "watertight": bool(solid.is_watertight),
          "euler_number": solid.euler_number, "removed_components": count - 1,
          "method": "Voxelize, morphological close and directional solid fill, keep largest solid, marching cubes"}
(ROOT / "solidification.json").write_text(json.dumps(report, indent=2) + "\n")
print("ROCK_SOLID", json.dumps(report), flush=True)
