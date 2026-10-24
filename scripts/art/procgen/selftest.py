"""Exercises every procgen module and checks the exported GLB round-trips.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest.py -- <output_dir>
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
from mathutils import Vector

from procgen import bake, core, curves, export, shapes

out = Path(core.args()[0]).resolve()
core.empty_scene()
rng = core.rng(7, 'selftest')

wood = shapes.Builder('Wood')
shapes.timber(wood, Vector((0, 0, 0)), Vector((0, 0, 2.4)), 0.2, 0.2, Vector((1, 0, 0)), rng)
shapes.timber(wood, Vector((0, 0, 1.0)), Vector((3, 0, 1.0)), 0.18, 0.26, Vector((0, 0, 1)), rng)
for i in range(6):
    y = -0.6 + i * 0.25
    shapes.plank(wood, Vector((0.2, y, 1.16)), Vector((2.8, y, 1.16)), 0.22, 0.05, Vector((0, 0, 1)), rng)
iron = shapes.Builder('Iron')
shapes.bar(iron, Vector((1.0, -0.12, 0.85)), Vector((1.0, 0.12, 0.85)), 0.05, 0.008, Vector((0, 0, 1)), rng)
rope_points = curves.catenary(Vector((0, 0, 2.2)), Vector((3, 0.2, 1.6)), 0.02)
assert abs(rope_points[0].z - 2.2) < 1e-6 and abs(rope_points[-1].z - 1.6) < 1e-6
assert 0.05 < curves.sag(rope_points) < 0.5, curves.sag(rope_points)
curves.tube(wood, rope_points, 0.018, twist=6.0)
links = curves.chain(iron, curves.catenary(Vector((0, 0.5, 2.0)), Vector((2, 0.5, 2.0)), 0.03), 0.11, 0.013)
objects = [wood.to_object(), iron.to_object()]
sharp = objects[0].data.attributes.get('sharp_edge')
smooth = objects[0].data.attributes.get('sharp_face')
assert smooth is None or not all(v.value for v in smooth.data), 'faces must shade smooth'
assert sharp is not None and any(v.value for v in sharp.data), 'chamfer edges must stay sharp'
stats = bake.ao_to_color(objects, samples=16)
assert all(0.18 <= s['min'] <= s['mean'] <= 1.0 for s in stats.values()), stats
assert stats['Wood']['min'] < 0.9, 'contacts should darken'
path = export.glb(objects, out / 'procgen_selftest.glb')

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(path))
imported = {o.name: o for o in bpy.data.objects if o.type == 'MESH'}
for name in ('Wood', 'Iron'):
    mesh = imported[name].data
    assert mesh.uv_layers, name + ' lost UVs'
    assert mesh.color_attributes, name + ' lost Color'
report = core.write_report(out / 'procgen_selftest.json', {'links': links, 'ao': stats}, [path])
print('PROCGEN_SELFTEST_OK', report['ao'], 'links', links, flush=True)
