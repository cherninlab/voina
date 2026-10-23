"""Blender background geometry inspection. Does not alter source scans or bitmap textures."""
from pathlib import Path
import json
import math
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
report = []
for scan_id in ("001", "002"):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    source = Path("/Users/theochernin/Downloads") / ("theo_3d_scan_" + scan_id)
    bpy.ops.import_scene.gltf(filepath=str(source / "scene.gltf"))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    lower = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    upper = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    center = (lower + upper) / 2
    size = upper - lower
    report.append({"scan": scan_id, "blender_world_bounds": [list(lower), list(upper)], "size": list(size),
                   "objects": [{"name": obj.name, "vertices": len(obj.data.vertices), "polygons": len(obj.data.polygons)} for obj in meshes]})
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (0.035, 0.035, 0.035)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    camera_data = bpy.data.cameras.new("inspection_camera")
    camera = bpy.data.objects.new("inspection_camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(size) * 1.5
    camera_data.clip_end = max(size) * 15
    for view, direction in (("front", Vector((1.1, -1.3, 0.9))), ("back", Vector((-1.1, 1.3, 0.9)))):
        camera.location = center + direction * max(size)
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(OUT / ("scan-" + scan_id + "-" + view + ".png"))
        bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / ("scan-" + scan_id + ".blend")))
(OUT / "scan_geometry.json").write_text(json.dumps(report, indent=2) + "\n")
print("SCAN_INSPECTION_OK: two originals, four geometry renders")
