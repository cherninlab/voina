"""Independent, read-only exported-mesh/provenance check (use the CL3D Python env)."""
import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np
import trimesh

OUT = Path(__file__).resolve().parent


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads((OUT / 'manifest.json').read_text())
    assets = manifest['assets']
    assert len(assets) == 18
    assert Counter(a['kind'] for a in assets) == {'ashlar': 6, 'rock': 6, 'column_drum': 3, 'brick_clump': 3}
    report = {'task': 'T-167', 'asset_count': 18, 'lod_count': 54, 'lods': [],
              'closure_method': 'Geometric position weld at duplicated glTF UV/sharp-normal seams; delivered files are not modified.'}
    for asset in assets:
        reference = OUT / asset['reference']
        receipt = json.loads(reference.with_suffix('.receipt.json').read_text())
        assert digest(reference) == asset['input_sha256'] == receipt['sha256']
        assert digest(OUT / asset['raw']) == asset['raw_sha256']
        assert (OUT / asset['prompt']).is_file()
        assert len(asset['lods']) == 3
        for level, entry in enumerate(asset['lods']):
            path = OUT / entry['path']
            assert not Path(entry['path']).is_absolute()
            assert digest(path) == entry['sha256']
            mesh = trimesh.load(path, force='scene').to_geometry()
            mesh.merge_vertices(merge_tex=True, merge_norm=True)
            assert mesh.is_watertight and mesh.is_winding_consistent and mesh.volume > 0, path
            assert np.isfinite(mesh.vertices).all() and np.isfinite(mesh.vertex_normals).all(), path
            assert np.max(np.abs(mesh.bounds.mean(axis=0))) < 1e-6, path
            assert len(mesh.faces) == entry['triangles'] <= [1500, 600, 200][level], path
            assert 0.15 <= max(mesh.extents) <= 0.8, path
            assert np.allclose(mesh.extents, entry['dims_m'], atol=1e-5), path
            report['lods'].append({'path': entry['path'], 'triangles': len(mesh.faces),
                'watertight': True, 'winding_consistent': True, 'volume_m3': float(mesh.volume),
                'origin_error_m': float(np.max(np.abs(mesh.bounds.mean(axis=0))))})
    (OUT / 'review/mesh-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print('RUBBLE_MESH_AUDIT_OK: 18 sources / 54 closed positive-volume LODs, exact bounds-centre origins, dimensions, budgets and source hashes')


if __name__ == '__main__':
    main()
