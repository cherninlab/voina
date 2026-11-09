"""One stone arch carries the ledge landing into the nave's shaft wall.

Uses the existing pier, route elevations and walking ribbon. No new route.
Blender: --factory-startup -b --python scripts/art/build_nave_abutment.py
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_architecture as architecture
from build_upper_crossing import prism
from procgen import core, export, masonry, passage, stonekinds, stonelib

core.empty_scene()
layout=json.loads((core.ROOT/'content/environments/procedural_bridge_v1/layout.json').read_text())
ledge=next(r for r in layout['routes'] if r['id']=='central_ledge')
nave=next(r for r in layout['routes'] if r['id']=='nave')
rng=core.rng(177,'nave-abutment')
lib=stonelib.Library(rng,'squared_rubble',count=16,triangles=200)
flags=stonekinds.Library(core.rng(177,'passage-floor-field'),'floor_flag',count=24,triangles=110,name='flag')
passage.PAVING=flags
floor=-18.0
joint=architecture.blender_point(nave['points'][0])
segments=[(ledge,len(ledge['points'])-2,1.0),(nave,0,6.5/13.0)]
stations=[]
travel=0.0
for route,index,end in segments:
    a,b=(architecture.blender_point(route['points'][i]) for i in (index,index+1))
    e,f=(architecture.blender_point(route['edges'][i]) for i in (index,index+1))
    length=Vector((b.x-a.x,b.y-a.y,0)).length*end
    count=math.ceil(length/.4)
    for k in range(count+1):
        if stations and k==0:
            continue
        t=end*k/count
        stations.append((a.lerp(b,t),e.lerp(f,t),travel+length*k/count))
    travel+=length

def arch_volume(name,margin,recess):
    vertices=[]
    for at,edge,s in stations:
        side=edge.normalized()
        width=edge+side*margin
        depth=.8+3.2*(1-math.sin(math.pi*s/travel))
        vertices += [at-width-Vector((0,0,recess)),at+width-Vector((0,0,recess)),
                     at-width-Vector((0,0,depth)),at+width-Vector((0,0,depth))]
    faces=[(0,2,3,1)]
    for k in range(len(stations)-1):
        n=k*4;m=n+4
        faces += [(n,n+1,m+1,m),(n+2,m+2,m+3,n+3),(n,n+4,n+6,n+2),(n+1,n+3,n+7,n+5)]
    n=(len(stations)-1)*4;faces.append((n,n+1,n+3,n+2))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces)
    import bmesh
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges),name
    bm.to_mesh(mesh);bm.free()
    return core.link(bpy.data.objects.new(name,mesh))

body=arch_volume('abutment_core',.13,.16);body['tone']=-1.0
mask=arch_volume('facing_envelope',.48,.12)
walls=[]
for sign in (-1,1):
    for route,index,end in segments:
        a,b=(architecture.blender_point(route['points'][i]) for i in (index,index+1))
        e,f=(architecture.blender_point(route['edges'][i]) for i in (index,index+1))
        b=a.lerp(b,end);f=e.lerp(f,end)
        a+=e*sign+e.normalized()*sign*.18
        b+=f*sign+f.normalized()*sign*.18
        if sign<0:a,b=b,a
        d=Vector((b.x-a.x,b.y-a.y,0)).normalized()
        length=Vector((b.x-a.x,b.y-a.y,0)).length
        wall=masonry.Wall(length,5.8,.35,course=(.26,.38),stone=(.55,1.0),proud=(-.003,.009))
        parts=wall.build(lib,rng,name='abutment_course',core=False)
        masonry.place(parts,Vector((a.x,a.y,floor-4.2)),d,passage.UP)
        walls+=parts
pending=[]
for obj in walls:
    passage._bake_transform(obj)
    modifier=obj.modifiers.new('continuous_arch','BOOLEAN');modifier.operation='INTERSECT';modifier.solver='EXACT';modifier.object=mask
    pending.append(obj)
depsgraph=bpy.context.evaluated_depsgraph_get()
meshes=[bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph)) for o in pending]
for obj,mesh in zip(pending,meshes):obj.modifiers.clear();obj.data=mesh
walls=[o for o in walls if o.data.polygons]
for obj in pending:
    if not obj.data.polygons:core.discard(obj)
core.discard(mask)
for obj in walls:obj['tone']=rng.uniform(.86,1.04)

# One continuous paving field reaches from the old pier through the portal.
a=architecture.blender_point(ledge['points'][-2]);e=architecture.blender_point(ledge['edges'][-2])
b=joint;f=architecture.blender_point(ledge['edges'][-1])
c=joint+Vector((0,-passage.THICKNESS,0));g=Vector((-2.4,0,0))
polygon=architecture.ccw([Vector((v.x,v.y)) for v in [a-e,b-f,c-g,c+g,b+f,a+e]])
clip=prism('landing_footprint',[(v.x,v.y) for v in polygon],floor-5,floor+5)
low=Vector((min(v.x for v in polygon),min(v.y for v in polygon),floor))
high=Vector((max(v.x for v in polygon),max(v.y for v in polygon),floor))
profile=masonry.Opening(-(high.x-low.x)/2,(high.x-low.x)/2)
paving=passage.pave_field(flags,Vector(((low.x+high.x)/2,low.y,floor)),Vector((0,1,0)),high.y-low.y,profile.half,'landing_flags')
for obj in paving:
    passage._bake_transform(obj)
    modifier=obj.modifiers.new('paving_outline','BOOLEAN');modifier.operation='INTERSECT';modifier.solver='EXACT';modifier.object=clip
depsgraph=bpy.context.evaluated_depsgraph_get()
meshes=[bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph)) for o in paving]
for obj,mesh in zip(paving,meshes):obj.modifiers.clear();obj.data=mesh
kept=[o for o in paving if o.data.polygons]
for obj in paving:
    if not obj.data.polygons:core.discard(obj)
core.discard(clip)
fit={'at':joint,'arrivals':[{'route':ledge,'slope':-.1},{'route':nave,'slope':0}]}
architecture.fit_junction_floor({21:kept},fit)
groups={0:[body],1:walls,2:kept}
core.flush_trash()
out=core.ROOT/'content/environments/red_descent/passage_landings_v1'
architecture.PASSAGE_REPORTS['nave_abutment']={'design':'One continuous segmental arch from the existing ledge pier into the shaft wall; one paving field through the portal',
 'source_routes':{r['id']:r['layout_hash'] for r in (ledge,nave)},'old_endpoint_bracket_replaced':True,'arch_depth_m':{'spring':4.0,'crown':.8}}
architecture.bake_all([('meshes','nave_abutment',groups)],out)
metadata={'routes':{r['id']:r['layout_hash'] for r in (ledge,nave)},'route':'central_ledge','segment':len(ledge['points'])-2,
 'deck':nave['points'][0],'base':[8.62264,-21.2,26.67925],'seat':[7,-18.97,21],
 'floor_polygon':[[v.x,-v.y] for v in polygon],'floor_y':floor}
(out/'landing.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('NAVE_ABUTMENT_BUILT',len(walls),'facing stones',len(kept),'flags',flush=True)
