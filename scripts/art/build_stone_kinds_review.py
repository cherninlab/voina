"""Review of the stone kinds (T-182): one wall panel per kind, laid course by
course with masonry.Wall, a floor-flag patch, close-ups and a stone lineup,
all shaded with the T-180 limestone maps in Cycles.

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_stone_kinds_review.py -- \
        [--out DIR] [--samples 96] [--only dressed_ashlar,thin_slab] [--quick] [--no-sheet]

Writes <out>/review/{contact_sheet,closeups,lineup}.png and
<out>/stone_kinds.json (triangle counts, library sizes, seed). Panels are
about 2.5 x 1.8 m. The squared_rubble panel is the reference the new kinds
must sit with: built exactly as build_architecture.py builds its walls
(stonelib.Library + masonry.Wall defaults).

Shading follows build_stone_surface.py's review: the limestone albedo,
normal_gl and roughness (and AO) through the dungeon_surface stand-in
material, box-projected per stone face in world metres at surface() density
0.555 with a random offset per stone, times the stone's tone and the fresh
channel, as the game's vertex colour does. A warm point torch rakes each
panel from the upper left; a dim cool area fill comes from behind the camera.
"""
import argparse
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
import numpy as np
from mathutils import Matrix, Vector

import build_stone_surface as surface
from procgen import core, disturb, masonry, stonekinds, stonelib

OUT = core.ROOT / 'content/environments/procedural_stone_kinds_v1'
LIMESTONE = core.ROOT / 'content/environments/procedural_stone_surface_v1/limestone'
SEED = 182
PANEL = (2.5, 1.8)
SPACING = 6.0
ROW = 6.0  # lineup rows, far enough apart that each close view shows one kind

# label, kind, library count, triangles (None = kind default)
PANELS = [
    ('squared_rubble (reference)', 'squared_rubble', 44, 200),
    ('dressed_ashlar', 'dressed_ashlar', 36, None),
    ('thin_slab', 'thin_slab', 90, None),
    ('small_squared', 'small_squared', 200, None),
    ('big_quoin', 'big_quoin', 18, None),
    ('galleted_rubble', 'galleted_rubble', 60, None),
    ('floor_flag', 'floor_flag', 22, None),
]


DUMP = None  # --dump DIR: also write every view on its own, for inspection


def parse() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default=str(OUT))
    parser.add_argument('--samples', type=int, default=96)
    parser.add_argument('--only', default='')
    parser.add_argument('--quick', action='store_true', help='fewer stones, small renders')
    parser.add_argument('--no-sheet', action='store_true', help='skip the panels, render only the lineup')
    parser.add_argument('--dump', default='', help='also write each view as its own PNG here')
    return parser.parse_args(core.args())


# -- shading -------------------------------------------------------------------

def stone_material() -> bpy.types.Material:
    """T-180's review material, times tone (object) and +8 % on fresh breaks."""
    material = surface.review_material('KindsLimestone', LIMESTONE, 0.75)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes['Principled BSDF']
    source = bsdf.inputs['Base Color'].links[0].from_socket
    tone = nodes.new('ShaderNodeAttribute')
    tone.attribute_type = 'OBJECT'
    tone.attribute_name = 'tone'
    colour = nodes.new('ShaderNodeAttribute')
    colour.attribute_type = 'GEOMETRY'
    colour.attribute_name = 'Color'
    split = nodes.new('ShaderNodeSeparateColor')
    links.new(colour.outputs['Color'], split.inputs[0])
    fresh = nodes.new('ShaderNodeMath')
    fresh.operation = 'MULTIPLY_ADD'
    links.new(split.outputs[2], fresh.inputs[0])
    fresh.inputs[1].default_value = 0.08
    fresh.inputs[2].default_value = 1.0
    factor = nodes.new('ShaderNodeMath')
    factor.operation = 'MULTIPLY'
    links.new(tone.outputs['Fac'], factor.inputs[0])
    links.new(fresh.outputs[0], factor.inputs[1])
    scale = nodes.new('ShaderNodeVectorMath')
    scale.operation = 'SCALE'
    links.new(source, scale.inputs[0])
    links.new(factor.outputs[0], scale.inputs['Scale'])
    links.new(scale.outputs['Vector'], bsdf.inputs['Base Color'])
    return material


def flat(name: str, colour, roughness: float = 0.95) -> bpy.types.Material:
    return surface.flat_material(name, colour, roughness)


def bake_in(objects: list, rng) -> None:
    """World-space meshes with box-projected UVs (surface.project_uvs's
    orientation), each stone offset to its own piece of the tile."""
    for obj in objects:
        obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        if obj.matrix_world.determinant() < 0.0:
            obj.data.flip_normals()
        obj.matrix_world = Matrix.Identity(4)
        mesh = obj.data
        if 'UVMap' in mesh.uv_layers:
            mesh.uv_layers.remove(mesh.uv_layers['UVMap'])
        uv = mesh.uv_layers.new(name='UVMap')
        shift = (rng.uniform(0.0, 1.0), rng.uniform(0.0, 1.0))
        up = Vector((0.0, 0.0, 1.0))
        for poly in mesh.polygons:
            n = poly.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            n = Vector([math.copysign(1.0, n[i]) if i == axis else 0.0 for i in range(3)])
            tangent = Vector((1.0, 0.0, 0.0)) if axis == 2 else up.cross(n)
            bitangent = n.cross(tangent)
            for index in poly.loop_indices:
                p = mesh.vertices[mesh.loops[index].vertex_index].co
                uv.data[index].uv = (p.dot(tangent) * surface.DENSITY + shift[0], p.dot(bitangent) * surface.DENSITY + shift[1])


# -- building ------------------------------------------------------------------

def tris(mesh) -> int:
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def library(kind: str, rng, count: int, triangles):
    if kind in stonekinds.KINDS:
        return stonekinds.Library(rng, kind, count=count, triangles=triangles)
    return stonelib.Library(rng, kind, count=count, triangles=triangles)


def build_panel(index: int, label: str, kind: str, count: int, triangles, quick: bool) -> dict:
    rng = core.rng(SEED, 'panel', kind)
    started = time.time()
    lib = library(kind, rng, max(8, count // 3) if quick else count, triangles)
    counts = [tris(entry[2] if kind in stonekinds.KINDS else entry[1]) for entry in lib.entries]
    look = stonekinds.KINDS.get(kind, {}).get('wall', {})
    floor = kind == 'floor_flag'
    wall = masonry.Wall(PANEL[0], PANEL[1], thickness=0.12 if floor else 0.5, **look)
    parts = wall.build(lib, rng, name=f'{kind}_panel')
    spalls = stonekinds.gallet(parts, rng) if kind == 'galleted_rubble' else []
    parts += spalls
    origin = Vector((index * SPACING, 0.0, 0.0))
    if floor:
        masonry.place(parts, origin, Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)))
    else:
        masonry.place(parts, origin, Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)))
    stones_ = [p for p in parts if float(p.get('tone', 1.0)) >= 0.0]
    mortar = [p for p in parts if float(p.get('tone', 1.0)) < 0.0]
    print('PANEL', kind, len(stones_), 'stones', len(spalls), 'spalls', f'{time.time() - started:.1f} s', flush=True)
    return {'label': label, 'kind': kind, 'index': index, 'stones': stones_, 'mortar': mortar, 'floor': floor,
            'library': len(lib.entries), 'triangles': counts, 'spalls': len(spalls),
            'spall_triangles': [tris(s.data) for s in spalls], 'lib': lib}


# Bands of the mixed panel, bottom up: (kind, height, Wall settings).
MIXED = [
    ('big_quoin', 0.46, dict(course=(0.46, 0.46), stone=(0.6, 1.1), joint=(0.004, 0.009), proud=(-0.002, 0.004))),
    ('squared_rubble', 0.66, {}),
    ('dressed_ashlar', 0.3, dict(course=(0.3, 0.3), stone=(0.45, 0.9), joint=(0.003, 0.007), proud=(-0.002, 0.004))),
    ('thin_slab', 0.38, stonekinds.KINDS['thin_slab']['wall']),
]


def build_mixed(index: int, libs: dict) -> dict:
    """The kinds in one wall, as a mason would combine them: a plinth course
    of big quoins, squared rubble (the reference), a dressed ashlar band and
    thin slab walling above, all laid with masonry.Wall from the panels'
    libraries, so they must sit together."""
    rng = core.rng(SEED, 'mixed')
    parts, y = [], 0.0
    for kind, height, settings in MIXED:
        band = masonry.Wall(PANEL[0], height, thickness=0.5, **settings).build(libs[kind], rng, name=f'mixed_{kind}')
        for obj in band:
            obj.matrix_world = Matrix.Translation((0.0, y, 0.0)) @ obj.matrix_world
        parts += band
        y += height
    masonry.place(parts, Vector((index * SPACING, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)))
    stones_ = [p for p in parts if float(p.get('tone', 1.0)) >= 0.0]
    mortar = [p for p in parts if float(p.get('tone', 1.0)) < 0.0]
    print('PANEL mixed', len(stones_), 'stones', flush=True)
    return {'label': 'mixed: quoin plinth, squared rubble, ashlar band, thin slabs', 'kind': 'mixed', 'index': index,
            'stones': stones_, 'mortar': mortar, 'floor': False}


def build_lineup(rng, kinds: list, y0: float = -40.0) -> list:
    """Rows of single stones per kind at natural size, fronts to -y, on a ground."""
    objects = []
    for row, kind in enumerate(kinds):
        x = 0.0
        for k in range(5):
            if kind in stonekinds.KINDS:
                size = stonekinds.natural_size(kind, rng)
                if kind == 'big_quoin':
                    size *= 0.6
                size.x = min(size.x, 0.7)
            else:
                size = Vector((rng.uniform(0.35, 0.6), rng.uniform(0.26, 0.34), 0.25))
            stone = stonekinds.make(kind, rng, size, name=f'line_{kind}_{k}',
                                    triangles=200 if kind == 'squared_rubble' else None)
            if kind == 'floor_flag':
                # A flag lies with its walking face (front, -y) up.
                stone.data.transform(Matrix.Rotation(math.radians(-90), 4, 'X'))
            if kind == 'galleted_rubble' and k == 4:
                bpy.data.objects.remove(stone)
                for g in range(4):
                    pin = stonekinds.spall(rng, name=f'line_spall_{g}')
                    zmin = min(v.co.z for v in pin.data.vertices)
                    pin.location = Vector((x + 0.06 * g + 0.03, y0 - row * ROW, -zmin))
                    pin['tone'] = rng.uniform(0.85, 1.15)
                    objects.append(pin)
                x += 0.3
                continue
            zmin = min(v.co.z for v in stone.data.vertices)
            xmin = min(v.co.x for v in stone.data.vertices)
            xmax = max(v.co.x for v in stone.data.vertices)
            stone.location = Vector((x - xmin, y0 - row * ROW, -zmin))
            stone['tone'] = rng.uniform(0.85, 1.15)
            x += xmax - xmin + 0.08
            objects.append(stone)
    return objects


# -- rendering -----------------------------------------------------------------

def light(name: str, kind: str, colour, energy: float, location, size: float, target=None):
    return surface.light(name, kind, colour, energy, location, size, target)


def caption(camera, text: str, lens: float, aspect: float) -> bpy.types.Object:
    curve = bpy.data.curves.new(f'caption_{text}', 'FONT')
    curve.body = text
    curve.size = 0.018 * 50.0 / lens
    obj = core.link(bpy.data.objects.new(f'caption_{text}', curve))
    material = bpy.data.materials.get('Caption') or bpy.data.materials.new('Caption')
    bsdf = material.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
    bsdf.inputs['Emission Color'].default_value = (0.85, 0.85, 0.8, 1)
    bsdf.inputs['Emission Strength'].default_value = 1.0
    curve.materials.append(material)
    obj.parent = camera
    half_w = 18.0 / lens
    obj.location = (-half_w * 0.95, -half_w * aspect * 0.9, -1.0)
    return obj


def show_only(collections: dict, name: str) -> None:
    for key, coll in collections.items():
        coll.hide_render = key != name


def render(eye, target, size, samples: int, lens: float, label: str = None) -> np.ndarray:
    scene = bpy.context.scene
    tag = caption(scene.camera, label, lens, size[1] / size[0]) if label else None
    scene.cycles.samples = samples
    camera = scene.camera
    camera.location = eye
    camera.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat('-Z', 'Y').to_euler()
    camera.data.lens = lens
    import tempfile
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'view.png'
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(str(path))
        pixels = np.empty(size[0] * size[1] * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
    if tag:
        bpy.data.objects.remove(tag)
    if DUMP:
        disturb.write_png(DUMP / f'{label or "view"}_{len(list(DUMP.glob("*.png")))}.png',
                          np.clip(pixels.reshape(size[1], size[0], 4)[::-1, :, :3] * 255.0 + 0.5, 0, 255).astype(np.uint8))
    rgb = pixels.reshape(size[1], size[0], 4)[::-1, :, :3]
    return np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)


def grid(images: list, columns: int) -> np.ndarray:
    h, w, _ = images[0].shape
    rows = (len(images) + columns - 1) // columns
    sheet = np.full((rows * h + (rows - 1) * 6, columns * w + (columns - 1) * 6, 3), 18, np.uint8)
    for k, image in enumerate(images):
        r, c = divmod(k, columns)
        sheet[r * (h + 6):r * (h + 6) + h, c * (w + 6):c * (w + 6) + w] = image
    return sheet


def main() -> None:
    global DUMP
    options = parse()
    out = Path(options.out).resolve()
    if options.dump:
        DUMP = Path(options.dump).resolve()
        DUMP.mkdir(parents=True, exist_ok=True)
    scene = core.empty_scene()
    device = surface.use_gpu(scene)
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Dark')
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.013, 0.015, 1.0)
    camera = core.link(bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')))
    scene.camera = camera
    only = [k for k in options.only.split(',') if k]
    panels = [p for p in PANELS if not only or p[1] in only or p[1] == 'squared_rubble']
    material = stone_material()
    # Mortar: the same limestone maps, dark and flatter (grimed lime deep in the joints).
    mortar = surface.review_material('KindsMortar', LIMESTONE, 0.45, tint=(0.36, 0.34, 0.31))
    ground = flat('Ground', (0.035, 0.032, 0.03))
    rng = core.rng(SEED, 'mapping')
    collections = {}
    built = []
    started = time.time()

    def collect(name: str, objects: list) -> None:
        coll = bpy.data.collections.new(name)
        scene.collection.children.link(coll)
        for obj in objects:
            for user in list(obj.users_collection):
                user.objects.unlink(obj)
            coll.objects.link(obj)
        collections[name] = coll

    lineup_kinds = [p[1] for p in panels]
    lineup = build_lineup(core.rng(SEED, 'lineup'), lineup_kinds)
    bake_in(lineup, rng)
    for obj in lineup:
        obj.data.materials.append(material)
    plane = bpy.data.meshes.new('lineup_ground')
    plane.from_pydata([(-3, -90, 0), (8, -90, 0), (8, -34, 0), (-3, -34, 0)], [], [(0, 1, 2, 3)])
    plane.materials.append(ground)
    collect('lineup', lineup + [core.link(bpy.data.objects.new('lineup_ground', plane))])
    if not options.no_sheet:
        libs = {}
        jobs = list(enumerate(panels))
        if not only:
            jobs.append((len(panels), None))
        for index, job in jobs:
            if job is None:
                panel = build_mixed(index, libs)
                kind = 'mixed'
            else:
                label, kind, count, triangles = job
                panel = build_panel(index, label, kind, count, triangles, options.quick)
                libs[kind] = panel.pop('lib')
            bake_in(panel['stones'], rng)
            for obj in panel['stones']:
                obj.data.materials.clear()
                obj.data.materials.append(material)
            bake_in(panel['mortar'], rng)
            for obj in panel['mortar']:
                obj.data.materials.append(mortar)
            x = index * SPACING
            floor = bpy.data.meshes.new(f'{kind}_ground')
            if panel['floor']:
                floor.from_pydata([(x - 1, -1, -0.13), (x + 3.5, -1, -0.13), (x + 3.5, 2.8, -0.13), (x - 1, 2.8, -0.13)], [], [(0, 1, 2, 3)])
            else:
                floor.from_pydata([(x - 1, -3, 0), (x + 3.5, -3, 0), (x + 3.5, 0.6, 0), (x - 1, 0.6, 0)], [], [(0, 1, 2, 3)])
            floor.materials.append(ground)
            collect(kind, panel['stones'] + panel['mortar'] + [core.link(bpy.data.objects.new(f'{kind}_ground', floor))])
            built.append(panel)
    print('BUILT', f'{time.time() - started:.1f} s', flush=True)

    size = (640, 480) if options.quick else (1000, 750)
    samples = max(8, options.samples // 3) if options.quick else options.samples
    review = out / 'review'
    review.mkdir(parents=True, exist_ok=True)
    lights = []

    def lit(objects: list) -> None:
        for obj in lights:
            bpy.data.objects.remove(obj)
        lights.clear()
        lights.extend(objects)

    # Lineup: one close view per kind's row of single stones, front and a little above.
    show_only(collections, 'lineup')
    cells = []
    for row, kind in enumerate(lineup_kinds):
        y = -40.0 - row * ROW
        objs = [o for o in collections['lineup'].objects if o.name.startswith(f'line_{kind}_') or
                (kind == 'galleted_rubble' and o.name.startswith('line_spall_'))]
        xs = [v.co.x for o in objs for v in o.data.vertices]
        middle = (min(xs) + max(xs)) * 0.5
        width = max(xs) - min(xs)
        lit([light('torch', 'POINT', (1.0, 0.78, 0.56), 160.0, (middle - width * 0.5 - 0.4, y - 0.9, 1.1), 0.05),
             light('fill', 'AREA', (0.6, 0.72, 0.85), 25.0, (middle + 1.5, y - 3.0, 1.2), 2.0, (middle, y, 0.1))])
        distance = max(width, 0.8) * 1.25
        cells.append(render((middle, y - distance, distance * 0.42), (middle, y + 0.05, 0.12),
                            (900, 420) if not options.quick else (600, 280), samples, 40.0, kind))
    disturb.write_png(review / 'lineup.png', grid(cells, 2))
    print('RENDERED lineup', flush=True)

    sheets, closeups = [], []
    for panel in built:
        x = panel['index'] * SPACING
        show_only(collections, panel['kind'])
        label = panel['label']
        if panel['floor']:
            lit([light('torch', 'POINT', (1.0, 0.78, 0.56), 260.0, (x - 0.5, 0.2, 1.4), 0.05),
                 light('fill', 'AREA', (0.6, 0.72, 0.85), 30.0, (x + 1.25, -3.0, 2.5), 2.5, (x + 1.25, 0.9, 0.0))])
            sheets.append(render((x + 1.25, -1.35, 2.1), (x + 1.25, 0.85, 0.0), size, samples, 30.0, label))
            closeups.append(render((x + 1.3, -0.25, 1.15), (x + 1.05, 0.65, 0.0), size, samples, 40.0, label))
        else:
            lit([light('torch', 'POINT', (1.0, 0.78, 0.56), 420.0, (x - 0.9, -1.1, 2.3), 0.05),
                 light('fill', 'AREA', (0.6, 0.72, 0.85), 40.0, (x + 1.8, -4.0, 1.4), 2.5, (x + 1.25, 0.0, 0.9))])
            sheets.append(render((x + 1.25 + 0.5, -3.1, 1.05), (x + 1.25, 0.0, 0.88), size, samples, 38.0, label))
            if panel['kind'] == 'mixed':
                # Where the plinth, the rubble and the ashlar band meet.
                closeups.append(render((x + 1.35, -1.25, 0.9), (x + 0.95, 0.0, 0.78), size, samples, 32.0, label))
            else:
                closeups.append(render((x + 1.15, -0.95, 1.05), (x + 0.75, 0.0, 0.92), size, samples, 50.0, label))
        print('RENDERED', panel['kind'], flush=True)
    if sheets:
        disturb.write_png(review / 'contact_sheet.png', grid(sheets, 4))
        disturb.write_png(review / 'closeups.png', grid(closeups, 4))
    report = {
        'task': 'T-182', 'seed': SEED, 'device': device, 'samples': samples, 'quick': options.quick,
        'panels': {p['kind']: {'library_stones': p['library'], 'placed': len(p['stones']), 'spalls': p['spalls'],
                               'triangles': {'min': min(p['triangles']), 'mean': round(sum(p['triangles']) / len(p['triangles']), 1),
                                             'max': max(p['triangles'])},
                               **({'spall_triangles': {'min': min(p['spall_triangles']), 'max': max(p['spall_triangles'])}}
                                  if p['spall_triangles'] else {})}
                   for p in built if 'triangles' in p},
        'mixed': [f'{kind} {height} m' for kind, height, _ in MIXED],
    }
    files = [review / name for name in ('contact_sheet.png', 'closeups.png', 'lineup.png') if (review / name).exists()]
    core.write_report(out / 'stone_kinds.json', report, files)
    print('STONE_KINDS_REPORT', json.dumps(report['panels']), flush=True)


if __name__ == '__main__':
    main()
