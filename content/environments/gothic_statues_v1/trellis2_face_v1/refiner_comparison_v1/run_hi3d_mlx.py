"""Run the pinned, unquantized Hi3D MLX model on a matching image and coarse mesh."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys
import time
import traceback
import types

root = Path(__file__).resolve().parent
lab = Path('/Users/theochernin/Projects/CherninLab3D')
source = lab / 'vendor/mlx-vlm-hi3d'
weights = lab / 'models/Hi3Dv1.0-mlx'
parser = argparse.ArgumentParser()
parser.add_argument('--case', required=True, choices=['tunic', 'pillar'])
parser.add_argument('--resolution', type=int, choices=[512, 1024], default=512)
args = parser.parse_args()
case = root / args.case
out = case / f'hi3d_mlx_r{args.resolution}_s0'
out.mkdir(exist_ok=True)
assert not (out / 'receipt.json').exists(), 'Existing attempt preserved'
start = time.monotonic()
report = dict(status='loading', model='mlx-community/Hi3Dv1.0-mlx',
              model_revision='195cfd9974fc9d22094d8b14ef823da08c0d1402',
              seed=0, steps=25, octree_resolution=args.resolution,
              texture_generation=False, geometry_generated=False,
              inference_location='local Apple Silicon MLX Metal GPU')


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(8 << 20), b''):
            h.update(b)
    return h.hexdigest()


def save():
    report['wall_seconds'] = time.monotonic()-start
    (out/'receipt.json').write_text(json.dumps(report, indent=2)+'\n')


try:
    import numpy as np
    import mlx.core as mx
    from PIL import Image
    import trimesh

    report['mlx_version'] = importlib.metadata.version('mlx')
    report['code_revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    assert report['code_revision'] == 'ec824bbc06f950cb1dac0505e7233a65f404620e'
    # Import only the released inference architecture; no chat/audio/training packages.
    for name, relative in [('mlx_vlm', ''), ('mlx_vlm.models', 'models'),
                           ('mlx_vlm.models.llava', 'models/llava'),
                           ('mlx_vlm.models.dinov2', 'models/dinov2'),
                           ('mlx_vlm.models.sam3d_objects', 'models/sam3d_objects')]:
        p = types.ModuleType(name)
        p.__path__ = [str(source/'mlx_vlm'/relative)]
        sys.modules[name] = p
    from mlx_vlm.models.hi3d import Model
    from mlx_vlm.models.hi3d.mesh import read_mesh

    mx.set_default_device(mx.gpu)
    report['device'] = str(mx.default_device())
    mx.set_memory_limit(48 * 1024**3)
    index = json.loads((weights/'model.safetensors.index.json').read_text())
    expected = json.loads((root/'hi3d_model_artifacts.json').read_text())
    report['checkpoint_sha256'] = {}
    for name in sorted(set(index['weight_map'].values())):
        h = digest(weights/name)
        assert h == expected[name]['lfs']['sha256'], name
        report['checkpoint_sha256'][name] = h
    image = case/'ultrashape_s12_l8192_r512/input.png'
    coarse = case/'hunyuan21_single_s42/raw.glb'
    report.update(input_sha256=digest(image), coarse_sha256=digest(coarse),
                  background='Same background-only alpha input as UltraShape, with released Hi3D white framing')
    vertices, faces = read_mesh(str(coarse))
    model = Model.from_pretrained(weights)
    report['load_seconds'] = time.monotonic()-start
    report['status'] = 'refining'
    save()

    def progress(message):
        report['progress'] = str(message)
        save()
        print(message, flush=True)

    result = model(Image.open(image), vertices, faces, resolution=args.resolution,
                   steps=25, seed=0, progress=progress)
    assert len(result.faces) and np.isfinite(result.vertices).all()
    mesh = trimesh.Trimesh(result.vertices, result.faces, process=False)
    mesh.export(out/'raw.glb')
    report.update(status='complete', geometry_generated=True, vertices=len(mesh.vertices),
                  triangles=len(mesh.faces), output_sha256=digest(out/'raw.glb'),
                  stage_timings=result.timings, peak_memory_gb=mx.get_peak_memory()/1e9)
except BaseException as e:
    report.update(status='failed', error=str(e), traceback=traceback.format_exc())
    raise
finally:
    save()
print('HI3D_MLX_COMPLETE', json.dumps(report), flush=True)
