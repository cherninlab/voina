"""Closed stair-vault mortar from the authoritative room/profile generator."""
import json,math,sys
from pathlib import Path
import bpy,bmesh
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_architecture as architecture
from procgen import core,vault,export

OUT=core.ROOT/'content/environments/red_descent/masonry_repairs_v1'
OUT.mkdir(parents=True,exist_ok=True)
layout_path=core.ROOT/'content/environments/procedural_bridge_v1/layout.json'
layout=json.loads(layout_path.read_text())
report={'source_layout_sha256':core.sha256(layout_path),'rooms':{},'method':'Native cloister profile; original intrados, 0.24m finite roof-side thickness, closed mitres and connected exact union. No added junction blocks.'}
for rid in ['first_stair_hall','second_stair_hall']:
    core.empty_scene()
    room=next(room for room in layout['rooms'] if room['id']==rid)
    inner=architecture.outset(architecture.ccw([architecture.flat(p) for p in room['points']]),-architecture.THICKNESS*.5)
    rise=architecture.vault_rise(room,layout)
    reach=vault.inradius(inner)
    radius=(reach*reach+rise*rise)/(2*rise)
    centre_h=rise-radius
    start=math.atan2(-centre_h,-reach)
    length=radius*(start-math.pi*.5)
    def at(s):
        phi=start-s/radius
        return reach+radius*math.cos(phi),centre_h+radius*math.sin(phi)
    normals=vault._normals(inner)
    pieces=[]
    for i,(a,n) in enumerate(zip(inner,normals)):
        planes=[]
        for j,(b,m) in enumerate(zip(inner,normals)):
            if i==j:continue
            k=Vector((n.x-m.x,n.y-m.y,0))
            if k.length<1e-6:continue
            c=a.dot(n)-b.dot(m)
            planes.append((k*(c/k.length_squared),k.normalized()))
        obj=vault._shell(inner,i,n,at,length,room['floor']+room['height'],reach,centre_h,planes,f'Cement_{rid}_{i}')
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-6)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        assert all(e.is_manifold for e in bm.edges),(rid,i,'Open web')
        bm.to_mesh(obj.data);bm.free();pieces.append(obj)
    target=pieces[0]
    for other in pieces[1:]:
        core.select_only([target])
        mod=target.modifiers.new('Bond cement webs','BOOLEAN');mod.operation='UNION';mod.solver='EXACT';mod.object=other
        bpy.ops.object.modifier_apply(modifier=mod.name);core.discard(other)
    bm=bmesh.new();bm.from_mesh(target.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-6)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges),(rid,'Open cement union')
    if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
    bm.to_mesh(target.data);bm.free();target.name='CementVault_'+rid
    target.data.update();target.data.calc_loop_triangles();target.data.normals_split_custom_set([(0,0,0)]*len(target.data.loops))
    colour=target.data.color_attributes.new('Color','FLOAT_COLOR','CORNER')
    for item in colour.data:item.color=(.72,.72,.72,1)
    target.data.color_attributes.active_color=colour
    for face in target.data.polygons:face.use_smooth=False
    file=rid+'.glb';export.glb([target],OUT/file)
    source=core.ROOT/'content/environments/procedural_architecture_v1/rooms'/file
    report['rooms'][rid]={'source_sha256':core.sha256(source),'room':room,'file':file,'replace_mortar':f'Mortar_{rid}_4','triangles':len(target.data.loop_triangles),'rise_m':rise,'thickness_m':.24}
(OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n')
print('MASONRY_BACKING_BUILT',json.dumps(report),flush=True)
