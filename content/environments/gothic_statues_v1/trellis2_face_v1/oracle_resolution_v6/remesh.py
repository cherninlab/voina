"""Apply the official geometry remeshing branch using the optional Metal backend."""
import argparse
import hashlib
import importlib
import json
from pathlib import Path
import sys
import time
from types import SimpleNamespace

import numpy as np
import torch
import trimesh

root=Path(__file__).resolve().parent
native=Path("/Users/theochernin/Projects/CherninLab3D/vendor/trellis2mlx")
sys.path.insert(0,str(native))
from trellmlx.source_metal_remesh import rebuild_surface, verify_deep_bvh_traversal
import cumesh
import mtlbvh

parser=argparse.ArgumentParser()
parser.add_argument("--resolution",type=int,choices=[768,1536])
parser.add_argument("--smoke",action="store_true")
args=parser.parse_args()
assert args.smoke != (args.resolution is not None)
torch.set_num_threads(4)
backend=SimpleNamespace(torch=torch,mesh=cumesh.CuMesh,bvh=cumesh.cuBVH,
                        remesh=cumesh.remeshing.remesh_narrow_band_dc)
identity={}
for name in ["cumesh","cumesh._C","cumesh.metal_backend","cumesh.metal_remeshing","mtlbvh","mtlbvh._C"]:
    p=Path(importlib.import_module(name).__file__).resolve()
    identity[name]={"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()}
for name in ["cumesh._C","mtlbvh._C"]:
    p=Path(identity[name]["path"]).parent/(name.split(".")[0]+".metallib")
    assert p.exists()
    identity[name+".metallib"]={"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()}
folder=root/"backend_smoke" if args.smoke else root/str(args.resolution)/"remeshed"
folder.mkdir(parents=True,exist_ok=True)
assert not (folder/"remesh.json").exists(), "Existing trial preserved"
started=time.monotonic()
report={"status":"running","backend":identity,"torch":torch.__version__,"stages":[],
        "scope":"official geometry stage order via Torch-facing Metal kernels; no texture stage"}
path=folder/"remesh.json"
def write():
    path.write_text(json.dumps(report,indent=2)+"\n")
def phase(name):
    report["active_phase"]=name;write();print("REMESH_PHASE",name,flush=True)
def capture(name,arrays):
    v,f=arrays["vertices"],arrays["faces"]
    report["stages"].append({"name":name,"vertices":len(v),"triangles":len(f),
                             "seconds":time.monotonic()-started});write()
    if name=="rebuilt":
        np.savez_compressed(folder/"rebuilt_full.npz",vertices=v.numpy(),faces=f.numpy())
try:
    if args.smoke:
        report["deep_bvh"]={}
        verify_deep_bvh_traversal(backend,report["deep_bvh"])
        cube=trimesh.creation.box(extents=[.6]*3)
        vertices=cube.vertices.astype(np.float32);faces=cube.faces.astype(np.int32)
        grid,target=32,2000
    else:
        smoke=json.loads((root/"backend_smoke/remesh.json").read_text())
        assert smoke["status"]=="complete" and smoke["backend"]==identity, "Backend smoke identity mismatch"
        data=np.load(root/str(args.resolution)/"checkpoints/mesh_raw.npz")
        vertices=data["vertices"].astype(np.float32);faces=data["faces"].astype(np.int32)
        grid,target=args.resolution,2000000
    report.update(grid=grid,target_faces=target,band=1.,project_back=.9)
    result,_,_,_=rebuild_surface(torch.from_numpy(vertices),torch.from_numpy(faces),
        backend=backend,grid_size=grid,target_faces=target,band=1.,project_back=.9,
        capture=capture,phase=phase,verbose=True)
    v,f=[a.numpy() for a in result.read()]
    assert len(f)>0 and np.isfinite(v).all() and f.min()>=0 and f.max()<len(v)
    if args.smoke:
        assert abs(float(np.ptp(v,axis=0).max())-.6)<.08
    # Same transform as the raw source, so before/after geometry stays aligned.
    source_v=vertices[:,[0,2,1]]*np.array([1,1,-1])
    center=(source_v.max(0)+source_v.min(0))/2
    scale=1.4/np.ptp(source_v,axis=0).max()
    floor=(source_v[:,1].min()-center[1])*scale
    v=(v[:,[0,2,1]]*np.array([1,1,-1])-center)*scale
    v[:,1]-=floor
    mesh=trimesh.Trimesh(v,f,process=False)
    mesh.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
        name="Neutral remeshed inspection",baseColorFactor=[180,169,149,255],
        roughnessFactor=.78,doubleSided=False))
    mesh.export(folder/"statue.glb",include_normals=True)
    report.update(status="complete",active_phase=None,seconds=time.monotonic()-started,
        vertices=len(v),triangles=len(f),watertight=bool(mesh.is_watertight),
        winding_consistent=bool(mesh.is_winding_consistent))
except BaseException as exc:
    report.update(status="failed",error=f"{type(exc).__name__}: {exc}")
    raise
finally:
    write()
print("METAL_REMESH_OK",json.dumps({k:v for k,v in report.items() if k!="backend" and k!="stages"}),flush=True)
