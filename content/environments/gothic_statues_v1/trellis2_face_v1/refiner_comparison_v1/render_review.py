"""Render actual trial meshes with matching studio lighting."""
from pathlib import Path
import runpy, math
import bpy
from mathutils import Vector
root=Path(__file__).resolve().parent
state=runpy.run_path(str(root.parent.parent/'e01_crawling_v1/render_review.py'),run_name='__main__')
args,camera,scene,span=state['args'],state['camera'],state['scene'],state['span']
case='pillar' if 'pillar' in args.mesh.parts else 'tunic'
regions={'tunic':[('face',(-.04,-.03,1.20),.30),('left_hand',(-.30,-.02,.74),.30),('right_hand',(.16,-.08,.81),.30)],'pillar':[('face',(-.09,-.04,1.19),.30),('left_hand',(-.28,-.02,.64),.30),('right_hand',(.16,.04,.87),.30)]}[case]
for name,target,frame in regions:
 target=Vector(target);camera.location=target+Vector((0,-1,.06))*span*3
 camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
 camera.data.ortho_scale=frame;scene.render.filepath=str((args.out/(name+'.png')).resolve())
 bpy.ops.render.render(write_still=True)
print('REFINER_DETAIL_REVIEW_OK',flush=True)
