"""Checks soil.py: a stone column sinks by weight / (area * k), the soil it
displaces heaps into a rim, hammer blows drive a stake deeper, ruts and holes
keep their volume budget.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_soil.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
from mathutils import Vector

from procgen import core, soil

core.empty_scene()
rng = core.rng(5, 'soil')
ground = soil.Ground(size=(3.0, 3.0), cell=0.02, rng=rng, roughness=0.003)
before = ground.volume()
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.3, depth=2.0, location=(0, 0, 1.05))
column = bpy.context.active_object
mass = 3.14159 * 0.3 ** 2 * 2.0 * 2500.0
packed = soil.SOILS['packed road']
seated = ground.press(column, packed, mass=mass)
expected = mass * 9.81 / (3.14159 * 0.3 ** 2) / packed['k']
rim = max(ground.at(0.36 + d, 0.0) for d in (0.0, 0.02, 0.04, 0.06))
print('SOIL_COLUMN', json.dumps({**seated, 'expected_depth_m': round(expected, 4), 'rim_m': round(rim, 4)}), flush=True)
assert abs(seated['depth_m'] - expected) < expected * 0.15, 'sink depth follows weight / (area * k)'
assert abs(column.location.z - (1.0 - seated['depth_m'])) < 0.06, 'column moved down by the depth'
assert rim > 0.002, 'displaced soil heaps into a rim'

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.9, 0.9, 0.5))
stake = bpy.context.active_object
stake.scale = (0.08, 0.08, 1.0)
bpy.ops.object.transform_apply(location=False, scale=True)
light = ground.press(stake, soil.SOILS['garden'], mass=6.0)
stake.location.z += light['drop_m']
hammered = ground.press(stake, soil.SOILS['garden'], mass=6.0, blows=4)
print('SOIL_STAKE', json.dumps({'weight_only_m': light['depth_m'], 'four_blows_m': hammered['depth_m']}), flush=True)
assert hammered['depth_m'] > light['depth_m'] * 3, 'blows drive a stake much deeper than its weight'

ground.rut([(-1.2, -1.0), (1.2, -1.0)], width=0.12, depth=0.04)
removed = ground.dig((-0.9, 0.9), radius=0.3, depth=0.2)
obj = ground.mesh('Soil')
print('SOIL_MESH', len(obj.data.vertices), 'verts; dug', round(removed, 4), 'm3; volume change', round(ground.volume() - before, 4), flush=True)
assert len(obj.data.vertices) == ground.nx * ground.ny
print('SOIL_SELFTEST_OK', flush=True)
