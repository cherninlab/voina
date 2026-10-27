"""Compare denser decoding with separately conditioned head and hand geometry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback

root = Path(__file__).resolve().parent
base = root.parent / 'hunyuan21_oracle_v1'
lab = Path('/Users/theochernin/Projects/CherninLab3D')
compat = lab / 'vendor/hunyuan3d-2.1-mac-rocm'
upstream = lab / 'vendor/Hunyuan3D-2.1'
weights = lab / 'models/Hunyuan3D-2.1/hunyuan3d-dit-v2-1'
parser = argparse.ArgumentParser()
parser.add_argument('--jobs', nargs='+', choices=['body512', 'head384', 'raised384', 'hip384',
                    'head_context_black384', 'head_context_alpha384', 'head_context_alpha_fresh384',
                    'raised_context384', 'raised_context_black384', 'hip_context384', 'upper_body_black384'],
                    default=['head_context_black384', 'head_context_alpha384', 'raised_context384', 'hip_context384'])
args = parser.parse_args()
os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
os.environ.setdefault('PYTORCH_MPS_HIGH_WATERMARK_RATIO', '1.0')
os.environ.setdefault('PYTORCH_MPS_LOW_WATERMARK_RATIO', '0.8')
sys.path.insert(0, str(compat))
import torch
import backend
import compat_patches
from PIL import Image


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(8 << 20), b''):
            h.update(block)
    return h.hexdigest()


assert torch.backends.mps.is_available()
checkpoint_hash = digest(weights / 'model.fp16.ckpt')
assert checkpoint_hash == json.loads((base / 'model_artifacts.json').read_text())[
    'hunyuan3d-dit-v2-1/model.fp16.ckpt']['lfs']['oid']
compat_patches.apply(backend.detect(force_kind='mps', force_dtype='float16'))
sys.path.insert(0, str(upstream / 'hy3dshape'))
from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
compat_patches.patch_scheduler_timestep_lookup()
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_single_file(
    str(weights / 'model.fp16.ckpt'), str(weights / 'config.yaml'),
    device='mps', dtype=torch.float16, use_safetensors=False)
devices = {}
for name in ['model', 'vae', 'conditioner']:
    p = next(getattr(pipe, name).parameters())
    assert p.device.type == 'mps' and p.dtype == torch.float16
    devices[name] = {'device': str(p.device), 'dtype': str(p.dtype)}
print('DETAIL_MPS_READY', devices, flush=True)
for job in args.jobs:
    folder = root / job
    folder.mkdir(exist_ok=True)
    assert not (folder / 'receipt.json').exists(), f'Preserve existing trial: {job}'
    started = time.monotonic()
    source = base / '384_s42_maskfix/segmented_input.png' if job == 'body512' else root / 'inputs' / f'{job[:-3]}.png'
    resolution = 512 if job == 'body512' else 384
    report = {'status': 'running', 'model': 'tencent/Hunyuan3D-2.1', 'job': job,
              'checkpoint_sha256': checkpoint_hash, 'source_sha256': digest(source),
              'source': str(source), 'components': devices, 'torch': torch.__version__,
              'device': 'local Mac MPS', 'seed': 42, 'steps': 50, 'guidance': 5,
              'octree_resolution': resolution, 'query_chunk': 8000, 'textures': False,
              'decoder': type(pipe.vae.volume_decoder).__name__}

    def save():
        report['seconds'] = time.monotonic() - started
        (folder / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    save()
    try:
        if job == 'body512':
            latent_path = base / '384_s42_maskfix/shape_latents.pt'
            report.update(method='Decode the same saved final shape latents at 512; no resampling',
                          latent_sha256=digest(latent_path))
            latents = torch.load(latent_path, map_location='cpu', weights_only=True).to('mps', dtype=torch.float16)
            with torch.inference_mode():
                mesh = pipe._export(latents, 'trimesh', box_v=1.01, mc_level=0.,
                                    num_chunks=8000, octree_resolution=512, mc_algo=None)[0]
        else:
            report['method'] = 'Independent image-to-shape reconstruction from the recorded head/hand crop'

            def progress(step, timestep, outputs):
                report['step'] = int(step) + 1
                if int(step) == 49:
                    torch.save(outputs.prev_sample.detach().cpu(), folder / 'shape_latents.pt')
                    report['status'] = 'decoding'
                save()
                if int(step) % 10 == 0:
                    print(job, 'STEP', int(step) + 1, flush=True)

            mesh = pipe(image=Image.open(source), num_inference_steps=50, guidance_scale=5.,
                        octree_resolution=384, num_chunks=8000,
                        generator=torch.Generator(device='cpu').manual_seed(42),
                        callback=progress, callback_steps=1)[0]
        torch.mps.synchronize()
        mesh.export(folder / 'raw.glb')
        report.update(status='complete', triangles=len(mesh.faces), vertices=len(mesh.vertices),
                      output_sha256=digest(folder / 'raw.glb'))
        print('DETAIL_COMPLETE', job, report['triangles'], time.monotonic() - started, flush=True)
    except BaseException as exc:
        report.update(status='failed', error=str(exc), traceback=traceback.format_exc())
        raise
    finally:
        save()
    torch.mps.empty_cache()
