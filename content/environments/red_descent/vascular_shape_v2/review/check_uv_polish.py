"""Prove the UV/tint follow-up retains every shipped triangle position."""
from pathlib import Path
import hashlib
import json
import trimesh

PROJECT = Path(__file__).resolve().parents[5]
OUTPUT = Path(__file__).parent / 'validation'
baseline = json.loads((OUTPUT / 'polish-baseline.json').read_text())
result = {}
for room, expected in baseline['geometry'].items():
    scene = trimesh.load(PROJECT / 'content/environments/procedural_roots_v1' / (room + '.glb'), force='scene')
    result[room] = {}
    assert set(scene.graph.nodes_geometry) == set(expected)
    for name in scene.graph.nodes_geometry:
        transform, key = scene.graph[name]
        mesh = scene.geometry[key].copy()
        mesh.apply_transform(transform)
        digest = hashlib.sha256(mesh.triangles.tobytes()).hexdigest()
        assert digest == expected[name]['position_triangles_sha256'], (room, name, 'Triangle positions changed')
        assert len(mesh.faces) == expected[name]['triangles']
        result[room][name] = {'triangles': len(mesh.faces), 'position_triangles_sha256': digest, 'same_geometry': True}
(OUTPUT / 'polish-geometry-check.json').write_text(json.dumps(result, indent=2) + '\n')
print('UV_POLISH_GEOMETRY_UNCHANGED:', baseline['commit'])
