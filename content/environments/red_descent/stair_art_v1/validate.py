"""Independent exported art closure, normals and swept-route headroom checks."""
from pathlib import Path
import hashlib,json
import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parent
layout=json.loads((ROOT.parents[1]/'procedural_bridge_v1/layout.json').read_text())
scene=trimesh.load(ROOT/'ritual_wall_art.glb',force='scene')
report={}
for name in scene.graph.nodes_geometry:
    transform,key=scene.graph[name];mesh=scene.geometry[key].copy();mesh.apply_transform(transform)
    alignment=np.einsum('ij,ij->i',mesh.vertex_normals[mesh.faces].mean(axis=1),mesh.face_normals)
    assert (alignment>0).all(),(name,'Inward or zero-area shading normal')
    mesh.merge_vertices(merge_tex=True,merge_norm=True)
    incident=np.bincount(mesh.edges_unique_inverse)
    assert mesh.is_watertight and mesh.is_winding_consistent,(name,int((incident==1).sum()),int((incident>2).sum()))
    assert all(piece.volume>0 for piece in mesh.split()),(name,'Inside-out component')
    conflicts=0;nearest_head_clearance=float('inf')
    for route in layout['routes']:
        points=np.array(route['points'])
        for a,b in zip(points,points[1:]):
            delta=b[[0,2]]-a[[0,2]]
            t=np.clip(((mesh.vertices[:,[0,2]]-a[[0,2]])@delta)/(delta@delta),0,1)
            plan=a[[0,2]]+t[:,None]*delta
            distance=np.linalg.norm(mesh.vertices[:,[0,2]]-plan,axis=1)
            foot=a[1]+t*(b[1]-a[1])
            close=distance<float(route['width'])/2+.35
            in_body=close&(mesh.vertices[:,1]>foot-.15)&(mesh.vertices[:,1]<foot+2.7)
            conflicts+=int(in_body.sum())
            if close.any():nearest_head_clearance=min(nearest_head_clearance,float((mesh.vertices[close,1]-foot[close]-2.7).min()))
    assert conflicts==0,(name,'Decor enters full-width swept route/headroom',conflicts)
    report[name]={'triangles':len(mesh.faces),'watertight':bool(mesh.is_watertight),'winding_consistent':bool(mesh.is_winding_consistent),'boundary_edges':int((incident==1).sum()),'nonmanifold_edges':int((incident>2).sum()),'closed_components':len(mesh.split()),'route_conflicts':conflicts,'minimum_overhead_margin_m':None if not np.isfinite(nearest_head_clearance) else nearest_head_clearance}
result={'sha256':hashlib.sha256((ROOT/'ritual_wall_art.glb').read_bytes()).hexdigest(),'meshes':report,'method':'All exported vertices against every route segment: full half-width plus0.35m capsule radius, floor-0.15..floor+2.7m. Fixtures remain above the protected envelope. Actual collision/traversal checked separately.'}
(ROOT/'mesh-validation.json').write_text(json.dumps(result,indent=2)+'\n')
print('STAIR_ART_MESH_OK',json.dumps(result),flush=True)
