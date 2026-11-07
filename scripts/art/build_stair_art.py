"""Original shallow ritual wall fixtures; Blender5.2, no external mesh inputs."""
import json, math, sys
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from procgen import core, export

OUT = core.ROOT / 'content/environments/red_descent/stair_art_v1'
core.empty_scene()
objects = []
placements = []
support = {}
# Measure the existing bowed, worn stone face instead of assuming a flat wall.
for hall, group in [('first_stair_hall',0),('second_stair_hall',2)]:
    bpy.ops.import_scene.gltf(filepath=str(core.ROOT/'content/environments/procedural_architecture_v1/rooms'/(hall+'.glb')))
    bpy.context.view_layer.update()
    samples=[]
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH' and obj.name.startswith('Stone') and obj.name.endswith('_'+str(group)):
            for polygon in obj.data.polygons:
                normal=core.to_godot((obj.matrix_world.to_3x3()@polygon.normal).normalized())
                if Vector(normal).dot(Vector((0,0,1) if group==0 else (0,0,-1)))>.65:
                    samples.extend(Vector(core.to_godot(obj.matrix_world@obj.data.vertices[i].co)) for i in polygon.vertices)
    assert samples,(hall,'Missing mounting stone')
    support[hall]=samples
    for obj in list(bpy.context.scene.objects):core.discard(obj)


def extrude(name, outline, back, front, bevel=.003):
    count = len(outline)
    vertices = [(x,y,z) for z in (back,front) for x,y in outline]
    faces = [tuple(range(count-1,-1,-1)),tuple(range(count,count*2))]
    faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],faces);mesh.update()
    obj = core.link(bpy.data.objects.new(name,mesh))
    if bevel:
        core.select_only([obj])
        mod = obj.modifiers.new('Worn arris','BEVEL');mod.width=bevel;mod.segments=3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def oval(width,height,count=64):
    return [(width*.5*math.cos(i*math.tau/count),height*.5*math.sin(i*math.tau/count)) for i in range(count)]


def tube(name, points, radius, closed=False):
    curve = bpy.data.curves.new(name,'CURVE');curve.dimensions='3D'
    curve.bevel_depth=radius;curve.bevel_resolution=2;curve.resolution_u=2;curve.use_fill_caps=True
    spline = curve.splines.new('POLY');spline.points.add(len(points)-1)
    for index,(point,co) in enumerate(zip(spline.points,points)):
        point.co=(*co,1);point.radius=.92+.08*math.sin(index*1.7)
    spline.use_cyclic_u=closed
    obj=core.link(bpy.data.objects.new(name,curve));core.select_only([obj])
    bpy.ops.object.convert(target='MESH')
    return bpy.context.object


def bead(name, at, scale):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=at)
    obj=bpy.context.object;obj.name=name;obj.scale=scale
    return obj


def rim(name,width,height,z,radius=.007):
    return tube(name,[(x,y,z) for x,y in oval(width,height)],radius,True)


def carve(obj, at, scale):
    cutter=bead('Recess cutter',at,scale)
    core.select_only([obj])
    mod=obj.modifiers.new('Closed shallow carving','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name);core.discard(cutter)


def placed(room,name,at,normal,pieces,meaning):
    # Read final location/scale matrices, including the last unsampled bead.
    bpy.context.view_layer.update()
    normal=Vector(normal);side=Vector((normal.z,0,-normal.x));up=Vector((0,1,0))
    def blender(v):return Vector((v.x,-v.z,v.y))
    local=[obj.matrix_world@Vector(corner) for obj in pieces for corner in obj.bound_box]
    xmin,xmax=min(p.x for p in local),max(p.x for p in local)
    ymin,ymax=min(p.y for p in local),max(p.y for p in local)
    samples=[(p-Vector(at)).dot(normal) for p in support[room]
             if xmin-.025<(p-Vector(at)).dot(side)<xmax+.025 and ymin-.025<p.y-at[1]<ymax+.025]
    assert samples,(room,name,'No supporting face under fixture')
    depth=max(samples)
    offset=depth+(-.006 if name=='Clamped vessels' else .026)
    mounted=Vector(at)+normal*offset
    frame=Matrix((blender(side),blender(up),blender(normal)*.65)).transposed().to_4x4()
    frame.translation=blender(mounted)
    for obj in pieces:
        obj['hall']=room
        local_matrix=obj.matrix_world.copy()
        obj.data=obj.data.copy()
        uv=obj.data.uv_layers.new(name='Ritual_metres')
        obj.data.uv_layers.active=uv
        uv.active_render=True
        for loop in obj.data.loops:
            point=local_matrix@obj.data.vertices[loop.vertex_index].co
            uv.data[loop.index].uv=(point.x*2.0,point.y*2.0)
        obj.matrix_world=frame@local_matrix
        obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4)
        objects.append(obj)
    placements.append({'room':room,'name':name,'at':list(mounted),'nominal_at':at,'support_front_depth_m':depth,'relief_depth_scale':.65,'normal':list(normal),'purpose':meaning})


def bell_mask():
    pieces=[extrude('Stone',oval(.98,1.12),-.035,.012,.012),rim('StoneRim',.88,1.01,.020,.012)]
    outline=[(-.30,-.24),(-.26,-.16),(-.18,.08),(-.20,.26),(-.13,.38),(0,.43),(.13,.38),(.20,.26),(.18,.08),(.26,-.16),(.30,-.24)]
    face=extrude('Stone',outline,.005,.055,.014)
    for x in (-.095,.095):carve(face,(x,.20,.066),(.052,.027,.025))
    carve(face,(0,-.045,.068),(.054,.13,.028))
    pieces += [bead('Soot',(-.095,.20,.043),(.045,.021,.004)),bead('Soot',(.095,.20,.043),(.045,.021,.004)),bead('Soot',(0,-.045,.043),(.041,.11,.003)),face,bead('Stone',(0,.105,.052),(.032,.09,.012)),tube('Bronze',[(-.27,-.23,.059),(0,-.265,.058),(.27,-.23,.059)],.006)]
    # Seven eroded oath notches mark the medallion rather than adding loose props.
    for i in range(7):
        angle=math.pi*.17+i*math.pi*.11
        x,y=.41*math.cos(angle),.48*math.sin(angle)
        pieces.append(tube('Iron',[(x-.012,y-.018,.026),(x+.012,y+.018,.026)],.003))
    for x,y in [(-.32,-.36),(.32,-.36),(-.32,.36),(.32,.36)]:
        pieces += [tube('Iron',[(x,y,-.10),(x,y,.021)],.006),bead('Bronze',(x,y,.024),(.011,.011,.005))]
    return pieces


def tablet(width,height,principal=False):
    outline=oval(width,height) if principal else [(-width*.5,-height*.38),(-width*.5,height*.35),(0,height*.5),(width*.5,height*.35),(width*.5,-height*.38),(0,-height*.5)]
    pieces=[extrude('Iron',outline,-.028,.012,.006)]
    points=[(x*.86,y*.87,.021) for x,y in outline]
    pieces.append(tube('Bronze',points,.006,True))
    if principal:
        # A sealed membrane behind a grille: no open model back or glowing cavity.
        pieces.append(bead('Tissue',(0,-.01,.022),(width*.27,height*.32,.009)))
        for x in (-.12,0,.12):
            pieces.append(tube('Iron',[(x,-height*.29,.043),(x*.9,0,.050),(x,height*.29,.043)],.009))
        pieces.append(tube('Bronze',[(-width*.3,-.06,.047),(width*.3,-.06,.047)],.006))
    else:
        for y,span in [(-.08,width*.45),(.02,width*.6),(.13,width*.3)]:
            pieces.append(tube('Bronze',[(-span*.5,y,.028),(span*.5,y,.028)],.004))
        pieces.append(tube('Bronze',[(0,-height*.3,.026),(0,height*.3,.026)],.004))
    for y in (-height*.36,height*.34):
        pieces += [tube('Iron',[(0,y,-.10),(0,y,.015)],.007),bead('Bronze',(0,y,.021),(.013,.013,.009))]
    return pieces


first='first_stair_hall'
placed(first,'Bell oath',(36.4,-3.65,-41.55),(0,0,1),bell_mask(),'One shallow carved bell-mask oath medallion above the northern turn')
for name,at in [('West votive',(32.7,-3.75,-41.55)),('East votive',(39.4,-3.75,-41.55))]:
    placed(first,name,at,(0,0,1),tablet(.27,.68),'Small iron votive tablet flanking the bell oath')

second='second_stair_hall'
placed(second,'Vascular reliquary',(-28.7,-16.9,38.05),(0,0,-1),tablet(1.10,1.30,True),'Principal sealed oval membrane reliquary with a three-bar grille')
for name,at in [('Lower witness',(-26.9,-17.0,38.05)),('Upper witness',(-30.5,-17.0,38.05))]:
    placed(second,name,at,(0,0,-1),tablet(.25,.60),'Narrow iron witness tablet')

pieces=[]
for start,end,offset in [(-1.8,-.38,-.07),(.38,1.8,-.10)]:
    path=[]
    for k in range(41):
        t=k/40;u=start+(end-start)*t
        path.append((u,offset+math.sin(t*math.tau)*.085,.033+math.sin(t*math.pi)*.007))
    vein=tube('Tissue',path,.014);vein.scale.z=.45;vein.location.z=.022
    pieces.append(vein)
    for k in (9,25):
        u,v,_=path[k]
        pieces.append(tube('Iron',[(u,v-.055,.014),(u,v-.022,.048),(u,v+.022,.048),(u,v+.055,.014)],.007))
        for sign in (-1,1):pieces.append(bead('Bronze',(u,v+sign*.058,.015),(.012,.012,.008)))
    u,v,_=path[18]
    pieces.append(bead('Tissue',(u,v,.034),(.08,.043,.013)))
    pieces.append(tube('Tissue',[(u,v,.032),(u+.10,v+.13,.028),(u+.20,v+.19,.018)],.004))
placed(second,'Clamped vessels',(-28.7,-16.9,38.05),(0,0,-1),pieces,'Short localized flattened vessels, nodules and four wall-fixed iron clamps')

# Each source component is closed before joining by hall/material for few draw calls.
groups={};topology={}
for obj in objects:
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges),(obj.name,'Open art component')
    if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
    assert bm.calc_volume()>0,(obj.name,'Empty art component')
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    colour=obj.data.color_attributes.new('Color','FLOAT_COLOR','CORNER')
    for polygon in obj.data.polygons:
        polygon.use_smooth=False
        tone=.05 if obj.name.startswith('Soot') else .78+.15*math.sin(polygon.center.x*31+polygon.center.y*17+polygon.center.z*11)**2
        for index in polygon.loop_indices:colour.data[index].color=(tone,tone,tone,1)
    obj.data.color_attributes.active_color=colour
    key=(obj['hall'],'Iron' if obj.name.startswith('Soot') else obj.name.split('.')[0]);groups.setdefault(key,[]).append(obj)

merged=[]
for (hall,kind),parts in groups.items():
    core.select_only(parts)
    if len(parts)>1:bpy.ops.object.join()
    obj=bpy.context.view_layer.objects.active;obj.name=kind+'_'+hall
    obj.data.calc_loop_triangles();topology[obj.name]={'triangles':len(obj.data.loop_triangles),'source_closed_components':len(parts)}
    merged.append(obj)

OUT.mkdir(parents=True,exist_ok=True)
export.glb(merged,OUT/'ritual_wall_art.glb')
report={'baseline':'366005e','generator':'scripts/art/build_stair_art.py','provenance':'Original project-created procedural reliefs, sealed plaques, capillary vessels and iron fixings. H-011 references guide motifs only; no image-to-mesh inference or external mesh used.','placements':placements,'meshes':topology,'stairs_sha256':{id:core.sha256(core.ROOT/'content/environments/red_descent/masonry_repairs_v1/stairs'/(id+'.glb')) for id in (first,second)},'sha256':core.sha256(OUT/'ritual_wall_art.glb'),'seal_bands':{first:{'at':[36.4,-4.6,-41.55],'normal':[0,0,1],'length_m':3.8},second:{'at':[-28.7,-17.85,38.05],'normal':[0,0,-1],'length_m':3.8}},'collision':'None; route, room, stair and vault collision are unchanged.'}
(OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n')
print('STAIR_ART_BUILT',sum(item['triangles'] for item in topology.values()),'triangles',len(merged),'batched meshes',flush=True)
