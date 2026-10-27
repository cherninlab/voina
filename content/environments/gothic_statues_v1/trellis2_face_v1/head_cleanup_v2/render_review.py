"""Add crown and back-of-head evidence to the existing geometry review."""
from pathlib import Path
import runpy
import bpy
from mathutils import Vector

root=Path(__file__).resolve().parent
state=runpy.run_path(str(root.parent/'render_detail.py'),run_name='__main__')
cam=state['cam'];scene=state['scene'];args=state['args']
target=Vector((.015,0,1.24));cam.data.ortho_scale=.41
for name,offset in [('crown',(0,-.40,1)),('top',(0,.001,1)),('back',(0,1,.08)),('back45',(-.7,.8,.3))]:
    cam.location=target+Vector(offset)
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str((args.out/(name+'.png')).resolve())
    bpy.ops.render.render(write_still=True)
print('HEAD_CROWN_REVIEW_OK',flush=True)
