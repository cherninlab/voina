"""Blender: validate arch cutters and whole-bay trimming without a stone bake."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from procgen import core, masonry, passage
import bmesh
import json
import build_architecture as architecture

core.empty_scene()
wall=masonry.Wall(6,6,4,[masonry.Opening(1,5,spring=2.4)])
mass=wall.core('hollow_clip')
control=mass.copy(); control.data=mass.data.copy();core.link(control)
masonry.clip(control,Vector((0,0,-2)),Vector((0,0,1)))
control.data.calc_loop_triangles()
control_tree=BVHTree.FromPolygons([v.co for v in control.data.vertices],[list(t.vertices) for t in control.data.loop_triangles],all_triangles=True)
assert control_tree.ray_cast(Vector((3,1.6,0)),Vector((0,0,-1)),5)[0] is not None,'Negative control did not reproduce the sealed opening'
assert passage.clip_mass(mass,Vector((0,0,-2)),Vector((0,0,1)))
bm=bmesh.new();bm.from_mesh(mass.data)
assert all(e.is_manifold for e in bm.edges),'Hollow cap backing is open'
bm.free()
mesh=mass.data;mesh.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[list(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
assert tree.ray_cast(Vector((3,1.6,0)),Vector((0,0,-1)),5)[0] is None,'Clip sealed the doorway'
assert tree.ray_cast(Vector((3,1.6,-3)),Vector((0,1,0)),5)[0] is not None,'Clip removed the roof'
o=masonry.Opening(-2.7,2.7,spring=2.4)
centre=Vector((0,0,0))
x=Vector((1,0,0))
d=Vector((.780869,.624695,0)).normalized()
cut=passage.clearance(o,centre,d,-o.half,15,'arch')
mesh=cut.data
mesh.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[list(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
# A real closed arch: roof and walls, plus no premature partition at the mouth.
assert tree.ray_cast(d*4+Vector((0,0,1.6)),Vector((0,0,1)),10)[0] is not None
box=passage.box('backing',centre,x,3.6,-.15,5.8)
passage.subtract({0:[box]},[cut])
mesh=box.data;mesh.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[list(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
assert tree.ray_cast(d*2+Vector((0,0,1.6)),Vector((0,0,1)),10)[0] is not None
assert tree.ray_cast(Vector((0,0,1.6)),d,4)[0] is None, 'Skew arrival blocked by backing'
rock=passage.rock_shell(o,Vector((0,0,0)),x,12,0,'selftest')
bm=bmesh.new(); bm.from_mesh(rock.data)
assert all(e.is_manifold for e in bm.edges), 'Open rock lining'
assert bm.calc_volume(signed=True) > 0, 'Rock lining winding inverted'
bm.free()
before=[v.co.copy() for v in rock.data.vertices]
passage.shape_run({0:[rock]},o,Vector((0,0,0)),Vector((12,0,0)),'hewn_rock')
for a,b in zip(before,rock.data.vertices):
    if a.x <= 4 or a.x >= 8:
        assert (a-b.co).length < 1e-5,'Profile moved at a join'
assert max((a-b.co).length for a,b in zip(before,rock.data.vertices)) > .1
backing=passage.run_mass(o,Vector((0,0,0)),Vector((20,0,0)),'variable_backing')
passage.shape_run({0:[backing]},o,Vector((0,0,0)),Vector((20,0,0)),'masonry')
backing.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in backing.data.vertices],[list(t.vertices) for t in backing.data.loop_triangles],all_triangles=True)
end=tree.ray_cast(Vector((1,0,1.6)),Vector((0,0,1)),10)[0]
middle=tree.ray_cast(Vector((10,0,1.6)),Vector((0,0,1)),10)[0]
assert end is not None and middle is not None and middle.z < end.z-.15,'Collision backing did not follow the varying crown'
assert tree.ray_cast(Vector((10,0,.1)),Vector((0,0,-1)),2)[0] is None,'Core floor plate blocks a neighbouring ramp'
sloped=passage.clearance(o,centre,x,-3,10,'sloped',slope=.2)
mesh=sloped.data; mesh.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[list(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
hit=tree.ray_cast(Vector((4,0,1.6)),Vector((0,0,1)),10)[0]
assert hit is not None and abs(hit.z-(o.crown+.8)) < .01,'Sloped arrival lost its roof height'
mirrored=passage.box('mirror',centre,x,1,0,2)
mirrored.matrix_world=Matrix.Diagonal((-1,1,1,1))
passage._bake_transform(mirrored)
bm=bmesh.new();bm.from_mesh(mirrored.data)
assert bm.calc_volume(signed=True)>0,'Mirrored stone winding inverted'
bm.free()
templates=passage._ring_variants(core.rng(24,'test'),masonry.Opening(-.5,.5),False,40,count=1)
assert templates and templates[0], 'Isolated arch template generation failed'
layout=json.loads((core.ROOT/'content/environments/procedural_bridge_v1/layout.json').read_text())
_,nodes=architecture.network(layout)
node=nodes[(22.0,-10.0,-30.0)]
arrival=next(a for a in node['arrivals'] if a['route']['id']=='chapel_approach' and a['run']==0)
d=arrival['away']; middle=node['at']+d*3.1
wall=passage.box('crossing_wall',middle,Vector((1,0,0)),3,-.15,5.6)
cutters=architecture.joining_clearances(node,'return_gallery',4)
groups={0:[wall]};passage.subtract(groups,cutters)
assert groups[0], 'Joining clearance deleted the entire wall'
wall.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in wall.data.vertices],[list(t.vertices) for t in wall.data.loop_triangles],all_triangles=True)
assert tree.ray_cast(middle-d*4.5+Vector((0,0,1.6)),d,9)[0] is None,'Neighbour wall blocks the joining route'
assert tree.ray_cast(middle+Vector((0,0,1.6)),Vector((0,0,1)),6)[0] is not None,'Neighbour cut removed the roof'
# Mortar must be behind a roof's intrados, rather than coplanar with its stones.
open_stone=passage.box('open_library_stone',centre,x,3,0,6)
shell=bmesh.new();shell.from_mesh(open_stone.data)
bmesh.ops.delete(shell,geom=[f for f in shell.faces if f.normal.y > .5],context='FACES')
assert any(e.is_boundary for e in shell.edges),'Hidden-back fixture is already closed'
shell.to_mesh(open_stone.data);shell.free()
passage.close_stone_back(open_stone)
shell=bmesh.new();shell.from_mesh(open_stone.data)
assert all(e.is_manifold for e in shell.edges),'Library stone is not a solid before the opening cut'
shell.free()
opening=passage.clearance(o,centre,Vector((0,1,0)),-5,5,'stone_doorway')
passage.subtract({0:[open_stone]},[opening])
open_stone.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in open_stone.data.vertices],[list(t.vertices) for t in open_stone.data.loop_triangles],all_triangles=True)
assert tree.ray_cast(Vector((0,-4,1.6)),Vector((0,1,0)),8)[0] is None,'Solid wall opening retains detached faces'
recessed=passage.clearance(o,centre,x,-3,10,'recessed',padding=passage.RECESS)
recessed.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in recessed.data.vertices],[list(t.vertices) for t in recessed.data.loop_triangles],all_triangles=True)
hit=tree.ray_cast(Vector((0,0,1.6)),Vector((0,0,1)),10)[0]
assert hit is not None and hit.z > o.crown+.03,'Mortar cuts mask the roof stones'
# The marked nave bay used a horizontal landing over a falling mitred ramp.
node=nodes[(-14.0,-19.0,24.0)]
flag=passage.box('ramp_flag',Vector((-16.6849,-24.3704,-19)),x,.02,-.12,.015)
before=max(v.co.z for v in flag.data.vertices)
architecture.fit_junction_floor({21:[flag]},node)
assert max(v.co.z for v in flag.data.vertices) < before-.08,'Bay flag still floats above the nave ramp'
# Overlap has one stable owner, rather than two nearly coincident flag layers.
node=nodes[(-41.0,-23.0,14.0)]
assert not architecture.joining_floor_clearances(node,'cave_bypass',0),'First paving owner was cut away'
assert architecture.joining_floor_clearances(node,'root_tunnel',2),'Second paving layer retains its overlap'
print('PASSAGE_SELFTEST_OK',flush=True)
rock['frame']=[1,0,0,0,0,1,0,-1,0]
architecture.map_stone(rock,core.rng(177,'rock-uv-a'))
first=[tuple(v.uv) for v in rock.data.uv_layers['UVMap'].data]
rock['frame']=[0,1,0,0,0,1,1,0,0]
architecture.map_stone(rock,core.rng(177,'rock-uv-b'))
assert first==[tuple(v.uv) for v in rock.data.uv_layers['UVMap'].data],'Rock strata change with arbitrary object frame or random seed'
print('PASSAGE_ROCK_UV_CONTINUITY_OK',flush=True)
# Two independent builders must meet on the same stone surface, colour and UV.
from procgen import stonekinds
passage.PAVING=stonekinds.Library(core.rng(177,'field-test'),'floor_flag',count=4,triangles=110,name='flag')
left=passage.pave_field(passage.PAVING,Vector((0,.35,0)),Vector((1,0,0)),1,.34,'left')
right=passage.pave_field(passage.PAVING,Vector((1,.35,0)),Vector((1,0,0)),1,.34,'right')
l=next(o for o in left if list(o['paving_cell'])==[1,0])
r=next(o for o in right if list(o['paving_cell'])==[1,0])
assert l['tone']==r['tone'],'A shared flag changes colour across the builder boundary'
for obj in (l,r):architecture.map_stone(obj,core.rng(177,'irrelevant',obj.name))
def seam(obj):
    mesh=obj.data
    return {(round(mesh.vertices[loop.vertex_index].co.y,5),round(mesh.vertices[loop.vertex_index].co.z,5)):
            tuple(round(v,4) for v in mesh.uv_layers['UVMap'].data[i].uv)
            for i,loop in enumerate(mesh.loops) if abs(mesh.vertices[loop.vertex_index].co.x-1)<1e-5 and
            mesh.polygons[next(p.index for p in mesh.polygons if i in p.loop_indices)].normal.z>.7}
a,b=seam(l),seam(r)
assert a and b and a==b,('Paving surface/UV seam between independent builders',a,b)
print('PASSAGE_PAVING_CONTINUITY_OK',flush=True)
# Real cave_bypass_2-back stripe: the old junction core led the rock by 34 cm.
node=nodes[(-43.0,-23.0,-6.0)]
hewn=passage.skew_bay(None,core.rng(177,'hewn-regression'),node['profile'],node['at'],node['axis'],node['arrivals'],'hewn_regression')
eye=core.to_blender([-40.03147888,-21.4,-3.62518286])
direction=Vector((-.919336677,.179663002,.350059003))
def first_distance(objects):
    distances=[]
    for obj in objects:
        obj.data.calc_loop_triangles()
        tree=BVHTree.FromPolygons([obj.matrix_world@v.co for v in obj.data.vertices],
                                 [t.vertices[:] for t in obj.data.loop_triangles],all_triangles=True)
        hit=tree.ray_cast(eye,direction,20)
        if hit[0] is not None:distances.append(hit[3])
    return min(distances) if distances else float('inf')
rock_distance,core_distance=first_distance(hewn[0]),first_distance(hewn[20])
assert rock_distance < core_distance-.025,('Mortar protrudes through hewn lining',rock_distance,core_distance)
print('PASSAGE_HEWN_STRIPE_REGRESSION_OK',rock_distance,core_distance,flush=True)
