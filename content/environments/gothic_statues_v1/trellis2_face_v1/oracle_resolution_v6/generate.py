"""Generate the 768/1536 comparison with one source, seed and HR conditioning."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import numpy as np
from PIL import Image
import trimesh

root=Path(__file__).resolve().parent
cl3d=Path("/Users/theochernin/Projects/CherninLab3D")
parser=argparse.ArgumentParser()
parser.add_argument("--resolution",type=int,choices=[768,1536],required=True)
args=parser.parse_args()
folder=root/str(args.resolution);folder.mkdir(exist_ok=True)
assert not (folder/"checkpoints/mesh_raw.npz").exists(), "Existing trial preserved"
source=root/"source.png"
if not source.exists():
    shutil.copy2(root.parent/"plastic_oracle_v5/source.png",source)
os.environ.setdefault("U2NET_HOME",str(cl3d/"models/matting/models/u2net"))
sys.path.insert(0,str(cl3d/"vendor/trellis2mlx"))
from trellmlx.preprocess import preprocess_image_with_provenance
prepared=preprocess_image_with_provenance(source)
foreground=prepared.image
side=round(max(foreground.size)*1.15)
canvas=Image.new("RGB",(side,side))
canvas.paste(foreground,((side-foreground.width)//2,(side-foreground.height)//2))
canvas.resize((1024,1024),Image.Resampling.LANCZOS).save(folder/"conditioning.png")
(folder/"preprocess.json").write_text(json.dumps(prepared.provenance,indent=2)+"\n")
command=[str(cl3d/".venv-trellis2/bin/python"),"-u",str(root/"native_hr_conditioning.py"),
         "--image",str(folder/"conditioning.png"),"--output",str(folder/"raw.glb"),
         "--resolution",str(args.resolution),"--steps","24","--seed","42","--max-tokens","32768",
         "--no-rembg","--target-faces","0","--no-cleanup","--no-hole-fill",
         "--save-checkpoints",str(folder/"checkpoints"),"--stop-after-stage","mesh_raw"]
started=time.monotonic()
subprocess.run(command,cwd=cl3d/"vendor/trellis2mlx",check=True)
data=np.load(folder/"checkpoints/mesh_raw.npz")
v=data["vertices"][:,[0,2,1]]*np.array([1,1,-1]);f=data["faces"]
mesh=trimesh.Trimesh(v,f,process=False)
mesh.vertices-=mesh.bounds.mean(axis=0);mesh.vertices*=1.4/max(mesh.extents)
mesh.vertices[:,1]-=mesh.bounds[0,1]
mesh.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name="Neutral inspection",baseColorFactor=[180,169,149,255],roughnessFactor=.78,doubleSided=True))
mesh.export(folder/"raw.glb",include_normals=True)
run=json.loads((root.parent/"plastic_oracle_v5/result.json").read_text())
run.update(resolution_requested=args.resolution,resolution_actual=args.resolution,
           source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
           conditioning_sha256=hashlib.sha256((folder/"conditioning.png").read_bytes()).hexdigest(),
           conditioning_dimensions=[1024,1024],lr_feature_pixels=512,hr_feature_pixels=1024,
           triangles=len(f),vertices=len(v),cleanup="none",seconds=time.monotonic()-started,
           command=command,preprocessing=prepared.provenance,
           peak_mlx_memory_gib=json.loads((folder/"runtime_patch.json").read_text())["peak_mlx_memory_gib"])
(folder/"result.json").write_text(json.dumps(run,indent=2)+"\n")
print("HIGH_RES_GENERATION_OK",args.resolution,len(f),flush=True)
