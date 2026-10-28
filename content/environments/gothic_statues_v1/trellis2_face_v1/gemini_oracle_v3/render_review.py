"""Render the supplied figure in the shared studio and its actual detail regions."""
from pathlib import Path
import runpy, math, sys
import bpy
from mathutils import Vector
root=Path(__file__).resolve().parent
studio=root.parent.parent/'e01_crawling_v1/render_review.py'
if any('reconstruction_s42_alpha_head' in arg for arg in sys.argv):
 source=studio.read_text();anchor='center=(lo+hi)/2;span=max(hi-lo)';assert source.count(anchor)==1
 source=source.replace(anchor,'center=Vector((0,0,.7));span=1.4')
 state={'__name__':'__main__','__file__':str(studio)};exec(compile(source,str(studio),'exec'),state)
else:
 state=runpy.run_path(str(studio),run_name='__main__')
args,camera,scene,span=state['args'],state['camera'],state['scene'],state['span']
is_multiview = 'multiview' in args.mesh.parts
hand_left = (-.23,-.10,.84) if is_multiview else (-.26,-.03,.79)
hand_right = (.23,-.10,.80) if is_multiview else (.10,-.10,.71)
for name,target,frame,azimuth,elevation in [
 ('face',(-.04,-.05,1.18),.28,0,5),('face45',(-.04,-.05,1.18),.32,40,8),
 ('left_hand',hand_left,.30,0,8),('right_hand',hand_right,.30,0,8),
 ('head_back',(-.04,0,1.18),.42,180,8),('feet',(0,0,.13),.50,0,12)]:
 target=Vector(target);az,el=math.radians(azimuth),math.radians(elevation)
 camera.location=target+Vector((math.sin(az)*math.cos(el),-math.cos(az)*math.cos(el),math.sin(el)))*span*3
 camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
 camera.data.ortho_scale=frame;scene.render.filepath=str((args.out/(name+'.png')).resolve())
 bpy.ops.render.render(write_still=True)
print('GEMINI_SCULPTURE_REVIEW_OK',flush=True)
