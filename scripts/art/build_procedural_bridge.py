"""Blender background: wooden bridge decks baked from the game's real routes.

    godot --headless --path . -s scripts/art/export_dungeon_layout.gd -- --out=/abs/layout.json
    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_procedural_bridge.py -- \
        /abs/layout.json content/environments/procedural_bridge_v1 [--seed 20261024] [--samples 64]

For each open wooden route the deck follows the walking ribbon exactly:
P(s, l) = lerp(A, B, s) + lerp(EA, EB, s) * l, with A/B the route nodes and EA/EB
the mitered half-width vectors Godot uses for collision. Lines of constant s
are level, so boards laid along them sit flat on the ribbon with no stair
steps; at bends they fan with slightly wider gaps outside, like a real deck.
Stringers run along constant-l lines and are mitered on the shared node line.
Posts stand outside the deck edge, carry a handrail and a sagging rope rail.
Output per route: <id>.glb (Wood_/Iron_/Rope_ nodes per segment, each with
extras.layout_hash) and <id>.json (report). Godot falls back to procedural
timber when the stored layout_hash no longer matches the route.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Matrix, Vector

from procgen import bake, core, curves, export, shapes

BOARD_PITCH = 0.30
BOARD_GAP = 0.012
BOARD_THICKNESS = 0.06
BOARD_OVERHANG = 0.03
STRINGER_WIDTH = 0.22
RIM_WIDTH = 0.20
INNER_STRINGER = 0.35
POST = 0.16
POST_GAP = 0.035
POST_SPACING = 2.2
RAIL_TOP = 1.10
ROPE_HEIGHT = 0.58
UP = Vector((0, 1, 0))
GODOT_TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def parse():
    values = core.args()
    options = {'seed': 20261024, 'samples': 64, 'routes': None}
    positional = []
    i = 0
    while i < len(values):
        if values[i] == '--seed':
            options['seed'] = int(values[i + 1]); i += 2
        elif values[i] == '--samples':
            options['samples'] = int(values[i + 1]); i += 2
        elif values[i] == '--routes':
            options['routes'] = values[i + 1].split(','); i += 2
        else:
            positional.append(values[i]); i += 1
    return Path(positional[0]).resolve(), Path(positional[1]).resolve(), options


def flat(v: Vector) -> Vector:
    return Vector((v.x, 0.0, v.z))


class Segment:
    """Walking ribbon between two route nodes, in Godot coordinates."""

    def __init__(self, a, b, ea, eb):
        self.a, self.b, self.ea, self.eb = a, b, ea, eb

    def point(self, s: float, l: float) -> Vector:
        return self.a.lerp(self.b, s) + self.ea.lerp(self.eb, s) * l

    def along(self, l: float) -> Vector:
        """dP/ds at lateral l: direction of a stringer line."""
        return (self.b - self.a) + (self.eb - self.ea) * l

    def normal(self, s: float) -> Vector:
        n = (self.ea.lerp(self.eb, s)).cross(self.along(0.0)).normalized()
        return n if n.y > 0 else -n


def miter_plane(node: Vector, edge: Vector) -> tuple:
    """Vertical plane through the node containing its mitered edge."""
    return node, edge.normalized().cross(UP).normalized()


def build_route(route: dict, seed: int, report: dict) -> list:
    rid = route['id']
    points = [Vector(p) for p in route['points']]
    edges = [Vector(e) for e in route['edges']]
    segments = [Segment(points[i], points[i + 1], edges[i], edges[i + 1]) for i in range(len(points) - 1)]
    objects = []
    proxies = []
    boards_total = 0
    for index, seg in enumerate(segments):
        rng = core.rng(seed, rid, index)
        wood = shapes.Builder(f'Wood_{index}')
        iron = shapes.Builder(f'Iron_{index}')
        rope = shapes.Builder(f'Rope_{index}')
        flat_length = flat(seg.b - seg.a).length
        count = max(2, round(flat_length / BOARD_PITCH))
        # Boards: one per s-interval along the level s-line, width from the
        # narrowest spacing so neighbours never touch.
        for k in range(count):
            s0, s1 = k / count, (k + 1) / count
            sm = (s0 + s1) * 0.5
            left, right = seg.point(sm, -1.0), seg.point(sm, 1.0)
            axis = (right - left).normalized()
            spacing = min(((seg.point(s1, l) - seg.point(s0, l)) - axis * (seg.point(s1, l) - seg.point(s0, l)).dot(axis)).length for l in (-1.0, 0.0, 1.0))
            normal = seg.normal(sm)
            lift = rng.uniform(-0.004, 0.006)
            reach = BOARD_OVERHANG + rng.uniform(-0.01, 0.01)
            a = left - axis * reach - normal * (BOARD_THICKNESS * 0.5 - lift)
            b = right + axis * (BOARD_OVERHANG + rng.uniform(-0.01, 0.01)) - normal * (BOARD_THICKNESS * 0.5 - lift)
            shapes.plank(wood, a, b, spacing - BOARD_GAP - rng.uniform(0, 0.01), BOARD_THICKNESS, normal, rng, segment=0.5)
            boards_total += 1
        # Stringers along constant-l lines, mitered on both node lines.
        half = seg.ea.length
        for l, width in ((-1.0 + RIM_WIDTH * 0.5 / half, RIM_WIDTH), (-INNER_STRINGER, STRINGER_WIDTH),
                         (INNER_STRINGER, STRINGER_WIDTH), (1.0 - RIM_WIDTH * 0.5 / half, RIM_WIDTH)):
            drop = BOARD_THICKNESS + (report['stringer_bottom'] - BOARD_THICKNESS) * 0.5
            a = seg.point(0.0, l) - UP * drop
            b = seg.point(1.0, l) - UP * drop
            shapes.timber(wood, a, b, width, report['stringer_bottom'] - BOARD_THICKNESS, seg.normal(0.5), rng,
                          segment=0.5, start_cut=miter_plane(seg.a - UP * drop, seg.ea),
                          end_cut=miter_plane(seg.b - UP * drop, seg.eb), bow=0.0, crook=0.0, twist=0.0)
        objects.append((index, wood, iron, rope))
    # Posts, handrails and rope rails along both deck edges.
    posts_total = 0
    for sign in (-1.0, 1.0):
        stations = []  # (position on deck edge, outward, segment index)
        for index, seg in enumerate(segments):
            edge_length = flat(seg.point(1.0, sign) - seg.point(0.0, sign)).length
            parts = max(1, math.ceil(edge_length / POST_SPACING))
            for part in range(parts + (1 if index == len(segments) - 1 else 0)):
                s = part / parts
                if part == 0:
                    outward = (seg.ea * sign).normalized()
                elif part == parts:
                    outward = (seg.eb * sign).normalized()
                else:
                    direction = flat(seg.along(sign)).normalized()
                    outward = Vector((-direction.z, 0.0, direction.x)) * (1 if Vector((-direction.z, 0, direction.x)).dot(seg.ea * sign) > 0 else -1)
                stations.append((seg.point(s, sign) + outward * (POST_GAP + POST * 0.5), outward, min(index, len(segments) - 1)))
        tops = []
        posts_total += len(stations)
        for k, (base, outward, index) in enumerate(stations):
            rng = core.rng(seed, rid, 'post', sign, k)
            wood, iron = objects[index][1], objects[index][2]
            bottom = base - UP * (report['stringer_bottom'] + 0.04)
            top = base + UP * (RAIL_TOP + 0.04)
            shapes.timber(wood, bottom, top, POST, POST, outward, rng, segment=0.5, chamfer=0.02)
            for height in (-0.14, -0.34):
                bolt = base + UP * height + outward * (POST * 0.5 + 0.004)
                shapes.bar(iron, bolt - outward * 0.006, bolt + outward * 0.012, 0.035, 0.035, UP, rng)
            tops.append(base + UP * (RAIL_TOP - 0.045))
        # Handrail members post to post, mitered where direction changes.
        for k in range(len(tops) - 1):
            rng = core.rng(seed, rid, 'rail', sign, k)
            wood = objects[stations[k][2]][1]
            a, b = tops[k], tops[k + 1]
            here = (b - a).normalized()
            start_cut = end_cut = None
            if k > 0:
                before = (a - tops[k - 1]).normalized()
                start_cut = (a, (before + here).normalized())
            if k + 2 < len(tops):
                after = (tops[k + 2] - b).normalized()
                end_cut = (b, (here + after).normalized())
            shapes.timber(wood, a, b, 0.13, 0.09, UP, rng, segment=0.5, start_cut=start_cut, end_cut=end_cut, chamfer=0.018)
            rope_points = curves.catenary(core.to_blender(stations[k][0] + UP * ROPE_HEIGHT),
                                          core.to_blender(stations[k + 1][0] + UP * ROPE_HEIGHT), 0.006, 12)
            curves.tube(objects[stations[k][2]][3], [Vector(core.to_godot(p)) for p in rope_points], 0.022, sides=6,
                        color=(1.0, rng.random(), 0.0, 1.0), twist=9.0)
    # Iron straps where each stringer bears on a transom (supported nodes only).
    supported = [Vector(s['deck']) for s in route['supports']]
    for node, point in enumerate(points):
        if not any((point - s).length < 0.01 for s in supported):
            continue
        index = min(node, len(segments) - 1)
        iron = objects[index][2]
        rng = core.rng(seed, rid, 'strap', node)
        side = edges[node].normalized()
        along = side.cross(UP).normalized()
        seat = point - UP * report['seat_depth']
        proxies.append((seat, side, along, edges[node].length))
        for l in (-1.0 + RIM_WIDTH * 0.5 / edges[node].length, -INNER_STRINGER, INNER_STRINGER, 1.0 - RIM_WIDTH * 0.5 / edges[node].length):
            center = point + edges[node] * l
            for face in (-1.0, 1.0):
                strap = center + along * face * (STRINGER_WIDTH * 0.5 + 0.006)
                shapes.bar(iron, strap - UP * (report['stringer_bottom'] - 0.12), strap - UP * (report['seat_depth'] + 0.16),
                           0.07, 0.01, along * face, rng)
    result = []
    for index, wood, iron, rope in objects:
        for builder in (wood, iron, rope):
            if builder.pieces:
                obj = builder.to_object()
                obj['layout_hash'] = route['layout_hash']
                obj['route'] = rid
                obj['segment'] = index
                obj.data.transform(GODOT_TO_BLENDER)
                result.append(obj)
    report['routes'][rid] = {'layout_hash': route['layout_hash'], 'segments': len(segments), 'boards': boards_total,
                             'posts': posts_total}
    return result, proxies


def transom_proxies(proxies) -> list:
    """Supporting transoms only occlude during the AO bake; Godot builds them."""
    objects = []
    for seat, side, along, half in proxies:
        builder = shapes.Builder('TransomProxy')
        shapes.prism(builder, seat - side * (half + 0.25), seat + side * (half + 0.25), 0.40, 0.44, UP,
                     core.rng(0, 'proxy'), chamfer=0.01, wear=0.0, segment=1.0)
        obj = builder.to_object()
        obj.data.transform(GODOT_TO_BLENDER)
        objects.append(obj)
    return objects


def triangles(objects) -> int:
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)


def main():
    layout_path, out, options = parse()
    layout = json.loads(layout_path.read_text())
    out.mkdir(parents=True, exist_ok=True)
    for route in layout['routes']:
        if not route['wood'] or route['enclosed']:
            continue
        if options['routes'] and route['id'] not in options['routes']:
            continue
        core.empty_scene()
        report = {'route': route['id'], 'seed': options['seed'], 'samples': options['samples'],
                  'seat_depth': layout['baked_seat_depth'], 'stringer_bottom': layout['baked_stringer_bottom'],
                  'routes': {}}
        objects, proxies = build_route(route, options['seed'], report)
        occluders = transom_proxies(proxies)
        ao = bake.ao_to_color(objects, samples=options['samples'], distance=0.6)
        for obj in occluders:
            bpy.data.objects.remove(obj, do_unlink=True)
        path = export.glb(objects, out / (route['id'] + '.glb'))
        info = report['routes'][route['id']]
        info['triangles'] = triangles(objects)
        info['objects'] = len(objects)
        data = {'method': 'deck follows the walking ribbon; boards on level s-lines; stringers mitered on node lines; '
                          'posts outside the edge with handrail and catenary rope; Cycles AO in Color.R',
                'layout_source': core.relative(layout_path), 'seed': options['seed'], 'samples': options['samples'],
                'seat_depth': report['seat_depth'], 'stringer_bottom': report['stringer_bottom'],
                'layout_hash': route['layout_hash'], 'ao': ao, **info}
        core.write_report(out / (route['id'] + '.json'), data, [path])
        print('BRIDGE_BAKE_OK', route['id'], json.dumps({k: data[k] for k in ('triangles', 'boards', 'objects')}), flush=True)


main()
