"""Recessed room cores and fitted stair/vault masonry from the native layout."""
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
report=json.loads((OUT/'build.json').read_text()) if any(flag in core.args() for flag in ('--walls-only', '--stairs-only')) else {'routes':{r['id']:r['layout_hash'] for r in layout['routes']},'source_layout_sha256':core.sha256(layout_path),'rooms':{},'method':'Native cloister profile; original intrados, 0.24m finite roof-side thickness, closed mitres and connected exact union. No added junction blocks.'}
for rid in ([] if any(flag in core.args() for flag in ('--walls-only', '--stairs-only')) else ['first_stair_hall','second_stair_hall']):
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
print('MASONRY_BACKING_BUILT',list(report['rooms']),flush=True)

# Replace the whole native stair group, so repaired returns are part of the
# masonry rather than extra cubes placed over the old bodies.
from procgen import stonelib
for rid, group in ([] if '--walls-only' in core.args() else [('choir',9),('first_stair_hall',5),('second_stair_hall',5)]):
    selected=next((a.split('=',1)[1] for a in core.args() if a.startswith('--room=')),None)
    if selected and rid!=selected:continue
    core.empty_scene()
    room=next(room for room in layout['rooms'] if room['id']==rid)
    rng=core.rng(20261107,'fitted-stairs',rid)
    library=stonelib.Library(rng,'squared_rubble',count=24,triangles=140)
    architecture.KINDS['flag']=architecture.stonekinds.Library(rng,'floor_flag',count=16,triangles=110,name='repair_flag')
    pieces=architecture.stair_bodies(room,layout,rng,library)
    cores=[];stone=[];discarded=0
    for obj in pieces:
        obj.data=obj.data.copy();obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4)
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-6)
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        if not bm.faces or abs(bm.calc_volume())<.00008:
            bm.free();core.discard(obj);discarded+=1;continue
        assert all(e.is_manifold for e in bm.edges),(rid,obj.name,'Open stair piece',sum(not e.is_manifold for e in bm.edges))
        if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data);bm.free();obj.data.update()
        if obj.get('tone',0)<0:
            # Bond mitred cores with 1 mm of hidden overlap, avoiding
            # edge-only Boolean contacts. Visible face setbacks remain recessed.
            shell=bmesh.new();shell.from_mesh(obj.data);shell.normal_update()
            for vertex in shell.verts:vertex.co+=vertex.normal*.001
            shell.to_mesh(obj.data);shell.free();obj.data.update()
            cores.append(obj)
        else:stone.append(obj)
    target=cores[0]
    for other in cores[1:]:
        core.select_only([target])
        mod=target.modifiers.new('Bond stair cores','BOOLEAN');mod.operation='UNION';mod.solver='MANIFOLD';mod.object=other
        bpy.ops.object.modifier_apply(modifier=mod.name);core.discard(other)
    check=bmesh.new();check.from_mesh(target.data)
    bmesh.ops.remove_doubles(check,verts=list(check.verts),dist=1e-6)
    print('STAIR_UNION_TOPOLOGY',rid,len(check.faces),sum(e.is_boundary for e in check.edges),sum(len(e.link_faces)>2 for e in check.edges),flush=True)
    check.free()
    target['tone']=-1.0
    merged=architecture.merge('fitted_'+rid,{0:stone+[target]},rng)
    for obj in merged:
        bm=bmesh.new();bm.from_mesh(obj.data)
        if obj.name.startswith('Mortar'):
            for vertex in bm.verts:vertex.co=Vector(tuple(round(v,5) for v in vertex.co))
            bmesh.ops.dissolve_limit(bm,angle_limit=.0001,use_dissolve_boundaries=False,verts=list(bm.verts),edges=list(bm.edges))
        tolerance=1e-5
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=tolerance)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=tolerance)
        # Boolean cleanup can leave zero-face edges, which are not part of
        # the solid. Remove those wires rather than exporting loose debris.
        bmesh.ops.delete(bm,geom=[e for e in bm.edges if e.is_wire],context='EDGES')
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        if obj.name.startswith('Mortar'):
            # Triangulation can expose collinear Boolean boundary points.
            # Dissolve those zero-area faces before exporting normals.
            for _ in range(2):
                bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
                bmesh.ops.delete(bm,geom=[e for e in bm.edges if e.is_wire],context='EDGES')
                bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        assert all(e.is_manifold for e in bm.edges),(rid,obj.name,'Open merged stairs',sum(e.is_boundary for e in bm.edges),sum(e.is_wire for e in bm.edges),sum(len(e.link_faces)>2 for e in bm.edges))
        bm.to_mesh(obj.data);bm.free();obj.data.update();obj.data.calc_loop_triangles()
        obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
        for face in obj.data.polygons:face.use_smooth=False
        for item in obj.data.color_attributes['Color'].data:
            grey=.72 if obj.name.startswith('Mortar') else item.color[1]*1.25
            item.color=(grey,grey,grey,1)
    filename='stairs/'+rid+'.glb';export.glb(merged,OUT/filename)
    source=core.ROOT/'content/environments/procedural_architecture_v1/rooms'/(rid+'.glb')
    entry=report['rooms'].setdefault(rid,{'source_sha256':core.sha256(source),'room':room})
    entry.update({'stairs_file':filename,'replace_stair_group':group,'stairs_triangles':sum(len(obj.data.loop_triangles) for obj in merged),'tiny_trim_fragments_removed':discarded,'stairs_method':'Complete free-span facings, fitted raised-walk end returns, native treads, unioned continuous mortar; replaces original stair group.'})
    (OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n')
    print('FITTED_STAIRS_BUILT',rid,entry['stairs_triangles'],'triangles',discarded,'tiny fragments removed',flush=True)

# Keep continuous cores behind both worn faces and inside bonded corners.
# Original wall collision stays at the actual masonry contact boundary.
from procgen import masonry
for room in ([] if '--stairs-only' in core.args() else layout['rooms']):
    core.empty_scene();rid=room['id'];walls=[];planes=[]
    for number,(a,b,openings) in enumerate(architecture.room_walls(room,layout)):
        length=(b-a).length;end=.10
        shifted=[masonry.Opening(o.x0-end,o.x1-end,o.sill,o.spring,o.window,o.rise) for o in openings]
        outside=architecture.exposed(a,b,layout)
        thickness=architecture.THICKNESS-(.12 if outside else 0)
        wall=masonry.Wall(length-2*end,room['height'],thickness,shifted,recess=.12)
        obj=wall.core(f'recessed_{rid}_{number}')
        along=Vector((b.x-a.x,b.y-a.y,0)).normalized()
        inward=along.cross(Vector((0,0,1)))
        masonry.place([obj],Vector((a.x,a.y,room['floor']))+inward*architecture.THICKNESS*.5+along*end,along,Vector((0,0,1)))
        obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4)
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        assert all(e.is_manifold for e in bm.edges),(rid,number,'Open inset wall')
        bm.to_mesh(obj.data);bm.free();obj.data.update();obj.data.calc_loop_triangles()
        obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
        obj.name=f'Mortar_{rid}_{number}'
        colour=obj.data.color_attributes.new('Color','FLOAT_COLOR','CORNER')
        for item in colour.data:item.color=(.72,.72,.72,1)
        obj.data.color_attributes.active_color=colour
        for face in obj.data.polygons:face.use_smooth=False
        walls.append(obj)
        planes.append({'name':obj.name,'nominal_front':core.to_godot(Vector((a.x,a.y,room['floor']))+inward*architecture.THICKNESS*.5),'front_normal':core.to_godot(inward),'wall_start':core.to_godot(Vector((a.x,a.y,room['floor']))),'along':core.to_godot(along),'length_m':length,'outside_faced':outside})
    filename='walls/'+rid+'.glb';export.glb(walls,OUT/filename)
    source=core.ROOT/'content/environments/procedural_architecture_v1/rooms'/(rid+'.glb')
    entry=report['rooms'].setdefault(rid,{'source_sha256':core.sha256(source),'room':room})
    entry.update({'walls_file':filename,'front_recess_m':.12,'corner_end_recess_m':.10,'wall_collision':'Original stone contact boundary preserved','wall_planes':planes})
    (OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n')
    print('RECESSED_ROOM_CORES_BUILT',rid,len(walls),flush=True)

report['method']='Native room cores recessed behind worn stone faces; closed roof-side vault shells; fitted full-mitre stair masonry replaces source visuals, preserving original stone contact collision. No extra junction blocks.'
(OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n')
