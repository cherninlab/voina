"""Reconstruct a tightly framed head from the approved Oracle image."""
import hashlib
import json
from pathlib import Path
import subprocess
import time

import numpy as np
from PIL import Image, ImageDraw
import trimesh

ROOT = Path(__file__).resolve().parent
CL3D = Path('/Users/theochernin/Projects/CherninLab3D')
SOURCE = ROOT.parent / 'trellis2_statues_v1/source/oracle.png'
OUT = ROOT / 'head_512'
OUT.mkdir(parents=True, exist_ok=True)
image = Image.open(SOURCE).convert('RGBA')
# Isolate the head and neck; the original alpha also excludes its background.
# Horns remain on the existing sculpture and are deliberately outside this crop.
outline = [(443,130),(508,116),(561,120),(596,143),(614,183),
           (609,222),(588,265),(589,323),(624,367),(423,367),
           (449,309),(443,269),(409,245),(414,211),(425,169)]
mask = Image.new('L', image.size, 0)
ImageDraw.Draw(mask).polygon(outline, fill=255)
alpha = np.minimum(np.asarray(image.getchannel('A')), np.asarray(mask))
image.putalpha(Image.fromarray(alpha))
image = image.crop((393,102,639,379))
image.save(ROOT / 'source_head.png')
canvas = Image.new('RGBA', (332,332))
canvas.alpha_composite(image, ((332-image.width)//2,(332-image.height)//2))
rgb = Image.new('RGB', canvas.size, (0,0,0))
rgb.paste(canvas, mask=canvas.getchannel('A'))
rgb.resize((512,512), Image.Resampling.LANCZOS).save(OUT/'conditioning.png')
native = CL3D / 'vendor/trellis2mlx/generate.py'
bootstrap = 'import mlx.core as mx,runpy,sys;mx.set_memory_limit(42*1024**3);sys.argv=[sys.argv[1],*sys.argv[2:]];runpy.run_path(sys.argv[0],run_name="__main__")'
command = [str(CL3D/'.venv-trellis2/bin/python'), '-u', '-c', bootstrap,
    str(native), '--image', str(OUT/'conditioning.png'), '--output', str(OUT/'raw.glb'),
    '--resolution','512','--steps','12','--seed','42','--no-cascade','--no-rembg',
    '--target-faces','0','--no-cleanup','--no-hole-fill',
    '--save-checkpoints',str(OUT/'checkpoints'),'--stop-after-stage','mesh_raw']
started = time.monotonic()
subprocess.run(command, cwd=native.parent, check=True)
data = np.load(OUT/'checkpoints/mesh_raw.npz')
v = data['vertices'][:,[0,2,1]] * np.array([1,1,-1])
trimesh.Trimesh(v,data['faces'],process=False).export(OUT/'raw.glb')
(OUT/'result.json').write_text(json.dumps({
    'model':'microsoft/TRELLIS.2-4B', 'model_revision':'af44b45f2e35a493886929c6d786e563ec68364d',
    'source':str(SOURCE), 'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'conditioning_sha256':hashlib.sha256((OUT/'conditioning.png').read_bytes()).hexdigest(),
    'method':'Head and neck crop from approved source; no generated replacement image',
    'source_polygon':outline,'input_count':1,'resolution':512,'seed':42,'steps':12,
    'triangles':len(data['faces']),'seconds':time.monotonic()-started,'command':command
},indent=2)+'\n')
print('HEAD_RECONSTRUCTION_OK',len(data['faces']),flush=True)
