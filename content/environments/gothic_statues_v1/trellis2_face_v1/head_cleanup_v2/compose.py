"""Replace head surroundings while retaining original face/body buffers exactly."""
import copy
import json
from pathlib import Path
import sys

import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT))
from glb_io import read_glb,write_glb,array,append_indices
from regions import head_region,protected_face,face_radius,facial_depth

patch_path=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'surround_full.glb'
prepared='--prepared' in sys.argv
base,bb=read_glb(ROOT.parent/'baked_150k/statue.glb')
patch,pb=read_glb(patch_path)
p=base['meshes'][0]['primitives'][0]
v=array(base,bb,p['attributes']['POSITION']);f=array(base,bb,p['indices']).reshape(-1,3)
protect=protected_face(v[f],radius=.99).any(1)
remove=head_region(v[f].mean(1))&~protect
kept=f[~remove]
p['indices']=append_indices(base,bb,kept)
q=patch['meshes'][0]['primitives'][0]
w=array(patch,pb,q['attributes']['POSITION']);g=array(patch,pb,q['indices']).reshape(-1,3)
if not prepared:
    depth,covered=facial_depth(v,f[protect],w)
    # Keep structural backing behind the approved skin; do not cut a new hole
    # through the cranium. The inset also avoids an interpolated cap triangle
    # crossing in front of the original lips or eyelids.
    rad=face_radius(w)
    inset=.0003+.0032*np.clip((.93-rad)/.15,0,1)
    overlap=(rad<1.18)&covered&(w[:,2]>depth-inset)&(w[:,1]<1.258)
    weight=np.clip((1.18-rad)/.10,0,1)*np.clip((1.258-w[:,1])/.006,0,1)
    target=np.minimum(w[:,2],depth-inset)
    w[overlap,2]+=(target[overlap]-w[overlap,2])*weight[overlap]
acc=patch['accessors'][q['attributes']['POSITION']];view=patch['bufferViews'][acc['bufferView']]
offset=view.get('byteOffset',0)+acc.get('byteOffset',0);stride=view.get('byteStride',12)
dest=np.ndarray(w.shape,dtype='<f4',buffer=pb,offset=offset,strides=(stride,4));dest[:]=w
acc['min']=w.min(0).tolist();acc['max']=w.max(0).tolist()
q['indices']=append_indices(patch,pb,g)
if not prepared:
    normals=np.asarray(trimesh.Trimesh(w,g,process=False).vertex_normals,dtype='<f4')
    accn=patch['accessors'][q['attributes']['NORMAL']];viewn=patch['bufferViews'][accn['bufferView']]
    normal_data=np.ndarray(normals.shape,dtype='<f4',buffer=pb,
        offset=viewn.get('byteOffset',0)+accn.get('byteOffset',0),
        strides=(viewn.get('byteStride',12),4));normal_data[:]=normals
    write_glb(ROOT/'surround_patch_high.glb',copy.deepcopy(patch),bytearray(pb))

bb.extend(b'\x00'*((-len(bb))%4));binary_offset=len(bb)
offsets={key:len(base.get(key,[])) for key in ['bufferViews','accessors','images','samplers','textures','materials','meshes','nodes']}
for view in patch.get('bufferViews',[]):
    view['byteOffset']=view.get('byteOffset',0)+binary_offset;view['buffer']=0
for acc in patch.get('accessors',[]):acc['bufferView']+=offsets['bufferViews']
for im in patch.get('images',[]):
    if 'bufferView' in im:im['bufferView']+=offsets['bufferViews']
for tex in patch.get('textures',[]):
    if 'source' in tex:tex['source']+=offsets['images']
    if 'sampler' in tex:tex['sampler']+=offsets['samplers']
def remap_textures(value):
    if isinstance(value,dict):
        for key,child in value.items():
            if key.endswith('Texture') and isinstance(child,dict) and 'index' in child:child['index']+=offsets['textures']
            else:remap_textures(child)
    elif isinstance(value,list):
        for child in value:remap_textures(child)
for material in patch.get('materials',[]):remap_textures(material)
for mesh in patch['meshes']:
    for prim in mesh['primitives']:
        prim['attributes']={key:value+offsets['accessors'] for key,value in prim['attributes'].items()}
        prim['indices']+=offsets['accessors']
        if 'material' in prim:prim['material']+=offsets['materials']
for node in patch.get('nodes',[]):
    if 'mesh' in node:node['mesh']+=offsets['meshes']
    if 'children' in node:node['children']=[i+offsets['nodes'] for i in node['children']]
for key in offsets:base.setdefault(key,[]).extend(patch.get(key,[]))
scene=base['scenes'][base.get('scene',0)]
scene['nodes'].extend(i+offsets['nodes'] for i in patch['scenes'][patch.get('scene',0)]['nodes'])
bb.extend(pb);write_glb(ROOT/'statue.glb',base,bb)
report={'source':'../baked_150k/statue.glb','patch':str(patch_path),
    'old_surround_triangles_removed':int(remove.sum()),'original_triangles_kept':len(kept),
    'protected_face_triangles_kept':int(protect.sum()),'new_patch_triangles':len(g),
    'total_triangles':len(kept)+len(g),'original_vertex_and_image_buffers_unchanged':True}
(ROOT/'composition.json').write_text(json.dumps(report,indent=2)+'\n')
print('HEAD_CLEANUP_COMPOSED',json.dumps(report),flush=True)
