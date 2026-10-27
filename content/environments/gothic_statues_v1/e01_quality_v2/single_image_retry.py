"""Retry the approved new statue with one image and installed shape models."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK','1')
root=Path(__file__).resolve().parent
cl3d=Path('/Users/theochernin/Projects/CherninLab3D')
parser=argparse.ArgumentParser()
parser.add_argument('--model',choices=['trellis','triposg'],required=True)
parser.add_argument('--steps',type=int,default=75)
parser.add_argument('--seed',type=int,default=42)
args=parser.parse_args()
folder=root/'single_image_retry_v1'/f'{args.model}_seed{args.seed}'
folder.mkdir(parents=True,exist_ok=True)
source=root/'four_view_reconstruction_v1/inputs/front_masked.png'
assert source.exists(),source
import numpy as np
from PIL import Image
import torch
import trimesh
torch.set_num_threads(4)
assert torch.backends.mps.is_available()
image=Image.open(source).convert('RGBA')
started=time.monotonic()
if args.model=='trellis':
    os.environ['SPARSE_BACKEND']='pytorch';os.environ['ATTN_BACKEND']='sdpa'
    sys.path.insert(0,str(cl3d/'vendor/trellis-mac-mps'))
    from trellis.pipelines import TrellisImageTo3DPipeline
    pipe=TrellisImageTo3DPipeline.from_pretrained(str(cl3d/'models/TRELLIS-E01-mesh'))
    pipe.to(torch.device('mps'))
    print('SINGLE_IMAGE_TRELLIS_START',flush=True)
    output=pipe.run(image,seed=args.seed,formats=['mesh'],
        sparse_structure_sampler_params={'steps':args.steps},slat_sampler_params={'steps':args.steps})
    result=output['mesh'][0];assert result.success
    vertices=result.vertices.detach().float().cpu().numpy()
    vertices=vertices[:,[0,2,1]]*np.array([1,1,-1])
    vertices*=2/max(np.ptp(vertices,axis=0))
    rgb=result.vertex_attrs[:,:3].detach().float().cpu().numpy()
    rgba=np.column_stack([np.clip(rgb*255,0,255).astype(np.uint8),np.full(len(rgb),255,np.uint8)])
    mesh=trimesh.Trimesh(vertices,result.faces.detach().cpu().numpy(),vertex_colors=rgba,process=True)
    model='microsoft/TRELLIS-image-large';revision='25e0d31ffbebe4b5a97464dd851910efc3002d96'
    settings={'structure_steps':args.steps,'shape_steps':args.steps,'preprocess':'published native foreground crop and black composite'}
else:
    sys.path.insert(0,str(cl3d/'vendor/TripoSG'))
    from triposg.pipelines.pipeline_triposg import TripoSGPipeline
    box=image.getchannel('A').getbbox();assert box
    crop=image.crop(box);size=round(max(crop.size)*1.2)
    image=Image.new('RGB',(size,size),'white');image.paste(crop,((size-crop.width)//2,(size-crop.height)//2),crop)
    image.save(folder/'conditioning.png')
    print('Loading single-image TripoSG',flush=True)
    pipe=TripoSGPipeline.from_pretrained(str(cl3d/'models/TripoSG'),torch_dtype=torch.float16,
        local_files_only=True).to('mps',torch.float16)
    output=pipe(image=image,num_inference_steps=args.steps,num_tokens=2048,guidance_scale=7,
        generator=torch.Generator(device='cpu').manual_seed(args.seed),dense_octree_depth=7,
        hierarchical_octree_depth=9,use_flash_decoder=False)
    mesh=output.meshes[0]
    model='VAST-AI/TripoSG';revision='2c1c516d22d58db486a058d98d31bb6177344e06'
    settings={'steps':args.steps,'tokens':2048,'guidance':7,'extraction':'hierarchical marching cubes 7 to 9',
        'preprocess':'foreground crop, 20 percent side padding, white composite; published image encoder size'}
assert len(mesh.faces)>0 and np.isfinite(mesh.vertices).all()
mesh.export(folder/'raw.glb',include_normals=True)
parts=sorted(mesh.split(only_watertight=False),key=lambda m:m.area,reverse=True)
main=parts[0];fraction=float(main.area/mesh.area)
assert fraction>.9,(args.model,fraction)
main.vertices-=main.bounds.mean(axis=0);main.vertices*=1.4/max(np.ptp(main.vertices,axis=0));main.vertices[:,1]-=main.vertices[:,1].min()
main.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
    name='Neutral marble geometry review',baseColorFactor=[201,193,174,255],metallicFactor=0,roughnessFactor=.78))
main.export(folder/'preview.glb',include_normals=True)
report={'model':model,'model_revision':revision,'input_count':1,'source':str(source),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'view':'front','device':'mps',
    'seed':args.seed,**settings,'raw_triangles':len(mesh.faces),'raw_watertight':bool(mesh.is_watertight),
    'preview_triangles':len(main.faces),'preview_watertight':bool(main.is_watertight),
    'preview_retained_area_fraction':fraction,'cleanup':'largest connected component only, no hand edits or smoothing',
    'seconds':time.monotonic()-started,'mesh_sha256':hashlib.sha256((folder/'preview.glb').read_bytes()).hexdigest()}
(folder/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print('SINGLE_IMAGE_RETRY_OK',json.dumps(report),flush=True)
