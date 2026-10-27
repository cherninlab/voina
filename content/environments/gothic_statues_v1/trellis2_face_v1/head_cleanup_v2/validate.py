"""Prove protected face/body data preservation and physical crown coverage."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np

ROOT=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT))
from glb_io import read_glb,array
from regions import head_region,protected_face,face_radius

old,ob=read_glb(ROOT.parent/'baked_150k/statue.glb')
new,nb=read_glb(ROOT/'statue.glb')
op=old['meshes'][0]['primitives'][0];np0=new['meshes'][0]['primitives'][0]
assert np0['attributes']==op['attributes']
assert nb[:len(ob)]==ob,'Original geometry/image payload was modified'
assert new['materials'][:len(old['materials'])]==old['materials']
assert len(new['images'])>=4
for material in new['materials']:
    assert 'normalTexture' in material and 'occlusionTexture' in material
    assert material['normalTexture']['index']<len(new['textures'])
    assert material['occlusionTexture']['index']<len(new['textures'])
for mesh in new['meshes']:
    for p in mesh['primitives']:
        v=array(new,nb,p['attributes']['POSITION']);f=array(new,nb,p['indices'])
        assert np.isfinite(v).all() and f.min()>=0 and f.max()<len(v)
vertices=array(old,ob,op['attributes']['POSITION']);faces=array(old,ob,op['indices']).reshape(-1,3)
out=array(new,nb,np0['indices']).reshape(-1,3)
protect=protected_face(vertices[faces],radius=.99).any(1)
remove=head_region(vertices[faces].mean(1))&~protect
assert np.array_equal(out,faces[~remove]),'Unexpected original faces changed'
protected_vertices=np.unique(faces[protect])
face_hash=hashlib.sha256(vertices[protected_vertices].tobytes()).hexdigest()

def bvh(document,binary):
    all_vertices=[];all_faces=[];offset=0
    for mesh in document['meshes']:
        for p in mesh['primitives']:
            v=array(document,binary,p['attributes']['POSITION'])
            f=array(document,binary,p['indices']).reshape(-1,3)
            all_vertices.extend(v.tolist());all_faces.extend((f+offset).tolist());offset+=len(v)
    return BVHTree.FromPolygons(all_vertices,all_faces,all_triangles=True)

before=bvh(old,ob);after=bvh(new,nb)
tests=[]
for x in np.linspace(-.06,.075,19):
    for z in np.linspace(-.05,.115,22):
        in_crown=((x+.005)/.055)**2+((z-.032)/.08)**2<1
        in_join=((x-.052)/.018)**2+((z-.085)/.023)**2<1
        if not (in_crown or in_join):continue
        origin=Vector((float(x),1.45,float(z)));direction=Vector((0,-1,0))
        a=before.ray_cast(origin,direction)[0];b=after.ray_cast(origin,direction)[0]
        tests.append({'x':float(x),'z':float(z),'before_y':float(a.y) if a else None,
            'after_y':float(b.y) if b else None})
covered=sum(t['after_y'] is not None and t['after_y']>1.24 for t in tests)
assert covered==len(tests),'Repaired crown still contains an opening in the test area'

points=vertices[faces].mean(1)
core=protected_face(points,radius=.8)&(points[:,2]>.09)
points=points[core][::max(1,int(core.sum())//200)]
errors=[];changed=[]
for p in points:
    origin=Vector((float(p[0]),float(p[1]),.5));direction=Vector((0,0,-1))
    a=before.ray_cast(origin,direction)[0];b=after.ray_cast(origin,direction)[0]
    if a is not None and b is not None:
        error=abs(a.z-b.z);errors.append(error)
        if error>.00001:changed.append({'point':p.tolist(),'error':error})
assert len(errors)>100
print('FACE_FRONT_MAX_ERROR_M',max(errors),flush=True)
if changed:print('CHANGED_FRONT_PROBES',json.dumps(changed[:12]),flush=True)
assert max(errors)<.00001,'New geometry is covering the approved face'
report={'original_vertex_normal_uv_tangent_and_image_buffers_byte_identical':True,
    'original_materials_unchanged':True,'protected_face_triangles':int(protect.sum()),
    'materials_with_normal_and_ao':len(new['materials']),'embedded_images':len(new['images']),
    'protected_face_upper_y_m':1.252,'hairline_above_this_height_repaired':True,
    'protected_face_position_sha256':face_hash,'face_front_ray_tests':len(errors),
    'max_face_front_depth_change_m':max(errors),'crown_covered_rays':covered,
    'crown_test_rays':len(tests),'before_low_or_missing_crown_rays':sum(t['before_y'] is None or t['before_y']<1.24 for t in tests),
    'crown_samples':tests,'source_original_triangles_kept':len(out),
    'total_triangles':sum(array(new,nb,p['indices']).size//3 for m in new['meshes'] for p in m['primitives'])}
(ROOT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('HEAD_CLEANUP_VALID',json.dumps({k:v for k,v in report.items() if k!='crown_samples'}),flush=True)
