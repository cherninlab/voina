"""Reconstruct E01 with the pinned MIT TripoSG model; no background model needed."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
parser = argparse.ArgumentParser()
parser.add_argument('--cl3d-root', type=Path, required=True)
parser.add_argument('--seed', type=int, default=1234)
parser.add_argument('--steps', type=int, default=50)
parser.add_argument('--name', default='triposg')
args = parser.parse_args()
root = Path(__file__).resolve().parent
vendor = args.cl3d_root / 'vendor/TripoSG'
sys.path.insert(0, str(vendor))
import numpy as np
from PIL import Image
import torch
from triposg.pipelines.pipeline_triposg import TripoSGPipeline

started = time.monotonic()
source = root / 'source/approved.png'
rgba = Image.open(source).convert('RGBA')
bbox = rgba.getchannel('A').getbbox()
assert bbox, 'Source has no foreground'
crop = rgba.crop(bbox)
side = round(max(crop.size) * 1.2)
image = Image.new('RGB', (side, side), 'white')
image.paste(crop, ((side-crop.width)//2, (side-crop.height)//2), crop)
image.save(root / 'source/triposg_input.png')
print('Loading TripoSG on MPS', flush=True)
pipe = TripoSGPipeline.from_pretrained(
    str(args.cl3d_root / 'models/TripoSG'), torch_dtype=torch.float16,
    local_files_only=True,
).to('mps', torch.float16)

def progress(pipeline, index, timestep, values):
    if (index+1) % 10 == 0:
        print(f'Sampling {index+1}/{args.steps}, {time.monotonic()-started:.1f}s', flush=True)
    if index == args.steps-1:
        torch.save(values['latents'].detach().cpu(), root / f'mesh/{args.name}_latents.pt')
    return values

output = pipe(
    image=image, generator=torch.Generator(device='cpu').manual_seed(args.seed),
    num_inference_steps=args.steps, num_tokens=2048, guidance_scale=7.0,
    dense_octree_depth=7, hierarchical_octree_depth=9,
    use_flash_decoder=False, callback_on_step_end=progress,
)
mesh = output.meshes[0]
assert len(mesh.faces) > 0 and np.isfinite(mesh.vertices).all()
target = root / f'mesh/{args.name}_raw.glb'
mesh.export(target, include_normals=True)
metadata = {
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'model': 'VAST-AI/TripoSG',
    'model_revision': '2c1c516d22d58db486a058d98d31bb6177344e06',
    'code_revision': subprocess.check_output(['git','-C',str(vendor),'rev-parse','HEAD'], text=True).strip(),
    'license': 'MIT', 'device': 'mps', 'dtype': 'float16',
    'steps': args.steps, 'num_tokens': 2048, 'guidance': 7.0, 'seed': args.seed,
    'extraction': 'hierarchical marching cubes, depths 7 to 9',
    'preprocess': 'unchanged alpha crop, 10 percent padding, white composite',
    'vertices': len(mesh.vertices), 'triangles': len(mesh.faces),
    'watertight': bool(mesh.is_watertight),
    'winding_consistent': bool(mesh.is_winding_consistent),
    'bounds': mesh.bounds.tolist(), 'elapsed_seconds': time.monotonic()-started,
    'mesh_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
}
(root / f'mesh/{args.name}_raw.json').write_text(json.dumps(metadata, indent=2)+'\n')
print(json.dumps(metadata, indent=2), flush=True)
