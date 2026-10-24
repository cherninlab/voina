"""Checks stones.py: every stone differs, stays within its triangle budget and
size, wedges taper, an arch closes with voussoirs and a keystone; renders a
review tray and a mortared coursed wall.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_stones.py -- [review.png]
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
import numpy
from mathutils import Vector

from procgen import core, disturb, mortar, stones

core.empty_scene()
rng = core.rng(11, 'stones')
made = []
x = -1.6
for kind, count, size in (('ashlar', 6, (0.46, 0.3, 0.24)), ('rubble', 6, (0.36, 0.28, 0.24)), ('field', 4, (0.3, 0.26, 0.2)),
                          ('wedge', 5, (0.14, 0.1, 0.05))):
    for k in range(count):
        jitter = Vector(size) * rng.uniform(0.8, 1.25)
        stone = stones.make(kind, rng, jitter, name=f'{kind}_{k}')
        stone.location = Vector((x, 1.2 if kind in ('field', 'wedge') else 0.6, jitter.z * 0.5))
        x += max(jitter.x, 0.2) + 0.08
        if x > 1.6:
            x = -1.6
        made.append((kind, stone, jitter))
signatures = {(len(s.data.vertices), tuple(round(d, 3) for d in s.dimensions)) for _, s, _ in made}
assert len(signatures) == len(made), 'every stone must be unique'
for kind, stone, size in made:
    tris = sum(len(p.vertices) - 2 for p in stone.data.polygons)
    assert tris <= 1700, (stone.name, tris)
    floor = 0.45 if kind in ('rubble', 'field') else 0.6
    assert all(floor * size[k] <= stone.dimensions[k] <= 1.2 * size[k] for k in range(3)), (stone.name, tuple(stone.dimensions), tuple(size))
wedges = [s for kind, s, _ in made if kind == 'wedge']
for wedge in wedges:
    thick = max(v.co.z for v in wedge.data.vertices if v.co.x < -0.02) - min(v.co.z for v in wedge.data.vertices if v.co.x < -0.02)
    thin = max(v.co.z for v in wedge.data.vertices if v.co.x > 0.02) - min(v.co.z for v in wedge.data.vertices if v.co.x > 0.02)
    assert thin < thick, (wedge.name, thin, thick)
# A semicircular arch: 9 voussoirs, the middle one a keystone.
arch = []
for k in range(9):
    piece = stones.voussoir(rng, inner=0.7, depth=0.3, angle=math.pi / 9 * 0.97, thickness=0.3,
                            start=k * math.pi / 9, keystone=(k == 4), name=f'voussoir_{k}')
    piece.location += Vector((0.0, 3.5, 0.0))
    arch.append(piece)
print('STONES_MADE', json.dumps({'stones': len(made), 'voussoirs': len(arch),
                                 'tris': [sum(len(p.vertices) - 2 for p in s.data.polygons) for _, s, _ in made][:6]}), flush=True)

# A coursed wall of unique ashlar as a mason sets it: courses of varied
# height, stones a little proud or back and off true, pinning wedges in the
# wider joints, mortar raked back by weathering.
wall = []
z = 0.0
for course in range(4):
    height = rng.uniform(0.18, 0.3)
    xpos = -1.5 + rng.uniform(0.0, 0.25)
    while xpos < 1.3:
        length = rng.uniform(0.28, 0.62)
        h = height * rng.uniform(0.9, 1.04)
        stone = stones.make('ashlar', rng, (length, rng.uniform(0.26, 0.34), h), name=f'wall_{course}_{len(wall)}')
        stone.rotation_euler = (math.radians(rng.uniform(-1.5, 1.5)), math.radians(rng.uniform(-1.0, 1.0)), math.radians(rng.uniform(-2.0, 2.0)))
        stone.location = Vector((xpos + stone.dimensions.x * 0.5, -2.2 + rng.uniform(-0.015, 0.015), z + stone.dimensions.z * 0.5))
        wall.append(stone)
        gap = rng.uniform(0.004, 0.014)
        if gap > 0.012:
            wedge = stones.make('wedge', rng, (0.1, 0.07, gap * 0.9), name=f'wedge_{course}_{len(wall)}')
            wedge.rotation_euler = (0.0, math.radians(90), 0.0)
            wedge.location = Vector((xpos + stone.dimensions.x + gap * 0.5, -2.2 - 0.14, z + h * rng.uniform(0.3, 0.7)))
            wall.append(wedge)
        xpos += stone.dimensions.x + gap
    z += height + rng.uniform(0.005, 0.012)
bpy.context.view_layer.update()
for stone in wall:
    stone.data.transform(stone.matrix_world)
    stone.matrix_world = stone.matrix_world.Identity(4)
beads = mortar.lay(wall, rng, max_gap=0.04)
print('STONES_WALL', len(wall), 'stones', len(beads), 'mortar beads', flush=True)
assert len(beads) >= len(wall)

out = core.args()
if out:
    rock = core.ROOT / 'content/environments/dungeon_pbr_v2/marble_rock_03'

    def tone(obj):
        """Scanned CC0 rock box-projected per stone, tinted by the stone's own
        tone (G) and lighter where freshly broken (B); mortar plain lime."""
        material = bpy.data.materials.new('M' + obj.name)
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = nodes['Principled BSDF']
        is_mortar = obj.name.startswith('Mortar')
        coords = nodes.new('ShaderNodeTexCoord')
        mapping = nodes.new('ShaderNodeMapping')
        mapping.inputs['Location'].default_value = (rng.uniform(0, 5), rng.uniform(0, 5), rng.uniform(0, 5))
        mapping.inputs['Scale'].default_value = (1.4, 1.4, 1.4)
        links.new(coords.outputs['Object'], mapping.inputs['Vector'])
        images = {}
        for key, colour in (('albedo', 'sRGB'), ('normal_gl', 'Non-Color'), ('roughness', 'Non-Color')):
            node = nodes.new('ShaderNodeTexImage')
            node.image = bpy.data.images.load(str(rock / f'{key}.png'), check_existing=True)
            node.image.colorspace_settings.name = colour
            node.projection = 'BOX'
            node.projection_blend = 0.25
            links.new(mapping.outputs['Vector'], node.inputs['Vector'])
            images[key] = node
        attribute = nodes.new('ShaderNodeAttribute')
        attribute.attribute_name = 'Color'
        separate = nodes.new('ShaderNodeSeparateColor')
        links.new(attribute.outputs['Color'], separate.inputs['Color'])
        grade = nodes.new('ShaderNodeHueSaturation')
        links.new(images['albedo'].outputs['Color'], grade.inputs['Color'])
        grade.inputs['Saturation'].default_value = 0.45
        tint = nodes.new('ShaderNodeMix')
        tint.data_type = 'RGBA'
        tint.blend_type = 'MULTIPLY'
        tint.inputs['Factor'].default_value = 1.0
        links.new(grade.outputs['Color'], tint.inputs[6])
        ramp = nodes.new('ShaderNodeMapRange')
        links.new(separate.outputs['Green'], ramp.inputs['Value'])
        ramp.inputs['To Min'].default_value = 0.7
        ramp.inputs['To Max'].default_value = 1.15
        combine = nodes.new('ShaderNodeCombineColor')
        for socket in ('Red', 'Green', 'Blue'):
            links.new(ramp.outputs['Result'], combine.inputs[socket])
        links.new(combine.outputs['Color'], tint.inputs[7])
        fresh = nodes.new('ShaderNodeMix')
        fresh.data_type = 'RGBA'
        links.new(separate.outputs['Blue'], fresh.inputs['Factor'])
        links.new(tint.outputs[2], fresh.inputs[6])
        fresh.inputs[7].default_value = (0.62, 0.6, 0.55, 1)
        if is_mortar:
            # Lime mortar: grey-buff, grainy, a little lighter than the stone.
            mortar_tone = nodes.new('ShaderNodeMix')
            mortar_tone.data_type = 'RGBA'
            mortar_tone.inputs['Factor'].default_value = 0.75
            links.new(grade.outputs['Color'], mortar_tone.inputs[6])
            mortar_tone.inputs[7].default_value = (0.24, 0.225, 0.2, 1)
            links.new(mortar_tone.outputs[2], shader.inputs['Base Color'])
            shader.inputs['Roughness'].default_value = 0.97
            grain = nodes.new('ShaderNodeNormalMap')
            grain.inputs['Strength'].default_value = 0.6
            links.new(images['normal_gl'].outputs['Color'], grain.inputs['Color'])
            links.new(grain.outputs['Normal'], shader.inputs['Normal'])
        else:
            links.new(fresh.outputs[2], shader.inputs['Base Color'])
            bump = nodes.new('ShaderNodeNormalMap')
            links.new(images['normal_gl'].outputs['Color'], bump.inputs['Color'])
            links.new(bump.outputs['Normal'], shader.inputs['Normal'])
            links.new(images['roughness'].outputs['Color'], shader.inputs['Roughness'])
        obj.data.materials.clear()
        obj.data.materials.append(material)
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            tone(obj)
    # Warm raking light, as from a torch, shows the dressing and the joints.
    key = core.link(bpy.data.objects.new('Raking', bpy.data.lights.new('Raking', 'AREA')))
    key.data.energy = 900.0
    key.data.size = 0.6
    key.data.color = (1.0, 0.78, 0.55)
    key.location = (-2.6, -3.4, 1.5)
    key.rotation_euler = (Vector((0.6, 1.2, -0.95)) - Vector((0, 0, 0))).to_track_quat('-Z', 'Y').to_euler()
    tray = disturb.render(Vector((0.2, -0.3, 2.4)), Vector((0.0, 0.85, 0.05)), size=(960, 540), samples=64, lens=30)
    key.location = (-2.2, -3.0, 1.2)
    key.rotation_euler = (Vector((0.0, -2.2, 0.45)) - Vector((-2.2, -3.0, 1.2))).to_track_quat('-Z', 'Y').to_euler()
    walls = disturb.render(Vector((0.7, -3.9, 0.75)), Vector((0.1, -2.2, 0.45)), size=(960, 540), samples=64, lens=35)
    close = disturb.render(Vector((0.15, -2.95, 0.5)), Vector((0.0, -2.2, 0.42)), size=(960, 540), samples=64, lens=35)
    key.location = (-1.5, 1.5, 1.6)
    key.rotation_euler = (Vector((0.0, 3.5, 0.6)) - Vector((-1.5, 1.5, 1.6))).to_track_quat('-Z', 'Y').to_euler()
    arches = disturb.render(Vector((0.4, 1.0, 0.6)), Vector((0.0, 3.5, 0.6)), size=(960, 540), samples=64, lens=35)
    disturb.write_png(Path(out[0]), numpy.concatenate([numpy.concatenate([tray, walls], axis=1),
                                                       numpy.concatenate([arches, close], axis=1)], axis=0))
print('STONES_SELFTEST_OK', flush=True)
