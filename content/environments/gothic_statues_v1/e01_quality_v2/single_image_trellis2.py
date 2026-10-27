"""Run the prepared larger shape model after official DINOv3 access is granted."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

import numpy as np
from PIL import Image
from huggingface_hub import get_hf_file_metadata,hf_hub_url,hf_hub_download
import trimesh

root=Path(__file__).resolve().parent
cl3d=Path('/Users/theochernin/Projects/CherninLab3D')
parser=argparse.ArgumentParser()
parser.add_argument('--resolution',type=int,choices=[512,768,1024],default=512)
parser.add_argument('--steps',type=int,default=12)
parser.add_argument('--seed',type=int,default=42)
parser.add_argument('--check-only',action='store_true')
args=parser.parse_args()
weights=cl3d/'models/TRELLIS.2-4B/ckpts'
required=['ss_flow_img_dit_1_3B_64_bf16','slat_flow_img2shape_dit_1_3B_512_bf16','shape_dec_next_dc_f16c32_fp16']
if args.resolution>512:required+=['slat_flow_img2shape_dit_1_3B_1024_bf16']
assert all((weights/(name+'.safetensors')).is_file() for name in required)
assert (cl3d/'.venv-trellis2/bin/python').exists()
encoder='facebook/dinov3-vitl16-pretrain-lvd1689m'
try:meta=get_hf_file_metadata(hf_hub_url(encoder,'model.safetensors'))
except Exception as exc:
    print('Required official DINOv3 access unavailable:',type(exc).__name__)
    print('Meta access request is awaiting review.' if 'awaiting a review' in str(exc) else str(exc).splitlines()[0][:160])
    sys.exit(2)
print('TRELLIS2_PREFLIGHT_OK',meta.commit_hash,flush=True)
if args.check_only:sys.exit(0)
for name in ['model.safetensors','config.json','preprocessor_config.json']:
    hf_hub_download(encoder,name,revision=meta.commit_hash)

folder=root/'single_image_retry_v1'/f'trellis2_{args.resolution}_seed{args.seed}'
folder.mkdir(exist_ok=True)
source=root/'four_view_reconstruction_v1/inputs/front_masked.png'
image=Image.open(source).convert('RGBA')
alpha=np.asarray(image.getchannel('A'));yy,xx=np.where(alpha>204)
assert len(xx)>0
cx=(xx.min()+xx.max())/2;cy=(yy.min()+yy.max())/2
side=round(max(xx.max()-xx.min(),yy.max()-yy.min())*1.2)
crop=image.crop((round(cx-side/2),round(cy-side/2),round(cx+side/2),round(cy+side/2))).resize((512,512),Image.Resampling.LANCZOS)
pixels=np.asarray(crop).astype(np.float32)/255
Image.fromarray((pixels[:,:,:3]*pixels[:,:,3:4]*255).astype(np.uint8)).save(folder/'conditioning.png')
checkpoint=folder/'checkpoints'
command=[str(cl3d/'.venv-trellis2/bin/python'),str(cl3d/'vendor/trellis2mlx/generate.py'),
    '--image',str(folder/'conditioning.png'),'--output',str(folder/'raw.glb'),
    '--resolution',str(args.resolution),'--steps',str(args.steps),'--seed',str(args.seed),
    '--no-rembg','--target-faces','0','--no-cleanup','--no-hole-fill',
    '--save-checkpoints',str(checkpoint),'--stop-after-stage','mesh_raw']
if args.resolution==512:command.append('--no-cascade')
started=time.monotonic()
subprocess.run(command,cwd=cl3d/'vendor/trellis2mlx',check=True)
data=np.load(checkpoint/'mesh_raw.npz');vertices=data['vertices'];faces=data['faces']
assert len(faces)>0 and np.isfinite(vertices).all()
vertices=vertices[:,[0,2,1]]*np.array([1,1,-1])
mesh=trimesh.Trimesh(vertices,faces,process=False);mesh.export(folder/'raw.glb',include_normals=True)
mesh.vertices-=mesh.bounds.mean(axis=0);mesh.vertices*=1.4/max(mesh.extents);mesh.vertices[:,1]-=mesh.bounds[0,1]
mesh.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral marble geometry review',baseColorFactor=[201,193,174,255],metallicFactor=0,roughnessFactor=.78))
mesh.export(folder/'preview.glb',include_normals=True)
(folder/'result.json').write_text(json.dumps({'model':'microsoft/TRELLIS.2-4B',
    'model_revision':'af44b45f2e35a493886929c6d786e563ec68364d','encoder':encoder,
    'encoder_revision':meta.commit_hash,'input_count':1,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'resolution_requested':args.resolution,'steps':args.steps,'seed':args.seed,'runtime':'MLX native',
    'triangles':len(mesh.faces),'cleanup':'none; native raw topology retained','seconds':time.monotonic()-started,
    'command':command},indent=2)+'\n')
print('TRELLIS2_SINGLE_IMAGE_OK',len(mesh.faces),flush=True)
