"""Audit exported GLBs and their embedded maps, including topology across UV seams."""
import hashlib
import io
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
import trimesh

root = Path(__file__).resolve().parent
reports = []
for filename, expected in [('e01_crawling_lod0.glb',80000),('e01_crawling_lod1.glb',30000)]:
    path = root/'asset'/filename
    data = path.read_bytes()
    magic,version,length = struct.unpack_from('<4sII',data)
    assert magic == b'glTF' and version == 2 and length == len(data)
    json_length,json_type = struct.unpack_from('<II',data,12)
    assert json_type == 0x4e4f534a
    gltf = json.loads(data[20:20+json_length])
    material = gltf['materials'][0]
    pbr = material['pbrMetallicRoughness']
    assert all(key in material for key in ['normalTexture','occlusionTexture'])
    assert all(key in pbr for key in ['baseColorTexture','metallicRoughnessTexture'])
    primitive = gltf['meshes'][0]['primitives'][0]
    assert all(key in primitive['attributes'] for key in ['POSITION','NORMAL','TANGENT','TEXCOORD_0'])
    mesh = trimesh.load(path, force='mesh')
    assert len(mesh.faces) == expected
    assert np.isfinite(mesh.vertices).all() and np.isfinite(mesh.vertex_normals).all()
    geometry = trimesh.Trimesh(mesh.vertices,mesh.faces,process=True)
    geometry.merge_vertices(merge_tex=True,merge_norm=True)
    assert geometry.is_watertight and geometry.is_winding_consistent
    assert len(geometry.split()) == 1
    assert abs(geometry.bounds[0,1]) < .001, 'glTF floor origin within 1 mm after decimation'
    assert abs(max(geometry.extents)-2.2) < .002
    binary = data[28+json_length:]
    maps = []
    for image in gltf['images']:
        view = gltf['bufferViews'][image['bufferView']]
        start = view.get('byteOffset',0)
        decoded = Image.open(io.BytesIO(binary[start:start+view['byteLength']]))
        assert decoded.size == (2048,2048)
        pixels = np.asarray(decoded.convert('RGB'))
        assert pixels.std() > 0, 'Map is empty/constant'
        maps.append({'size':list(decoded.size),'channels':decoded.mode,'std':float(pixels.std())})
    reports.append({'file':filename,'triangles':len(mesh.faces),'vertices_with_uv_seams':len(mesh.vertices),
        'closed_geometry':bool(geometry.is_watertight),'components':1,'bounds':geometry.bounds.tolist(),
        'normal_uv_tangent_attributes':True,'pbr_maps_embedded':True,'maps':maps,
        'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
report = {'result':'pass','checks':reports,
          'limits':'Technical validation does not establish image fidelity or close-up art approval.'}
(root/'review/asset_validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
