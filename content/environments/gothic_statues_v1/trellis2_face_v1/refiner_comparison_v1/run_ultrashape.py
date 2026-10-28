"""Pinned UltraShape weights with the community MPS inference implementation."""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback
import types

os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
os.environ.setdefault('PYTORCH_MPS_HIGH_WATERMARK_RATIO', '1.0')
os.environ.setdefault('PYTORCH_MPS_LOW_WATERMARK_RATIO', '0.8')
os.environ.setdefault('USE_SAGEATTN', '0')
root = Path(__file__).resolve().parent
lab = Path('/Users/theochernin/Projects/CherninLab3D')
port = lab / 'vendor/ultrashape-mac'
parser = argparse.ArgumentParser()
parser.add_argument('--case', choices=['tunic', 'pillar'], required=True)
parser.add_argument('--preflight', action='store_true')
parser.add_argument('--steps', type=int, default=12)
parser.add_argument('--latents', type=int, default=8192)
parser.add_argument('--resolution', type=int, default=512)
args = parser.parse_args()
case = root / args.case
out = case / ('ultrashape_preflight' if args.preflight else f'ultrashape_s{args.steps}_l{args.latents}_r{args.resolution}')
out.mkdir(exist_ok=True)
assert not (out / 'receipt.json').exists(), 'Preserve existing attempts'
started = time.monotonic()
report = dict(status='loading', model='infinith/UltraShape', seed=42,
              model_revision='5aeb21a7185d39f042d02b2695802f125a6f5159',
              mode='preflight' if args.preflight else 'refinement',
              steps=args.steps, latents=args.latents, octree_resolution=args.resolution,
              guidance=5.0, chunks=4096, device_requested='mps',
              geometry_generated=False, texture_generation=False)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(8 << 20), b''):
            h.update(block)
    return h.hexdigest()


def save():
    report['wall_seconds'] = time.monotonic() - started
    (out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')


try:
    import numpy as np
    import torch
    from PIL import Image
    from scipy import ndimage
    from omegaconf import OmegaConf

    assert torch.backends.mps.is_available(), 'MPS required; no silent CPU model'
    report['torch'] = torch.__version__
    report['port_revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=port, text=True).strip()
    assert report['port_revision'] == '2724fd7b5496f3c90789da3217d0ad6021ea939e'
    ckpt = lab / 'models/UltraShape-1.0/ultrashape_v1.pt'
    report['checkpoint_sha256'] = digest(ckpt)
    assert report['checkpoint_sha256'] == json.loads((root / 'model_artifact.json').read_text())['file']['lfs']['sha256']
    # Import inference modules directly, without unrelated training/UI __init__ imports.
    for name, path in [('ultrashape', port/'ultrashape'),
                       ('ultrashape.models', port/'ultrashape/models'),
                       ('ultrashape.models.autoencoders', port/'ultrashape/models/autoencoders')]:
        package = types.ModuleType(name)
        package.__path__ = [str(path)]
        sys.modules[name] = package
    ae = sys.modules['ultrashape.models.autoencoders']
    ae.ShapeVAE = importlib.import_module('ultrashape.models.autoencoders.model').ShapeVAE
    ae.SurfaceExtractors = importlib.import_module('ultrashape.models.autoencoders.surface_extractors').SurfaceExtractors
    from ultrashape.utils.misc import instantiate_from_config
    from ultrashape.pipelines import UltraShapePipeline
    from ultrashape.surface_loaders import SharpEdgeSurfaceLoader
    from ultrashape.utils import voxelize_from_point

    conf = OmegaConf.load(port / 'configs/infer_dit_refine.yaml').model.params
    conf.conditioner_config.params.main_image_encoder.kwargs.version = str(lab/'models/TripoSG/image_encoder_dinov2')
    (out / 'runtime_config.yaml').write_text(OmegaConf.to_yaml(conf))
    weights = torch.load(ckpt, map_location='cpu', mmap=True, weights_only=True)
    components = {}
    report['components'] = {}
    for name, key in [('vae', 'vae_config'), ('dit', 'dit_cfg'), ('conditioner', 'conditioner_config')]:
        module = instantiate_from_config(conf[key])
        module.load_state_dict(weights[name], strict=True)
        module.eval().requires_grad_(False).to(device='mps', dtype=torch.float16)
        parameter = next(module.parameters())
        assert parameter.device.type == 'mps'
        report['components'][name] = dict(device=str(parameter.device), dtype=str(parameter.dtype),
                                           parameters=sum(p.numel() for p in module.parameters()), strict_weights=True)
        components[name] = module
    del weights
    pipe = UltraShapePipeline(vae=components['vae'], model=components['dit'],
                              conditioner=components['conditioner'], device='mps', dtype=torch.float16,
                              scheduler=instantiate_from_config(conf.scheduler_cfg),
                              image_processor=instantiate_from_config(conf.image_processor_cfg))
    source = case / 'source.jpg'
    coarse = case / 'hunyuan21_single_s42/raw.glb'
    report.update(source_sha256=digest(source), coarse_sha256=digest(coarse))
    image = Image.open(source).convert('RGBA')
    rgb = np.asarray(image)[..., :3]
    labels, _ = ndimage.label(rgb.max(axis=2) <= 24)
    touching = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    touching = touching[touching != 0]
    rgba = np.array(image)
    rgba[np.isin(labels, touching), 3] = 0
    image = Image.fromarray(rgba)
    image.save(out / 'input.png')
    report['input_sha256'] = digest(out / 'input.png')
    report['background'] = 'Only border-connected near-black pixels (maxRGB<=24) made transparent; no part mask'
    report['load_seconds'] = time.monotonic() - started
    save()
    with torch.inference_mode(), torch.autocast(device_type='mps', dtype=torch.float16):
        if args.preflight:
            prepared = pipe.prepare_image(image)
            pixels = prepared.pop('image')
            conditioning = pipe.encode_cond(image=pixels, additional_cond_inputs=prepared,
                                             do_classifier_free_guidance=True, dual_guidance=False)
            voxels = torch.randint(0, 128, (2, 32, 3), device='mps')
            velocity = pipe.model(torch.zeros((2, 32, 64), device='mps', dtype=torch.float16),
                                  torch.ones((2,), device='mps', dtype=torch.float16)*.5,
                                  conditioning, voxel_cond=voxels)
            assert torch.isfinite(velocity).all()
            report.update(status='complete', denoiser_shape=list(velocity.shape), finite=True)
        else:
            torch.manual_seed(42)
            np.random.seed(42)
            loader = SharpEdgeSurfaceLoader(num_sharp_points=204800, num_uniform_points=204800)
            surface = loader(str(coarse), normalize_scale=.99)
            # Coordinate selection on CPU avoids unsupported MPS unique/bincount; model is on MPS.
            _, voxels = voxelize_from_point(surface[:, :, :3], args.latents, resolution=128)
            report['status'] = 'sampling'
            save()

            def progress(step, timestep, outputs):
                report['sampling_step'] = int(step)+1
                report['status'] = 'decoding' if step+1 == args.steps else 'sampling'
                save()
                print('ULTRASHAPE_STEP', int(step)+1, '/', args.steps, flush=True)

            mesh, _ = pipe(image=image, voxel_cond=voxels.to('mps'), box_v=1.0,
                           num_inference_steps=args.steps, guidance_scale=5.0,
                           octree_resolution=args.resolution, num_chunks=4096,
                           generator=torch.Generator(device='cpu').manual_seed(42),
                           callback=progress, callback_steps=1)
            mesh = mesh[0]
            assert mesh is not None and len(mesh.faces) > 0 and np.isfinite(mesh.vertices).all()
            mesh.export(out / 'raw.glb')
            report.update(status='complete', geometry_generated=True, vertices=len(mesh.vertices),
                          triangles=len(mesh.faces), output_sha256=digest(out / 'raw.glb'))
except BaseException as exc:
    report.update(status='failed', error=str(exc), traceback=traceback.format_exc())
    raise
finally:
    save()
print('ULTRASHAPE_COMPLETE', json.dumps(report), flush=True)
