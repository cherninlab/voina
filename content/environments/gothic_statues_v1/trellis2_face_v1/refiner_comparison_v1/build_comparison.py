"""Expose only completed, validated trial meshes in the comparison viewer."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
variants = []
for case in ('tunic', 'pillar'):
    for folder in sorted((root / case).iterdir()):
        if not (folder / 'validation.json').exists() or not (folder / 'receipt.json').exists():
            continue
        receipt = json.loads((folder / 'receipt.json').read_text())
        validation = json.loads((folder / 'validation.json').read_text())
        if receipt['status'] != 'complete':
            continue
        assert hashlib.sha256((folder / 'review.glb').read_bytes()).hexdigest() == validation['review_sha256']
        coarse = folder.name.startswith('hunyuan')
        hi3d = folder.name.startswith('hi3d')
        label = 'Coarse · Hunyuan3D-2.1' if coarse else ('Hi3D MLX' if hi3d else 'UltraShape')
        if not coarse:
            label += f" · {receipt['steps']} steps · {receipt['octree_resolution']}"
        prefix = '../' + case + '/' + folder.name + '/'
        camera = {'tunic': {'face': ['-.04m 1.20m .03m', '0deg 85deg .62m'],
                            'left': ['-.30m .74m .02m', '0deg 82deg .68m'],
                            'right': ['.16m .81m .08m', '0deg 82deg .68m']},
                  'pillar': {'face': ['-.09m 1.19m .04m', '0deg 85deg .62m'],
                             'left': ['-.28m .64m .02m', '0deg 82deg .68m'],
                             'right': ['.16m .87m -.04m', '0deg 82deg .68m']}}[case]
        method = 'Original RGB image to Hunyuan3D-2.1.' if coarse else 'One image with background-only alpha and its own coarse mesh; ' + receipt['model'] + '.'
        variants.append(dict(id=case+'_'+folder.name, label=case.title()+' · '+label,
                             mesh=prefix+'review.glb', images=prefix+'review/',
                             input='../'+case+'/source.jpg', receipt=prefix+'receipt.json',
                             triangles=validation['triangles'], input_title='Supplied '+case+' reference',
                             method=method, note=receipt.get('visual_finding', 'Experimental geometry; visual review pending.'),
                             cameras=camera))
assert variants, 'No validated meshes to show'
preferred = ['tunic_ultrashape_s50_l32768_r1024', 'tunic_ultrashape_s12_l8192_r512']
selected = next((x for x in preferred if any(v['id'] == x for v in variants)), variants[0]['id'])
(root / 'comparison.json').write_text(json.dumps(dict(selected=selected, variants=variants,
                                                     mesh_visual_acceptance=False), indent=2)+'\n')
print('COMPARISON_READY', len(variants))
