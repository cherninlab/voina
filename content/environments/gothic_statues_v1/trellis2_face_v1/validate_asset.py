"""Validate geometry, embedded maps and source provenance of the trial export."""
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
import trimesh

root=Path(__file__).resolve().parent
report={}
for name in ['oracle_150k.glb','baked_150k/statue.glb']:
    path=root/name
    scene=trimesh.load(path,force='scene',process=False)
    meshes=list(scene.geometry.values())
    triangles=sum(len(m.faces) for m in meshes)
    assert triangles<=150000
    assert all(np.isfinite(m.vertices).all() for m in meshes)
    assert all(m.faces.min()>=0 and m.faces.max()<len(m.vertices) for m in meshes)
    raw=path.read_bytes();length,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4E4F534A
    gltf=json.loads(raw[20:20+length])
    if 'baked' in name:
        for mesh in gltf['meshes']:
            for p in mesh['primitives']:
                assert all(x in p['attributes'] for x in ['POSITION','NORMAL','TANGENT','TEXCOORD_0'])
        assert 'normalTexture' in gltf['materials'][0]
        assert 'occlusionTexture' in gltf['materials'][0]
        assert len(gltf['images'])>=2
    welded=trimesh.util.concatenate(meshes)
    welded.merge_vertices(merge_tex=True,merge_norm=True,digits_vertex=7)
    counts=np.bincount(welded.edges_unique_inverse)
    report[name]={'triangles':triangles,'bytes':len(raw),'embedded_images':len(gltf.get('images',[])),
        'watertight':all(m.is_watertight for m in meshes),
        'winding_consistent':all(m.is_winding_consistent for m in meshes),
        'geometric_boundary_edges':int((counts==1).sum()),
        'geometric_non_manifold_edges':int((counts>2).sum())}
for name in ['normal','ao']:
    p=root/'baked_150k'/(name+'.png');im=np.asarray(Image.open(p))
    assert im.shape[:2]==(4096,4096)
    spatial_std=im[:,:,:3].std(axis=(0,1))
    assert float(spatial_std[0])>2
    if name=='normal':assert float(spatial_std[1])>2
    report[name]={'dimensions':list(im.shape),'per_channel_spatial_std':spatial_std.tolist()}
def binary_chunks(path):
    data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0]
    return data[20+length:]
assert binary_chunks(root/'baked_150k/statue.glb')==binary_chunks(root/'baked_150k/geometry_only.glb')
report['map_comparison_geometry_identical']=True
(root/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('STATUE_REDUCTION_BAKE_VALID',json.dumps(report))
