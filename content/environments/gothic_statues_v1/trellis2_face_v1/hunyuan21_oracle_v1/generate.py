"""Run the official Hunyuan3D-2.1 shape checkpoint locally through MPS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import traceback

root = Path(__file__).resolve().parent
lab = Path('/Users/theochernin/Projects/CherninLab3D')
upstream = lab / 'vendor/Hunyuan3D-2.1'
compat = lab / 'vendor/hunyuan3d-2.1-mac-rocm'
weights = lab / 'models/Hunyuan3D-2.1/hunyuan3d-dit-v2-1'
parser = argparse.ArgumentParser()
parser.add_argument('--seed', type=int, choices=[0, 42], default=42)
parser.add_argument('--clean-black-background', action='store_true')
args = parser.parse_args()
out = root / (f'384_s{args.seed}' + ('_maskfix' if args.clean_black_background else ''))
out.mkdir(exist_ok=True)
assert not (out / 'receipt.json').exists(), 'Existing attempt preserved'
os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
os.environ.setdefault('PYTORCH_MPS_HIGH_WATERMARK_RATIO', '1.0')
os.environ.setdefault('PYTORCH_MPS_LOW_WATERMARK_RATIO', '0.8')
os.environ.setdefault('U2NET_HOME', str(lab / 'models/matting/models/u2net'))
sys.path.insert(0, str(compat))
import backend
import torch
import compat_patches


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(8 << 20), b''):
            value.update(block)
    return value.hexdigest()


started = time.monotonic()
report = {'status': 'loading', 'model': 'tencent/Hunyuan3D-2.1',
          'model_revision': '0b94677654c57bb9a6b6845cd7b704ccf551d327',
          'checkpoint': str(weights / 'model.fp16.ckpt'),
          'device_requested': 'mps', 'inference_location': 'local Mac; no hosted inference',
          'torch': torch.__version__, 'architecture': platform.machine(),
          'steps': 50, 'guidance_scale': 5.0, 'octree_resolution': 384,
          'query_chunk': 8000, 'seed': args.seed, 'dtype': 'float16', 'texture_stage': False}
report['mask_method'] = 'u2net + supplied black background removal' if args.clean_black_background else 'u2net'


def save():
    report['wall_seconds'] = time.monotonic() - started
    (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')


try:
    assert torch.backends.mps.is_available(), 'MPS unavailable; no silent CPU route'
    report['upstream_revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=upstream, text=True).strip()
    report['compat_revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=compat, text=True).strip()
    report['checkpoint_sha256'] = digest(weights / 'model.fp16.ckpt')
    manifest = json.loads((root / 'model_artifacts.json').read_text())
    assert report['checkpoint_sha256'] == manifest['hunyuan3d-dit-v2-1/model.fp16.ckpt']['lfs']['oid']
    report['config_sha256'] = digest(weights / 'config.yaml')
    source = root / 'source.png'
    report['source_sha256'] = digest(source)
    assert report['source_sha256'] == '528eac8ce3cabf3727872f169c834641eacf8eaadf3374152499a702c8263c41'
    b = backend.detect(force_kind='mps', force_dtype='float16')
    report['backend_description'] = backend.describe(b)
    compat_patches.apply(b)
    sys.path.insert(0, str(upstream))
    sys.path.insert(0, str(upstream / 'hy3dshape'))
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
    report['scheduler_compat_patch'] = compat_patches.patch_scheduler_timestep_lookup()
    from PIL import Image
    from rembg import new_session, remove
    image = remove(Image.open(source).convert('RGB'), session=new_session('u2net'))
    if args.clean_black_background:
        import numpy as np
        pixels = np.array(image)
        # This supplied reference has a near-black backdrop and bright plastic parts.
        # U2Net incorrectly keeps the black opening between the horns opaque.
        source_rgb = np.array(Image.open(source).convert('RGB'))
        backdrop_alpha = np.clip((source_rgb.max(axis=2).astype(float) - 12) / 12, 0, 1) * 255
        pixels[:, :, 3] = np.minimum(pixels[:, :, 3], backdrop_alpha).astype('uint8')
        image = Image.fromarray(pixels)
        report['mask_black_thresholds'] = [12, 24]
    image.save(out / 'segmented_input.png')
    report['input_sha256'] = digest(out / 'segmented_input.png')
    save()
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_single_file(
        str(weights / 'model.fp16.ckpt'), str(weights / 'config.yaml'),
        device='mps', dtype=torch.float16, use_safetensors=False)
    report['components'] = {}
    for name in ('model', 'vae', 'conditioner'):
        module = getattr(pipe, name)
        parameter = next(module.parameters())
        assert parameter.device.type == 'mps', name + ' did not load on MPS'
        report['components'][name] = {'device': str(parameter.device), 'dtype': str(parameter.dtype),
                                      'parameters': sum(p.numel() for p in module.parameters())}
    report['load_seconds'] = time.monotonic() - started
    report['status'] = 'sampling'
    save()
    print('LOCAL_HUNYUAN21_MPS_READY', json.dumps(report['components']), flush=True)

    def progress(step, timestep, outputs):
        report['sampling_step'] = int(step) + 1
        if int(step) == report['steps'] - 1:
            torch.save(outputs.prev_sample.detach().cpu(), out / 'shape_latents.pt')
            report['status'] = 'decoding'
        save()
        if int(step) % 5 == 0 or int(step) == report['steps'] - 1:
            print('HUNYUAN21_STEP', int(step) + 1, '/', report['steps'], flush=True)

    run_started = time.monotonic()
    mesh = pipe(image=image, num_inference_steps=report['steps'],
                guidance_scale=report['guidance_scale'], octree_resolution=report['octree_resolution'],
                num_chunks=report['query_chunk'], generator=torch.Generator(device='cpu').manual_seed(args.seed),
                callback=progress, callback_steps=1)[0]
    torch.mps.synchronize()
    mesh.export(out / 'raw.glb')
    report.update(status='complete', inference_seconds=time.monotonic() - run_started,
                  vertices=len(mesh.vertices), triangles=len(mesh.faces), output_sha256=digest(out / 'raw.glb'),
                  mps_allocated_gib=torch.mps.current_allocated_memory() / 1024**3,
                  mps_driver_allocated_gib=torch.mps.driver_allocated_memory() / 1024**3)
except BaseException as exc:
    report.update(status='failed', error=f'{type(exc).__name__}: {exc}', traceback=traceback.format_exc())
    raise
finally:
    save()
print('LOCAL_HUNYUAN21_COMPLETE', json.dumps(report), flush=True)
