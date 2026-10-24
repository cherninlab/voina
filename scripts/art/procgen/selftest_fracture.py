"""Checks fracture.py: a glued stone column stands untouched at rest, a heavy
ball knocks chunks off it, and wood cells grow long along the grain.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_fracture.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
from mathutils import Vector

from procgen import core, disturb, fracture, rigid


def column(seed: int, hit: bool) -> dict:
    core.empty_scene()
    disturb.reset()
    rigid.world(frame_end=600, substeps=40, iterations=60)
    rng = core.rng(seed, 'column')
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.35, depth=3.5, location=(0, 0, 1.75))
    source = bpy.context.active_object
    impact = Vector((0.3, 0.0, 1.6))
    cells = fracture.voronoi(source, fracture.seeds(source, rng, 28, focus=impact if hit else None), name='Column')
    bpy.data.objects.remove(source, do_unlink=True)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.25))
    ground = bpy.context.active_object
    ground.scale = (20, 20, 0.5)
    bpy.ops.object.transform_apply(location=False, scale=True)
    # Floor top exactly at z = 0, under the column's (cracked) foot.
    ground.location = (0.0, 0.0, -0.25)
    rigid.body(ground, passive=True, shape='BOX')
    for cell in cells:
        rigid.body(cell, mass=rigid.mass(cell, 2500.0), friction=0.8, margin=0.0002)
    joints = fracture.glue(cells, rng, 'stone')
    for cell in cells:
        if min((cell.matrix_world @ v.co).z for v in cell.data.vertices) < 0.01:
            disturb.nail(cell, ground, cell.matrix_world.translation, collide=True)
    rest = disturb.rest_pose(cells)
    if hit:
        disturb.roll(Vector((3.0, 0.0, 1.6)), Vector((-8.0, 0.0, 0.0)), radius=0.3, start=5)
    settled = rigid.settle(cells, threshold=0.01, min_frames=disturb.quiet_frame(), max_frames=600)
    moved = disturb.displacements(cells, rest)
    detached = [n for n, (d, a) in moved.items() if d > 0.05]
    return {'seed': seed, 'hit': hit, 'cells': len(cells), 'joints': len(joints), 'detached': len(detached),
            'max_move_m': round(max(d for d, a in moved.values()), 3), 'settled': settled['settled'], 'frames': settled['frame']}


def wood_elongation() -> float:
    core.empty_scene()
    rng = core.rng(3, 'wood')
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    beam = bpy.context.active_object
    beam.scale = (3.0, 0.25, 0.25)
    bpy.ops.object.transform_apply(scale=True)
    cells = fracture.voronoi(beam, fracture.seeds(beam, rng, 20), fracture.grain('wood', Vector((1, 0, 0))), name='Beam')
    along = sum(c.dimensions.x for c in cells) / len(cells)
    across = sum((c.dimensions.y + c.dimensions.z) * 0.5 for c in cells) / len(cells)
    return along / across


results = [column(seed, hit) for seed in (1, 2) for hit in (False, True)]
for r in results:
    print('FRACTURE_TRY', json.dumps(r), flush=True)
assert all(r['detached'] == 0 for r in results if not r['hit']), 'a glued column must stand at rest'
assert all(r['detached'] > 0 for r in results if r['hit']), 'a heavy ball must knock chunks off'
ratio = wood_elongation()
print('FRACTURE_WOOD_ELONGATION', round(ratio, 2), flush=True)
assert ratio > 2.0, 'wood cells must run along the grain'
print('FRACTURE_SELFTEST_OK', flush=True)
