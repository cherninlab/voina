"""Ambient occlusion baked into the red channel of each object's "Color" attribute.

Godot's Mobile renderer has no SSAO, so contact darkening where boards rest on
bearers, posts meet rails or stones touch must come from the mesh. Cycles
traces against every visible object in the scene, so neighbouring pieces and
any proxy walls or floors occlude each other; hide what should not.
"""
import bpy

from . import core


def ao_to_color(objects, samples: int = 64, distance: float = 0.6, floor: float = 0.18) -> dict:
    """Bake AO for each object and store it in Color.R (G/B/A are kept).
    `floor` is the darkest allowed value so crevices never go pure black.
    Returns min/mean AO per object name for the report."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.render.bake.use_clear = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new('BakeWorld')
    scene.world.light_settings.distance = distance
    material = bpy.data.materials.get('ProcgenBake') or bpy.data.materials.new('ProcgenBake')
    stats = {}
    for obj in objects:
        mesh = obj.data
        if not mesh.materials:
            mesh.materials.append(material)
        color = mesh.color_attributes['Color']
        ao = mesh.color_attributes.get('BakedAO') or mesh.color_attributes.new('BakedAO', 'FLOAT_COLOR', color.domain)
        mesh.color_attributes.active_color = ao
        core.select_only([obj])
        bpy.ops.object.bake(type='AO')
        values = []
        for target, source in zip(color.data, ao.data):
            value = max(floor, source.color[0])
            values.append(value)
            target.color = (value, target.color[1], target.color[2], target.color[3])
        mesh.color_attributes.remove(ao)
        mesh.color_attributes.active_color = mesh.color_attributes['Color']
        stats[obj.name] = {'min': round(min(values), 3), 'mean': round(sum(values) / len(values), 3)}
    return stats
