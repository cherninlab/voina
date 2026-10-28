"""Dedicated Hunyuan3D-2mv joint-view inference, with a geometry-free preflight."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback

root = Path(__file__).resolve().parent
lab = Path('/Users/theochernin/Projects/CherninLab3D')
parser = argparse.ArgumentParser()
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument('--preflight', action='store_true')
mode.add_argument('--reconstruct', action='store_true')
parser.add_argument('--background', choices=['black', 'alpha'], default='black')
parser.add_argument('--crop', choices=['full', 'head'], default='full')
args = parser.parse_args()
os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
os.environ.setdefault('PYTORCH_MPS_HIGH_WATERMARK_RATIO', '1.0')
os.environ.setdefault('PYTORCH_MPS_LOW_WATERMARK_RATIO', '.8')
sys.path.insert(0, str(lab / 'vendor/hunyuan3d-2.1-mac-rocm'))
import backend
import compat_patches
import torch
from PIL import Image, ImageDraw
from safetensors import safe_open

assert torch.backends.mps.is_available()
compat_patches.apply(backend.detect(force_kind='mps', force_dtype='float16'))
sys.path.insert(0, str(lab / 'vendor/Hunyuan3D-2.1/hy3dshape'))
from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
compat_patches.patch_scheduler_timestep_lookup()
meta = json.loads((root / 'model.json').read_text())
checkpoint = Path(meta['checkpoint'])
assert checkpoint.stat().st_size == meta['bytes']
out = root / ('preflight' if args.preflight else 'reconstruction_s42' + ('_alpha' if args.background == 'alpha' else '') + ('_head' if args.crop == 'head' else ''))
out.mkdir(exist_ok=True)
assert not (out / 'receipt.json').exists(), 'Preserve the existing attempt'
report = {'status': 'loading', 'model': meta['repo_id'], 'revision': meta['revision'],
          'checkpoint_sha256': meta['sha256'], 'mode': 'preflight' if args.preflight else 'reconstruct',
          'inference_location': 'Local Mac MPS', 'torch': torch.__version__,
          'input_views': ['front', 'left', 'back', 'right'], 'geometry_generated': False,
          'background': args.background, 'crop': args.crop}
started = time.monotonic()


def save():
    report['seconds'] = time.monotonic() - started
    (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')


try:
    h = hashlib.sha256()
    with checkpoint.open('rb') as stream:
        for block in iter(lambda: stream.read(8 << 20), b''):
            h.update(block)
    assert h.hexdigest() == meta['sha256']
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_single_file(
        str(checkpoint), str(root / 'mps_config.yaml'), device='mps',
        dtype=torch.float16, use_safetensors=True)
    report['components'] = {}
    with safe_open(checkpoint, framework='pt', device='cpu') as state:
        keys = set(state.keys())
        for name in ['model', 'vae', 'conditioner']:
            module = getattr(pipe, name)
            parameter = next(module.parameters())
            assert parameter.device.type == 'mps' and parameter.dtype == torch.float16
            expected = module.state_dict()
            missing = [key for key in expected if name + '.' + key not in keys]
            # The published inference VAE omits its point-cloud encoder and
            # pre_kl. Image-to-shape uses post_kl/transformer/geo_decoder only.
            unused_missing = [key for key in missing if name == 'vae' and
                              (key.startswith('encoder.') or key.startswith('pre_kl.'))]
            active_missing = [key for key in missing if key not in unused_missing]
            mismatch = [key for key, value in expected.items()
                        if name + '.' + key in keys and list(value.shape) != state.get_slice(name + '.' + key).get_shape()]
            assert not active_missing and not mismatch, (name, active_missing, mismatch)
            report['components'][name] = {'device': str(parameter.device), 'dtype': str(parameter.dtype),
                'parameters': sum(p.numel() for p in module.parameters()), 'active_missing_keys': active_missing,
                'unused_encoder_keys_omitted': len(unused_missing), 'shape_mismatches': mismatch}
    if args.preflight:
        # Dummy color discs verify all four camera slots without using unapproved
        # generated references or sampling a shape.
        images = {}
        for name, color in zip(report['input_views'], ['blue', 'orange', 'purple', 'gold']):
            im = Image.new('RGB', (512, 512), 'black')
            ImageDraw.Draw(im).ellipse((100, 55, 412, 457), fill=color)
            images[name] = im
        with torch.inference_mode():
            inputs = pipe.prepare_image(images)
            image = inputs.pop('image')
            report['prepared_image_shape'] = list(image.shape)
            report['camera_indices'] = inputs['view_idxs']
            cond = pipe.encode_cond(image, inputs, do_classifier_free_guidance=True, dual_guidance=False)
            report['joint_condition_shape'] = list(cond['main'].shape)
            assert image.shape[:2] == (1, 4)
            assert cond['main'].shape == (2, 5480, 1536)
            latents = torch.randn((2, 3072, 64), device='mps', dtype=torch.float16)
            result = pipe.model(latents, torch.full((2,), .5, device='mps', dtype=torch.float16), cond, guidance=None)
            assert torch.isfinite(result).all().item()
            torch.mps.synchronize()
            report['denoiser_output_shape'] = list(result.shape)
            report['joint_four_view_forward_finite'] = True
        report['status'] = 'complete'
    else:
        report.update(status='sampling', steps=50, guidance=5, seed=42, octree_resolution=384, query_chunk=8000)
        images = {name: Image.open(root / (name + '.png')) for name in report['input_views']}
        report['input_sha256'] = {name: hashlib.sha256((root / (name + '.png')).read_bytes()).hexdigest()
                                 for name in report['input_views']}
        if args.crop == 'head':
            report['crop_box'] = [220, 60, 804, 610]
            cropped = root / 'inputs_head'
            cropped.mkdir(exist_ok=True)
            for name in images:
                images[name] = images[name].crop(tuple(report['crop_box']))
                images[name].save(cropped / (name + '.png'))
        if args.background == 'alpha':
            import cv2
            import numpy as np
            matte_folder = root / ('inputs_alpha_head' if args.crop == 'head' else 'inputs_alpha')
            matte_folder.mkdir(exist_ok=True)
            alpha_hashes = {}
            for name, im in images.items():
                rgb = np.asarray(im.convert('RGB'))
                dark = (rgb.max(axis=2) <= 24).astype('uint8')
                _, labels = cv2.connectedComponents(dark, connectivity=8)
                border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
                border = border[border != 0]
                bg = np.isin(labels, border)
                alpha = np.where(bg, 0, 255).astype('uint8')
                images[name] = Image.fromarray(np.dstack([rgb, alpha]))
                path = matte_folder / (name + '.png')
                images[name].save(path)
                alpha_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
            report['prepared_input_sha256'] = alpha_hashes
            report['matting'] = 'Only border-connected near-black background (maxRGB<=24) made transparent; interior dark details retained; no part masks'

        def progress(step, timestep, outputs):
            report['sampling_step'] = int(step) + 1
            save()
            if int(step) % 10 == 0:
                print('MULTIVIEW_STEP', int(step) + 1, flush=True)

        mesh = pipe(image=images, num_inference_steps=50, guidance_scale=5.,
                    octree_resolution=384, num_chunks=8000,
                    generator=torch.Generator(device='cpu').manual_seed(42),
                    callback=progress, callback_steps=1)[0]
        torch.mps.synchronize()
        mesh.export(out / 'raw.glb')
        report.update(status='complete', geometry_generated=True, triangles=len(mesh.faces),
                      output_sha256=hashlib.sha256((out / 'raw.glb').read_bytes()).hexdigest())
except BaseException as exc:
    report.update(status='failed', error=str(exc), traceback=traceback.format_exc())
    raise
finally:
    save()
print('HUNYUAN2MV_' + report['mode'].upper() + '_COMPLETE', json.dumps(report), flush=True)
