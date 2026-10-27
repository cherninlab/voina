"""Reuse the existing mesh renderer, then inspect the head and both hands."""
from pathlib import Path
import math
import runpy

import bpy
from mathutils import Vector

root = Path(__file__).resolve().parent
state = runpy.run_path(str(root.parent.parent / "e01_crawling_v1/render_review.py"), run_name="__main__")
args = state["args"]
camera, scene, span = state["camera"], state["scene"], state["span"]
for name, target, frame, azimuth, elevation in [
    ("face", (.035, -.06, 1.17), .27, 0, 5),
    ("face45", (.035, -.06, 1.17), .31, 40, 10),
    ("crown", (.025, 0, 1.27), .40, 0, 80),
    ("head_back", (.035, 0, 1.17), .44, 180, 10),
    ("weapon_hand", (-.22, -.01, .67), .32, 0, 5),
    ("free_hand", (.24, -.01, .67), .30, 0, 5),
]:
    target = Vector(target)
    az, el = math.radians(azimuth), math.radians(elevation)
    camera.location = target + Vector((math.sin(az)*math.cos(el), -math.cos(az)*math.cos(el), math.sin(el))) * span * 3
    camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = frame
    scene.render.filepath = str((args.out / (name+".png")).resolve())
    bpy.ops.render.render(write_still=True)
print("PLASTIC_WARRIOR_REVIEW_OK", flush=True)
