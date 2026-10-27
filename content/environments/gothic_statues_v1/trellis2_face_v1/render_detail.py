"""Render matching actual-geometry face and full-body views in Blender."""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

p=argparse.ArgumentParser()
p.add_argument('--mesh',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--head-only',action='store_true')
p.add_argument('--keep-material',action='store_true')
args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
args.out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(args.mesh.resolve()))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box]
lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
center=(lo+hi)/2;span=max(hi-lo)
mat=bpy.data.materials.new('Neutral marble');mat.use_nodes=True
shader=mat.node_tree.nodes.get('Principled BSDF')
shader.inputs['Base Color'].default_value=(.58,.53,.45,1)
shader.inputs['Roughness'].default_value=.73
for obj in objects:
    if not args.keep_material:
        obj.data.materials.clear();obj.data.materials.append(mat)
    for f in obj.data.polygons:f.use_smooth=True
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
scene.cycles.use_denoising=True;scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=800;scene.render.resolution_y=800
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.world=bpy.data.worlds.new('Review');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.065,.072,.08,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
for name,offset,power,size in [('Key',(-2,-3,4),900,3),('Fill',(3,-1,2),500,3),('Rim',(1,3,3),1100,2)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size*span/2
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light)
    light.location=center+Vector(offset)*span
    light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('Review camera',bpy.data.cameras.new('Review camera'))
scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO'
if args.head_only:
    target=center;frame=span*1.15
else:
    target=Vector((0,-.015,1.235));frame=.235
for name,deg in [('face',0),('face45',45),('profile',90)]:
    az=math.radians(deg);cam.location=target+Vector((math.sin(az),-math.cos(az),.01))*span*3
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=frame
    scene.render.filepath=str((args.out/(name+'.png')).resolve());bpy.ops.render.render(write_still=True)
if not args.head_only:
    cam.location=center+Vector((-.65,-2.9,.55))*span
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=span*1.17
    scene.render.filepath=str((args.out/'body.png').resolve());bpy.ops.render.render(write_still=True)
print('FACE_DETAIL_RENDER_OK',flush=True)
