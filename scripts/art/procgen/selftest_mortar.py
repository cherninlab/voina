"""Checks mortar.py on a small rubble wall: every joint gets a bead touching
both stones, a calm wall stands untouched, and a strong tremor shakes old
mortar loose.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_mortar.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
from mathutils import Vector

from procgen import core, disturb, mortar, rigid, shapes

UP = Vector((0, 0, 1))


def wall(seed: int, intensity: float, weakness: float) -> dict:
    core.empty_scene()
    disturb.reset()
    rigid.world(frame_end=600, substeps=40, iterations=60)
    rng = core.rng(seed, 'wall')
    stones = []
    z = 0.0005
    for course in range(3):
        height = rng.uniform(0.22, 0.3)
        x = -1.0 + (0.25 if course % 2 else 0.0)
        while x < 1.0:
            length = rng.uniform(0.35, 0.55)
            a, b = Vector((x, 0.0, z + height * 0.5)), Vector((x + length, 0.0, z + height * 0.5))
            builder = shapes.Builder(f'Stone_{course}_{len(stones)}')
            shapes.prism(builder, a, b, 0.3, height, UP, rng, chamfer=0.025, wear=0.06, segment=1.0)
            stone = builder.to_object()
            disturb.orient(stone, a, b, UP)
            stones.append(stone)
            x += length + rng.uniform(0.008, 0.02)
        z += height + rng.uniform(0.008, 0.018)
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    ground = bpy.context.active_object
    ground.scale = (6, 6, 0.5)
    bpy.ops.object.transform_apply(location=False, scale=True)
    ground.location = (0.0, 0.0, -0.25)
    rigid.body(ground, passive=True, shape='BOX')
    disturb.kinematic([ground])
    beads = mortar.lay(stones, rng, max_gap=0.025, squeeze=0.005)
    for stone in stones:
        rigid.body(stone, mass=rigid.mass(stone, 2400.0), friction=0.8, margin=0.0002)
    for bead in beads:
        rigid.body(bead, mass=rigid.mass(bead, mortar.DENSITY), friction=0.9, margin=0.0002)
    mortar.glue(beads, rng, weakness=weakness)
    # The wall stands on its footing by weight, as real walls do: nailing every
    # bed stone to the ground would close rigid loops through the mortar.
    touching = 0
    for bead in beads:
        a, b = (bpy.data.objects[n] for n in bead['joint'])
        gaps = [min(rigid.Shape(stone).bvh.find_nearest(bead.matrix_world @ v.co, 1.0)[3] for v in bead.data.vertices) for stone in (a, b)]
        touching += all(g < 0.004 for g in gaps)
    movers = stones + beads
    disturb.arm(8)
    rest = disturb.rest_pose(movers)
    if intensity > 0:
        disturb.shake([ground], rng, intensity)
    settled = rigid.settle(movers, threshold=0.01, min_frames=disturb.quiet_frame(), max_frames=600)
    moved = disturb.displacements(movers, rest)
    loose_stones = [s.name for s in stones if moved[s.name][0] > 0.01 or moved[s.name][1] > 2.0]
    loose_mortar = [b.name for b in mortar.failed(beads, rest)]
    return {'seed': seed, 'intensity': intensity, 'weakness': weakness, 'stones': len(stones), 'beads': len(beads),
            'beads_touching_both': touching, 'loose_stones': len(loose_stones), 'loose_mortar': len(loose_mortar),
            'settled': settled['settled']}


results = [wall(seed, intensity, weakness) for seed in (1, 2) for intensity, weakness in ((0.0, 1.0), (2.5, 12.0))]
for r in results:
    print('MORTAR_TRY', json.dumps(r), flush=True)
assert all(r['beads'] >= r['stones'] for r in results), 'every stone should be bedded and jointed'
assert all(r['beads_touching_both'] >= r['beads'] * 0.9 for r in results), 'beads must reach both stones'
assert all(r['loose_stones'] == 0 and r['loose_mortar'] == 0 for r in results if r['intensity'] == 0), 'a calm wall stands'
assert any(r['loose_mortar'] + r['loose_stones'] > 0 for r in results if r['intensity'] > 0), 'old mortar fails in a tremor'
print('MORTAR_SELFTEST_OK', flush=True)
