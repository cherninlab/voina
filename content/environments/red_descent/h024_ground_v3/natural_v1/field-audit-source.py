import sys,json
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'scripts/art'))
import build_architecture as architecture
from procgen import cave_ground,core,passage
from mathutils import Vector
layout=json.loads(Path('content/environments/procedural_bridge_v1/layout.json').read_text())
runs,nodes=architecture.network(layout)
cave_ground.SPINES=[(Vector((*architecture.blender_point(r['points'][i])[:2],0)),Vector((*architecture.blender_point(r['points'][i+1])[:2],0)),architecture.profile(r,layout).half,.12 if r['id']=='cave_bypass' else .02) for r in layout['routes'] if r['id'] in ('root_tunnel','cave_bypass') for i in range(len(r['points'])-1)]
cave_ground.TRANSITIONS=[]
for r in layout['routes']:
 if r['id'] not in ('root_tunnel','cave_bypass'):continue
 for stretch in runs[r['id']]:
  if stretch is None:continue
  segment,t0,t1,start,end=stretch
  a,b=(architecture.blender_point(r['points'][i]) for i in (segment,segment+1))
  for endpoint,t in ((start,t0),(end,t1)):
   if endpoint[0]=='room':cave_ground.TRANSITIONS.append((a.lerp(b,t),0))
   elif endpoint[0]=='node' and nodes[endpoint[1]].get('turning'):
    n=nodes[endpoint[1]];cave_ground.TRANSITIONS.append((n['turn_centre'],n['profile'].half+passage.THICKNESS))
samples=[]
for r in layout['routes']:
 if r['id'] not in ('root_tunnel','cave_bypass'):continue
 for stretch in runs[r['id']]:
  if stretch is None:continue
  segment,t0,t1,*_=stretch
  a,b=(architecture.blender_point(r['points'][i]) for i in (segment,segment+1));along=(b-a).normalized();side=along.cross(passage.UP)
  count=max(2,int((b-a).length*(t1-t0)/.3))
  for k in range(1,count):
   for across in (-1.5,-.75,0,.75,1.5):
    p=a.lerp(b,t0+(t1-t0)*k/count)+side*across
    earth,pool,bank=cave_ground.field(p)
    samples.append({'route':r['id'],'at':core.to_godot(p),'along':core.to_godot(along),'earth':earth,'pool':pool,'bank':bank,'height':cave_ground.height(p,p.z)-p.z})
pools=sorted((p for p in samples if p['pool']>.55 and p['bank']<.1),key=lambda p:p['pool'],reverse=True)
earth=sorted((p for p in samples if p['earth']>.9 and p['pool']<.05 and p['bank']<.1),key=lambda p:p['earth'],reverse=True)
assert pools and earth,'No visible soil/puddle regions'
summary={'samples':len(samples),'soil_fraction':sum(p['earth']>.78 for p in samples)/len(samples),'puddle_fraction':sum(p['pool']>.5 for p in samples)/len(samples),'views':{'earth':earth[0],'puddle':pools[0]},'routes':{r: {'samples':len([p for p in samples if p['route']==r]),'soil_fraction':sum(p['earth']>.78 for p in samples if p['route']==r)/sum(p['route']==r for p in samples)} for r in ('root_tunnel','cave_bypass')}}
Path('/tmp/h024-natural-field-audit.json').write_text(json.dumps(summary,indent=2)+'\n')
print('NATURAL_FIELD_AUDIT_OK',json.dumps(summary),flush=True)
