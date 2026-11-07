"""Independent exported topology and preserved intrados checks (CL3D Python)."""
from pathlib import Path
import trimesh,numpy as np,json,hashlib
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parents[1]/'procedural_architecture_v1/rooms'
report={}
for name in ['first_stair_hall','second_stair_hall']:
    scene=trimesh.load(ROOT/(name+'.glb'),force='scene')
    mesh=scene.to_geometry()
    alignment=np.einsum('ij,ij->i',mesh.vertex_normals[mesh.faces].mean(axis=1),mesh.face_normals)
    assert (alignment>0).all(),(name,'Inward shading normals')
    mesh.merge_vertices(merge_tex=True,merge_norm=True)
    incident=np.bincount(mesh.edges_unique_inverse)
    components=mesh.split(only_watertight=False)
    assert mesh.is_watertight and mesh.is_winding_consistent and len(components)==1,(name,mesh.is_watertight,len(components))
    old=trimesh.load(SOURCE/(name+'.glb'),force='scene')
    transform,key=old.graph['Mortar_'+name+'_4']
    source=old.geometry[key].copy();source.apply_transform(transform)
    _,distance,_=trimesh.proximity.closest_point_naive(mesh,source.vertices)
    assert distance.max()<.04,(name,'Intrados moved',distance.max())
    report[name]={'triangles':len(mesh.faces),'boundary_edges':int((incident==1).sum()),'nonmanifold_edges':int((incident>2).sum()),'components':len(components),'watertight':mesh.is_watertight,'consistent_winding':mesh.is_winding_consistent,'volume_m3':mesh.volume,'old_intrados_to_new_surface_max_m':float(distance.max()),'old_intrados_to_new_surface_99pct_m':float(np.quantile(distance,.99)),'sha256':hashlib.sha256((ROOT/(name+'.glb')).read_bytes()).hexdigest()}
(ROOT/'mesh-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('CLOSED_MASONRY_VALID',json.dumps(report),flush=True)
