"""Render actual exported geometry in Blender background for pose/mesh review."""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

parser=argparse.ArgumentParser()
parser.add_argument('--mesh',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--prefix',default='raw')
parser.add_argument('--size',type=int,default=900)
parser.add_argument('--keep-material',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
args.out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(args.mesh.resolve()))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box]
lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
center=(lo+hi)/2;span=max(hi-lo)
material=bpy.data.materials.new('Neutral limestone geometry review');material.use_nodes=True
bsdf=material.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value=(.58,.53,.45,1)
bsdf.inputs['Roughness'].default_value=.73
for obj in objects:
    if not args.keep_material:
        obj.data.materials.clear();obj.data.materials.append(material)
    for poly in obj.data.polygons:poly.use_smooth=True
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=args.size;scene.render.resolution_y=args.size;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.world=bpy.data.worlds.new('Review world');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.065,.072,.08,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.view_settings.view_transform='AgX'
camera=bpy.data.objects.new('Review camera',bpy.data.cameras.new('Review camera'))
scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
camera.data.ortho_scale=span*1.24
for name,offset,power,size in [('Key',(-2,-3,4),900,3),('Fill',(3,-1,2),500,3),('Rim',(1,3,3),1100,2)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size*span/2
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light)
    light.location=center+Vector(offset)*span
    light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
records=[]
for name,azimuth,elevation in [('hero',315,18),('front',0,5),('front45',45,15),('left',90,5),('back135',135,15),('back',180,5),('right',270,5)]:
    az=math.radians(azimuth);el=math.radians(elevation)
    camera.location=center+Vector((math.sin(az)*math.cos(el),-math.cos(az)*math.cos(el),math.sin(el)))*span*3
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=span*1.24
    if name=='hero':
        bpy.context.view_layer.update()
        projected=[camera.matrix_world.inverted()@p for p in points]
        camera.data.ortho_scale=max(max(p.x for p in projected)-min(p.x for p in projected),
            max(p.y for p in projected)-min(p.y for p in projected))*1.08
    path=args.out/f'{args.prefix}_{name}.png';scene.render.filepath=str(path.resolve())
    bpy.ops.render.render(write_still=True)
    records.append({'file':path.name,'azimuth':azimuth,'elevation':elevation})
(args.out/f'{args.prefix}_views.json').write_text(json.dumps({'source_mesh':str(args.mesh.resolve()),
    'actual_geometry_renders':True,'world_bounds':[list(lo),list(hi)],'blender_version':bpy.app.version_string,'views':records},indent=2)+'\n')
print('REVIEW_RENDER_OK',flush=True)
