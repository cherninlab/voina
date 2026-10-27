"""Build a local hair/crown repair; approved face is excluded during composition."""
import json
from pathlib import Path
import sys
import time

import bpy
import bmesh
import numpy as np

ROOT=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT))
from glb_io import read_glb,array
from regions import head_region,protected_face,face_radius

started=time.monotonic()
doc,binary=read_glb(ROOT.parent/'baked_150k/statue.glb')
primitive=doc['meshes'][0]['primitives'][0]
vertices=array(doc,binary,primitive['attributes']['POSITION'])
faces=array(doc,binary,primitive['indices']).reshape(-1,3)
head=faces[head_region(vertices[faces].mean(1))]
# Convert glTF Y-up to Blender Z-up, with the same scale and origin.
points=vertices[:,[0,2,1]]*np.array([1,-1,1])
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
mesh=bpy.data.meshes.new('Local head source');mesh.from_pydata(points.tolist(),[],head.tolist());mesh.update()
obj=bpy.data.objects.new('Hair and crown repair',mesh);bpy.context.collection.objects.link(obj)
bpy.context.view_layer.objects.active=obj;obj.select_set(True)
bm=bmesh.new();bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
shell=obj.modifiers.new('Bounded thickness for broken hair sheets','SOLIDIFY')
shell.thickness=.004;shell.offset=0;shell.use_rim=True
bpy.ops.object.modifier_apply(modifier=shell.name)
# Close the missing cranium beneath the hair. The facial surface is never used
# from this repair; composition retains its original geometry and material data.
bpy.ops.mesh.primitive_uv_sphere_add(segments=96,ring_count=64,
    location=(-.005,-.032,1.235))
cap=bpy.context.object;cap.name='Rebuilt crown beneath hair'
for v in cap.data.vertices:
    x,y,z=v.co
    theta=np.arctan2(y,x);vertical=np.clip(z,-1,1)
    wave=.005*np.sin(14*theta+4*vertical)*max(0,1-vertical*vertical)
    # Sweep broad S-shaped stone hair ridges front-to-back over the repair.
    # These are real relief geometry and are included in the normal-map bake.
    phase=12*np.pi*(x+.12*np.sin(2*np.pi*y))
    relief=.004*np.sin(phase)*max(0,float(z))**.5
    v.co=(x*.072*(1+wave),y*.105*(1+wave),z*.043*(1+wave)+relief)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);cap.select_set(True)
bpy.context.view_layer.objects.active=obj;bpy.ops.object.join()
# A small fitted lobe meets the frontal rim at the right temple; the main
# ellipsoid alone leaves that asymmetric part of the opening uncovered.
bpy.ops.mesh.primitive_uv_sphere_add(segments=64,ring_count=32,location=(.052,-.085,1.244))
join=bpy.context.object;join.name='Frontal crown join'
for v in join.data.vertices:v.co=(v.co.x*.023,v.co.y*.030,v.co.z*.030)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);join.select_set(True)
bpy.context.view_layer.objects.active=obj;bpy.ops.object.join()
mod=obj.modifiers.new('Unite crown and local hair','REMESH');mod.mode='VOXEL'
mod.voxel_size=.0014;mod.adaptivity=.06;mod.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=mod.name)
smooth=obj.modifiers.new('Soften broken hair edges','SMOOTH');smooth.factor=.65;smooth.iterations=5
bpy.ops.object.modifier_apply(modifier=smooth.name)
for f in obj.data.polygons:f.use_smooth=True
mat=bpy.data.materials.new('Repaired hair marble');mat.use_nodes=True
mat.use_backface_culling=False
bsdf=mat.node_tree.nodes['Principled BSDF']
bsdf.inputs['Base Color'].default_value=(.58,.53,.45,1);bsdf.inputs['Roughness'].default_value=.73
obj.data.materials.clear();obj.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'surround_full.glb'),export_format='GLB',use_selection=True)
(ROOT/'repair.json').write_text(json.dumps({'method':'Local Blender sheet repair, cranial cap, VDB union and bounded smoothing',
    'voxel_size_m':.0014,'sheet_thickness_m':.004,'smoothing_iterations':5,
    'scalp_center_gltf':[-.005,1.235,.032],'scalp_radii_m':[.072,.043,.105],
    'frontal_join_center_gltf':[.052,1.244,.085],'frontal_join_radii_m':[.023,.030,.030],
    'crown_hair_relief_m':.004,'crown_hair_pattern':'Swept S-shaped geometric ridges',
    'source_head_triangles':len(head),'polygons_before_face_exclusion':len(obj.data.polygons),
    'seconds':time.monotonic()-started},indent=2)+'\n')
print('HEAD_SURROUND_REPAIR_OK',flush=True)
