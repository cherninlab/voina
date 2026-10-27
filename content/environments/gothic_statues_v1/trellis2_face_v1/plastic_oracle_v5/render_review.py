"""Render the actual oracle mesh using the shared studio and local detail cameras."""
from pathlib import Path
import math
import runpy

import bpy
from mathutils import Vector

root = Path(__file__).resolve().parent
state = runpy.run_path(str(root.parent.parent / "e01_crawling_v1/render_review.py"), run_name="__main__")
args, camera, scene, span = state["args"], state["camera"], state["scene"], state["span"]
for name, target, frame, azimuth, elevation in [
    ("face", (-.06, -.06, 1.17), .27, 0, 5),
    ("face45", (-.06, -.06, 1.17), .31, 40, 10),
    ("crown", (-.06, 0, 1.27), .40, 0, 80),
    ("head_back", (-.06, 0, 1.17), .43, 180, 10),
    ("raised_hand", (.25, -.02, 1.04), .34, 0, 10),
    ("hip_hand", (-.17, -.07, .81), .32, 0, 5),
    ("legs", (-.08, 0, .36), .74, 0, 5),
]:
    target = Vector(target)
    az, el = math.radians(azimuth), math.radians(elevation)
    camera.location = target + Vector((math.sin(az)*math.cos(el), -math.cos(az)*math.cos(el), math.sin(el))) * span * 3
    camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = frame
    scene.render.filepath = str((args.out / (name+".png")).resolve())
    bpy.ops.render.render(write_still=True)
print("PLASTIC_ORACLE_REVIEW_OK", flush=True)
