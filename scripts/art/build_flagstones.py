"""Seamless flagstone floor modules for the dungeon, baked in Blender.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_flagstones.py -- \
    [outdir] [--seed N] [--only laid_a,border_b] [--samples 96] [--render DIR]

Families of 4 x 4 m modules that tile with themselves and with each other:
  laid_a/b/c      irregular flags (periodic Voronoi), a = sound, b = cracked, c = broken
  coursed_a/b/c   random rectangular flags in courses, same damage ladder
  border_a/b      4 x 0.5 m kerb course, periodic along X, finished long sides
Each GLB holds <id>_stones_lod{0,1,2} and <id>_dirt_lod{0,1,2} (dirt = bedding
plus fills of missing stones). In Godot a module spans x and z from 0 to 4 m
(border: z 0 to 0.5 m) with the walking plane at y = 0 and every vertex within
+/-2.1 cm of it. flagstones.json records seed, triangles, seam errors and hashes.
"""
import argparse
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
from mathutils import Matrix

from procgen import bake, core, export, shapes, tiles

P = 4.0
OUT = core.ROOT / 'content/environments/procedural_flagstone_v1'
TRI_BUDGET = (20000, 10000, 2500)
LOD_RANGES_M = ((0.0, 14.0), (14.0, 32.0), (32.0, 90.0))
BASE = dict(tiles.STYLE, fragments=(2, 4))
FAMILIES = {
    'laid': dict(kind='voronoi', period=(P, P), spacing=0.8, style={}, variants={
        'a': dict(density=1.0, style=dict(crack=0.12, broken=0.06, missing=0.0, chips=(0, 2))),
        'b': dict(density=0.92, style=dict(crack=0.32, crack_lines=(1, 2), broken=0.1, missing=0.07, chips=(1, 3))),
        'c': dict(density=0.72, style=dict(crack=0.28, crack_lines=(1, 2), broken=0.2, missing=0.14, chips=(1, 4),
                                           tilt=0.012, height=0.007, joint=(0.004, 0.0075), sink=0.006)),
    }),
    'coursed': dict(kind='coursed', period=(P, P), depth=(0.42, 0.8), length=(0.5, 1.2), style={}, variants={
        'a': dict(style=dict(crack=0.1, broken=0.05, missing=0.0, chips=(0, 2))),
        'b': dict(style=dict(crack=0.3, broken=0.1, missing=0.06, chips=(1, 3))),
        'c': dict(length_scale=0.8, style=dict(crack=0.28, crack_lines=(1, 2), broken=0.2, missing=0.12, chips=(1, 4),
                                                tilt=0.012, height=0.007, sink=0.006)),
    }),
    'border': dict(kind='kerb', period=(P, 0.5), length=(0.45, 1.0), style=dict(height=0.004, tilt=0.006), variants={
        'a': dict(style=dict(crack=0.1, broken=0.0, missing=0.0, chips=(0, 2))),
        'b': dict(style=dict(crack=0.25, broken=0.12, missing=0.0, chips=(1, 3))),
    }),
}


def parse() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog='build_flagstones.py')
    parser.add_argument('outdir', nargs='?', default=str(OUT))
    parser.add_argument('--seed', type=int, default=165)
    parser.add_argument('--only', default='', help='comma-separated module ids, e.g. laid_a,border_b')
    parser.add_argument('--samples', type=int, default=96, help='AO bake samples')
    parser.add_argument('--render', default='', help='directory for Blender review renders')
    return parser.parse_args(core.args())


def layouts(seed: int, name: str, family: dict) -> dict:
    variants = family['variants']
    if family['kind'] == 'voronoi':
        return tiles.voronoi_family(seed, family['period'], family['spacing'], variants)
    if family['kind'] == 'coursed':
        return tiles.coursed_family(seed, family['period'], family['depth'], family['length'], variants)
    return tiles.kerb_family(seed, family['period'][0], family['period'][1], family['length'], variants)


def neighbours(objects, period, periodic) -> list:
    copies = []
    for dx in ((-1, 0, 1) if periodic[0] else (0,)):
        for dy in ((-1, 0, 1) if periodic[1] else (0,)):
            if dx == dy == 0:
                continue
            for obj in objects:
                copy = obj.copy()
                copy.data = obj.data.copy()
                copy.location = (dx * period[0], dy * period[1], 0.0)
                copies.append(core.link(copy))
    return copies


def triangles(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def profiles(mesh, period, periodic) -> dict:
    return {name: (tiles.border_profile(mesh, axis, period[axis]), tiles.border_profile(mesh, axis, 0.0))
            for axis, name in ((0, 'x'), (1, 'y')) if periodic[axis]}


def seam_mm(a: dict, b: dict) -> dict:
    """Mismatch between the high border of `a` and the low border of `b`."""
    result = {}
    for name in a:
        high, low = a[name][0], b[name][1]
        if not high[0] and not low[0]:
            result[name] = 0.0
            continue
        if not high[0] or not low[0]:
            result[name] = math.inf
            continue
        result[name] = round(max(tiles.profile_distance(high, low), tiles.profile_distance(low, high)) * 1000, 4)
    return result


def build_module(module: str, family: dict, pieces: list, seed: int, samples: int) -> dict:
    period = family['period']
    periodic = (True, family['kind'] != 'kerb')
    lods, objects, borders = [], [], []
    for level in range(3):
        started = time.time()
        stones = shapes.Builder(f'{module}_stones_lod{level}')
        dirt = shapes.Builder(f'{module}_dirt_lod{level}')
        floor = tiles.Floor(stones, dirt, period, periodic, level, seed)
        for piece in pieces:
            floor.emit(piece)
        floor.bedding((16, 6, 1)[level])
        tiles.clip_module(stones.bm, period, periodic)
        tiles.clip_module(dirt.bm, period, periodic)
        pair = [stones.to_object(), dirt.to_object()]
        copies = neighbours(pair, period, periodic)
        ao = bake.ao_to_color(pair, samples=samples, distance=0.25, floor=0.2)
        for copy in copies:
            mesh = copy.data
            bpy.data.objects.remove(copy)
            bpy.data.meshes.remove(mesh)
        level_borders = {}
        z_low, z_high = math.inf, -math.inf
        for obj in pair:
            tiles.average_border_colour(obj.data, period, periodic)
            level_borders[obj.name.rsplit('_', 2)[-2]] = profiles(obj.data, period, periodic)
            for v in obj.data.vertices:
                z_low, z_high = min(z_low, v.co.z), max(z_high, v.co.z)
            low = min(v.co[axis] for v in obj.data.vertices for axis in (0, 1))
            high = [max(v.co[axis] for v in obj.data.vertices) for axis in (0, 1)]
            assert low > -1e-4 and high[0] < period[0] + 1e-4 and high[1] < period[1] + 1e-4, (obj.name, low, high)
        self_seam = {part: seam_mm(level_borders[part], level_borders[part]) for part in level_borders}
        if floor.counts['border_fallbacks']:
            raise SystemExit(f'{module} lod{level}: {floor.counts["border_fallbacks"]} border stones needed a geometry fallback')
        tris = sum(triangles(obj) for obj in pair)
        if tris > TRI_BUDGET[level]:
            raise SystemExit(f'{module} lod{level}: {tris} triangles exceeds budget {TRI_BUDGET[level]}')
        if abs(z_low) > tiles.LIMIT_Z + 0.0011 or z_high > tiles.LIMIT_Z:
            raise SystemExit(f'{module} lod{level}: height range {z_low:.4f}..{z_high:.4f} m exceeds +/-2 cm')
        for obj in pair:
            # Godot: the module spans +X and +Z from its corner (Blender -Y is Godot +Z).
            obj.data.transform(Matrix.Translation((0.0, -period[1], 0.0)))
            bpy.context.scene.collection.objects.unlink(obj)
        objects.extend(pair)
        borders.append(level_borders)
        lods.append(dict(level=level, triangles=tris, stones_triangles=triangles(pair[0]), z_range_m=[round(z_low, 4), round(z_high, 4)],
                         stone_top_range_m=[round(floor.top_range[0], 4), round(floor.top_range[1], 4)],
                         self_seam_mm=self_seam, ao=ao, counts=floor.counts, seconds=round(time.time() - started, 1)))
        print(f'FLAGSTONES {module} lod{level}: {tris} tris, z {z_low:+.4f}..{z_high:+.4f}, seam {self_seam}', flush=True)
    return dict(lods=lods, objects=objects, borders=borders)


def review_material(name: str, dirt: bool) -> bpy.types.Material:
    """Render-only stand-in for the Godot shader: AO, per-stone tone and wear from Color."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['Principled BSDF']
    attribute = nodes.new('ShaderNodeAttribute')
    attribute.attribute_name = 'Color'
    split = nodes.new('ShaderNodeSeparateColor')
    links.new(attribute.outputs['Color'], split.inputs['Color'])
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 9.0
    noise.inputs['Detail'].default_value = 8.0
    uv = nodes.new('ShaderNodeUVMap')
    links.new(uv.outputs['UV'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    if dirt:
        ramp.color_ramp.elements[0].color = (0.035, 0.026, 0.018, 1)
        ramp.color_ramp.elements[1].color = (0.11, 0.085, 0.06, 1)
        links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    else:
        ramp.color_ramp.elements[0].color = (0.19, 0.17, 0.145, 1)
        ramp.color_ramp.elements[1].color = (0.42, 0.39, 0.34, 1)
        mix = nodes.new('ShaderNodeMath')
        mix.operation = 'MULTIPLY_ADD'
        mix.inputs[1].default_value = 0.6
        links.new(split.outputs['Green'], mix.inputs[0])
        links.new(noise.outputs['Fac'], mix.inputs[2])
        scale = nodes.new('ShaderNodeMath')
        scale.operation = 'MULTIPLY'
        scale.inputs[1].default_value = 0.62
        links.new(mix.outputs['Value'], scale.inputs[0])
        links.new(scale.outputs['Value'], ramp.inputs['Fac'])
    tone = nodes.new('ShaderNodeMix')
    tone.data_type = 'RGBA'
    tone.blend_type = 'MULTIPLY'
    tone.inputs['Factor'].default_value = 1.0
    links.new(ramp.outputs['Color'], tone.inputs['A'])
    links.new(split.outputs['Red'], tone.inputs['B'])
    wear = nodes.new('ShaderNodeMix')
    wear.data_type = 'RGBA'
    wear.blend_type = 'SCREEN'
    links.new(split.outputs['Blue'], wear.inputs['Factor'])
    links.new(tone.outputs['Result'], wear.inputs['A'])
    wear.inputs['B'].default_value = (0.22, 0.2, 0.17, 1)
    links.new(wear.outputs['Result'], shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value = 0.9 if dirt else 0.78
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.08 if not dirt else 0.25
    bump.inputs['Distance'].default_value = 0.002
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return material


def render_family(name: str, ids: list, built: dict, directory: Path, seed: int) -> list:
    """3 x 3 grid of mixed variants under a low warm point light."""
    scene = bpy.context.scene
    for obj in list(scene.collection.objects):
        scene.collection.objects.unlink(obj)
    stone_material = bpy.data.materials.get('ReviewStone') or review_material('ReviewStone', False)
    dirt_material = bpy.data.materials.get('ReviewDirt') or review_material('ReviewDirt', True)
    period = FAMILIES[name]['period']
    r = core.rng(seed, 'render', name)
    rows = 3 if FAMILIES[name]['kind'] != 'kerb' else 6
    for i in range(3):
        for j in range(rows):
            module = ids[r.randrange(len(ids))] if FAMILIES[name]['kind'] != 'kerb' else ids[(i + j) % len(ids)]
            for part in ('stones', 'dirt'):
                source = next(o for o in built[module]['objects'] if o.name == f'{module}_{part}_lod0')
                copy = core.link(bpy.data.objects.new(f'{module}_{part}_{i}_{j}', source.data))
                copy.location = (i * period[0], (j + 1) * period[1] - (0.0 if rows == 3 else j * 0.02), 0.0)
                copy.data.materials.clear()
                copy.data.materials.append(stone_material if part == 'stones' else dirt_material)
    width, depth = 3 * period[0], rows * period[1]
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.02, 0.022, 0.026, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    light_data = bpy.data.lights.new('Torch', 'POINT')
    light_data.color = (1.0, 0.63, 0.3)
    light_data.energy = 260.0
    light_data.shadow_soft_size = 0.06
    light = core.link(bpy.data.objects.new('Torch', light_data))
    light.location = (width * 0.5 + 0.3, depth * 0.5 + 0.2, 0.45)
    camera_data = bpy.data.cameras.new('Camera')
    camera = core.link(bpy.data.objects.new('Camera', camera_data))
    scene.camera = camera
    outputs = []
    views = [('overview', (width * 0.5, -depth * 0.35, 9.0), (width * 0.5, depth * 0.5, 0.0), 40.0),
             ('torch', (width * 0.5 - 3.4, depth * 0.5 - 3.6, 1.6), (width * 0.5 + 0.5, depth * 0.5 + 0.6, 0.0), 50.0)]
    if FAMILIES[name]['kind'] == 'kerb':
        light.location = (width * 0.5, depth + 0.6, 0.4)
        views = [('overview', (width * 0.5, -1.8, 4.2), (width * 0.5, depth * 0.5, 0.0), 45.0)]
    for view, eye, target, lens_angle in views:
        camera.location = eye
        direction = (target[0] - eye[0], target[1] - eye[1], target[2] - eye[2])
        camera.rotation_euler = (math.atan2(math.hypot(direction[0], direction[1]), -direction[2]), 0.0,
                                 math.atan2(direction[1], direction[0]) - math.pi / 2)
        camera_data.angle = math.radians(lens_angle)
        path = directory / f'blender_{name}_{view}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        outputs.append(path)
        print('FLAGSTONES render', core.relative(path), flush=True)
    for obj in list(scene.collection.objects):
        scene.collection.objects.unlink(obj)
    return outputs


def main() -> None:
    options = parse()
    out = Path(options.outdir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    core.empty_scene()
    only = {item for item in options.only.split(',') if item}
    built, report_modules, families = {}, {}, {}
    for name, family in FAMILIES.items():
        ids = [f'{name}_{variant}' for variant in family['variants']]
        if only and not only.intersection(ids):
            continue
        period = family['period']
        periodic = (True, family['kind'] != 'kerb')
        base_style = dict(BASE, **family['style'], seed=options.seed)
        variant_layouts = layouts(options.seed, name, family)
        for variant, spec in family['variants'].items():
            module = f'{name}_{variant}'
            if only and module not in only:
                continue
            style = dict(base_style, **spec['style'])
            pieces = variant_layouts[variant]
            for piece in pieces:
                # Border stones are dressed from the family style so every variant agrees at the cut.
                tiles.dress(piece, core.rng(options.seed, 'stone', name, *piece.key),
                            base_style if piece.border else style, period, periodic)
            pieces = tiles.damage(pieces, options.seed, module, style, period, periodic)
            result = build_module(module, family, pieces, options.seed, options.samples)
            for obj in result['objects']:
                core.link(obj)
            path = export.glb(result['objects'], out / f'flagstone_{module}.glb')
            for obj in result['objects']:
                bpy.context.scene.collection.objects.unlink(obj)
            built[module] = result
            roles = {}
            for piece in pieces:
                roles[piece.role] = roles.get(piece.role, 0) + 1
            report_modules[module] = dict(
                family=name, glb=core.relative(path), size_m=[period[0], period[1]],
                periodic=dict(x=periodic[0], z=periodic[1]),
                pieces=roles, border_stones=sum(1 for p in pieces if p.border),
                cracked_stones=len({p.key[:-1] for p in pieces if p.role == 'stone' and any(k == tiles.CRACK for k in p.kinds)}),
                broken_corners=sum(1 for p in pieces if p.role == 'stone' and tiles.BREAK in p.kinds),
                lods=result['lods'])
        built_ids = [m for m in ids if m in built]
        if len(built_ids) > 1 or (built_ids and FAMILIES[name]['kind'] != 'kerb'):
            cross = {}
            for a in built_ids:
                for b in built_ids:
                    for level in range(3):
                        for part in built[a]['borders'][level]:
                            errors = seam_mm(built[a]['borders'][level][part], built[b]['borders'][level][part])
                            key = f'{a}->{b}'
                            worst = cross.setdefault(key, {})
                            for axis, value in errors.items():
                                worst[axis] = max(worst.get(axis, 0.0), value)
            families[name] = dict(modules=built_ids, cross_seam_mm=cross,
                                  worst_seam_mm=max(max(v.values()) for v in cross.values()))
            print(f'FLAGSTONES family {name}: worst cross-variant seam {families[name]["worst_seam_mm"]} mm', flush=True)
            if families[name]['worst_seam_mm'] > 1.0:
                print('FLAGSTONES cross', cross, flush=True)
                raise SystemExit(f'family {name}: seam mismatch {families[name]["worst_seam_mm"]} mm exceeds 1 mm')
    renders = []
    if options.render:
        directory = Path(options.render).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        for name, family in FAMILIES.items():
            ids = [m for m in built if m.startswith(name + '_')]
            if ids:
                renders += render_family(name, ids, built, directory, options.seed)
    files = [out / f'flagstone_{m}.glb' for m in built]
    report_path = out / ('flagstones.json' if not only else 'flagstones_partial.json')
    report = core.write_report(report_path, dict(
        generator='scripts/art/build_flagstones.py', seed=options.seed, ao_samples=options.samples,
        module_size_m=P, lod_ranges_m=[list(r) for r in LOD_RANGES_M], triangle_budget=list(TRI_BUDGET),
        conventions={
            'axes': 'Godot: module spans +X and +Z from its corner; walking plane y = 0; all vertices within +/-0.021 m.',
            'nodes': '<id>_stones_lod{0,1,2} (stones and fragments) and <id>_dirt_lod{0,1,2} (bedding plus dirt fills).',
            'Color.R': 'baked AO (Cycles, 0.25 m distance, neighbours present; opposite borders averaged)',
            'Color.G': 'per-stone variation 0..1 (cracked pieces share their stone; dirt: soil noise)',
            'Color.B': 'edge wear: 1 on arrises and chips, 0.25 at the top edge, 0 on the worn top',
            'UV': 'metres; stones rotated and offset per stone, dirt and bedding in plain module metres',
            'tiling': 'variants of one family share every border stone, so any variant tiles with any other',
        },
        modules=report_modules, families=families,
        renders=[core.relative(p) for p in renders]), files)
    print('FLAGSTONES_OK', core.relative(report_path), {m: [l['triangles'] for l in v['lods']] for m, v in report_modules.items()},
          {f: v['worst_seam_mm'] for f, v in families.items()}, flush=True)
    return report


if __name__ == '__main__':
    main()
