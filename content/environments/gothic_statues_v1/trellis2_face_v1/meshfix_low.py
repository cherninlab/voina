"""Apply dedicated digitized-mesh repair to the small reduced mesh."""
import json
from pathlib import Path
import time

import numpy as np
import pymeshfix
import trimesh

root=Path(__file__).resolve().parent;started=time.monotonic()
mesh=trimesh.load(root/'oracle_150k.glb',force='mesh',process=False)
mesh.merge_vertices(merge_tex=True,merge_norm=True,digits_vertex=7)
fix=pymeshfix.MeshFix(mesh.vertices.astype(np.float64),mesh.faces.astype(np.int32),verbose=True)
# Keep separate horn/hair components; do not connect unrelated nearby surfaces.
fix.repair(joincomp=False,remove_smallest_components=False)
out=trimesh.Trimesh(fix.points,fix.faces,process=False)
out.visual=mesh.visual
out.export(root/'oracle_repaired_low.glb',include_normals=True)
report={'tool':'PyMeshFix 0.18.1 / MeshFix','join_components':False,'remove_smallest_components':False,
    'source_triangles':len(mesh.faces),'triangles':len(out.faces),
    'watertight':bool(out.is_watertight),'winding_consistent':bool(out.is_winding_consistent),
    'seconds':time.monotonic()-started}
(root/'meshfix.json').write_text(json.dumps(report,indent=2)+'\n')
print('MESHFIX_REPAIR_OK',json.dumps(report),flush=True)
