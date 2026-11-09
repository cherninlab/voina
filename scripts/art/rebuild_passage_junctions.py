"""Rebuild skew junctions, or named routes and their nodes (Blender 5.2).

Pass route IDs after -- to rebuild from closed stone templates, rather than
trying volume cuts on an older merged bake with omitted backs.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_architecture as architecture
from procgen import core, passage, stonekinds, stonelib

core.empty_scene()
layout=json.loads((core.ROOT/'content/environments/procedural_bridge_v1/layout.json').read_text())
_,nodes=architecture.network(layout)
rng=core.rng(177,'junction-stones')
lib=stonelib.Library(rng,'squared_rubble',count=24,triangles=200)
passage.PAVING=stonekinds.Library(core.rng(177,'passage-floor-field'),'floor_flag',count=24,triangles=110,name='flag')
elements=[]
portals_only='--portals-only' in core.args()
if core.args() and not portals_only:
    quoins=stonelib.Library(rng,'ashlar',count=8,triangles=200,aspects=(1,2.6),name='quoin')
    elements,_,_,_=architecture.build_network(layout,set(core.args()[0].split(',')),rng,lib,quoins)
if portals_only:
    quoins=stonelib.Library(rng,'ashlar',count=8,triangles=200,aspects=(1,2.6),name='quoin')
for node in ([] if elements else sorted(nodes.values(),key=lambda n:n['godot'])):
    if (portals_only and node['kind'] != 'portal') or (not portals_only and not architecture.skew_node(node)):
        continue
    label='node_%d_%d_%d'%tuple(round(c) for c in node['godot'])
    if portals_only:
        arrival=node['arrivals'][0]
        groups=passage.portal(lib,core.rng(177,'passage',label),quoins,arrival['profile'],node['at'],-arrival['away'],label)
    else:
        groups=passage.skew_bay(lib,core.rng(177,'passage',label),node['profile'],node['at'],node['axis'],node['arrivals'],label)
        architecture.fit_junction_floor(groups,node)
    hewn=all(a['route']['id'] in ('root_tunnel','cave_bypass') for a in node['arrivals'])
    form='portal' if portals_only else 'hewn barrel chamber' if hewn else 'groin bay'
    architecture.PASSAGE_REPORTS[label]={'situation':{'form':form,'routes':sorted({a['route']['id'] for a in node['arrivals']}),
        'rule':'single hewn chamber with actual arrival openings' if hewn and not portals_only else 'partitioned vault webs; recessed backing; ramp-fitted bay flags'},
        'generator':'scripts/art/rebuild_passage_junctions.py','wall_library_count':24,'floor_library_count':24}
    elements.append(('passages',label,groups))
    print('JUNCTION_REBUILT',label,flush=True)
core.flush_trash()
architecture.bake_all(elements,core.ROOT/'content/environments/procedural_architecture_v1')
print('JUNCTIONS_BAKED',len(elements),flush=True)
