"""Remove only tiny disconnected artifacts from the selected reconstruction."""
import json
from pathlib import Path
import trimesh

root = Path(__file__).resolve().parent
source = root/'mesh/triposg_42_raw.glb'
mesh = trimesh.load(source, force='mesh')
parts = sorted(mesh.split(only_watertight=False),key=lambda part:len(part.faces),reverse=True)
main = parts[0]
assert len(main.faces)/len(mesh.faces) > .999, 'Review detached anatomy before discarding components'
assert main.is_watertight and main.is_winding_consistent
main.export(root/'mesh/clean_high.glb',include_normals=True)
report = {'source':source.name,'operation':'retain the reviewed main shell; remove tiny disconnected scraps',
    'retained_triangles':len(main.faces),'retained_watertight':bool(main.is_watertight),
    'removed_triangles':sum(len(part.faces) for part in parts[1:]),
    'removed_components':len(parts)-1,'anatomy_or_pose_changes':False}
(root/'mesh/cleanup.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
