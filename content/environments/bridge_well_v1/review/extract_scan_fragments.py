"""Crop two dense vertical wall patches, preserve UVs, decimate and export glTF.

Run with Blender --background --factory-startup --python this_file.py.
Source files and their bitmap textures remain unchanged.
"""
from pathlib import Path
from collections import defaultdict
import json
import math
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "scan_fragments"
OUT.mkdir(exist_ok=True)
records = []
for scan_id in ("001", "002"):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "review" / ("scan-" + scan_id + ".blend")))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        transform = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = transform
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "scan_" + scan_id + "_wall_fragment"
    # Dense vertical area is a reproducible selection criterion, not an invented wall.
    groups = defaultdict(float)
    for face in obj.data.polygons:
        normal = face.normal
        if abs(normal.z) > 0.35:
            continue
        axis = 0 if abs(normal.x) > abs(normal.y) else 1
        tangent = 1 - axis
        point = face.center
        key = (axis, 1 if normal[axis] > 0 else -1,
               math.floor(point[axis] / 0.5), math.floor(point[tangent] / 2.5), math.floor(point.z / 3.0))
        groups[key] += face.area
    key = max(groups, key=groups.get)
    axis, sign, normal_bin, tangent_bin, height_bin = key
    tangent = 1 - axis
    plane = (normal_bin + 0.5) * 0.5
    along = (tangent_bin + 0.5) * 2.5
    high = (height_bin + 0.5) * 3.0
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    discard = []
    for face in bm.faces:
        point = face.calc_center_median()
        if abs(point[axis] - plane) > 0.48 or abs(point[tangent] - along) > 1.35 or abs(point.z - high) > 1.6:
            discard.append(face)
    bmesh.ops.delete(bm, geom=discard, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0005)
    for vertex in bm.verts:
        point = vertex.co.copy()
        vertex.co = Vector((point[tangent] - along, -sign * (point[axis] - plane), point.z - high))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    before = len(obj.data.polygons)
    modifier = obj.modifiers.new("bounded_triangle_budget", "DECIMATE")
    modifier.ratio = min(1.0, 12000 / max(1, before))
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    path = OUT / ("scan_" + scan_id + "_wall_fragment.glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                             export_materials="EXPORT", export_image_format="AUTO", export_cameras=False,
                             export_lights=False, export_yup=True)
    records.append({"scan": scan_id, "file": path.relative_to(ROOT).as_posix(), "selection_bins": list(key),
                    "source_world_patch_center": {"normal": plane, "tangent": along, "height": high},
                    "selection_half_extents_m": [1.35, 0.48, 1.6], "polygons_before": before,
                    "polygons_after": len(obj.data.polygons), "bytes": path.stat().st_size,
                    "changes": "Selected existing wall faces, removed loose vertices, welded0.5mm, reoriented, decimated; UVs and source bitmap textures retained. No collision."})
(ROOT / "review/scan_fragments.json").write_text(json.dumps(records, indent=2) + "\n")
print("SCAN_FRAGMENTS_OK: ", records)
