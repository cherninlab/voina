"""Independent checks on actual GLB tubes and the full walking ribbons."""
from pathlib import Path
import hashlib,json
import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parents[3]
MODELS=PROJECT/'content/environments/procedural_roots_v1'
layout=json.loads((PROJECT/'content/environments/procedural_bridge_v1/layout.json').read_text())
results={}
for room in ('first_stair_hall','second_stair_hall'):
    path=MODELS/(room+'.glb');scene=trimesh.load(path,force='scene')
    report=json.loads(path.with_suffix('.json').read_text())
    assert report['files'][str(path.relative_to(PROJECT))]==hashlib.sha256(path.read_bytes()).hexdigest()
    for source,expected in report['sources'].items():
        assert hashlib.sha256((PROJECT/source).read_bytes()).hexdigest()==expected,source
    assert all(c['exposed_vertices']==0 for c in report['qa']['terminal_rings'])
    assert report['qa']['audit']['in_walking_corridor']==0
    assert report['qa']['graft']['back_exposed_vertices']==0
    assert report['triangles']<=report['budget']
    meshes={}
    for name in scene.graph.nodes_geometry:
        transform,key=scene.graph[name];mesh=scene.geometry[key].copy();mesh.apply_transform(transform)
        alignment=np.einsum('ij,ij->i',mesh.vertex_normals[mesh.faces].mean(axis=1),mesh.face_normals)
        assert (alignment>0).all(),(name,'Invalid shading normal')
        mesh.merge_vertices(merge_tex=True,merge_norm=True)
        incident=np.bincount(mesh.edges_unique_inverse)
        assert mesh.is_watertight and mesh.is_winding_consistent,(name,'Open or inconsistent tube')
        pieces=mesh.split();assert all(piece.volume>0 for piece in pieces)
        conflicts=0
        # Test both vertices and triangle centres against the actual mitred
        # route triangles, including the extra area on the outside of bends.
        samples=np.concatenate((mesh.vertices,mesh.triangles_center))
        for route in layout['routes']:
            points=np.array(route['points']);edges=np.array(route['edges'])
            for i in range(len(points)-1):
                a,b=points[i],points[i+1];ea,eb=edges[i],edges[i+1]
                for triangle in (np.array([a-ea,a+ea,b-eb]),np.array([a+ea,b+eb,b-eb])):
                    matrix=np.column_stack((triangle[1,[0,2]]-triangle[0,[0,2]],triangle[2,[0,2]]-triangle[0,[0,2]]))
                    if abs(np.linalg.det(matrix))<1e-8:continue
                    uv=(samples[:,[0,2]]-triangle[0,[0,2]])@np.linalg.inv(matrix).T
                    inside=(uv[:,0]>=0)&(uv[:,1]>=0)&(uv.sum(axis=1)<=1)
                    floor=triangle[0,1]+uv[:,0]*(triangle[1,1]-triangle[0,1])+uv[:,1]*(triangle[2,1]-triangle[0,1])
                    conflicts+=int((inside&(samples[:,1]>floor+.03)&(samples[:,1]<floor+2.7)).sum())
        assert conflicts==0,(name,'Growth enters the actual walking ribbon',conflicts)
        meshes[name]={'triangles':len(mesh.faces),'watertight':True,'winding_consistent':True,'closed_components':len(pieces),'boundary_edges':int((incident==1).sum()),'nonmanifold_edges':int((incident>2).sum()),'minimum_shading_alignment':float(alignment.min()),'walking_ribbon_conflicts':conflicts}
    ends=report['qa']['terminal_rings']
    results[room]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'meshes':meshes,
                   'closed_terminal_rings':len(ends),'parent_mounts':sum(c['end']=='branch' for c in ends),
                   'wall_mounts':sum(c['end']!='branch' for c in ends),'sources':report['sources']}
(ROOT/'mesh-validation.json').write_text(json.dumps(results,indent=2)+'\n')
print('VASCULAR_MESH_OK',json.dumps(results),flush=True)
