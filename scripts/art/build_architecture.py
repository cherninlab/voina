"""Blender background: Red Descent architecture built stone by stone from the
real layout, then baked.

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_architecture.py -- \
        content/environments/procedural_bridge_v1/layout.json <out_dir> --rooms entry,antechamber \
        --passages entry [--export] [--render view.png]

Rule one: an opening exists only where a route really crosses a wall at that
height (segment intersection, not nearness), centred on the crossing and as
wide as the route measured along the wall plus a margin. Short corner
chamfers never carry an arch; a crossing near a corner widens onto the longer
wall instead. Every wall is built course by course from the stone library
(procgen.masonry), openings get jambs, arches and keystones through the full
thickness, and a mortar core fills behind.

Rule two: an enclosed route is one passage with one cross-section (its
profile): the doorways where it crosses room walls and the barrel vault of
the tunnel between rooms are the same arch, so nothing stands inside an
arch and no box tunnel runs through a wall. Where the rooms are too low for a
semicircle the vault goes segmental.

Exports rooms/<id>.glb, passages/<route>_<segment>_<n>.glb and index.json,
which tells the game which old boxes each stone build replaces.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
import numpy
from mathutils import Matrix, Vector

from procgen import bake, core, disturb, export, masonry, stonelib

ROCK = core.ROOT / 'content/environments/dungeon_pbr_v2/marble_rock_03'
THICKNESS = 0.9
MARGIN = 0.5           # open doorways: clear width beyond the route, along the wall
SPRING = 2.6           # open doorways
CLEAR = 0.4            # passages: clear width beyond the walking ribbon
PASSAGE_SPRING = 2.4   # above the walking surface; a segmental vault where the rooms are low
RING = 0.4
HEADROOM = 0.35        # stone between an arch ring and the ceiling
MISFITS = []           # doorways the room outline has no room for; export refuses them


def parse():
    values = core.args()
    options = {'rooms': None, 'passages': '', 'render': None, 'export': False}
    i = 2
    while i < len(values):
        if values[i] in ('--room', '--rooms', '--passages', '--render'):
            options[values[i][2:].rstrip('s') + 's' if values[i] != '--render' else 'render'] = values[i + 1]
            i += 2
        elif values[i] == '--export':
            options['export'] = True
            i += 1
        else:
            i += 1
    return Path(values[0]).resolve(), Path(values[1]).resolve(), options


def flat(godot) -> Vector:
    """Godot (x, z) plan point to Blender (x, y)."""
    return Vector((godot[0], -godot[1]))


def ccw(points: list) -> list:
    area = sum(a.x * b.y - b.x * a.y for a, b in zip(points, points[1:] + points[:1])) * 0.5
    return points if area > 0 else list(reversed(points))


def contains(points: list, at: Vector) -> bool:
    """Point in polygon (even-odd), plan coordinates."""
    result = False
    for a, b in zip(points, points[1:] + points[:1]):
        if (a.y > at.y) != (b.y > at.y) and at.x < a.x + (at.y - a.y) * (b.x - a.x) / (b.y - a.y):
            result = not result
    return result


def rooms_of(route: dict, rooms: list) -> list:
    """Rooms a route passes through at their floor."""
    return [room for room in rooms
            if any(abs(p[1] - room['floor']) < 0.6 and contains([flat(q) for q in room['points']], flat((p[0], p[2])))
                   for p in route['points'])]


def profile(route: dict, layout: dict) -> masonry.Opening:
    """The passage's cross-section, centred on x = 0: clear width, springing,
    rise. The lowest room it passes through decides how flat the vault is."""
    width = route['width'] + CLEAR
    low = min([room['height'] for room in rooms_of(route, layout['rooms'])], default=99.0)
    rise = max(0.8, min(width * 0.5, low - PASSAGE_SPRING - RING - HEADROOM))
    return masonry.Opening(-width * 0.5, width * 0.5, sill=0.0, spring=PASSAGE_SPRING, rise=rise)


def crossings(edge_a: Vector, edge_b: Vector, floor: float, routes: list) -> list:
    """Where routes cross the wall a->b near floor level: (distance along the
    wall, route, sine of the crossing angle)."""
    result = []
    along = edge_b - edge_a
    length = along.length
    for route in routes:
        points = route['points']
        for p, q in zip(points, points[1:]):
            a, b = flat((p[0], p[2])), flat((q[0], q[2]))
            d = b - a
            denom = along.x * d.y - along.y * d.x
            if abs(denom) < 1e-9:
                continue
            w = a - edge_a
            t = (w.x * d.y - w.y * d.x) / denom
            u = (w.x * along.y - w.y * along.x) / denom
            if not (0.0 <= t <= 1.0 and 0.0 <= u <= 1.0):
                continue
            height = p[1] + (q[1] - p[1]) * u
            if abs(height - floor) > 0.6:
                continue
            result.append((t * length, route, abs(denom) / (length * d.length), points.index(p), u))
    return result


def door_route(route: dict, segment: int, u: float, layout: dict) -> dict:
    """The route a doorway really serves: an enclosed route that leaves the
    room on its last segment and hands over to an open crossing (a bridge,
    a ledge) right outside is a door onto that crossing, sized by it."""
    points = route['points']
    if not route['enclosed'] or segment != len(points) - 2:
        return route
    end = points[-1]
    for other in layout['routes']:
        if other is not route and not other['enclosed'] and other['points'][0] == end:
            return other
    return route


def exposed(a: Vector, b: Vector, layout: dict) -> bool:
    """True when the outside of room wall a->b (walked clockwise, interior
    on the right) looks into the open shaft rather than into rock."""
    outline = [flat(p) for p in layout['outline']]
    along = (b - a).normalized()
    outward = Vector((-along.y, along.x))
    hits = 0
    for t in (0.2, 0.5, 0.8):
        probe = a.lerp(b, t) + outward * 2.0
        hits += contains(outline, probe) and not any(contains([flat(q) for q in r['points']], probe) for r in layout['rooms'])
    return hits >= 2


def room_walls(room: dict, layout: dict) -> list:
    """(start, end, openings) per wall, face towards the room interior."""
    pts = [flat(p) for p in room['points']]
    pts = list(reversed(ccw(pts)))  # walk clockwise: the interior is on the right, where faces point
    floor, height = room['floor'], room['height']
    walls = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        length = (b - a).length
        openings = []
        for at, route, sine, segment, u in crossings(a, b, floor, layout['routes']):
            jamb = 0.5
            route = door_route(route, segment, u, layout)
            passage = profile(route, layout) if route['enclosed'] else None
            width = (passage.half * 2.0 if passage else route['width'] + MARGIN * sine) / max(sine, 0.35)
            if length < width + 2 * jamb + 0.4:
                # A corner chamfer: no arch of its own; the neighbour widens instead.
                continue
            x0 = max(jamb + 0.2, at - width * 0.5)
            x1 = min(length - jamb - 0.2, at + width * 0.5)
            if x1 - x0 < width - 0.02:
                # The route crosses too near a corner for its doorway: the room
                # outline must change (RedDescentLayout.rooms), not the door.
                MISFITS.append(f'{room["id"]} wall {len(walls)}: {route["id"]} needs {width:.2f} m, fits {x1 - x0:.2f} m')
            if passage:
                # The passage's own arch: same springing and crown as its vault.
                openings.append(masonry.Opening(x0, x1, sill=0.0, spring=passage.spring, rise=passage.crown - passage.spring))
                continue
            radius = (x1 - x0) * 0.5
            spring = min(SPRING, height - radius - 0.36 - 0.5)
            if spring < 1.9:
                continue
            openings.append(masonry.Opening(x0, x1, sill=0.0, spring=spring))
        walls.append((a, b, openings))
    return walls


def clip_segment(p: Vector, q: Vector, polygon: list):
    """Cyrus-Beck: (t_in, t_out, edge_in, edge_out) of segment p->q inside a
    convex counter-clockwise polygon, or None."""
    t_in, t_out, e_in, e_out = 0.0, 1.0, None, None
    d = q - p
    for k, (a, b) in enumerate(zip(polygon, polygon[1:] + polygon[:1])):
        n = Vector(((b - a).y, -(b - a).x)).normalized()  # outward for CCW
        num, den = (a - p).dot(n), d.dot(n)
        if abs(den) < 1e-12:
            if num < 0:
                return None
            continue
        t = num / den
        if den > 0 and t < t_out:
            t_out, e_out = t, k
        elif den < 0 and t > t_in:
            t_in, e_in = t, k
    return (t_in, t_out, e_in, e_out) if t_in < t_out else None


def outset(points: list, distance: float) -> list:
    """Convex CCW polygon grown outward by `distance` (edges offset, corners mitred)."""
    lines = []
    for a, b in zip(points, points[1:] + points[:1]):
        n = Vector(((b - a).y, -(b - a).x)).normalized()
        lines.append((a + n * distance, (b - a).normalized()))
    result = []
    for (p1, d1), (p2, d2) in zip(lines[-1:] + lines[:-1], lines):
        denom = d1.x * d2.y - d1.y * d2.x
        t = ((p2 - p1).x * d2.y - (p2 - p1).y * d2.x) / denom
        result.append(p1 + d1 * t)
    return result


def passages(route: dict, layout: dict) -> list:
    """Stretches of an enclosed route between two room walls, flat enough for
    a level vault: (segment index, t0, t1, plane at each end)."""
    result = []
    points = route['points']
    for index, (p, q) in enumerate(zip(points, points[1:])):
        a, b = flat((p[0], p[2])), flat((q[0], q[2]))
        inside = []
        for room in layout['rooms']:
            if min(p[1], q[1]) > room['floor'] + 0.6 or max(p[1], q[1]) < room['floor'] - 0.6:
                continue
            outline = ccw([flat(v) for v in room['points']])
            grown = outset(outline, THICKNESS * 0.5)
            hit = clip_segment(a, b, grown)
            if hit:
                inside.append((hit, grown))
        inside.sort(key=lambda h: h[0][0])
        for (first, grown_a), (second, grown_b) in zip(inside, inside[1:]):
            t0, t1 = first[1], second[0]
            if t1 - t0 < 0.5 / (b - a).length or first[3] is None or second[2] is None:
                continue
            if abs((q[1] - p[1]) * (t1 - t0)) > 0.3:
                print('PASSAGE_SKIPPED_SLOPED', route['id'], index, flush=True)
                continue
            planes = []
            for grown, k in ((grown_a, first[3]), (grown_b, second[2])):
                e0, e1 = grown[k], grown[(k + 1) % len(grown)]
                outward = Vector(((e1 - e0).y, -(e1 - e0).x)).normalized()
                planes.append((e0, outward))
            result.append((index, t0, t1, planes))
    return result


def build_passage(route: dict, layout: dict, index: int, t0: float, t1: float, planes: list, rng, lib, name: str) -> dict:
    """Side walls to the springing, a barrel vault of staggered voussoir rings
    and a mortar mass around it with the profile as its hole, all clipped to
    the outer faces of the room walls at both ends."""
    p, q = route['points'][index], route['points'][index + 1]
    a, b = flat((p[0], p[2])), flat((q[0], q[2]))
    run = (b - a).length
    d = Vector(((b - a).x, (b - a).y, 0.0)).normalized()
    up = Vector((0.0, 0.0, 1.0))
    side = d.cross(up)
    floor = p[1] + (q[1] - p[1]) * (t0 + t1) * 0.5
    o = profile(route, layout)
    # Overshoot into oblique room walls; the clip trims it back to their faces.
    reach = o.half + THICKNESS + RING
    ext = []
    for point, outward in planes:
        cosine = max(abs(Vector((d.x, d.y)).dot(outward)), 0.2)
        ext.append(min(reach * math.sqrt(1.0 - cosine * cosine) / cosine + 0.15, 2.5))
    s0, s1 = t0 * run - ext[0], t1 * run + ext[1]
    length = s1 - s0

    def at(s: float) -> Vector:
        return Vector((a.x, a.y, floor)) + d * s

    groups = {0: [], 1: [], 2: [], 3: []}
    rows = masonry.Wall(1.0, o.spring).courses(rng, {0.0, o.spring})
    for number, (origin, along) in enumerate(((at(s0) - side * o.half, d), (at(s1) + side * o.half, -d))):
        wall = masonry.Wall(length, o.spring, THICKNESS)
        pieces = wall.build(lib, rng, name=f'{name}_side{number}', rows=rows, core=False)
        masonry.place(pieces, origin, along, up)
        groups[number] = pieces
    frame = Matrix((side, d, up)).transposed().to_4x4()
    s, ring_number = s0, 0
    while length - (s - s0) > 1e-6:
        width = rng.uniform(0.34, 0.48)
        if s1 - (s + width) < 0.25:
            width = s1 - s
        joint = rng.uniform(0.008, 0.02)
        # Vault stones are seen from below at a distance: a lighter budget than door arches.
        for piece in masonry.ring(rng, o, RING, width - joint, f'{name}_ring{ring_number}', stagger=ring_number % 2 == 1,
                                  triangles=220):
            piece.data.transform(piece.matrix_world)
            piece.matrix_world = Matrix.Translation(at(s + width * 0.5) + up * o.cy) @ frame
            piece['tone'] = rng.uniform(0.8, 1.15)
            piece['frame'] = [*d, *up, *side]
            groups[2].append(piece)
        s += width
        ring_number += 1
    recess = 0.034
    mass = masonry.Wall(o.half * 2.0 + 2.0 * THICKNESS, o.crown + RING + 0.3, length + recess,
                        [masonry.Opening(THICKNESS - recess, THICKNESS + o.half * 2.0 + recess, 0.0, o.spring,
                                         o.crown - o.spring + recess)]).core(f'{name}_mass')
    masonry.place([mass], at(s0) - d * recess - side * (o.half + THICKNESS), side, up)
    groups[3].append(mass)
    for number in groups:
        kept = []
        for obj in groups[number]:
            if all(masonry.clip(obj, Vector((point.x, point.y, 0.0)), -Vector((outward.x, outward.y, 0.0)))
                   for point, outward in planes):
                kept.append(obj)
            else:
                bpy.data.objects.remove(obj, do_unlink=True)
        groups[number] = kept
    print('PASSAGE', name, f'{t1 * run - t0 * run:.2f} m', f'clear {o.half * 2:.2f} m', f'crown {o.crown:.2f} m',
          'segmental' if o.crown - o.spring < o.half - 1e-3 else 'semicircular', flush=True)
    return groups


def map_stone(obj, rng) -> None:
    """Texture coordinates in metres for a placed stone, in the convention of
    dungeon_surface.gdshader's world projection (u along t, v down b = n x t,
    t = up x n on upright faces, the wall's run on beds and soffits), but per
    face of the stone in its wall's frame instead of per vertex: projecting
    from bumpy vertex normals is what smeared the rock scan into swirls.
    UVMap gives each stone its own piece of the scan (random offset and a
    slight turn); UVWall stays continuous along the wall for the weathering
    masks. Blender v is stored unflipped: glTF's 1 - v makes it run down."""
    frame = obj.get('frame')
    if frame is None:
        return
    along, up, out = Vector(frame[0:3]), Vector(frame[3:6]), Vector(frame[6:9])
    mesh = obj.data
    own = mesh.uv_layers.get('UVMap') or mesh.uv_layers.new(name='UVMap')
    wall = mesh.uv_layers.get('UVWall') or mesh.uv_layers.new(name='UVWall')
    shift = Vector((rng.uniform(0.0, 40.0), rng.uniform(0.0, 40.0)))
    turn = rng.uniform(-0.45, 0.45)
    centre = sum((v.co for v in mesh.vertices), Vector()) / max(len(mesh.vertices), 1)
    for polygon in mesh.polygons:
        n = polygon.normal
        local = Vector((n.dot(along), n.dot(up), n.dot(out)))
        if abs(local.y) > 0.7:
            t = along
            normal = up if local.y > 0 else -up
        else:
            normal = (out if local.z > 0 else -out) if abs(local.z) >= abs(local.x) else (along if local.x > 0 else -along)
            t = up.cross(normal).normalized()
        b = normal.cross(t)
        t_own = t * math.cos(turn) + b * math.sin(turn)
        b_own = normal.cross(t_own)
        for index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[index].vertex_index].co
            wall.data[index].uv = (co.dot(t), co.dot(b))
            own.data[index].uv = ((co - centre).dot(t_own) + shift.x, (co - centre).dot(b_own) + shift.y)
    mesh.uv_layers.active = own


def merge(label: str, groups: dict, rng) -> list:
    """Join each group's stones and mortar into Stone_<label>_<n> and
    Mortar_<label>_<n>, with per-stone tone and fresh faces in the colour."""
    merged = []
    for number, pieces in sorted(groups.items()):
        stones_, cores = [], []
        for obj in pieces:
            obj.data = obj.data.copy()
            colour = obj.data.color_attributes.get('Color') or obj.data.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
            tone = float(obj.get('tone', 1.0))
            for item in colour.data:
                # Mortar reads dark: grimed lime deep in the joints, as in the paintovers.
                item.color = (1.0, max(tone, 0.0) / 1.25 if tone > 0 else 0.5, item.color[2] if tone > 0 else 0.0, 1.0)
            obj.data.color_attributes.active_color = colour
            (cores if tone < 0 else stones_).append(obj)
        for kind, objects in (('Stone', stones_), ('Mortar', cores)):
            if not objects:
                continue
            core.select_only(objects)
            bpy.ops.object.make_single_user(object=True, obdata=True)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            if kind == 'Stone':
                for obj in objects:
                    map_stone(obj, rng)
            bpy.ops.object.join()
            joined = bpy.context.view_layer.objects.active
            joined.name = f'{kind}_{label}_{number}'
            merged.append(joined)
    return merged


def bake_all(elements: list, out: Path, samples: int = 24) -> list:
    """AO for everything built together (so passages darken where they meet
    rooms), times each stone's tone, into vertex colour (the dungeon shader
    multiplies albedo by COLOR); collision from the mortar cores, whose holes
    are the true openings; one GLB per room or passage."""
    rng = core.rng(177, 'mapping')
    merged = [(kind, label, merge(label, groups, rng)) for kind, label, groups in elements]
    ao = bake.ao_to_color([obj for _, _, objects in merged for obj in objects], samples=samples, distance=0.5)
    written = []
    for kind, label, objects in merged:
        for obj in objects:
            colour = obj.data.color_attributes['Color']
            for item in colour.data:
                r, g, b, _ = item.color
                shade = r * g * 1.25 * (1.08 if b > 0.5 else 1.0)
                item.color = (shade, shade, shade, 1.0)
        collisions = [export.collision_copy(obj, 'colonly') for obj in objects if obj.name.startswith('Mortar')]
        for obj in collisions:
            obj.name = obj.name.replace('Mortar', 'Collision')
        path = export.glb(objects + collisions, out / kind / f'{label}.glb')
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
        core.write_report(out / kind / f'{label}.json', {'id': label, 'triangles': tris,
                                                         'ao': {o.name: ao[o.name] for o in objects if o.name in ao}}, [path])
        print('ARCHITECTURE_BAKED', kind, label, tris, 'tris', flush=True)
        written.append(path)
    return written


def build_room(room: dict, layout: dict, rng, lib, quoins, groups: dict = None) -> list:
    parts = []
    walls = room_walls(room, layout)
    # One set of courses for the whole room, so joints run on round corners.
    keys = {0.0, room['height']}
    for _, _, openings in walls:
        keys.update(o.spring for o in openings)
    rows = masonry.Wall(1.0, room['height']).courses(rng, keys)
    for number, (a, b, openings) in enumerate(walls):
        length = (b - a).length
        outside = exposed(a, b, layout)
        recess = masonry.Wall(1.0, 1.0).recess
        # A wall seen from the shaft is faced on both sides; its core stops
        # short of the outer face so the outer stones show.
        wall = masonry.Wall(length, room['height'], THICKNESS - (recess if outside else 0.0), openings)
        pieces = wall.build(lib, rng, quoins=quoins, name=f'{room["id"]}_{number}', rows=rows, interlock=0.28)
        along = Vector((b.x - a.x, b.y - a.y, 0.0))
        # The game's room wall is 0.9 m centred on the outline: put the stone
        # face on its inner face, where the collision already is.
        inward = along.normalized().cross(Vector((0, 0, 1)))
        masonry.place(pieces, Vector((a.x, a.y, room['floor'])) + inward * THICKNESS * 0.5, along, Vector((0, 0, 1)))
        if outside:
            mirrored = [masonry.Opening(length - o.x1, length - o.x0, o.sill, o.spring, o.window, o.rise) for o in openings]
            outer = masonry.Wall(length, room['height'], THICKNESS * 0.5, mirrored)
            back = outer.build(lib, rng, quoins=quoins, name=f'{room["id"]}_{number}_outer', rows=rows, core=False, dress=False)
            masonry.place(back, Vector((b.x, b.y, room['floor'])) - inward * THICKNESS * 0.5, -along, Vector((0, 0, 1)))
            pieces += back
        if groups is not None:
            groups[number] = pieces
        parts += pieces
        print('WALL', room['id'], number, f'{length:.2f} m', 'openings', [(round(o.x0, 2), round(o.x1, 2)) for o in openings],
              'faced both sides' if outside else '', flush=True)
    return parts


def stone_material() -> bpy.types.Material:
    """Review shading: the scanned CC0 rock box-projected, toned per stone;
    mortar cores lime grey."""
    material = bpy.data.materials.new('ReviewStone')
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['Principled BSDF']
    coords = nodes.new('ShaderNodeTexCoord')
    mapping = nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = (1.2, 1.2, 1.2)
    links.new(coords.outputs['Object'], mapping.inputs['Vector'])
    images = {}
    for key, space in (('albedo', 'sRGB'), ('normal_gl', 'Non-Color'), ('roughness', 'Non-Color')):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(str(ROCK / f'{key}.png'), check_existing=True)
        node.image.colorspace_settings.name = space
        node.projection = 'BOX'
        node.projection_blend = 0.3
        links.new(mapping.outputs['Vector'], node.inputs['Vector'])
        images[key] = node
    grade = nodes.new('ShaderNodeHueSaturation')
    grade.inputs['Saturation'].default_value = 0.35
    grade.inputs['Value'].default_value = 0.55
    links.new(images['albedo'].outputs['Color'], grade.inputs['Color'])
    tone = nodes.new('ShaderNodeAttribute')
    tone.attribute_type = 'OBJECT'
    tone.attribute_name = 'tone'
    clamp = nodes.new('ShaderNodeMath')
    clamp.operation = 'MAXIMUM'
    clamp.inputs[1].default_value = 0.45
    links.new(tone.outputs['Fac'], clamp.inputs[0])
    scale = nodes.new('ShaderNodeVectorMath')
    scale.operation = 'SCALE'
    links.new(grade.outputs['Color'], scale.inputs[0])
    links.new(clamp.outputs['Value'], scale.inputs['Scale'])
    links.new(scale.outputs['Vector'], shader.inputs['Base Color'])
    bump = nodes.new('ShaderNodeNormalMap')
    links.new(images['normal_gl'].outputs['Color'], bump.inputs['Color'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    links.new(images['roughness'].outputs['Color'], shader.inputs['Roughness'])
    return material


def render_room(room: dict, path: Path) -> None:
    pts = [flat(p) for p in room['points']]
    centre = sum(pts, Vector((0.0, 0.0))) / len(pts)
    floor = room['floor']
    material = stone_material()
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.data.materials.clear()
            obj.data.materials.append(material)
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(centre.x, centre.y, floor))
    bpy.context.active_object.data.materials.append(material)
    scene = bpy.context.scene
    scene.world = scene.world or bpy.data.worlds.new('Dark')
    scene.world.color = (0.003, 0.003, 0.004)
    for k, p in enumerate(pts[::2]):
        light = core.link(bpy.data.objects.new(f'Torch{k}', bpy.data.lights.new(f'Torch{k}', 'POINT')))
        light.data.energy = 450.0
        light.data.color = (1.0, 0.62, 0.32)
        light.data.shadow_soft_size = 0.15
        spot = centre.lerp(p, 0.75)
        light.location = Vector((spot.x, spot.y, floor + 2.2))
    views = []
    for k in range(2):
        e = centre.lerp(pts[k * len(pts) // 2], 0.35)
        t = centre.lerp(pts[(k * len(pts) // 2 + len(pts) // 2) % len(pts)], 0.9)
        eye, target = Vector((e.x, e.y, floor + 1.7)), Vector((t.x, t.y, floor + 2.0))
        views.append(disturb.render(eye, target, size=(960, 600), samples=48, lens=22))
    disturb.write_png(path, numpy.concatenate(views, axis=1))


def main():
    layout_path, out, options = parse()
    layout = json.loads(layout_path.read_text())
    core.empty_scene()
    rng = core.rng(177, 'architecture')
    # Wall stones: chunky silhouettes, fine surface from the game's normal maps;
    # backs inside the core are cut. Quoins keep their sides for the reveals.
    lib = stonelib.Library(rng, 'squared_rubble', count=160, triangles=200, hidden_back=0.06)
    quoins = stonelib.Library(rng, 'ashlar', count=40, triangles=320, aspects=(1.0, 2.6), name='quoin')
    wanted = options['rooms'].split(',') if options['rooms'] else None
    rooms = [r for r in layout['rooms'] if wanted is None or r['id'] in wanted]
    elements, parts = [], 0
    for room in rooms:
        groups = {}
        parts += len(build_room(room, layout, rng, lib, quoins, groups))
        elements.append(('rooms', room['id'], groups))
    index_path = out / 'index.json'
    index = json.loads(index_path.read_text()) if index_path.exists() else {'rooms': [], 'passages': []}
    built = []
    for route in layout['routes']:
        if route['id'] not in options['passages'].split(',') or not route['enclosed']:
            continue
        for number, (segment, t0, t1, planes) in enumerate(passages(route, layout)):
            label = f'{route["id"]}_{segment}_{number}'
            groups = build_passage(route, layout, segment, t0, t1, planes, rng, lib, label)
            parts += sum(len(g) for g in groups.values())
            elements.append(('passages', label, groups))
            built.append({'route': route['id'], 'segment': segment, 't0': round(t0, 4), 't1': round(t1, 4),
                          'file': f'passages/{label}.glb', 'layout_hash': route.get('layout_hash')})
    print('ARCHITECTURE_PARTS', parts, flush=True)
    for misfit in MISFITS:
        print('DOOR_DOES_NOT_FIT', misfit, flush=True)
    if options['export'] and MISFITS:
        raise SystemExit('Doorways do not fit their walls; fix the room outlines first')
    if options['export']:
        bake_all(elements, out)
        index['rooms'] = sorted(set(index['rooms']) | {r['id'] for r in rooms})
        done = {(p['route'], p['segment']) for p in built}
        index.pop('layout_hash', None)
        index['passages'] = sorted([p for p in index['passages'] if (p['route'], p['segment']) not in done] + built,
                                   key=lambda p: (p['route'], p['segment'], p['t0']))
        index_path.write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
    if options['render']:
        render_room(rooms[0], Path(options['render']))
        print('ARCHITECTURE_RENDERED', options['render'], flush=True)


if __name__ == '__main__':
    main()
