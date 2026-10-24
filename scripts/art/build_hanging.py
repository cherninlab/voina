"""Blender background: hanging dungeon dressing baked from cloth simulation.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_hanging.py -- \
    content/environments/procedural_hanging_v1 \
    [--review content/environments/red_descent/review/hanging_v1] [--only banner,rope] [--seed 164]

Types (three variants each): banner, tapestry (2-4 nails, torn hems, holes),
drape (cloth over a beam proxy that is not exported), web_corner and web_sheet
(alpha cards with metre UVs) and rope (catenary tube, no simulation).
Every cloth runs Blender's cloth modifier with its pins easing onto their
sockets, settles, is baked to a static mesh and measured: pin error against
the socket, edge length against the rest grid, last-frame motion. Cloth gets a
centred solidify; everything gets AO in Color.R. No collision is exported.
Sockets are glTF nodes named socket_<name> and are listed in bake.json in
Godot coordinates relative to each GLB origin. --review renders turntables.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Vector

from procgen import bake, cloth, core, curves, export, shapes

ARGS = core.args()
OUT = Path(ARGS[0]).resolve()
REVIEW = None
ONLY = None
SEED = 164
for index, value in enumerate(ARGS):
    if value == '--review':
        REVIEW = Path(ARGS[index + 1]).resolve()
    elif value == '--only':
        ONLY = set(ARGS[index + 1].split(','))
    elif value == '--seed':
        SEED = int(ARGS[index + 1])

PIN_LIMIT_M = 0.002
STRETCH_LIMIT = 1.05
SETTLE_LIMIT_M = 0.001
CLOTH_TRIANGLES = 6000
CLOTH_THICKNESS = 0.004
FRAMES = 300
GATHER_FRAMES = 30
UP = Vector((0, 0, 1))

# Blender axes: X = Godot X, Y = Godot -Z, Z = Godot Y.
BANNERS = [
    dict(size=(0.7, 1.7), cells=(20, 48), pin_at=(0.0, 1.0), gather=0.82, hem=0.05, shape='swallowtail',
         shape_depth=0.42, notches=1, holes=1, tears=1, fray=0.03, variation=0.15),
    # The right-hand nail is gone: that corner droops.
    dict(size=(1.0, 2.4), cells=(22, 52), pin_at=(0.0, 0.45, 0.8), gather=0.86, hem=0.14, shape='straight',
         shape_depth=0.0, notches=3, holes=2, tears=2, fray=0.06, variation=0.5),
    dict(size=(0.55, 1.3), cells=(16, 38), pin_at=(0.0, 1.0), gather=0.86, hem=0.04, shape='point',
         shape_depth=0.36, notches=0, holes=1, tears=1, fray=0.02, variation=0.85),
]
TAPESTRIES = [
    dict(size=(1.8, 1.3), cells=(40, 29), pin_at=(0.0, 0.5, 1.0), gather=0.9, hem=0.07, shape='straight',
         shape_depth=0.0, notches=2, holes=2, tears=1, fray=0.04, variation=0.3),
    # Fourth nail lost: the right third hangs from its neighbour.
    dict(size=(2.4, 1.6), cells=(42, 28), pin_at=(0.0, 0.34, 0.67), gather=0.9, hem=0.10, shape='straight',
         shape_depth=0.0, notches=4, holes=3, tears=2, fray=0.05, variation=0.6),
    dict(size=(1.4, 1.9), cells=(28, 38), pin_at=(0.0, 0.33, 0.67, 1.0), gather=0.85, hem=0.22, shape='straight',
         shape_depth=0.0, notches=3, holes=4, tears=3, fray=0.10, variation=0.9),
]
# Beam sections are the dungeon's: cloth bearer, roof tie, wall bearer
# (gameplay/environment/dungeon_structure.gd), width across x height.
DRAPES = [
    dict(size=(1.1, 1.5), cells=(22, 40), beam=(0.25, 0.25), split=0.5, gather=0.84, hem=0.05, holes=1, tears=1,
         variation=0.2),
    dict(size=(1.4, 2.6), cells=(24, 46), beam=(0.42, 0.55), split=0.42, gather=0.9, hem=0.10, holes=2, tears=2,
         variation=0.55),
    dict(size=(0.9, 1.8), cells=(20, 44), beam=(0.30, 0.38), split=0.6, gather=0.8, hem=0.12, holes=1, tears=2,
         variation=0.8),
]
# Corner webs: apex at the origin, anchored along two edges. 'ceiling' edges
# run along Godot +X and +Z (under a ceiling between two walls); 'frame'
# edges run along +X (beam underside) and -Y (post face).
WEB_CORNERS = [
    dict(size=(0.5, 0.45), cells=(16, 15), corner='ceiling', sag=0.07, holes=1, tears=1, variation=0.3),
    dict(size=(0.8, 0.7), cells=(18, 16), corner='ceiling', sag=0.12, holes=2, tears=2, variation=0.6),
    dict(size=(0.6, 0.75), cells=(16, 18), corner='frame', sag=0.08, holes=2, tears=1, variation=0.9),
]
# Sheets between two parallel beams: line A at Godot z = -gap/2, line B at
# +gap/2 and `rise` lower. 1.26 m is the clear gap between the procedural deck
# stringers (0.30 m at +/-0.78 m) of non-baked wooden routes.
WEB_SHEETS = [
    dict(length=0.9, gap=1.26, rise=0.0, sag=0.22, cells=(16, 22), holes=2, tears=1, variation=0.25),
    dict(length=0.6, gap=0.7, rise=0.0, sag=0.16, cells=(14, 18), holes=3, tears=1, variation=0.55),
    dict(length=1.3, gap=1.5, rise=0.3, sag=0.3, cells=(20, 24), holes=3, tears=2, variation=0.85),
]
ROPES = [
    dict(span=1.8, rise=0.0, slack=0.035, radius=0.013, tail=0.0, variation=0.2),
    dict(span=3.0, rise=-0.6, slack=0.05, radius=0.018, tail=0.0, variation=0.5),
    dict(span=1.4, rise=0.0, slack=0.10, radius=0.011, tail=0.55, variation=0.8),
]


def godot(v) -> list:
    return [round(c, 6) for c in core.to_godot(v)]


def box(name: str, centre: Vector, size: Vector) -> bpy.types.Object:
    """Axis-aligned proxy cuboid (Blender coordinates); never exported."""
    mesh = bpy.data.meshes.new(name)
    hx, hy, hz = size.x / 2, size.y / 2, size.z / 2
    verts = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj.location = centre
    return obj


def beam(name: str, length: float, width: float, height: float, centre: Vector = Vector()) -> bpy.types.Object:
    """Chamfered beam proxy along X like the dungeon's hewn timber (chamfer
    12% of the smaller side); a cloth collider or AO occluder, never exported."""
    c = min(width, height) * 0.12
    w, h = width / 2, height / 2
    ring = [(-w + c, -h), (w - c, -h), (w, -h + c), (w, h - c), (w - c, h), (-w + c, h), (-w, h - c), (-w, -h + c)]
    verts = [(x, y, z) for x in (-length / 2, length / 2) for y, z in ring]
    faces = [tuple(reversed(range(8))), tuple(range(8, 16))]
    faces += [(k, (k + 1) % 8, (k + 1) % 8 + 8, k + 8) for k in range(8)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj.location = centre
    return obj


def wave(rng, amplitude: float):
    """Gentle out-of-plane ripple that seeds buckling; zero at v = 0."""
    terms = [(rng.uniform(2.5, 6.0), rng.uniform(0.8, 2.5), rng.uniform(0, 6.3), rng.uniform(0.4, 1.0))
             for _ in range(3)]

    def offset(u: float, v: float) -> float:
        fade = min(1.0, v / 0.25)
        return amplitude * fade * sum(w * math.sin(a * u * math.tau / 2 + b * v + p) for a, b, p, w in terms) / 2
    return offset


def outline(rng, spec: dict, width: float, height: float, hole_box=None, hole_radius=(0.04, 0.12)):
    """Mask for a cloth hanging from its v = 0 edge: ragged hem, frayed sides, holes."""
    hem = cloth.ragged_edge(rng, spec['hem'], notches=spec.get('notches', 0), notch_depth=height * 0.12,
                            shape=spec.get('shape', 'straight'), shape_depth=spec.get('shape_depth', 0.0))
    left, right = cloth.smooth_noise(rng, 9), cloth.smooth_noise(rng, 9)
    holes = cloth.blobs(rng, spec['holes'], hole_box or (0.15 * width, 0.3 * height, 0.85 * width, 0.8 * height),
                        hole_radius)
    fray = spec.get('fray', 0.03)

    def keep(u: float, v: float) -> bool:
        if v > height - hem(u / width):
            return False
        t = v / height
        if u < fray * t * t * (1.2 + left(t)) or u > width - fray * t * t * (1.2 + right(t)):
            return False
        return not holes(u, v)
    keep.holes = holes.count
    return keep


def tears(rng, panel: cloth.Panel, count: int, max_rows: int, from_end: bool = True) -> int:
    made = 0
    for _ in range(count * 4):
        if made >= count:
            break
        col = rng.randint(2, panel.cols - 2)
        length = rng.randint(max(3, max_rows // 2), max_rows)
        row0, row1 = (panel.rows - length, panel.rows) if from_end else (0, length)
        if panel.tear(col, row0, row1) >= 2:
            made += 1
    return made


def hanging(kind: str, variant: int, spec: dict) -> dict:
    """Banner or tapestry: nails along the top edge, gathered by `gather`."""
    rng = core.rng(SEED, kind, variant)
    width, height = spec['size']
    ripple = wave(rng, 0.02)
    # Origin at the midpoint of the outermost nails.
    middle = (spec['pin_at'][0] + spec['pin_at'][-1]) / 2 * width

    def place(u: float, v: float) -> Vector:
        return Vector((u - middle, ripple(u / width, v), -v))
    keep = outline(rng, spec, width, height)
    panel = cloth.Panel(f'{kind.title()}{variant}', spec['size'], spec['cells'], place, keep=keep,
                        variation=spec['variation'])
    made = tears(rng, panel, spec['tears'], panel.rows // 4)
    sockets = {}
    for index, fraction in enumerate(spec['pin_at']):
        col = round(fraction * panel.cols)
        rest = panel.vert(col, 0).co
        target = Vector((rest.x * spec['gather'], 0.0, 0.0))
        panel.pin(col, 0, target)
        sockets[f'pin_{index}'] = target
    obj = panel.build(front=Vector((0, -1, 0)))
    # The beam the nails go into: gathered cloth buckles against it instead of
    # through it, and it darkens the top edge in the AO bake. Not exported.
    proxy = cloth.collider(beam('BeamProxy', 2 * width + 0.6, 0.25, 0.25, Vector((0, 0, 0.125))))
    metrics = cloth.simulate(obj, panel, cloth.CANVAS, FRAMES, GATHER_FRAMES, collide=True, distance=0.003)
    proxy.modifiers.clear()
    metrics['max_above_nails_m'] = max(v.co.z for v in obj.data.vertices)
    cloth.thicken(obj, CLOTH_THICKNESS)
    return dict(object=obj, sockets=sockets, proxies=[proxy], metrics=metrics, thickness_m=CLOTH_THICKNESS,
                panel=panel, size_m=list(spec['size']), cells=list(spec['cells']), gather=spec['gather'],
                hem_shape=spec['shape'], holes=keep.holes, tears=made,
                mount='Origin is the midpoint of the nail line; nails lie on local X at y = 0, cloth hangs '
                      'towards -Y with its front facing +Z. Put the origin on a beam underside (or a wall '
                      'face) with local X along the beam.')


def drape(variant: int, spec: dict) -> dict:
    """Cloth thrown over a beam proxy, nailed twice on the beam top and gathered."""
    rng = core.rng(SEED, 'drape', variant)
    width, height = spec['size']
    beam_w, beam_h = spec['beam']
    cols, rows = spec['cells']
    top = beam_h / 2 + 0.006
    centre_row = round(spec['split'] * rows)
    v0 = centre_row / rows * height
    ripple = wave(rng, 0.01)

    def place(u: float, v: float) -> Vector:
        return Vector((u - width / 2, v - v0, top + 0.6 * ripple(u / width, abs(v - v0) + 0.25)))
    hem_a = cloth.ragged_edge(rng, spec['hem'], notches=1, notch_depth=height * 0.06)
    hem_b = cloth.ragged_edge(rng, spec['hem'], notches=2, notch_depth=height * 0.06)
    holes = cloth.blobs(rng, spec['holes'], (0.15 * width, 0.05 * height, 0.85 * width, 0.95 * height), (0.04, 0.1),
                        avoid=lambda u, v: abs(v - v0) < beam_w)

    def keep(u: float, v: float) -> bool:
        return hem_a(u / width) < v < height - hem_b(u / width) and not holes(u, v)
    panel = cloth.Panel(f'Drape{variant}', spec['size'], spec['cells'], place, keep=keep, variation=spec['variation'])
    made = tears(rng, panel, (spec['tears'] + 1) // 2, rows // 5, from_end=True)
    made += tears(rng, panel, spec['tears'] // 2, rows // 5, from_end=False)
    sockets = {}
    for index, fraction in enumerate((0.22, 0.78)):
        col = round(fraction * cols)
        rest = panel.vert(col, centre_row).co
        target = Vector((rest.x * spec['gather'], 0.0, top))
        panel.pin(col, centre_row, target)
        sockets[f'nail_{index}'] = target
    obj = panel.build(front=UP)
    proxy = cloth.collider(beam('BeamProxy', width + 1.0, beam_w, beam_h))
    metrics = cloth.simulate(obj, panel, cloth.LINEN, FRAMES, GATHER_FRAMES, collide=True, distance=0.004,
                             calm=(FRAMES - 90, 40.0))
    proxy.modifiers.clear()
    cloth.thicken(obj, CLOTH_THICKNESS)
    clearance = min_clearance(obj, beam_w, beam_h)
    return dict(object=obj, sockets=sockets, proxies=[proxy], metrics=metrics, thickness_m=CLOTH_THICKNESS,
                panel=panel, size_m=list(spec['size']), cells=list(spec['cells']), gather=spec['gather'],
                holes=holes.count, tears=made, beam_proxy_godot={'centre': [0, 0, 0], 'size': [width + 1.0, beam_h, beam_w]},
                beam_clearance_m=clearance,
                mount=f'Origin is the beam axis; the beam runs along local X with a {beam_w:.2f} m wide x '
                      f'{beam_h:.2f} m tall section (Godot dungeon timber). Nails sit on the beam top.')


def min_clearance(obj, beam_w: float, beam_h: float) -> float:
    """Signed distance from the chamfered beam section (see beam()) to the
    deepest cloth vertex; negative means the cloth is inside the beam."""
    w, h, c = beam_w / 2, beam_h / 2, min(beam_w, beam_h) * 0.12
    worst = math.inf
    for v in obj.data.vertices:
        y, z = abs(v.co.y), abs(v.co.z)
        worst = min(worst, max(y - w, z - h, (y + z - (w + h - c)) / math.sqrt(2)))
    return round(worst, 5)


def web_corner(variant: int, spec: dict) -> dict:
    """Web sheet in a corner, anchored along two edges and sagging between."""
    rng = core.rng(SEED, 'web_corner', variant)
    l1, l2 = spec['size']
    if spec['corner'] == 'ceiling':
        d1, d2, normal, front = Vector((1, 0, 0)), Vector((0, -1, 0)), Vector((0, 0, -1)), UP
    else:
        d1, d2, normal, front = Vector((1, 0, 0)), Vector((0, 0, -1)), Vector((0, -1, 0)), Vector((0, -1, 0))
    edge = cloth.smooth_noise(rng, 11)
    holes = cloth.blobs(rng, spec['holes'], (0.2 * l1, 0.2 * l2, 0.6 * l1, 0.6 * l2), (0.02, 0.06))

    def reach(u: float, v: float) -> float:
        return (u / l1) ** 0.8 + (v / l2) ** 0.8

    def place(u: float, v: float) -> Vector:
        # Pre-draped: the sheet bellies away from the corner (zero on both anchors).
        belly = spec['sag'] * math.sin(math.pi / 2 * min(1.0, u / l1 * 1.4)) * math.sin(math.pi / 2 * min(1.0, v / l2 * 1.4))
        return d1 * u + d2 * v + normal * belly

    def keep(u: float, v: float) -> bool:
        theta = math.atan2(v / l2, u / l1) / (math.pi / 2)
        return reach(u, v) < 0.93 + 0.07 * edge(theta) and not holes(u, v)
    panel = cloth.Panel(f'WebCorner{variant}', spec['size'], spec['cells'], place, keep=keep,
                        variation=spec['variation'], wear_width=0.06)
    made = 0
    for _ in range(spec['tears']):
        col = rng.randint(panel.cols // 3, panel.cols - 3)
        made += panel.tear(col, max(2, panel.rows // 2 - 2), panel.rows) >= 2
    pinned = 0
    for col in range(panel.cols + 1):
        if panel.vert(col, 0).link_faces:
            panel.pin(col, 0, panel.vert(col, 0).co.copy())
            pinned += 1
    for row in range(1, panel.rows + 1):
        if panel.vert(0, row).link_faces:
            panel.pin(0, row, panel.vert(0, row).co.copy())
            pinned += 1
    ends = [max((v.co.copy() for v, _ in panel.pins), key=lambda p: p.dot(d)) for d in (d1, d2)]
    sockets = {'apex': Vector((0, 0, 0)), 'end_u': ends[0], 'end_v': ends[1]}
    obj = panel.build(front=front)
    metrics = cloth.simulate(obj, panel, cloth.WEB, FRAMES, 2)
    cloth.smooth(obj)
    return dict(object=obj, sockets=sockets, proxies=[], metrics=metrics, thickness_m=0.0, panel=panel,
                size_m=list(spec['size']), cells=list(spec['cells']), corner=spec['corner'], pinned_vertices=pinned,
                holes=holes.count, tears=made, alpha_card=True,
                uv='metres from the apex: U along end_u, V along end_v (cobweb.gdshader draws radial threads round UV 0,0)',
                mount=('Origin is the corner apex. Anchored edges run along local +X and +Z: put it under a '
                       'ceiling where two walls meet, rotated so both edges lie on the walls.'
                       if spec['corner'] == 'ceiling' else
                       'Origin is the corner apex. Anchored edges run along local +X (beam underside) and -Y '
                       '(post face): put it where a beam meets a post, front facing +Z.'))


def web_sheet(variant: int, spec: dict) -> dict:
    """Web sheet slung between two parallel beams."""
    rng = core.rng(SEED, 'web_sheet', variant)
    length, gap, rise, sag = spec['length'], spec['gap'], spec['rise'], spec['sag']
    cols, rows = spec['cells']
    # Rest width is the sagging arc's length, so the anchors are never compressed.
    arc = sum(math.dist((gap * i / 64, -rise * i / 64 - sag * math.sin(math.pi * i / 64)),
                        (gap * (i + 1) / 64, -rise * (i + 1) / 64 - sag * math.sin(math.pi * (i + 1) / 64)))
              for i in range(64))
    left, right = cloth.smooth_noise(rng, 9), cloth.smooth_noise(rng, 9)
    holes = cloth.blobs(rng, spec['holes'], (0.2 * length, 0.25 * arc, 0.8 * length, 0.75 * arc), (0.03, 0.08))

    def place(u: float, v: float) -> Vector:
        t = v / arc
        return Vector((u - length / 2, gap / 2 - gap * t, -rise * t - sag * math.sin(math.pi * t)))

    def keep(u: float, v: float) -> bool:
        t = v / arc
        bite = 0.1 * length * math.sin(math.pi * t) ** 0.7
        return bite * (1.1 + left(t)) < u < length - bite * (1.1 + right(t)) and not holes(u, v)
    panel = cloth.Panel(f'WebSheet{variant}', (length, arc), spec['cells'], place, keep=keep,
                        variation=spec['variation'], wear_width=0.06)
    made = 0
    for _ in range(spec['tears']):
        row = rng.randint(rows // 3, 2 * rows // 3)
        side = rng.random() < 0.5
        col0 = 0 if side else cols - cols // 3
        # Horizontal tears from a free side: split along a row line.
        edges = []
        for col in range(col0, col0 + cols // 3):
            a, b = panel.vert(col, row), panel.vert(col + 1, row)
            e = panel.bm.edges.get((a, b))
            if e is not None and len(e.link_faces) == 2:
                edges.append(e)
        if len(edges) >= 2:
            bmesh.ops.split_edges(panel.bm, edges=edges)
            made += 1
    line_a, line_b = [], []
    for col in range(cols + 1):
        for row, line in ((0, line_a), (rows, line_b)):
            vert = panel.vert(col, row)
            if vert.link_faces:
                panel.pin(col, row, vert.co.copy())
                line.append(vert.co.copy())
    sockets = {'a_0': line_a[0], 'a_1': line_a[-1], 'b_0': line_b[0], 'b_1': line_b[-1]}
    obj = panel.build(front=UP)
    metrics = cloth.simulate(obj, panel, cloth.WEB, FRAMES, 2)
    cloth.smooth(obj)
    return dict(object=obj, sockets=sockets, proxies=[], metrics=metrics, thickness_m=0.0, panel=panel,
                size_m=[length, round(arc, 4)], gap_m=gap, rise_m=rise, cells=list(spec['cells']), holes=holes.count,
                tears=made, alpha_card=True,
                uv='metres: U along the beams, V across from line A (cobweb.gdshader sheet style)',
                mount='Origin is midway between the anchor lines. Line A (a_0-a_1) runs along local X at '
                      f'z = {-gap / 2:.3f}, line B at z = {gap / 2:.3f}, y = {-rise:.3f}: put the lines on the inner '
                      'faces or undersides of two parallel beams.')


def rope(variant: int, spec: dict) -> dict:
    """Catenary rope between two sockets with bound ends; optional hanging tail."""
    a = Vector((0, 0, 0))
    b = Vector((spec['span'], 0, spec['rise']))
    radius = spec['radius']
    color = (1.0, spec['variation'], 0.0, 1.0)
    builder = shapes.Builder(f'Rope{variant}')
    points = curves.catenary(a, b, spec['slack'], count=40)
    curves.tube(builder, points, radius, sides=8, color=color, twist=6.0)
    ring_a = list(builder.bm.verts)[:8]
    builder.bm.verts.ensure_lookup_table()
    ring_b = [builder.bm.verts[i] for i in range(len(builder.bm.verts) - 8, len(builder.bm.verts))]
    pin_error = max((sum((v.co for v in ring), Vector()) / 8 - target).length for ring, target in ((ring_a, a), (ring_b, b)))
    for end, inward in ((a, points[1] - a), (b, points[-2] - b)):
        binding(builder, end, inward.normalized(), radius, color)
    tail_length = 0.0
    if spec['tail']:
        down = Vector((0, 0, -1))
        out = (b - points[-2]).normalized()
        tail = [b + down * spec['tail'] * t + out * 0.05 * math.sin(math.pi * t * 0.8) for t in (i / 16 for i in range(17))]
        curves.tube(builder, tail, radius * 0.95, sides=8, color=color, twist=6.0)
        builder.bm.verts.ensure_lookup_table()
        end_ring = [builder.bm.verts[i] for i in range(len(builder.bm.verts) - 8, len(builder.bm.verts))]
        centre = sum((v.co for v in end_ring), Vector()) / 8
        for v in end_ring:
            v.co = centre + (v.co - centre) * 1.25  # frayed end
        builder.face(list(reversed(end_ring)), [Vector((0.0, 0.0))] * 8, color)
        tail_length = spec['tail']
    length = sum((q - p).length for p, q in zip(points, points[1:]))
    design = (b - a).length * (1 + spec['slack'])
    obj = builder.to_object(smooth_angle=80.0)
    return dict(object=obj, sockets={'a': a, 'b': b}, proxies=[], panel=None, thickness_m=0.0,
                metrics={'max_pin_error_m': pin_error, 'max_edge_stretch': None, 'length_ratio': length / design,
                         'sag_m': curves.sag(points), 'frames': 0},
                radius_m=radius, span_m=spec['span'], rise_m=spec['rise'], slack=spec['slack'], tail_m=tail_length,
                simulated=False,
                mount='Origin is socket a; socket b is span along local X and rise in Y. Fix both ends to beam '
                      'faces; the bound ends hide the tube openings.')


def binding(builder, centre: Vector, axis: Vector, radius: float, color) -> None:
    """Short whipping coil round the rope end."""
    side = axis.cross(UP)
    if side.length < 1e-6:
        side = axis.cross(Vector((1, 0, 0)))
    side.normalize()
    up = axis.cross(side)
    steps, turns, length = 30, 2.5, radius * 3.5
    coil = [centre + axis * (length * i / steps) + (side * math.cos(turns * math.tau * i / steps) +
                                                    up * math.sin(turns * math.tau * i / steps)) * radius * 1.2
            for i in range(steps + 1)]
    curves.tube(builder, coil, radius * 0.45, sides=6, color=color)


def place_sockets(sockets: dict) -> list:
    empties = []
    for name, at in sockets.items():
        empty = core.link(bpy.data.objects.new(f'socket_{name}', None))
        empty.empty_display_type = 'SPHERE'
        empty.empty_display_size = 0.02
        empty.location = at
        empties.append(empty)
    return empties


def bounds_godot(obj) -> dict:
    points = [core.to_godot(v.co) for v in obj.data.vertices]
    return {'min': [round(min(p[i] for p in points), 4) for i in range(3)],
            'max': [round(max(p[i] for p in points), 4) for i in range(3)]}


def run(kind: str, variant: int, build) -> dict:
    core.empty_scene()
    result = build()
    obj = result.pop('object')
    obj.name = f'{kind}_{variant}'
    obj.data.name = obj.name
    sockets = result.pop('sockets')
    proxies = result.pop('proxies')
    panel = result.pop('panel')
    metrics = result.pop('metrics')
    ao = bake.ao_to_color([obj], samples=48, distance=0.35)[obj.name]
    for proxy in proxies:
        bpy.data.objects.remove(proxy, do_unlink=True)
    obj['hanging'] = {'type': kind, 'variant': variant,
                      'sockets_godot': {name: godot(at) for name, at in sockets.items()}}
    empties = place_sockets(sockets)
    path = export.glb([obj] + empties, OUT / f'{kind}_{variant}.glb')
    entry = {'type': kind, 'variant': variant, 'seed': SEED, 'file': core.relative(path),
             'triangles': cloth.triangles(obj), 'vertices': len(obj.data.vertices),
             'sockets_godot': {name: godot(at) for name, at in sockets.items()},
             'bounds_godot': bounds_godot(obj), 'ao': ao, 'collision': False, **result}
    for key, value in metrics.items():
        entry[key] = round(value, 7) if isinstance(value, float) else value
    if panel is not None:
        # Exported surface at each socket: the solidified shell sits thickness / 2 either side of
        # the simulated mid surface the pins were measured on; alpha cards sit on it.
        entry['socket_surface_gap_m'] = round(max(min((v.co - at).length for v in obj.data.vertices)
                                                  for at in sockets.values()), 6)
    if 'settle_worst_rest' in entry:
        entry['settle_worst_rest'] = godot(entry['settle_worst_rest'])
    if panel is not None:
        entry['pins'] = len(panel.pin_ids)
        entry['islands_dropped'] = panel.islands_dropped
        entry['cells_eroded'] = panel.cells_eroded
        assert entry['max_pin_error_m'] <= PIN_LIMIT_M, (kind, variant, entry['max_pin_error_m'])
        assert entry['max_edge_stretch'] <= STRETCH_LIMIT, (kind, variant, entry['max_edge_stretch'])
        assert entry['settle_motion_m'] < SETTLE_LIMIT_M, (kind, variant, entry['settle_motion_m'])
        # Cloth stays out of the beam it hangs from (mid surface; half the solidify is 2 mm).
        assert entry.get('max_above_nails_m', 0.0) <= 0.003, (kind, variant, entry.get('max_above_nails_m'))
        assert entry.get('beam_clearance_m', 0.0) >= -0.003, (kind, variant, entry.get('beam_clearance_m'))
    else:
        assert entry['max_pin_error_m'] <= PIN_LIMIT_M, (kind, variant, entry['max_pin_error_m'])
    if not result.get('alpha_card'):
        assert entry['triangles'] <= CLOTH_TRIANGLES or kind == 'rope', (kind, variant, entry['triangles'])
    print(f'HANGING_ASSET {kind}_{variant} tris={entry["triangles"]} pin={entry["max_pin_error_m"]:.6f} '
          f'stretch={entry.get("max_edge_stretch")} settle={entry.get("settle_motion_m")} '
          f'sim={entry.get("sim_seconds")}s ao={ao} motion={entry.get("motion_per_second_m")} '
          f'worst={entry.get("settle_worst_rest")}', flush=True)
    return entry


def builders():
    for variant, spec in enumerate(BANNERS):
        yield 'banner', variant, lambda spec=spec, variant=variant: hanging('banner', variant, spec)
    for variant, spec in enumerate(TAPESTRIES):
        yield 'tapestry', variant, lambda spec=spec, variant=variant: hanging('tapestry', variant, spec)
    for variant, spec in enumerate(DRAPES):
        yield 'drape', variant, lambda spec=spec, variant=variant: drape(variant, spec)
    for variant, spec in enumerate(WEB_CORNERS):
        yield 'web_corner', variant, lambda spec=spec, variant=variant: web_corner(variant, spec)
    for variant, spec in enumerate(WEB_SHEETS):
        yield 'web_sheet', variant, lambda spec=spec, variant=variant: web_sheet(variant, spec)
    for variant, spec in enumerate(ROPES):
        yield 'rope', variant, lambda spec=spec, variant=variant: rope(variant, spec)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    report_path = OUT / 'bake.json'
    previous = {}
    if ONLY and report_path.exists():
        import json
        previous = {f"{a['type']}_{a['variant']}": a for a in json.loads(report_path.read_text())['assets']}
    assets = []
    for kind, variant, build in builders():
        key = f'{kind}_{variant}'
        if ONLY and kind not in ONLY:
            if key in previous:
                assets.append(previous[key])
            continue
        assets.append(run(kind, variant, build))
    simulated = [a for a in assets if a.get('max_edge_stretch') is not None]
    summary = {
        'assets': len(assets),
        'max_pin_error_m': max(a['max_pin_error_m'] for a in assets),
        'max_edge_stretch': max(a['max_edge_stretch'] for a in simulated) if simulated else None,
        'max_settle_motion_m': max(a['settle_motion_m'] for a in simulated) if simulated else None,
        'max_cloth_triangles': max((a['triangles'] for a in assets if a['type'] in ('banner', 'tapestry', 'drape')),
                                   default=0),
    }
    report = core.write_report(report_path, {
        'method': 'Blender cloth modifier with gravity; pinned vertices ease from the rest grid onto their sockets '
                  'over gather_frames through a shape key, the evaluated last frame is baked to a static mesh. '
                  'Banners, tapestries and drapes collide with an unexported chamfered beam proxy. Webs are '
                  'pre-draped cards settled under gravity. Ropes are analytic catenary tubes. '
                  'max_pin_error_m: settled pin vertex to socket. max_edge_stretch: settled / rest edge length. '
                  'settle_motion_m: largest vertex move over the last frame.',
        'generator': 'scripts/art/build_hanging.py', 'toolkit': 'scripts/art/procgen (cloth.py, curves.py, bake.py)',
        'seed': SEED, 'realtime_physics': False, 'collision_exported': False,
        'units': 'metres; sockets and bounds in Godot coordinates relative to each GLB origin',
        'color_attribute': 'COLOR_0: R = baked AO, G = variation, B = edge wear (free edges, cloth and webs)',
        'limits': {'max_pin_error_m': PIN_LIMIT_M, 'max_edge_stretch': STRETCH_LIMIT,
                   'settle_motion_m': SETTLE_LIMIT_M, 'cloth_triangles': CLOTH_TRIANGLES},
        'summary': summary, 'assets': assets,
    }, files=sorted(OUT.glob('*.glb')))
    print('HANGING_BAKE_OK', report['summary'], flush=True)
    if REVIEW is not None:
        render_turntables(report)


DYES = [(0.32, 0.035, 0.025), (0.36, 0.22, 0.07), (0.06, 0.12, 0.11), (0.16, 0.10, 0.06)]


def review_material(kind: str) -> bpy.types.Material:
    """Cycles look for review renders only: Color.R as AO, G picks a dye,
    B (edge wear) bleaches cloth edges and fades webs. Nothing is exported."""
    material = bpy.data.materials.new(f'Review_{kind}')
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['Principled BSDF']
    attribute = nodes.new('ShaderNodeVertexColor')
    attribute.layer_name = 'Color'
    split = nodes.new('ShaderNodeSeparateColor')
    links.new(attribute.outputs['Color'], split.inputs['Color'])
    shade = nodes.new('ShaderNodeMix')
    shade.data_type = 'RGBA'
    shade.blend_type = 'MULTIPLY'
    shade.inputs['Factor'].default_value = 1.0
    links.new(split.outputs['Red'], shade.inputs['B'])
    if kind == 'rope':
        shade.inputs['A'].default_value = (0.30, 0.22, 0.13, 1)
        shader.inputs['Roughness'].default_value = 0.9
    elif kind.startswith('web'):
        shade.inputs['A'].default_value = (0.75, 0.75, 0.72, 1)
        fade = nodes.new('ShaderNodeMath')
        fade.operation = 'MULTIPLY_ADD'
        fade.inputs[1].default_value = -0.6
        fade.inputs[2].default_value = 0.55
        links.new(split.outputs['Blue'], fade.inputs[0])
        links.new(fade.outputs[0], shader.inputs['Alpha'])
        shader.inputs['Roughness'].default_value = 0.5
    else:
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.interpolation = 'CONSTANT'
        ramp.color_ramp.elements[0].color = (*DYES[0], 1)
        for index, dye in enumerate(DYES[1:], start=1):
            element = ramp.color_ramp.elements.new(index / len(DYES))
            element.color = (*dye, 1)
        ramp.color_ramp.elements[-1].position = (len(DYES) - 1) / len(DYES)
        links.new(split.outputs['Green'], ramp.inputs['Fac'])
        bleach = nodes.new('ShaderNodeMix')
        bleach.data_type = 'RGBA'
        bleach.inputs['B'].default_value = (0.10, 0.085, 0.065, 1)
        grime = nodes.new('ShaderNodeMath')
        grime.operation = 'MULTIPLY'
        grime.inputs[1].default_value = 0.6
        links.new(split.outputs['Blue'], grime.inputs[0])
        links.new(grime.outputs[0], bleach.inputs['Factor'])
        links.new(ramp.outputs['Color'], bleach.inputs['A'])
        links.new(bleach.outputs['Result'], shade.inputs['A'])
        shader.inputs['Roughness'].default_value = 0.95
        shader.inputs['Sheen Weight'].default_value = 0.4
    links.new(shade.outputs['Result'], shader.inputs['Base Color'])
    return material


def review_props(entry: dict, wood: bpy.types.Material) -> list:
    """Unexported context (beams, walls) so the turntable shows where it hangs."""
    kind = entry['type']
    props = []
    if kind in ('banner', 'tapestry'):
        span = entry['bounds_godot']['max'][0] - entry['bounds_godot']['min'][0]
        props.append(beam('Beam', span + 0.3, 0.25, 0.25, Vector((0, 0, 0.125))))
    elif kind == 'drape':
        size = entry['beam_proxy_godot']['size']
        span = entry['bounds_godot']['max'][0] - entry['bounds_godot']['min'][0]
        props.append(beam('Beam', span + 0.3, size[2], size[1]))
    elif kind == 'web_sheet':
        for name in ('a', 'b'):
            p0 = core.to_blender(entry['sockets_godot'][f'{name}_0'])
            p1 = core.to_blender(entry['sockets_godot'][f'{name}_1'])
            outward = 1 if name == 'a' else -1
            props.append(box(f'Beam_{name}', (p0 + p1) / 2 + Vector((0, outward * 0.11, 0.1)),
                             Vector(((p1 - p0).length + 0.4, 0.22, 0.24))))
    elif kind == 'web_corner':
        end_u = core.to_blender(entry['sockets_godot']['end_u'])
        end_v = core.to_blender(entry['sockets_godot']['end_v'])
        if entry['corner'] == 'ceiling':
            # Wall/ceiling arrises only: full walls would hide the web.
            props.append(box('ArrisU', Vector((end_u.x / 2, 0.015, 0.015)), Vector((end_u.x + 0.1, 0.03, 0.03))))
            props.append(box('ArrisV', Vector((-0.015, end_v.y / 2, 0.015)), Vector((0.03, -end_v.y + 0.1, 0.03))))
            props.append(box('Corner', Vector((-0.015, 0.015, -0.2)), Vector((0.03, 0.03, 0.45))))
        else:
            props.append(box('Beam', Vector((end_u.x / 2, 0, 0.1)), Vector((end_u.x + 0.5, 0.2, 0.2))))
            props.append(box('Post', Vector((-0.1, 0, end_v.z / 2)), Vector((0.2, 0.2, -end_v.z + 0.4))))
    elif kind == 'rope':
        for name in ('a', 'b'):
            props.append(box(f'Block_{name}', core.to_blender(entry['sockets_godot'][name]), Vector((0.08, 0.14, 0.14))))
    for prop in props:
        prop.data.materials.append(wood)
    return props


def render_turntables(report: dict) -> None:
    import numpy
    REVIEW.mkdir(parents=True, exist_ok=True)
    temp = REVIEW / '_frames'
    temp.mkdir(exist_ok=True)
    kinds = []
    for entry in report['assets']:
        if entry['type'] not in kinds:
            kinds.append(entry['type'])
    for kind in kinds:
        core.empty_scene()
        scene = bpy.context.scene
        scene.render.engine = 'CYCLES'
        scene.cycles.device = 'CPU'
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
        scene.render.resolution_x, scene.render.resolution_y = 960, 600
        scene.render.film_transparent = False
        scene.world = bpy.data.worlds.new('ReviewWorld')
        scene.world.use_nodes = True
        scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.011, 0.011, 1)
        material = review_material(kind)
        wood = bpy.data.materials.new('ReviewWood')
        wood.use_nodes = True
        wood.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.09, 0.06, 0.04, 1)
        marker = bpy.data.materials.new('ReviewSocket')
        marker.use_nodes = True
        marker.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (1.0, 0.1, 0.05, 1)
        marker.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = 4.0
        ink = bpy.data.materials.new('ReviewInk')
        ink.use_nodes = True
        ink.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (0.6, 0.6, 0.6, 1)
        ink.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = 1.0
        pivots = []
        cursor = 0.0
        top, bottom = -math.inf, math.inf
        for entry in (e for e in report['assets'] if e['type'] == kind):
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=str(core.ROOT / entry['file']))
            imported = [o for o in bpy.data.objects if o not in before]
            meshes = [o for o in imported if o.type == 'MESH']
            assert len(meshes) == 1 and meshes[0].data.uv_layers and meshes[0].data.color_attributes, entry['file']
            sockets = [o for o in imported if o.name.startswith('socket_')]
            assert len(sockets) == len(entry['sockets_godot']), (entry['file'], [o.name for o in sockets])
            mesh = meshes[0]
            mesh.data.materials.clear()
            mesh.data.materials.append(material)
            props = review_props(entry, wood)
            for socket in sockets:
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=socket.matrix_world.translation)
                bpy.context.active_object.data.materials.append(marker)
                props.append(bpy.context.active_object)
            group = imported + props
            low = core.to_blender(entry['bounds_godot']['min'])
            high = core.to_blender(entry['bounds_godot']['max'])
            lo = Vector((min(low.x, high.x), min(low.y, high.y), min(low.z, high.z)))
            hi = Vector((max(low.x, high.x), max(low.y, high.y), max(low.z, high.z)))
            radius = max(hi.x - lo.x, hi.y - lo.y) / 2 + 0.15
            centre = (lo + hi) / 2
            pivot = core.link(bpy.data.objects.new(f'Pivot_{entry["variant"]}', None))
            pivot.location = Vector((cursor + radius, 0, 0))
            for obj in group:
                if obj.parent is None:
                    obj.location -= Vector((centre.x, centre.y, 0))
                    obj.parent = pivot
            label = bpy.data.curves.new(f'Label_{entry["variant"]}', 'FONT')
            label.body = f'{kind}_{entry["variant"]}'
            label.size = 0.07
            label.align_x = 'CENTER'
            text = core.link(bpy.data.objects.new(label.name, label))
            text.location = Vector((cursor + radius, -radius - 0.1, lo.z - 0.12))
            text.rotation_euler = (math.radians(90), 0, 0)
            text.data.materials.append(ink)
            pivots.append(pivot)
            cursor += 2 * radius + 0.2
            top, bottom = max(top, hi.z), min(bottom, lo.z - 0.2)
        width = cursor - 0.2
        camera = core.link(bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')))
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = max(width, (top - bottom + 0.3) * 1.6) * 1.08
        middle = Vector((width / 2, 0, (top + bottom) / 2))
        # Webs live overhead: look up at them as a player would.
        tilt = math.radians(-35 if kind.startswith('web') else 12)
        camera.location = middle + Vector((0, -10 * math.cos(tilt), 10 * math.sin(tilt)))
        camera.rotation_euler = (math.radians(90) - tilt, 0, 0)
        scene.camera = camera
        for name, energy, colour, at in (('Key', 160, (1.0, 0.72, 0.45), (-2.0, -3.0, 2.5)),
                                         ('Fill', 40, (0.55, 0.65, 0.8), (3.0, -2.0, 0.5)),
                                         ('Rim', 90, (1.0, 0.85, 0.7), (1.0, 3.0, 2.0))):
            light = core.link(bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA')))
            light.data.energy, light.data.color, light.data.size = energy, colour, 2.0
            light.location = middle + Vector(at)
            light.rotation_euler = (middle - light.location).to_track_quat('-Z', 'Y').to_euler()
        if kind.startswith('web'):
            # A torch below, as webs are usually seen.
            light = core.link(bpy.data.objects.new('Under', bpy.data.lights.new('Under', 'AREA')))
            light.data.energy, light.data.color, light.data.size = 120, (1.0, 0.7, 0.45), 1.0
            light.location = middle + Vector((-0.5, -1.5, -2.0))
            light.rotation_euler = (middle - light.location).to_track_quat('-Z', 'Y').to_euler()
        frames = []
        for angle in (0, 90, 180, 270):
            for pivot in pivots:
                pivot.rotation_euler = (0, 0, math.radians(angle))
            scene.render.filepath = str(temp / f'{kind}_{angle}.png')
            bpy.ops.render.render(write_still=True)
            image = bpy.data.images.load(scene.render.filepath)
            pixels = numpy.empty(image.size[0] * image.size[1] * 4, dtype=numpy.float32)
            image.pixels.foreach_get(pixels)
            frames.append(pixels.reshape(image.size[1], image.size[0], 4))
        # Blender image rows run bottom-up: the top row of the sheet is the last block.
        sheet = numpy.concatenate([numpy.concatenate(frames[2:], axis=1), numpy.concatenate(frames[:2], axis=1)], axis=0)
        out = bpy.data.images.new(f'turntable_{kind}', sheet.shape[1], sheet.shape[0])
        out.pixels.foreach_set(sheet.ravel())
        out.filepath_raw = str(REVIEW / f'turntable_{kind}.png')
        out.file_format = 'PNG'
        out.save()
        print('HANGING_TURNTABLE', core.relative(REVIEW / f'turntable_{kind}.png'), flush=True)
    for leftover in temp.iterdir():
        leftover.unlink()
    temp.rmdir()


if __name__ == '__main__':
    main()
