"""Reuse the mesh review, then show the highest reaching hand at close range."""
from pathlib import Path
import math
import runpy
import bpy
from mathutils import Vector

root=Path(__file__).resolve().parent
state=runpy.run_path(str(root.parent/'e01_crawling_v1/render_review.py'),run_name='__main__')
args=state['args'];camera=state['camera'];scene=state['scene']
points=[o.matrix_world@v.co for o in state['objects'] for v in o.data.vertices]
low=min(v.z for v in points);height=max(v.z for v in points)-low
upper=[v for v in points if v.z>low+height*.96]
target=sum(upper,Vector())/len(upper)-Vector((0,0,height*.06))
scene.render.resolution_x=700;scene.render.resolution_y=700
camera.data.ortho_scale=height*.35
for name,azimuth in [('hand_front',0),('hand_back',180)]:
    angle=math.radians(azimuth)
    camera.location=target+Vector((math.sin(angle),-math.cos(angle),.06))*height*3
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str((args.out/f'{args.prefix}_{name}.png').resolve())
    bpy.ops.render.render(write_still=True)
print('SINGLE_HAND_REVIEW_OK',flush=True)
