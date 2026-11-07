"""Blender-only reduction of the local TripoSG rock, with two static LODs."""
import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root / "mesh/rock_solid.glb"))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
assert len(meshes) == 1
rock = meshes[0]
matrix = rock.matrix_world.copy()
rock.parent = None
rock.data.transform(matrix)
rock.matrix_world.identity()
points = [vertex.co for vertex in rock.data.vertices]
low = Vector(tuple(min(point[i] for point in points) for i in range(3)))
high = Vector(tuple(max(point[i] for point in points) for i in range(3)))
origin = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
for vertex in rock.data.vertices:
    vertex.co = (vertex.co - origin) / (high.z - low.z)
raw_count = len(rock.data.polygons)
# The single-view source has gaps. A solid voxel shell closes them before LOD reduction.
bpy.ops.object.select_all(action="DESELECT")
rock.select_set(True)
bpy.context.view_layer.objects.active = rock
rock.data.remesh_voxel_size = 0.0075
rock.data.remesh_voxel_adaptivity = 0.0
bpy.ops.object.voxel_remesh()
# Remove the voxel staircase without rounding away the broad rock silhouette.
smooth = rock.modifiers.new("VoxelSurfaceRelax", "SMOOTH")
smooth.factor = 0.8
smooth.iterations = 8
bpy.ops.object.modifier_apply(modifier=smooth.name)
source_count = sum(len(face.vertices) - 2 for face in rock.data.polygons)
report = {"source_triangles": raw_count, "voxel_shell_faces": source_count, "voxel_size_unit_height": 0.0075, "finishing": "Closed voxel shell, Blender quadric reduction, Y-up unit height GLBs", "outputs": {}}
for level, budget in [(0, 18000), (1, 4500)]:
    obj = rock.copy()
    obj.data = rock.data.copy()
    obj.name = f"UpperRock_LOD{level}"
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    decimate = obj.modifiers.new("Budget", "DECIMATE")
    decimate.ratio = budget / source_count
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    shell = bmesh.new()
    shell.from_mesh(obj.data)
    bmesh.ops.remove_doubles(shell, verts=list(shell.verts), dist=0.000001)
    bmesh.ops.dissolve_degenerate(shell, edges=list(shell.edges), dist=0.000001)
    boundary = [edge for edge in shell.edges if edge.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(shell, edges=boundary, sides=0)
    bmesh.ops.triangulate(shell, faces=list(shell.faces))
    bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
    assert all(edge.is_manifold for edge in shell.edges), f"Open or nonmanifold rock LOD{level}"
    shell.to_mesh(obj.data)
    shell.free()
    obj.data.update()
    obj.data.calc_loop_triangles()
    obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
    # Keep crisp large planes rather than smoothing the rock into a pebble.
    for face in obj.data.polygons:
        face.use_smooth = False
    bpy.ops.export_scene.gltf(
        filepath=str(root / f"rock_lod{level}.glb"), export_format="GLB",
        use_selection=True, export_materials="NONE", export_animations=False,
    )
    report["outputs"][f"lod{level}"] = {"triangles": len(obj.data.polygons), "vertices": len(obj.data.vertices), "boundary_edges": 0, "nonmanifold_edges": 0}
(root / "rock-build.json").write_text(json.dumps(report, indent=2) + "\n")
print("ROCK_REDUCED", json.dumps(report), flush=True)
