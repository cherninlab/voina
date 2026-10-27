"""Apply the native port's surface-preserving cleanup to saved raw geometry."""
import argparse
import json
from pathlib import Path
import sys
import time

import numpy as np
import trimesh

parser=argparse.ArgumentParser()
parser.add_argument('folder',type=Path)
args=parser.parse_args();folder=args.folder.resolve()
sys.path.insert(0,'/Users/theochernin/Projects/CherninLab3D/vendor/trellis2mlx')
from trellmlx.mesh_cleanup import cleanup_mesh
from trellmlx.exterior_surface_repair import repair_exterior_surface

data=np.load(folder/'checkpoints/mesh_raw.npz');vertices=data['vertices'];faces=data['faces']
raw_faces=len(faces);started=time.monotonic()
vertices,faces=cleanup_mesh(vertices,faces,max_hole_perimeter=0,keep_largest=False,
    preserve_surface_parts=True,do_fix_normals=True,verbose=True)
faces,repair=repair_exterior_surface(vertices,faces,component_orientation_confidence=.5)
assert len(faces)>0 and np.isfinite(vertices).all()
vertices=vertices[:,[0,2,1]]*np.array([1,1,-1])
mesh=trimesh.Trimesh(vertices,faces,process=False)
mesh.vertices-=mesh.bounds.mean(axis=0);mesh.vertices*=1.4/max(mesh.extents);mesh.vertices[:,1]-=mesh.bounds[0,1]
mesh.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral marble geometry review',baseColorFactor=[180,169,149,255],metallicFactor=0,roughnessFactor=.78,doubleSided=True))
mesh.export(folder/'clean_high.glb',include_normals=True)
report={'method':'native MLX port cleanup_mesh plus exterior_surface_repair',
    'raw_triangles':raw_faces,'clean_triangles':len(mesh.faces),'vertices':len(mesh.vertices),
    'hole_filling':False,'decimation':False,'keep_largest_only':False,'surface_preservation':True,
    'winding_consistent':bool(mesh.is_winding_consistent),'watertight':bool(mesh.is_watertight),
    'exterior_repair':repair,'seconds':time.monotonic()-started}
(folder/'finish.json').write_text(json.dumps(report,indent=2)+'\n')
print('TRELLIS2_GEOMETRY_FINISH_OK',json.dumps({k:v for k,v in report.items() if k!='exterior_repair'}),flush=True)
