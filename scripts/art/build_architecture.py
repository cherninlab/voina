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

from procgen import bake, core, disturb, export, masonry, passage, stonekinds, stonelib, vault

ROCK = core.ROOT / 'content/environments/dungeon_pbr_v2/marble_rock_03'
THICKNESS = 0.9
MARGIN = 0.5           # open doorways: clear width beyond the route, along the wall
SPRING = 2.6           # open doorways
CLEAR = 0.4            # passages: clear width beyond the walking ribbon
PASSAGE_SPRING = 2.4   # above the walking surface; a segmental vault where the rooms are low
RING = 0.4
HEADROOM = 0.35        # stone between an arch ring and the ceiling
MISFITS = []           # doorways the room outline has no room for; export refuses them
UPPER = None           # (library, from height, stone lengths) for courses out of reach; set in main
KINDS = {}             # stonekinds libraries by role (T-182), set in main
# Masonry by room: rough galleted rubble in the crypts and cells, thin slab
# lacing courses through the great halls, squared rubble elsewhere.
ROUGH = {'cells', 'bones', 'window', 'ossuary'}
LACED = {'nave', 'chapel', 'choir', 'restraint', 'bell'}
STAIRS = True          # build masonry under raised walks
# Rooms rendered over their stone, the render peeling to show it (the nave's
# red, the paintovers' pale lime): the game picks the coat by room.
PLASTER = {'nave': 'red', 'chapel': 'lime', 'restraint': 'lime'}


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
        elif values[i] in ('--check', '--props', '--no-index', '--index-only'):
            options[values[i][2:]] = True
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


def clearances(route: dict, rooms: list) -> list:
    """Headroom under the ceiling of every room the route passes through,
    at the level it passes (a gallery high in a hall has little)."""
    result = []
    for room in rooms:
        outline = [flat(q) for q in room['points']]
        for p in route['points']:
            if room['floor'] - 0.6 <= p[1] <= room['floor'] + max(room['height'] - 3.5, 0.6) and contains(outline, flat((p[0], p[2]))):
                result.append(room['floor'] + room['height'] - p[1])
    return result


def profile(route: dict, layout: dict) -> masonry.Opening:
    """The passage's cross-section, centred on x = 0: clear width, springing,
    rise. The tightest ceiling it passes under decides how flat the vault is."""
    width = route['width'] + CLEAR
    low = min(clearances(route, layout['rooms']), default=99.0)
    rise = max(0.8, min(width * 0.5, low - PASSAGE_SPRING - RING - HEADROOM))
    return masonry.Opening(-width * 0.5, width * 0.5, sill=0.0, spring=PASSAGE_SPRING, rise=rise)


def crossings(edge_a: Vector, edge_b: Vector, floor: float, routes: list, height: float = 0.0) -> list:
    """Where routes cross the wall a->b between its floor and `height`
    above it (minus headroom): (distance along the wall, route, sine of the
    crossing angle, segment, parameter, sill above the floor)."""
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
            level = p[1] + (q[1] - p[1]) * u
            if level < floor - 0.6 or level > floor + max(height - 3.5, 0.6):
                continue
            # A ramp keeps falling through the wall: the sill sits under its lowest point there.
            sill = level - floor - abs(q[1] - p[1]) / d.length * 0.6 - 0.05
            sill = sill if sill > 0.6 else 0.0
            result.append((t * length, route, abs(denom) / (length * d.length), points.index(p), u, sill))
    return result


def door_route(route: dict, segment: int, u: float, layout: dict) -> dict:
    """The route a doorway really serves: an enclosed route that leaves the
    room on its last segment and hands over to an open crossing (a bridge,
    a ledge) right outside is a door onto that crossing, sized by it."""
    points = route['points']
    if not route['enclosed']:
        return route
    for other in layout['routes']:
        if other is route or other['enclosed']:
            continue
        if segment == len(points) - 2 and other['points'][0] == points[-1]:
            return other
        if segment == 0 and other['points'][-1] == points[0]:
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
        found = []
        for crossing in sorted(crossings(a, b, floor, layout['routes'], height), key=lambda c: -c[2]):
            # A route that turns on the wall line crosses it twice at one
            # point: keep the squarest crossing.
            if all(abs(crossing[0] - kept[0]) > 0.5 or abs(crossing[5] - kept[5]) > 2.0 for kept in found):
                found.append(crossing)
        for at, route, sine, segment, u, sill in sorted(found, key=lambda c: c[0]):
            jamb = 0.5
            route = door_route(route, segment, u, layout)
            passage = profile(route, layout) if route['enclosed'] else None
            width = (passage.half * 2.0 if passage else route['width'] + MARGIN * sine) / max(sine, 0.35)
            if length < width + 2 * jamb + 0.4:
                MISFITS.append(f'{room["id"]} wall {len(walls)} ({length:.2f} m): {route["id"]} crosses a wall too short for its {width:.2f} m doorway')
                continue
            x0 = max(jamb + 0.2, at - width * 0.5)
            x1 = min(length - jamb - 0.2, at + width * 0.5)
            if x1 - x0 < width - 0.02:
                # The route crosses too near a corner for its doorway: the room
                # outline must change (RedDescentLayout.rooms), not the door.
                MISFITS.append(f'{room["id"]} wall {len(walls)}: {route["id"]} needs {width:.2f} m, fits {x1 - x0:.2f} m')
            if passage:
                # The passage's own arch: same springing and crown as its vault.
                openings.append(masonry.Opening(x0, x1, sill=sill, spring=sill + passage.spring, rise=passage.crown - passage.spring))
                continue
            radius = (x1 - x0) * 0.5
            spring = min(SPRING, height - sill - radius - 0.36 - 0.5)
            if spring < 1.9:
                MISFITS.append(f'{room["id"]} wall {len(walls)}: no headroom for {route["id"]}\'s doorway')
                continue
            openings.append(masonry.Opening(x0, x1, sill=sill, spring=sill + spring))
        openings.sort(key=lambda o: o.x0)
        for first, second in zip(openings, openings[1:]):
            if second.x0 - first.x1 < 1.0 and second.sill < first.crown + RING + 0.5 and first.sill < second.crown + RING + 0.5:
                MISFITS.append(f'{room["id"]} wall {len(walls)}: openings {first.x0:.2f}-{first.x1:.2f} and '
                               f'{second.x0:.2f}-{second.x1:.2f} leave no pier between them')
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


def node_key(point) -> tuple:
    return tuple(round(c, 2) for c in point)


def blender_point(godot) -> Vector:
    return Vector((godot[0], -godot[2], godot[1]))


def stretches(route: dict, layout: dict) -> list:
    """Every part of an enclosed route outside the rooms: (segment, t0, t1,
    start, end); an end is ('room', point, outward) at a room wall's outer
    face or ('node', key) at a route vertex."""
    result = []
    points = route['points']
    for index, (p, q) in enumerate(zip(points, points[1:])):
        a, b = flat((p[0], p[2])), flat((q[0], q[2]))
        if (b - a).length < 1e-6:
            continue
        cuts = []
        for room in layout['rooms']:
            grown = outset(ccw([flat(v) for v in room['points']]), THICKNESS * 0.5)
            hit = clip_segment(a, b, grown)
            if not hit:
                continue
            heights = [p[1] + (q[1] - p[1]) * t for t in hit[:2]]
            if min(heights) > room['floor'] + max(room['height'] - 3.5, 0.6) or max(heights) < room['floor'] - 0.6:
                continue
            cuts.append((*hit, grown))
        cuts.sort(key=lambda c: c[0])

        def wall(grown, k):
            e0, e1 = grown[k], grown[(k + 1) % len(grown)]
            return ('room', e0, Vector(((e1 - e0).y, -(e1 - e0).x)).normalized())

        t, start = 0.0, ('node', node_key(p))
        for t_in, t_out, e_in, e_out, grown in cuts:
            if t_in > t + 1e-6 and e_in is not None:
                result.append((index, t, t_in, start, wall(grown, e_in)))
            start = wall(grown, e_out) if e_out is not None else ('node', node_key(q))
            t = max(t, t_out)
        if t < 1.0 - 1e-6:
            result.append((index, t, 1.0, start, ('node', node_key(q))))
    return [s for s in result if (s[2] - s[1]) * (flat((route['points'][s[0] + 1][0], route['points'][s[0] + 1][2])) -
                                                     flat((route['points'][s[0]][0], route['points'][s[0]][2]))).length > 0.3]


def network(layout: dict) -> tuple:
    """All enclosed routes as one network: stretches per route, and nodes
    (route vertices outside rooms) with what arrives at each, classified as
    a bay (bend or junction), a mitre (a slight bend), a portal (onto an open
    crossing) or a dead end."""
    runs, nodes = {}, {}
    for route in layout['routes']:
        if not route['enclosed']:
            continue
        runs[route['id']] = stretches(route, layout)
        points = route['points']
        for number, (segment, t0, t1, start, end) in enumerate(runs[route['id']]):
            a, b = blender_point(points[segment]), blender_point(points[segment + 1])
            away = Vector((b.x - a.x, b.y - a.y, 0.0)).normalized()
            for kind_end, direction, godot in ((start, away, points[segment]), (end, -away, points[segment + 1])):
                if kind_end[0] == 'node':
                    node = nodes.setdefault(kind_end[1], {'at': blender_point(godot), 'godot': godot, 'arrivals': [], 'open': []})
                    node['arrivals'].append({'route': route, 'run': number, 'away': direction, 'profile': profile(route, layout)})
    for route in layout['routes']:
        if route['enclosed']:
            continue
        for godot in (route['points'][0], route['points'][-1]):
            if node_key(godot) in nodes:
                nodes[node_key(godot)]['open'].append(route['id'])
    for key, node in nodes.items():
        arrivals = node['arrivals']
        node['profile'] = max((a['profile'] for a in arrivals), key=lambda o: o.half)
        if len(arrivals) == 1 and node['open']:
            # A room's own doorway opens straight onto the crossing: no stub of
            # tunnel and second portal squeezed between them.
            arrival = arrivals[0]
            segment, t0, t1, start, end = runs[arrival['route']['id']][arrival['run']]
            points = arrival['route']['points']
            stub = (t1 - t0) * (blender_point(points[segment + 1]) - blender_point(points[segment])).length
            if stub < 2.0 and 'room' in (start[0], end[0]):
                runs[arrival['route']['id']][arrival['run']] = None
                node['kind'] = 'door'
                continue
        # A bend or junction right outside a room's wall is that room's doorway:
        # a bay there would push its masonry into the room. The stub to the wall
        # goes, and the other passages run on to the room wall's outer face.
        stub = None
        for arrival in arrivals:
            stretch = runs[arrival['route']['id']][arrival['run']]
            if stretch is None:
                continue
            segment, t0, t1, start, end = stretch
            points = arrival['route']['points']
            length = (t1 - t0) * (blender_point(points[segment + 1]) - blender_point(points[segment])).length
            wall = start if start[0] == 'room' else end if end[0] == 'room' else None
            if wall and length < node['profile'].half + passage.THICKNESS and len(arrivals) > 1:
                stub = (arrival, wall)
        if stub:
            runs[stub[0]['route']['id']][stub[0]['run']] = None
            node['kind'], node['room_wall'] = 'door', stub[1]
            continue
        if len(arrivals) == 1:
            node['kind'] = 'portal' if node['open'] else 'dead'
        elif len(arrivals) == 2 and math.degrees(math.acos(max(-1.0, min(1.0, -arrivals[0]['away'].dot(arrivals[1]['away']))))) < 25.0:
            node['kind'] = 'mitre'
        else:
            node['kind'] = 'bay'
            x = arrivals[0]['away']
            y = Vector((0.0, 0.0, 1.0)).cross(x)
            directions = [x, y, -x, -y]
            sides = {}
            for arrival in arrivals:
                k = max(range(4), key=lambda i: directions[i].dot(arrival['away']))
                if k in sides:
                    MISFITS.append(f'bay at {node["godot"]}: two passages arrive through one side')
                sides[k] = arrival['profile']
                arrival['side'] = directions[k]
            node['axis'], node['sides'] = x, sides
        if node['kind'] == 'dead':
            MISFITS.append(f'passage {arrivals[0]["route"]["id"]} ends at {node["godot"]} without a room, junction or open crossing')
    return runs, nodes


def run_planes(route: dict, number: int, stretch: tuple, nodes: dict) -> tuple:
    """Clip planes and end extensions for one stretch, from what it meets."""
    segment, t0, t1, start, end = stretch
    points = route['points']
    a, b = blender_point(points[segment]), blender_point(points[segment + 1])
    d = Vector((b.x - a.x, b.y - a.y, 0.0)).normalized()
    planes, ext = [], [0.0, 0.0]
    for slot, (meets, away) in enumerate(((start, d), (end, -d))):
        if meets[0] == 'room':
            point, outward = meets[1], meets[2]
            cosine = max(abs(Vector((d.x, d.y)).dot(outward)), 0.2)
            ext[slot] = min(4.5 * math.sqrt(1.0 - cosine * cosine) / cosine + 0.15, 2.5)
            planes.append((Vector((point.x, point.y, 0.0)), -Vector((outward.x, outward.y, 0.0))))
            continue
        node = nodes[meets[1]]
        if node['kind'] == 'mitre':
            other = next(arrival['away'] for arrival in node['arrivals'] if not (arrival['route'] is route and arrival['run'] == number))
            deviation = math.acos(max(-1.0, min(1.0, -away.dot(other))))
            ext[slot] = 4.5 * math.tan(deviation * 0.5) + 0.15
            planes.append((node['at'], -(away - other).normalized()))
        elif node['kind'] == 'bay':
            arrival = next(arrival for arrival in node['arrivals'] if arrival['route'] is route and arrival['run'] == number and
                           arrival['away'].dot(away) > 0.99)
            planes.append((node['at'] + arrival['side'] * node['profile'].half, -arrival['side']))
        elif node['kind'] == 'portal':
            planes.append((node['at'] + away * passage.THICKNESS, -away))
        elif node['kind'] == 'door' and 'room_wall' in node:
            point, outward = node['room_wall'][1], node['room_wall'][2]
            cosine = max(abs(Vector((d.x, d.y)).dot(outward)), 0.2)
            ext[slot] = min(4.5 * math.sqrt(1.0 - cosine * cosine) / cosine + 0.15, 2.5) + (node['at'] - Vector((point.x, point.y, node['at'].z))).length
            planes.append((Vector((point.x, point.y, 0.0)), -Vector((outward.x, outward.y, 0.0))))
    return planes, ext


def write_index(layout: dict, out: Path) -> None:
    """index.json from the layout alone (every piece is deterministic from it):
    the rooms with a stone build on disk and their roof tops, every passage
    file, stretch and node, and the dressing sets' places. Run once after
    rooms and passages were built in parallel processes with --no-index."""
    index = {}
    built = [r for r in layout['rooms'] if (out / 'rooms' / f'{r["id"]}.glb').exists()]
    index['rooms'] = sorted(r['id'] for r in built)
    tops = {}
    for room in built:
        rise = vault_rise(room, layout)
        tops[room['id']] = round(room['floor'] + room['height'] + rise + (0.3 if rise else 0.0), 3)
    index['tops'] = tops
    runs, nodes = network(layout)
    coverage, files, built_nodes = [], [], []
    for route in layout['routes']:
        stretches_ = [x for x in runs.get(route['id'], []) if x is not None]
        if not stretches_ or not (out / 'passages' / f'{route["id"]}.glb').exists():
            continue
        for segment, t0, t1, start, end in stretches_:
            coverage.append({'route': route['id'], 'segment': segment, 't0': round(t0, 4), 't1': round(t1, 4)})
        files.append({'file': f'passages/{route["id"]}.glb', 'routes': {route['id']: route.get('layout_hash')}})
    for key, node in sorted(nodes.items()):
        label = 'node_%d_%d_%d' % tuple(round(c) for c in node['godot'])
        if node['kind'] not in ('bay', 'portal') or not (out / 'passages' / f'{label}.glb').exists():
            continue
        files.append({'file': f'passages/{label}.glb', 'routes': {a['route']['id']: a['route'].get('layout_hash') for a in node['arrivals']}})
        built_nodes.append({'at': list(node['godot']), 'radius': round(node['profile'].half + passage.THICKNESS + 0.3, 2), 'kind': node['kind']})
    index['passages'], index['files'], index['nodes'] = coverage, files, built_nodes
    sets = json.loads((core.ROOT / 'content/environments/procedural_props_aged_v1/sets.json').read_text())
    index['props'] = [spot for room in built for spot in prop_spots(room, layout, sets)]
    (out / 'index.json').write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
    print('ARCHITECTURE_INDEX', len(index['rooms']), 'rooms', len(files), 'passage files', len(index['props']), 'props', flush=True)


def build_network(layout: dict, wanted: set, rng, lib, quoins) -> tuple:
    """Stone pieces for the wanted enclosed routes: one element per route
    (its runs) and one per node they reach (bay or portal)."""
    runs, nodes = network(layout)
    elements, coverage, files, built_nodes = [], [], [], []
    for route in layout['routes']:
        if route['id'] not in wanted or route['id'] not in runs:
            continue
        groups, key = {}, 0
        points = route['points']
        for number, stretch in enumerate(runs[route['id']]):
            if stretch is None:
                continue
            segment, t0, t1, start, end = stretch
            a, b = blender_point(points[segment]), blender_point(points[segment + 1])
            planes, ext = run_planes(route, number, stretch, nodes)
            pieces = passage.run(lib, rng, profile(route, layout), a.lerp(b, t0), a.lerp(b, t1), f'{route["id"]}_{number}',
                                 ext=ext, planes=planes)
            for group in pieces.values():
                groups[key] = group
                key += 1
            coverage.append({'route': route['id'], 'segment': segment, 't0': round(t0, 4), 't1': round(t1, 4)})
            print('PASSAGE_RUN', route['id'], segment, f'{t0:.3f}-{t1:.3f}', start[0], end[0], flush=True)
        if not any(groups.values()):
            continue  # every stretch of this route lies inside rooms or is a door's stub
        elements.append(('passages', route['id'], groups))
        files.append({'file': f'passages/{route["id"]}.glb', 'routes': {route['id']: route.get('layout_hash')}})
    for key, node in sorted(nodes.items()):
        served = {a['route']['id'] for a in node['arrivals']}
        if not served & wanted or node['kind'] not in ('bay', 'portal'):
            continue
        label = 'node_%d_%d_%d' % tuple(round(c) for c in node['godot'])
        o = node['profile']
        if node['kind'] == 'bay':
            groups = passage.bay(lib, rng, quoins, o, node['at'], node['axis'], node['sides'], label)
        else:
            arrival = node['arrivals'][0]
            groups = passage.portal(lib, rng, quoins, arrival['profile'], node['at'], -arrival['away'], label)
        elements.append(('passages', label, groups))
        files.append({'file': f'passages/{label}.glb', 'routes': {a['route']['id']: a['route'].get('layout_hash') for a in node['arrivals']}})
        built_nodes.append({'at': list(node['godot']), 'radius': round(o.half + passage.THICKNESS + 0.3, 2), 'kind': node['kind']})
        print('PASSAGE_NODE', label, node['kind'], sorted(served), flush=True)
    return elements, coverage, files, built_nodes


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


def stone_kind(obj) -> str:
    """Which stone kind a placed stone is, from its library mesh's name (kept
    through copies as 'name.001'): each kind gets its own face material in game."""
    name = obj.data.name
    for key, kind in (('quoin_big_lib', 'quoin'), ('ashlar_lib', 'ashlar'), ('quoin_lib', 'ashlar'), ('slab_lib', 'slab'),
                      ('galleted_lib', 'galleted'), ('gallet', 'galleted'), ('Gallet', 'galleted'), ('flag_lib', 'flag'),
                      ('vault_template', 'arch'), ('_arch', 'arch'), ('_rib', 'arch')):
        if key in name:
            return kind
    return 'stone'


def merge(label: str, groups: dict, rng) -> list:
    """Join each group's stones and mortar into Stone_<label>_<n> and
    Mortar_<label>_<n>, with per-stone tone and fresh faces in the colour."""
    merged = []
    for number, pieces in sorted(groups.items()):
        stones_, cores, coats = [], [], []
        for obj in pieces:
            obj.data = obj.data.copy()
            colour = obj.data.color_attributes.get('Color') or obj.data.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
            tone = float(obj.get('tone', 1.0))
            for item in colour.data:
                # Mortar reads dark: grimed lime deep in the joints, as in the paintovers.
                grey = max(tone, 0.0) / 1.25 if tone > 0 else (0.5 if tone > -1.5 else 0.8)
                item.color = (1.0, grey, item.color[2] if tone > 0 else 0.0, 1.0)
            obj.data.color_attributes.active_color = colour
            (coats if tone <= -1.5 else cores if tone < 0 else stones_).append(obj)
        by_kind = {}
        for obj in stones_:
            by_kind.setdefault(stone_kind(obj), []).append(obj)
        batches = [(f'Stone-{kind}', objects) for kind, objects in sorted(by_kind.items())]
        for kind, objects in batches + [('Mortar', cores), ('Plaster', coats)]:
            if not objects:
                continue
            core.select_only(objects)
            bpy.ops.object.make_single_user(object=True, obdata=True)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            if kind.startswith('Stone'):
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
        if not objects:
            continue
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


def ribbon_level(layout: dict, at: Vector, ignore: tuple = None):
    """Walking level of any route ribbon over plan point `at`, or None."""
    for route in layout['routes']:
        points, edges = route['points'], route['edges']
        for i in range(len(points) - 1):
            if ignore == (route['id'], i):
                continue
            quad = [flat((points[i][0] + edges[i][0], points[i][2] + edges[i][2])),
                    flat((points[i + 1][0] + edges[i + 1][0], points[i + 1][2] + edges[i + 1][2])),
                    flat((points[i + 1][0] - edges[i + 1][0], points[i + 1][2] - edges[i + 1][2])),
                    flat((points[i][0] - edges[i][0], points[i][2] - edges[i][2]))]
            if contains(quad, at):
                a, b = flat((points[i][0], points[i][2])), flat((points[i + 1][0], points[i + 1][2]))
                t = max(0.0, min(1.0, (at - a).dot(b - a) / max((b - a).length_squared, 1e-9)))
                return points[i][1] + (points[i + 1][1] - points[i][1]) * t
    return None


def stair_bodies(room: dict, layout: dict, rng, lib) -> list:
    """Ramps and galleries that climb inside a room are built on masonry,
    against the room's walls: under each raised walk, a mortar body from the
    floor up to the walk (its collision too), carried out to the wall where
    the walk runs within 1.5 m of it. The open side gets a stone face and a
    parapet where the drop beside it is over a metre. Sloped walks get stone
    treads; level ones are paved."""
    parts = []
    floor = room['floor']
    outline = [flat(v) for v in room['points']]
    inner = outset(ccw(outline), -THICKNESS * 0.5)
    up = Vector((0.0, 0.0, 1.0))

    def kept(objects, planes):
        result = []
        for obj in objects:
            if all(masonry.clip(obj, point, normal) for point, normal in planes):
                result.append(obj)
            else:
                core.discard(obj)
        return result

    def to_wall(point2: Vector, outward2: Vector) -> float:
        """Distance from a plan point to the room's inner wall face, outward."""
        best = 99.0
        for a, b in zip(inner, inner[1:] + inner[:1]):
            e = b - a
            denom = outward2.x * e.y - outward2.y * e.x
            if abs(denom) < 1e-9:
                continue
            w = a - point2
            t = (w.x * e.y - w.y * e.x) / denom
            u = (w.x * outward2.y - w.y * outward2.x) / denom
            if t > 0 and 0.0 <= u <= 1.0:
                best = min(best, t)
        return best

    for route in layout['routes']:
        points, edges = route['points'], route['edges']
        for i in range(len(points) - 1):
            p, q = points[i], points[i + 1]
            if max(p[1], q[1]) < floor + 0.3 or min(p[1], q[1]) > floor + room['height']:
                continue
            if not (contains(outline, flat((p[0], p[2]))) and contains(outline, flat((q[0], q[2])))):
                continue
            a2, b2 = flat((p[0], p[2])), flat((q[0], q[2]))
            run = (b2 - a2).length
            if run < 0.2:
                continue
            d = Vector(((b2 - a2).x, (b2 - a2).y, 0.0)).normalized()
            side = d.cross(up)
            slope = (q[1] - p[1]) / run
            surface = (up - d * slope).normalized()
            name = f'{room["id"]}_{route["id"]}_{i}'
            # Where flights meet, each one's masonry and treads end on the corner's
            # mitre, so a climbing flight never meets the next one's body as a step.
            mitres = []
            for k, vertex, sign in ((i - 1, a2, -1.0), (i + 1, b2, 1.0)):
                if 0 <= k < len(points) - 1:
                    other = flat((points[k + 1][0], points[k + 1][2])) - flat((points[k][0], points[k][2]))
                    if other.length > 1e-6:
                        o3 = Vector((other.x, other.y, 0.0)).normalized()
                        bisector = (d + o3).normalized() if (d + o3).length > 1e-6 else d
                        mitres.append((Vector((vertex.x, vertex.y, 0.0)), bisector * sign))
            half = route['width'] * 0.5
            reach = {}
            for sign in (1.0, -1.0):
                outward = side * sign
                gap = to_wall(Vector(((a2 + b2) * 0.5).to_tuple()) + Vector((outward.x, outward.y)) * half,
                              Vector((outward.x, outward.y)))
                reach[sign] = gap if gap <= 1.5 else 0.0
            # The body: mortar from the floor to just under the walk, out to the wall where it is near.
            width = 2.0 * half + reach[1.0] + reach[-1.0]
            centre_shift = (reach[1.0] - reach[-1.0]) * 0.5
            low = min(p[1], q[1])
            body = masonry.Wall(width, max(p[1], q[1]) - floor + 0.2, run + 0.02, recess=0.0).core(name + '_body')
            origin = Vector((a2.x, a2.y, floor)) + side * (centre_shift - width * 0.5) - d * 0.01
            # Wall-local x runs across (side), y up, z out = side x up = -d: the block runs along -z, i.e. +d.
            masonry.place([body], origin, side, up)
            parts += kept([body], [(Vector((a2.x, a2.y, p[1] - 0.03)), surface)] + mitres)
            # Treads (sloped) or paving (level), across the walk and out to the wall.
            step = 0.34 if abs(slope) > 0.06 else rng.uniform(0.5, 0.8)
            s = 0.0
            while run - s > 0.05:
                depth = min(step if abs(slope) > 0.06 else rng.uniform(0.45, 0.85), run - s)
                top = p[1] + slope * (s + depth if slope > 0 else s) + 0.02
                x = -half - reach[-1.0]
                while width - (x + half + reach[-1.0]) > 0.05:
                    length = rng.uniform(0.7, 1.5)
                    if width - (x + length + half + reach[-1.0]) < 0.4:
                        length = width - (x + half + reach[-1.0])
                    joint = rng.uniform(0.006, 0.014)
                    stone = KINDS.get('flag', lib).place(rng, length - joint, depth - joint, 0.16, f'{name}_tread')
                    frame = Matrix((side, d, up)).transposed().to_4x4()
                    frame.translation = Vector((a2.x, a2.y, top)) + d * (s + depth * 0.5) + side * (x + length * 0.5)
                    stone.matrix_world = frame @ stone.matrix_world
                    stone['frame'] = [*side, *d, *up]
                    parts += kept([stone], mitres)
                    x += length
                s += depth
            # The open sides: a stone face down to the floor, and a parapet over a drop.
            for sign in (1.0, -1.0):
                if reach[sign]:
                    continue
                outward = side * sign
                o2 = Vector((outward.x, outward.y))
                # Where another walk takes over this edge (a corridor arriving, the
                # next flight), the face and parapet stop: only the longest stretch
                # of the edge no other walk covers is built.
                free, best, current = [], (0.0, 0.0), None
                steps = max(2, int(run / 0.2))
                for k in range(steps + 1):
                    sk = run * k / steps
                    level = p[1] + slope * sk
                    other = ribbon_level(layout, a2 + (b2 - a2) * (k / steps) + o2 * (half - 0.2), ignore=(route['id'], i))
                    covered = other is not None and abs(other - level) < 1.5
                    if not covered and current is None:
                        current = sk
                    if (covered or k == steps) and current is not None:
                        end = sk if covered else run
                        if end - current > best[1] - best[0]:
                            best = (current, end)
                        current = None
                s0, s1 = best
                if s1 - s0 < 0.4:
                    continue
                span = s1 - s0
                edge_a = Vector((a2.x, a2.y, 0.0)) + d * s0 + outward * (half + 0.03)
                probe = a2 + (b2 - a2) * ((s0 + s1) * 0.5 / run) + o2 * (half + 0.5)
                beside = ribbon_level(layout, probe, ignore=(route['id'], i))
                parapet = p[1] + slope * (s0 + s1) * 0.5 - (beside if beside is not None else floor) > 1.0
                rise = 1.0 if parapet else 0.0
                height = max(p[1], q[1]) - floor + rise + 0.05
                along = up.cross(outward)
                start = edge_a if along.dot(d) >= 0 else edge_a + d * span
                face = masonry.Wall(span, height, 0.4 if parapet else 0.3).build(lib, rng, name=f'{name}_face{int(sign)}', core=parapet)
                masonry.place(face, Vector((start.x, start.y, floor)), along, up)
                parts += kept(face, [(Vector((a2.x, a2.y, p[1] + rise)) + outward * half, surface)])
                if parapet:
                    along = up.cross(-outward)
                    start = edge_a - outward * 0.43
                    start = start if along.dot(d) >= 0 else start + d * span
                    back = masonry.Wall(span, height, 0.2).build(lib, rng, name=f'{name}_parapet{int(sign)}', core=False, dress=False)
                    masonry.place(back, Vector((start.x, start.y, floor)), along, up)
                    parts += kept(back, [(Vector((a2.x, a2.y, p[1])), -surface), (Vector((a2.x, a2.y, p[1] + rise)), surface)])
    return parts


def vault_rise(room: dict, layout: dict) -> float:
    """How high a room's cloister vault rises above its walls: about a third
    of its inradius, never into a room or route above it. 0 = flat lid."""
    inner = outset(ccw([flat(v) for v in room['points']]), -THICKNESS * 0.5)
    top = room['floor'] + room['height']
    rise = min(max(0.3 * vault.inradius(inner), 1.0), 3.0)
    outline = [flat(v) for v in room['points']]
    for other in layout['rooms']:
        if other is room or other['floor'] < top - 0.01:
            continue
        theirs = [flat(v) for v in other['points']]
        if any(contains(outline, q) for q in theirs) or any(contains(theirs, q) for q in outline):
            rise = min(rise, other['floor'] - top - 0.8)
    for route in layout['routes']:
        for q in route['points']:
            if q[1] > top and contains(outline, flat((q[0], q[2]))):
                rise = min(rise, q[1] - top - 1.0)
    return rise if rise >= 1.0 else 0.0


def bay_spots(faces: list, reach: float, rise: float, clear) -> list:
    """Where pilasters stand: (wall i, wall j, k, x on i, x on j, span) for
    facing antiparallel walls about twice the vault's reach apart, spaced
    about 4.8 m, kept to the vault's ridge zone and clear of doors and walks."""
    result = []
    for i, fi in enumerate(faces):
        for j, fj in enumerate(faces):
            if j <= i or fi[1].dot(fj[1]) > -0.99:
                continue
            span = (fj[0] - fi[0]).dot(fi[2])
            if span < 4.0 or (rise and abs(span - 2.0 * reach) > 0.5):
                continue
            # Wall j's extent projected on wall i's line.
            j0 = (fj[0] - fi[0]).dot(fi[1])
            j1 = (fj[0] + fj[1] * fj[4] - fi[0]).dot(fi[1])
            lo, hi = max(0.0, min(j0, j1)), min(fi[4], max(j0, j1))
            margin = reach * 0.9 if rise else 1.2
            lo, hi = lo + margin, hi - margin
            if hi < lo:
                continue
            count = max(1, round((hi - lo) / 4.8) + 1)
            spots = [(lo + hi) * 0.5] if count == 1 else [lo + (hi - lo) * k / (count - 1) for k in range(count)]
            for k, x in enumerate(spots):
                xj = (fi[0] + fi[1] * x - fj[0]).dot(fj[1])
                if clear(fi, x) and clear(fj, xj):
                    result.append((i, j, k, x, xj, span))
    return result


def room_faces(walls: list) -> list:
    """(inner face start, along, inward, openings, length) per wall."""
    faces = []
    for a, b, openings in walls:
        along = (b - a).normalized()
        inward = Vector((along.y, -along.x))
        faces.append((a + inward * THICKNESS * 0.5, along, inward, openings, (b - a).length))
    return faces


def walk_near(layout: dict, probe: Vector, floor: float, height: float) -> bool:
    level = ribbon_level(layout, probe)
    return level is not None and floor - 0.6 <= level <= floor + height


PROP_SETS = {'entry': 'refectory', 'antechamber': 'votive', 'restraint': 'refectory', 'cells': 'mortuary',
             'chapel': 'votive', 'nave': 'votive', 'ossuary': 'ossuary', 'bones': 'ossuary', 'window': 'mortuary',
             'bell': 'refectory', 'choir': 'votive'}


def prop_spots(room: dict, layout: dict, sets: dict) -> list:
    """Places along a room's walls for the T-171 dressing sets: backs to
    the wall, clear of doorways, pilasters, stairs, walks and each other.
    Deterministic from the layout, so the game and the bake agree."""
    family = PROP_SETS.get(room['id'])
    if not family:
        return []
    floor, height = room['floor'], room['height']
    walls = room_walls(room, layout)
    faces = room_faces(walls)
    inner = outset(ccw([flat(v) for v in room['points']]), -THICKNESS * 0.5)
    reach = vault.inradius(inner)
    rise = vault_rise(room, layout)
    pilasters = {(i, round(x, 2)) for i, j, k, x, xj, span in bay_spots(faces, reach, rise, lambda face, x: True)}
    pilasters |= {(j, round(xj, 2)) for i, j, k, x, xj, span in bay_spots(faces, reach, rise, lambda face, x: True)}
    area = abs(sum(a.x * b.y - b.x * a.y for a, b in zip(inner, inner[1:] + inner[:1]))) * 0.5
    wanted = 1 + int(area // 140)
    placed, taken = [], []
    variants = [k for k in sorted(sets) if sets[k]['family'] == family]
    order = sorted(range(len(faces)), key=lambda i: -faces[i][4])
    for i in order:
        start, along, inward, openings, length = faces[i]
        for step in range(int(length / 0.5)):
            if len(placed) >= wanted:
                return placed
            name = variants[(len(placed) + len(room['id'])) % len(variants)]
            bounds = sets[name]['bounds_godot']
            half = max(-bounds['min'][0], bounds['max'][0]) + 0.15
            back = -bounds['min'][2] + 0.1
            depth = back + bounds['max'][2] + 0.1
            x = 0.6 + half + step * 0.5
            if x > length - 0.6 - half:
                break
            if any(o.x0 - 0.6 - half < x < o.x1 + 0.6 + half for o in openings if o.sill < 1.0):
                continue
            if any(k == i and abs(px - x) < half + 0.8 for k, px in pilasters):
                continue
            centre = start + along * x + inward * back
            corners = [start + along * (x + sx * half) + inward * sz for sx in (-1, 0, 1) for sz in (0.1, depth * 0.5, depth + 1.3)]
            if any(walk_near(layout, c, floor, height) or not contains(inner, c) for c in corners):
                continue
            if any((centre - other).length < half + 2.5 for other in taken):
                continue
            taken.append(centre)
            yaw = math.atan2(inward.x, -inward.y)
            godot = (centre.x, floor, -centre.y)
            placed.append({'room': room['id'], 'set': name, 'at': [round(c, 3) for c in godot], 'facing': [round(inward.x, 4), round(-inward.y, 4)]})
    return placed


def laced(rows: list) -> list:
    """Every fifth course below 4.5 m gives its lowest 10 cm to a lacing course
    of thin slabs; course boundaries (sills, springs) stay where they were."""
    result = []
    for k, (y0, h) in enumerate(rows):
        if k % 5 == 3 and h > 0.3 and y0 < 4.5:
            result += [(y0, 0.1), (y0 + 0.1, h - 0.1)]
        else:
            result.append((y0, h))
    return result


def bays(room: dict, walls: list, rows: list, layout: dict, rng, lib, quoins, rise: float) -> list:
    """Pilasters dividing a room's long walls into bays and, under a vault, a
    transverse rib springing from each facing pair: the rib follows the
    vault's own curve a hand's breadth below it, and the pilaster stands out
    exactly as far as the rib springs from the wall. No pilaster stands in a
    doorway's way or where a walk runs along the wall."""
    parts = []
    floor, height = room['floor'], room['height']
    up = Vector((0.0, 0.0, 1.0))
    inner = outset(ccw([flat(v) for v in room['points']]), -THICKNESS * 0.5)
    reach = vault.inradius(inner)
    radius = (reach * reach + rise * rise) / (2.0 * rise) if rise else 0.0
    rib_half = math.sqrt(max((radius - 0.25) ** 2 - (radius - rise) ** 2, 0.0)) if rise else 0.0
    project = min(max(reach - rib_half, 0.3), 0.65) if rise else 0.4
    dressed = rng.random() < 0.6
    width = 0.95 if dressed else 0.78
    faces = room_faces(walls)

    def clear(face, x: float) -> bool:
        start, along, inward, openings, length = face
        if x < 1.0 or x > length - 1.0:
            return False
        if any(o.x0 - 1.0 - width * 0.5 < x < o.x1 + 1.0 + width * 0.5 for o in openings):
            return False
        for dx in (-0.8, 0.0, 0.8):
            for dz in (0.3, 1.2):
                probe = start + along * (x + dx) + inward * dz
                level = ribbon_level(layout, probe)
                if level is not None and floor - 0.6 <= level <= floor + height:
                    return False
        return True

    def pilaster(face, x: float, name: str) -> list:
        start, along, inward, _, _ = face
        a3, n3 = Vector((along.x, along.y, 0.0)), Vector((inward.x, inward.y, 0.0))
        base = Vector((start.x, start.y, floor)) + a3 * x
        result = []
        for row, (y0, h) in enumerate(rows):
            cap = dressed and row == len(rows) - 1
            foot = dressed and row == 0
            w = width + (0.16 if foot else 0.2 if cap else rng.uniform(-0.03, 0.03))
            out = project + (0.06 if foot else 0.1 if cap else rng.uniform(-0.008, 0.008))
            joint = rng.uniform(0.008, 0.016)
            stone = (KINDS.get('quoin', quoins) if dressed else lib).place(rng, w - joint, h - joint, out + 0.12, f'{name}_{row}')
            frame = Matrix((a3, up, n3)).transposed().to_4x4()
            frame.translation = base + up * (y0 + h * 0.5) + n3 * out
            stone.matrix_world = frame @ stone.matrix_world
            stone['frame'] = [*a3, *up, *n3]
            result.append(stone)
        body = masonry.Wall(width - 0.06, height, project - 0.03, recess=0.0).core(f'{name}_core')
        masonry.place([body], base - a3 * (width - 0.06) * 0.5 + n3 * (project - 0.03), a3, up)
        result.append(body)
        return result

    for i, j, k, x, xj, span in bay_spots(faces, reach, rise, clear):
        fi, fj = faces[i], faces[j]
        label = f'{room["id"]}_bay{i}_{j}_{k}'
        parts += pilaster(fi, x, label + 'a') + pilaster(fj, xj, label + 'b')
        if not rise:
            continue
        o = masonry.Opening(-rib_half, rib_half, 0.0, 0.0, rise=rise - 0.25)
        pa = fi[0] + fi[1] * x
        mid = pa + fi[2] * (span * 0.5)
        a3, n3 = Vector((fi[1].x, fi[1].y, 0.0)), Vector((fi[2].x, fi[2].y, 0.0))
        frame = Matrix((n3, a3, up)).transposed().to_4x4()
        frame.translation = Vector((mid.x, mid.y, floor + height + o.cy))
        for piece in masonry.ring(rng, o, 0.5, width - 0.12, label + '_rib', triangles=300):
            piece.data.transform(piece.matrix_world)
            piece.matrix_world = frame.copy()
            piece['tone'] = rng.uniform(0.8, 1.1)
            piece['frame'] = [*n3, *up, *a3]
            parts.append(piece)
    print('BAYS', room['id'], sum(1 for obj in parts if obj.name.endswith('_core')) if parts else 0, 'pilasters',
          'dressed' if dressed else 'plain', flush=True)
    return parts


def build_room(room: dict, layout: dict, rng, lib, quoins, groups: dict = None) -> list:
    parts = []
    walls = room_walls(room, layout)
    # One set of courses for the whole room, so joints run on round corners.
    keys = {0.0, room['height']}
    for _, _, openings in walls:
        keys.update(o.spring for o in openings)
        keys.update(o.sill for o in openings if o.sill > 0)
    # Courses deepen up the wall: big stones where nobody can reach them.
    low = masonry.Wall(1.0, min(room['height'], 4.5)).courses(rng, {k for k in keys if k <= 4.5} | {min(room['height'], 4.5)})
    high = []
    if room['height'] > 4.5:
        high = [(4.5 + y0, h) for y0, h in masonry.Wall(1.0, room['height'] - 4.5, course=(0.32, 0.56)).courses(
            rng, {k - 4.5 for k in keys if k > 4.5})]
    rows = low + high
    if room['id'] in LACED and KINDS:
        rows = laced(rows)
    wall_lib = KINDS.get('galleted', lib) if room['id'] in ROUGH else lib
    for number, (a, b, openings) in enumerate(walls):
        length = (b - a).length
        outside = exposed(a, b, layout)
        recess = masonry.Wall(1.0, 1.0).recess
        # A wall seen from the shaft is faced on both sides; its core stops
        # short of the outer face so the outer stones show.
        # No old wall is ruler-straight: a slight bulge, an outward lean, courses that wander.
        plastered = room['id'] in PLASTER
        wall = masonry.Wall(length, room['height'], THICKNESS - (recess if outside else 0.0), openings,
                            bow=rng.uniform(0.008, 0.02 if plastered else 0.03) * min(length / 6.0, 1.0),
                            lean=0.0 if plastered else rng.uniform(0.0, 0.0025),
                            wave=rng.uniform(0.004, 0.012), plinth=True, cornice=room['height'] > 3.5, thresholds=True)
        wall.lacing = KINDS.get('slab') if room['id'] in LACED else None
        pieces = wall.build(wall_lib, rng, quoins=KINDS.get('ashlar', quoins), name=f'{room["id"]}_{number}', rows=rows,
                            interlock=0.28, upper=UPPER)
        if room['id'] in ROUGH and KINDS:
            # Spalls pressed into the open joints of rough walling.
            pieces += stonekinds.gallet([q for q in pieces if q.get('tone', 1.0) > 0 and q.matrix_world.translation.y < 3.0], rng,
                                        cell=0.02, spacing=0.24, share=0.35, name=f'{room["id"]}_{number}_gallet')
        if plastered:
            # The render: a thin skin 5-6 cm proud of the stones, holed at the openings.
            coat = masonry.Wall(length, room['height'], 0.012, openings, recess=0.0).core(f'{room["id"]}_{number}_coat')
            coat.matrix_world = Matrix.Translation((0.0, 0.0, 0.072)) @ coat.matrix_world
            coat['tone'] = -2.0
            pieces.append(coat)
        along = Vector((b.x - a.x, b.y - a.y, 0.0))
        # The game's room wall is 0.9 m centred on the outline: put the stone
        # face on its inner face, where the collision already is.
        inward = along.normalized().cross(Vector((0, 0, 1)))
        masonry.place(pieces, Vector((a.x, a.y, room['floor'])) + inward * THICKNESS * 0.5, along, Vector((0, 0, 1)))
        if outside:
            mirrored = [masonry.Opening(length - o.x1, length - o.x0, o.sill, o.spring, o.window, o.rise) for o in openings]
            outer = masonry.Wall(length, room['height'], THICKNESS * 0.5, mirrored, bow=rng.uniform(0.008, 0.025),
                                 wave=rng.uniform(0.004, 0.012))
            back = outer.build(lib, rng, quoins=quoins, name=f'{room["id"]}_{number}_outer', rows=rows, core=False, dress=False,
                               upper=UPPER)
            masonry.place(back, Vector((b.x, b.y, room['floor'])) - inward * THICKNESS * 0.5, -along, Vector((0, 0, 1)))
            pieces += back
        if groups is not None:
            groups[number] = pieces
        parts += pieces
        print('WALL', room['id'], number, f'{length:.2f} m', 'openings', [(round(o.x0, 2), round(o.x1, 2)) for o in openings],
              'faced both sides' if outside else '', flush=True)
    # Stair masonry is being redesigned (flights against the hall walls on
    # solid masonry, stepped treads): left out until it reads right in game.
    pieces = stair_bodies(room, layout, rng, lib) if STAIRS else []
    if pieces:
        if groups is not None:
            groups[len(walls) + 1] = pieces
        parts += pieces
        print('STAIRS', room['id'], len(pieces), 'stones under raised walks', flush=True)
    rise = vault_rise(room, layout)
    pieces = bays(room, walls, rows, layout, rng, lib, quoins, rise)
    if pieces:
        if groups is not None:
            groups[len(walls) + 2] = pieces
        parts += pieces
    if rise:
        inner = outset(ccw([flat(v) for v in room['points']]), -THICKNESS * 0.5)
        # Wide vaults are laid in bigger stones (far overhead, and lighter to draw).
        wide = vault.inradius(inner) > 6.0
        pieces = vault.cloister(UPPER[0] if UPPER else lib, rng, inner, room['floor'] + room['height'], rise, f'{room["id"]}_vault',
                                course=(0.32, 0.5) if wide else (0.24, 0.4), lengths=(0.55, 1.25) if wide else (0.3, 0.9))
        if groups is not None:
            groups[len(walls)] = pieces
        parts += pieces
    room['vault_rise'] = rise
    print('VAULT', room['id'], f'rise {rise:.2f} m' if rise else 'flat lid', flush=True)
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
    # Up into the vault from beside a wall.
    e = centre.lerp(pts[0], 0.7)
    t = centre.lerp(pts[len(pts) // 2], 0.4)
    views.append(disturb.render(Vector((e.x, e.y, floor + 1.7)), Vector((t.x, t.y, floor + room['height'] + 1.0)), size=(960, 600),
                                samples=48, lens=18))
    disturb.write_png(path, numpy.concatenate(views, axis=1))


def main():
    layout_path, out, options = parse()
    layout = json.loads(layout_path.read_text())
    if options.get('index-only'):
        write_index(layout, out)
        return
    if options.get('props'):
        sets = json.loads((core.ROOT / 'content/environments/procedural_props_aged_v1/sets.json').read_text())
        placed = [spot for room in layout['rooms'] for spot in prop_spots(room, layout, sets)]
        index_path = out / 'index.json'
        index = json.loads(index_path.read_text()) if index_path.exists() else {}
        index['props'] = placed
        index_path.write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
        for spot in placed:
            print('PROP', spot['room'], spot['set'], spot['at'], flush=True)
        return
    if options.get('check'):
        # Rules only, no stones: every doorway and passage the layout implies.
        for room in layout['rooms']:
            for number, (a, b, openings) in enumerate(room_walls(room, layout)):
                for o in openings:
                    print('DOOR', room['id'], number, f'{o.x0:.2f}-{o.x1:.2f}', f'crown {o.crown:.2f}', flush=True)
        runs, nodes = network(layout)
        for route_id, stretches_ in runs.items():
            for segment, t0, t1, start, end in [x for x in stretches_ if x is not None]:
                print('PASSAGE_STRETCH', route_id, segment, f'{t0:.3f}-{t1:.3f}', start[0], end[0], flush=True)
        for key, node in sorted(nodes.items()):
            print('PASSAGE_NODE', node['godot'], node['kind'], [a['route']['id'] for a in node['arrivals']], node['open'], flush=True)
        for misfit in MISFITS:
            print('DOOR_DOES_NOT_FIT', misfit, flush=True)
        return
    core.empty_scene()
    rng = core.rng(177, 'architecture')
    # Wall stones: chunky silhouettes, fine surface from the game's normal maps;
    # backs inside the core are cut. Quoins keep their sides for the reveals.
    lib = stonelib.Library(rng, 'squared_rubble', count=160, triangles=200, hidden_back=0.06)
    quoins = stonelib.Library(rng, 'ashlar', count=40, triangles=320, aspects=(1.0, 2.6), name='quoin')
    global UPPER
    # Stone kinds by role (T-182): dressings, pier blocks, lacing slabs, rough walling, paving.
    KINDS.update({
        # Budgets: these stones come by the thousand, so keep them light (Godot's LODs thin them further).
        'ashlar': stonekinds.Library(rng, 'dressed_ashlar', count=40, triangles=200, name='ashlar', tone=(0.6, 1.15)),
        'quoin': stonekinds.Library(rng, 'big_quoin', count=24, triangles=240, name='quoin_big', tone=(0.6, 1.1)),
        'slab': stonekinds.Library(rng, 'thin_slab', count=40, triangles=110, name='slab', hidden_back=0.06, tone=(0.55, 1.15)),
        'galleted': stonekinds.Library(rng, 'galleted_rubble', count=120, triangles=160, name='galleted', hidden_back=0.06,
                                       tone=(0.5, 1.2)),
        'flag': stonekinds.Library(rng, 'floor_flag', count=40, triangles=110, name='flag', tone=(0.6, 1.1)),
    })
    passage.PAVING = KINDS['flag']
    # Above 4.5 m: bigger stones, a third of the triangles (Godot's LODs thin them further).
    UPPER = (stonelib.Library(rng, 'squared_rubble', count=60, triangles=70, aspects=(1.2, 3.4), hidden_back=0.06, name='upper'),
             4.5, (0.55, 1.4))
    wanted = options['rooms'].split(',') if options['rooms'] else None
    rooms = [r for r in layout['rooms'] if wanted is None or r['id'] in wanted]
    elements, parts = [], 0
    for room in rooms:
        groups = {}
        parts += len(build_room(room, layout, rng, lib, quoins, groups))
        elements.append(('rooms', room['id'], groups))
    index_path = out / 'index.json'
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    wanted_routes = {r['id'] for r in layout['routes'] if r['enclosed']} if options['passages'] == 'all' else set(options['passages'].split(',')) - {''}
    passage_elements, coverage, files, built_nodes = build_network(layout, wanted_routes, rng, lib, quoins)
    elements += passage_elements
    parts += sum(len(g) for _, _, groups in passage_elements for g in groups.values())
    print('ARCHITECTURE_PARTS', parts, flush=True)
    for misfit in MISFITS:
        print('DOOR_DOES_NOT_FIT', misfit, flush=True)
    if options['export'] and MISFITS:
        raise SystemExit('Doorways do not fit their walls; fix the room outlines first')
    core.flush_trash()
    if options['export'] and options.get('no-index'):
        bake_all(elements, out)
    elif options['export']:
        bake_all(elements, out)
        # The index describes what this run built; partial runs keep earlier rooms.
        index['rooms'] = sorted(set(index.get('rooms', [])) | {r['id'] for r in rooms})
        # Where each room's roof sits: over its vault, if it has one.
        tops = index.get('tops', {})
        for r in rooms:
            tops[r['id']] = round(r['floor'] + r['height'] + r.get('vault_rise', 0.0) + (0.3 if r.get('vault_rise') else 0.0), 3)
        index['tops'] = tops
        if wanted_routes:
            index['passages'] = coverage
            index['files'] = files
            index['nodes'] = built_nodes
        index.pop('layout_hash', None)
        index_path.write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
    if options['render']:
        render_room(rooms[0], Path(options['render']))
        print('ARCHITECTURE_RENDERED', options['render'], flush=True)


if __name__ == '__main__':
    main()
