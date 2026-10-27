"""Use installed MeshLab QEM with higher error weights on face and hands."""
import argparse
import json
from pathlib import Path
import time

import numpy as np
import pymeshlab
import trimesh

p=argparse.ArgumentParser();p.add_argument('mesh',type=Path);p.add_argument('out',type=Path)
p.add_argument('--triangles',type=int,default=150000)
args=p.parse_args();started=time.monotonic()
mesh=trimesh.load(args.mesh,force='mesh',process=False)
v=np.asarray(mesh.vertices);f=np.asarray(mesh.faces)
q=np.ones(len(v))
face=(abs(v[:,0]-.012)<.075)&(v[:,1]>1.10)&(v[:,1]<1.31)&(v[:,2]>.04)
hands=(abs(v[:,0])>.33)&(v[:,1]>.60)&(v[:,1]<.95)
q[face]=30;q[hands]=8
ms=pymeshlab.MeshSet();ms.add_mesh(pymeshlab.Mesh(vertex_matrix=v,face_matrix=f,v_scalar_array=q))
ms.apply_filter('meshing_remove_duplicate_faces');ms.apply_filter('meshing_remove_null_faces')
ms.apply_filter('meshing_decimation_quadric_edge_collapse',targetfacenum=args.triangles,
    qualitythr=.5,preserveboundary=True,boundaryweight=3,preservenormal=True,
    preservetopology=False,optimalplacement=True,qualityweight=True,autoclean=True)
out=ms.current_mesh()
low=trimesh.Trimesh(out.vertex_matrix(),out.face_matrix(),process=False)
low.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral marble',baseColorFactor=[180,169,149,255],metallicFactor=0,roughnessFactor=.78,doubleSided=True))
low.export(args.out,include_normals=True)
report={'source':str(args.mesh),'source_triangles':len(f),'target_triangles':args.triangles,
    'result_triangles':len(low.faces),'reduction_percent':100*(1-len(low.faces)/len(f)),
    'algorithm':'MeshLab quadric error metric; preserve boundary and normal; face quality x30, hands x8',
    'seconds':time.monotonic()-started}
args.out.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
print('WEIGHTED_QEM_OK',json.dumps(report),flush=True)
