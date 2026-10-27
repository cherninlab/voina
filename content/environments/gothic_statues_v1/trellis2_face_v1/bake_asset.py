"""Bake real high-to-low tangent normals and AO, then export portable GLB."""
import argparse
import json
from pathlib import Path
import struct
import sys
import time

import bpy
import numpy as np

p=argparse.ArgumentParser()
for flag in ['high','low','out']:p.add_argument('--'+flag,type=Path,required=True)
p.add_argument('--size',type=int,default=4096)
args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);started=time.monotonic()
args.out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def load(path,name):
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    objects=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    assert len(objects)==1
    obj=objects[0];world=obj.matrix_world.copy();obj.parent=None;obj.matrix_world=world;obj.name=name
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for poly in obj.data.polygons:poly.use_smooth=True
    return obj

high=load(args.high,'Oracle dense source');low=load(args.low,'Oracle reduced')
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.003)
bpy.ops.object.mode_set(mode='OBJECT')
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16
scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.bake.margin=12;scene.render.bake.normal_space='TANGENT'
mat=bpy.data.materials.new('Marble with baked geometric detail');mat.use_nodes=True
mat.use_backface_culling=False
low.data.materials.clear();low.data.materials.append(mat)
nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value=(.58,.53,.45,1);bsdf.inputs['Roughness'].default_value=.73
images={}
for name,kind in [('normal','NORMAL'),('ao','AO')]:
    im=bpy.data.images.new(name,width=args.size,height=args.size,alpha=False)
    im.colorspace_settings.name='Non-Color';im.file_format='PNG';im.filepath_raw=str((args.out/(name+'.png')).resolve())
    node=nodes.new('ShaderNodeTexImage');node.image=im;nodes.active=node
    bpy.ops.object.select_all(action='DESELECT');low.select_set(True);bpy.context.view_layer.objects.active=low
    if kind=='NORMAL':
        high.select_set(True)
        bpy.ops.object.bake(type='NORMAL',use_selected_to_active=True,
            use_cage=True,cage_extrusion=.0005,max_ray_distance=.004)
        # Thin shells can return the opposite-facing side. Flip valid backface
        # normals into the tangent hemisphere; ray misses use neutral normals.
        # This is normal-data validation, not invented sculptural detail.
        pixels=np.empty(args.size*args.size*4,np.float32);im.pixels.foreach_get(pixels)
        pixels=pixels.reshape(-1,4);vectors=pixels[:,:3]*2-1
        lengths=np.linalg.norm(vectors,axis=1)
        valid=(lengths>.85)&(lengths<1.15)
        back=valid&(vectors[:,2]<0);vectors[back]*=-1
        vectors[valid]/=lengths[valid,None]
        vectors[~valid]=[0,0,1]
        pixels[:,:3]=vectors*.5+.5;pixels[:,3]=1
        im.pixels.foreach_set(pixels.ravel());im.update()
        normal_validation={'flipped_backface_texels':int(back.sum()),
            'neutral_ray_miss_or_unused_texels':int((~valid).sum()),
            'total_texels':len(valid),'method':'unit-vector validation and tangent hemisphere orientation'}
    else:
        high.hide_render=True
        bpy.ops.object.bake(type='AO',use_selected_to_active=False)
    im.save();images[name]=(im,node)
    print('BAKE_MAP_OK',name,flush=True)
normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1
links.new(images['normal'][1].outputs['Color'],normal.inputs['Color'])
links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
settings=nodes.new('ShaderNodeGroup');settings.node_tree=group
links.new(images['ao'][1].outputs['Color'],settings.inputs['Occlusion'])
bpy.ops.object.select_all(action='DESELECT');low.select_set(True);bpy.context.view_layer.objects.active=low
bpy.ops.export_scene.gltf(filepath=str((args.out/'statue.glb').resolve()),export_format='GLB',
    use_selection=True,export_normals=True,export_tangents=True,export_materials='EXPORT')
# Match geometry and vertex shading exactly when comparing with maps disabled.
raw=(args.out/'statue.glb').read_bytes();length,kind=struct.unpack_from('<II',raw,12)
gltf=json.loads(raw[20:20+length]);binary_chunks=raw[20+length:]
for material in gltf['materials']:
    if 'occlusionTexture' in material:material['occlusionTexture']['strength']=.35
def pack_gltf(document):
    encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    return struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary_chunks))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+binary_chunks
(args.out/'statue.glb').write_bytes(pack_gltf(gltf))
for material in gltf['materials']:
    material.pop('normalTexture',None);material.pop('occlusionTexture',None)
(args.out/'geometry_only.glb').write_bytes(pack_gltf(gltf))
for im,node in images.values():im.pack()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str((args.out/'bake.blend').resolve()),compress=True)
report={'high':str(args.high),'low':str(args.low),'high_triangles':len(high.data.polygons),
    'triangles':len(low.data.polygons),'map_size':args.size,'maps':['normal.png','ao.png'],
    'normal_convention':'OpenGL tangent-space +Y','bake':'Cycles selected-to-active, auto cage 0.5mm, ray distance 4mm',
    'normal_validation':normal_validation,
    'ambient_occlusion_material_strength':.35,
    'blender_version':bpy.app.version_string,'seconds':time.monotonic()-started}
(args.out/'bake.json').write_text(json.dumps(report,indent=2)+'\n')
print('NORMAL_LOD_BAKE_OK',json.dumps(report),flush=True)
