"""Compare one higher-resolution Oracle run using the same single-image input."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

import numpy as np
import trimesh

root=Path(__file__).resolve().parent
cl3d=Path('/Users/theochernin/Projects/CherninLab3D')
folder=root/'oracle_768';folder.mkdir(exist_ok=True)
shutil.copy2(root/'oracle_512/conditioning.png',folder/'conditioning.png')
native=cl3d/'vendor/trellis2mlx/generate.py'
bootstrap='import mlx.core as mx,runpy,sys;mx.set_memory_limit(42*1024**3);sys.argv=[sys.argv[1],*sys.argv[2:]];runpy.run_path(sys.argv[0],run_name="__main__")'
command=[str(cl3d/'.venv-trellis2/bin/python'),'-u','-c',bootstrap,str(native),
    '--image',str(folder/'conditioning.png'),'--output',str(folder/'raw.glb'),
    '--resolution','768','--steps','12','--seed','42','--max-tokens','32768',
    '--no-rembg','--target-faces','0','--no-cleanup','--no-hole-fill',
    '--save-checkpoints',str(folder/'checkpoints'),'--stop-after-stage','mesh_raw']
started=time.monotonic()
subprocess.run(command,cwd=native.parent,check=True)
data=np.load(folder/'checkpoints/mesh_raw.npz')
v=data['vertices'][:,[0,2,1]]*np.array([1,1,-1]);f=data['faces']
assert len(f)>0 and np.isfinite(v).all()
trimesh.Trimesh(v,f,process=False).export(folder/'raw.glb',include_normals=True)
meta=json.loads((folder/'checkpoints/mesh_raw.json').read_text())
base=json.loads((root/'oracle_512/result.json').read_text())
base.update(resolution_requested=768,resolution_actual=meta['mesh_grid_size'],triangles=len(f),
    max_tokens=32768,memory_limit_guideline_gib=42,
    conditioning_sha256=hashlib.sha256((folder/'conditioning.png').read_bytes()).hexdigest(),
    seconds=time.monotonic()-started,command=command)
(folder/'result.json').write_text(json.dumps(base,indent=2)+'\n')
print('ORACLE_HIGHER_RESOLUTION_OK',len(f),meta['mesh_grid_size'],flush=True)
