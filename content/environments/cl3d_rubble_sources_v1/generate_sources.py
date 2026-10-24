"""Foreground-condition the ImageGen rubble references and run the existing CL3D runner.

Use /Users/theochernin/Projects/CherninLab3D/.venv/bin/python from repo root.
"""
import hashlib
import io
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
CL3D = Path('/Users/theochernin/Projects/CherninLab3D')
sys.path.insert(0, str(CL3D / 'CL3D'))
from hy3dgen.rembg import BackgroundRemover


def main() -> None:
    jobs = json.loads((OUT / 'generation_jobs.json').read_text())
    assert len(jobs) == 18 and all((ROOT / j['approved_input']).is_file() for j in jobs)
    remover = BackgroundRemover()
    records = []
    for job in jobs:
        source = ROOT / job['approved_input']
        target = ROOT / job['input']
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        rgba = remover(Image.open(source).convert('RGB'))
        assert rgba.mode == 'RGBA' and rgba.getchannel('A').getextrema()[0] == 0
        encoded = io.BytesIO()
        rgba.save(encoded, format='PNG')
        mask_bytes = encoded.getvalue()
        mask_hash = hashlib.sha256(mask_bytes).hexdigest()
        existing = ROOT / job['output']
        if existing.exists():
            prior = json.loads(existing.with_suffix('.json').read_text())
            assert prior['input_sha256'] == mask_hash, f'Existing CL3D output used different conditioning: {job["id"]}'
        target.write_bytes(mask_bytes)
        job['approved_input_sha256'] = source_hash
        records.append({'id': job['id'], 'reference_sha256': source_hash,
                        'conditioning_sha256': mask_hash,
                        'extractor': 'CL3D BackgroundRemover / installed rembg bria-rmbg'})
        print('CONDITIONING_READY', job['id'], flush=True)
    (OUT / 'conditioning.json').write_text(json.dumps(records, indent=2) + '\n')
    (OUT / 'generation_jobs.json').write_text(json.dumps(jobs, indent=2) + '\n')
    runner = CL3D / 'tests/dungeon_kit_01/generate_kit.py'
    subprocess.run([sys.executable, str(runner), str(OUT / 'generation_jobs.json')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
