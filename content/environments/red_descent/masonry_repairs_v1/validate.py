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
    closest,distance,_=trimesh.proximity.closest_point_naive(mesh,source.vertices)
    forward=np.einsum("ij,ij->i",closest-source.vertices,source.vertex_normals)
    assert distance.max()<.09 and forward.max()<.001,(name,"Backing intrudes toward stone face",distance.max(),forward.max())
    report[name]={'triangles':len(mesh.faces),'boundary_edges':int((incident==1).sum()),'nonmanifold_edges':int((incident>2).sum()),'components':len(components),'watertight':mesh.is_watertight,'consistent_winding':mesh.is_winding_consistent,'volume_m3':mesh.volume,'old_sheet_to_recessed_backing_max_m':float(distance.max()),'old_sheet_to_recessed_backing_99pct_m':float(np.quantile(distance,.99)),'sha256':hashlib.sha256((ROOT/(name+'.glb')).read_bytes()).hexdigest()}
(ROOT/'mesh-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('RECESSED_VAULTS_VALID',json.dumps(report),flush=True)

build=json.loads((ROOT/'build.json').read_text())
for room,entry in build['rooms'].items():
    if 'stairs_file' not in entry:continue
    filename=entry['stairs_file'];scene=trimesh.load(ROOT/filename,force='scene');results={}
    for node in scene.graph.nodes_geometry:
        transform,key=scene.graph[node];mesh=scene.geometry[key].copy();mesh.apply_transform(transform)
        alignment=np.einsum('ij,ij->i',mesh.vertex_normals[mesh.faces].mean(axis=1),mesh.face_normals)
        assert (alignment>0).all(),(room,node,'Inward shading normal')
        mesh.merge_vertices(merge_tex=True,merge_norm=True)
        incident=np.bincount(mesh.edges_unique_inverse)
        assert mesh.is_watertight and mesh.is_winding_consistent,(room,node,int((incident==1).sum()),int((incident>2).sum()))
        results[node]={'triangles':len(mesh.faces),'boundary_edges':int((incident==1).sum()),'nonmanifold_edges':int((incident>2).sum()),'watertight':mesh.is_watertight,'volume_m3':float(mesh.volume)}
    report[filename]={'objects':results,'triangles':sum(v['triangles'] for v in results.values()),'sha256':hashlib.sha256((ROOT/filename).read_bytes()).hexdigest()}
(ROOT/'mesh-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('FITTED_STAIRS_VALID',json.dumps({key:value['triangles'] for key,value in report.items() if key.startswith('stairs/')}),flush=True)

for room,entry in build['rooms'].items():
    if 'walls_file' not in entry:continue
    scene=trimesh.load(ROOT/entry['walls_file'],force='scene');walls={}
    for plane in entry['wall_planes']:
        name=plane['name'];transform,key=scene.graph[name]
        mesh=scene.geometry[key].copy();mesh.apply_transform(transform);mesh.merge_vertices(merge_tex=True,merge_norm=True)
        assert mesh.is_watertight and mesh.is_winding_consistent,(room,name,'Open recessed wall')
        origin=np.array(plane['nominal_front']);normal=np.array(plane['front_normal'])
        depths=(mesh.vertices-origin)@normal
        along=(mesh.vertices-np.array(plane['wall_start']))@np.array(plane['along'])
        assert depths.max()<-.1199,(room,name,'Cement reaches stone front',depths.max())
        if plane['outside_faced']:
            assert depths.min()>-.7801,(room,name,'Cement reaches outer stone front',depths.min())
        assert along.min()>.0999 and along.max()<plane['length_m']-.0999,(room,name,'Square cement end protrudes')
        walls[name]={'front_setback_m':float(-depths.max()),'start_setback_m':float(along.min()),'end_setback_m':float(plane['length_m']-along.max()),'watertight':mesh.is_watertight,'triangles':len(mesh.faces)}
    report[entry['walls_file']]={'walls':walls,'sha256':hashlib.sha256((ROOT/entry['walls_file']).read_bytes()).hexdigest()}
(ROOT/'mesh-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('RECESSED_WALLS_VALID',sum(len(v['walls']) for v in report.values() if 'walls' in v),'wall cores; front >=0.12m and ends >=0.10m recessed',flush=True)
