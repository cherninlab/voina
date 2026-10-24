"""Blender background: wooden bridges built from the game's real routes, then
aged by physics over a series of attempts.

    godot --headless --path . -s scripts/art/export_dungeon_layout.gd -- --out=/abs/layout.json
    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_procedural_bridge.py -- \
        /abs/layout.json content/environments/procedural_bridge_v1 [--seed 20261024] [--samples 32] \
        [--attempts 8] [--pick high_span=3] [--review DIR] [--ideal]

Construction follows the walking ribbon exactly:
P(s, l) = lerp(A, B, s) + lerp(EA, EB, s) * l, with A/B the route nodes and EA/EB
the mitered half-widths Godot uses for collision. Boards lie along level
s-lines, stringers along l-lines mitered on the shared node line, posts stand
outside the deck edge with a handrail and a sagging rope.

Then every board, post and rail becomes its own rigid body. Boards are nailed
to the rim stringers, posts hinge and bolt to them, rails are pinned and
nailed to posts. A share of the joints is rusted or rotten; some boards are
already gone, one post may be rotten at the foot, one rail end may have
failed. Each attempt shakes the stringers with a tremor (and some roll a
stone ball down the deck), lets everything settle, and measures loose,
fallen and missing boards, leaning posts, hanging rails and the deck's
deviation from the walking surface on the lanes. The most believable "aged"
attempt that stays walkable is kept (or --pick one); --review writes a
contact sheet with the chosen attempt framed. --ideal skips ageing.

Output per route: <id>.glb (Wood_/Iron_/Rope_ nodes per segment, extras.layout_hash)
and <id>.json (report with every attempt and the missing-board footprints the
Godot deck test skips).
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
import numpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from procgen import bake, core, curves, disturb, export, rigid, shapes

BOARD_PITCH = 0.30
BOARD_GAP = 0.012
BOARD_THICKNESS = 0.06
BOARD_OVERHANG = 0.02
STRINGER_WIDTH = 0.22
RIM_WIDTH = 0.20
INNER_STRINGER = 0.35
POST = 0.16
POST_GAP = 0.05
POST_SPACING = 2.2
RAIL_TOP = 1.10
ROPE_HEIGHT = 0.58
LANE = 0.75
LANE_TOLERANCE = 0.025
UP = Vector((0, 1, 0))
GODOT_TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
OAK = 700.0
# (tremor intensity, share of weak joints, roll a stone ball)
ATTEMPTS = [(0.0, 0.05, False), (0.4, 0.10, False), (0.7, 0.15, True), (1.0, 0.20, False),
            (1.0, 0.25, True), (1.3, 0.25, False), (1.7, 0.30, True), (2.2, 0.35, False)]


def parse() -> tuple:
    values = core.args()
    options = {'seed': 20261024, 'samples': 64, 'routes': None, 'attempts': len(ATTEMPTS), 'pick': {},
               'review': None, 'ideal': False, 'only': None, 'assemble': False, 'work': None}
    positional = []
    i = 0
    while i < len(values):
        key = values[i]
        if key in ('--seed', '--samples', '--attempts'):
            options[key[2:]] = int(values[i + 1]); i += 2
        elif key == '--routes':
            options['routes'] = values[i + 1].split(','); i += 2
        elif key == '--pick':
            options['pick'] = {k: int(v) for k, v in (p.split('=') for p in values[i + 1].split(','))}; i += 2
        elif key == '--review':
            options['review'] = Path(values[i + 1]).resolve(); i += 2
        elif key == '--ideal':
            options['ideal'] = True; i += 1
        elif key == '--only':
            options['only'] = int(values[i + 1]); i += 2
        elif key == '--assemble':
            options['assemble'] = True; i += 1
        elif key == '--work':
            options['work'] = Path(values[i + 1]).resolve(); i += 2
        else:
            positional.append(key); i += 1
    return Path(positional[0]).resolve(), Path(positional[1]).resolve(), options


def flat(v: Vector) -> Vector:
    return Vector((v.x, 0.0, v.z))


def b(v: Vector) -> Vector:
    """Godot point or direction to Blender."""
    return core.to_blender(v)


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


def piece(name: str, build, a: Vector, b_: Vector, up: Vector, smooth: float = 35.0) -> bpy.types.Object:
    """One prism built in Godot space, moved to Blender and given its own frame."""
    builder = shapes.Builder(name)
    build(builder)
    obj = builder.to_object(smooth_angle=smooth)
    obj.data.transform(GODOT_TO_BLENDER)
    disturb.orient(obj, b(a), b(b_), b(up))
    return obj


def collide_alone(obj: bpy.types.Object, index: int) -> None:
    """Rails overlap their neighbours inside each post: give each its own
    collision collection so only its joints act on it."""
    layers = [False] * 20
    layers[1 + index % 19] = True
    obj.rigid_body.collision_collections = layers


class Bridge:
    """One route's construction, ageing set-up and physics pieces for one attempt."""

    def __init__(self, route: dict, layout: dict, seed: int, setting: tuple):
        self.route, self.layout, self.seed = route, layout, seed
        self.intensity, self.weak, self.ball = setting
        self.rid = route['id']
        self.points = [Vector(p) for p in route['points']]
        self.edges = [Vector(e) for e in route['edges']]
        self.segments = [Segment(self.points[i], self.points[i + 1], self.edges[i], self.edges[i + 1])
                         for i in range(len(self.points) - 1)]
        self.bottom = layout['baked_stringer_bottom']
        self.seat = layout['baked_seat_depth']
        self.stringers, self.rims = [], []
        self.boards, self.posts, self.rails = [], [], []
        self.missing, self.straps = [], []
        self.attachments = []  # per side: [(post, local rope point, segment)]

    # -- construction ------------------------------------------------------
    def build(self) -> None:
        plan = core.rng(self.seed, self.rid, 'plan', self.weak)
        board_count = sum(max(2, round(flat(s.b - s.a).length / BOARD_PITCH)) for s in self.segments)
        gone = set()
        if self.weak >= 0.15:
            for _ in range(plan.choice([0, 1, 1, 2])):
                pick = plan.randrange(3, board_count - 3)
                if not {pick - 1, pick, pick + 1} & gone:
                    gone.add(pick)
        index = 0
        for number, seg in enumerate(self.segments):
            rng = core.rng(self.seed, self.rid, number)
            half = seg.ea.length
            rims = {}
            row = []
            for l, width in ((-1.0 + RIM_WIDTH * 0.5 / half, RIM_WIDTH), (-INNER_STRINGER, STRINGER_WIDTH),
                             (INNER_STRINGER, STRINGER_WIDTH), (1.0 - RIM_WIDTH * 0.5 / half, RIM_WIDTH)):
                drop = BOARD_THICKNESS + (self.bottom - BOARD_THICKNESS) * 0.5
                a, z = seg.point(0.0, l) - UP * drop, seg.point(1.0, l) - UP * drop
                stringer = piece(f'Stringer_{number}_{len(row)}', lambda bl, a=a, z=z, width=width, seg=seg, drop=drop: shapes.timber(
                    bl, a, z, width, self.bottom - BOARD_THICKNESS, seg.normal(0.5), rng, segment=0.5,
                    start_cut=miter_plane(seg.a - UP * drop, seg.ea), end_cut=miter_plane(seg.b - UP * drop, seg.eb),
                    bow=0.0, crook=0.0, twist=0.0), a, z, seg.normal(0.5))
                stringer['segment'] = number
                row.append(stringer)
                if abs(l) > 0.5:
                    rims[1.0 if l > 0 else -1.0] = (stringer, l)
            self.stringers += row
            self.rims.append(rims)
            count = max(2, round(flat(seg.b - seg.a).length / BOARD_PITCH))
            for k in range(count):
                s0, s1 = k / count, (k + 1) / count
                sm = (s0 + s1) * 0.5
                left, right = seg.point(sm, -1.0), seg.point(sm, 1.0)
                axis = (right - left).normalized()
                spacing = min(((seg.point(s1, l) - seg.point(s0, l)) - axis * (seg.point(s1, l) - seg.point(s0, l)).dot(axis)).length
                              for l in (-1.0, 0.0, 1.0))
                normal = seg.normal(sm)
                # Boards start a hair above the stringers: physics seats them.
                lift = rng.uniform(0.001, 0.005)
                width = spacing - BOARD_GAP - rng.uniform(0, 0.01)
                a = left - axis * (BOARD_OVERHANG + rng.uniform(-0.005, 0.005)) - normal * (BOARD_THICKNESS * 0.5 - lift)
                z = right + axis * (BOARD_OVERHANG + rng.uniform(-0.005, 0.005)) - normal * (BOARD_THICKNESS * 0.5 - lift)
                across = normal.cross(axis).normalized() * width * 0.5
                footprint = [[c.x, c.z] for c in (a - across, a + across, z + across, z - across)]
                if index in gone:
                    self.missing.append(footprint)
                    index += 1
                    continue
                # Ends are trimmed flush along the deck edge (plus overhang), so
                # skewed boards near bends never poke into the posts.
                cuts = []
                for side in (-1.0, 1.0):
                    tangent = flat(seg.along(side)).normalized()
                    out = Vector((-tangent.z, 0.0, tangent.x))
                    out *= 1 if out.dot(seg.ea * side) > 0 else -1
                    cuts.append((seg.point(sm, side) + out * (BOARD_OVERHANG + rng.uniform(-0.005, 0.005)), out))
                # No modelled bow or twist: the collision hull must hug the board;
                # its irregularity comes from the physics.
                board = piece(f'Board_{number}_{k}', lambda bl, a=a, z=z, width=width, normal=normal, cuts=cuts: shapes.plank(
                    bl, a - axis * 0.1, z + axis * 0.1, width, BOARD_THICKNESS, normal, rng, segment=0.5, bow=0.0, twist=0.0,
                    roughen=0.0, start_cut=cuts[0], end_cut=cuts[1]), a, z, normal)
                board['segment'] = number
                nails = [(rims[side][0], seg.point(sm, rims[side][1]) - normal * BOARD_THICKNESS) for side in (-1.0, 1.0)]
                self.boards.append((board, nails, footprint))
                index += 1
        self.build_rails(plan)
        self.build_straps()

    def build_rails(self, plan) -> None:
        rotten_post = plan.randrange(2, 40) if self.weak >= 0.2 and plan.random() < 0.6 else -1
        rotten_rail = (plan.randrange(2, 40), plan.choice([0, 1])) if self.weak >= 0.25 and plan.random() < 0.5 else (-1, 0)
        serial = 0
        for sign in (-1.0, 1.0):
            stations = []
            for index, seg in enumerate(self.segments):
                edge_length = flat(seg.point(1.0, sign) - seg.point(0.0, sign)).length
                parts = max(1, math.ceil(edge_length / POST_SPACING))
                for part in range(parts + (1 if index == len(self.segments) - 1 else 0)):
                    s = part / parts
                    tangent = flat(seg.along(sign)).normalized()
                    normal = Vector((-tangent.z, 0.0, tangent.x))
                    normal *= 1 if normal.dot(seg.ea * sign) > 0 else -1
                    clear = POST_GAP + POST * 0.5
                    interior = (part == 0 and index > 0) or (part == parts and index < len(self.segments) - 1)
                    if interior:
                        # Corner post on the miter, far enough out to clear both deck edges.
                        outward = ((seg.ea if part == 0 else seg.eb) * sign).normalized()
                        clear /= max(0.5, outward.dot(normal))
                    else:
                        # Route ends and mid-span posts stand square to their own edge.
                        outward = normal
                    stations.append((seg.point(s, sign) + outward * clear, outward, tangent, index))
            side_posts = []
            for k, (base, outward, tangent, index) in enumerate(stations):
                rng = core.rng(self.seed, self.rid, 'post', sign, k)
                bottom, top = base - UP * (self.bottom + 0.04), base + UP * (RAIL_TOP + 0.04)
                post = piece(f'Post_{int(sign)}_{k}', lambda bl, bottom=bottom, top=top, outward=outward: shapes.timber(
                    bl, bottom, top, POST, POST, outward, rng, segment=0.5, chamfer=0.02), bottom, top, outward)
                post['segment'] = index
                rotten = serial == rotten_post
                serial += 1
                self.posts.append((post, base, tangent, index, sign, rotten))
                side_posts.append((post, base, index))
                for height in (-0.14, -0.34):
                    bolt = base + UP * height + outward * (POST * 0.5 + 0.004)
                    self.straps.append((index, lambda bl, bolt=bolt, outward=outward, rng=rng: shapes.bar(
                        bl, bolt - outward * 0.006, bolt + outward * 0.012, 0.035, 0.035, UP, rng), post.name))
            tops = [base + UP * (RAIL_TOP - 0.045) for _, base, _ in side_posts]
            for k in range(len(tops) - 1):
                rng = core.rng(self.seed, self.rid, 'rail', sign, k)
                a, z = tops[k], tops[k + 1]
                here = (z - a).normalized()
                start_cut = (a, ((a - tops[k - 1]).normalized() + here).normalized()) if k > 0 else None
                end_cut = (z, (here + (tops[k + 2] - z).normalized()).normalized()) if k + 2 < len(tops) else None
                rail = piece(f'Rail_{int(sign)}_{k}', lambda bl, a=a, z=z, s=start_cut, e=end_cut: shapes.timber(
                    bl, a, z, 0.13, 0.09, UP, rng, segment=0.5, start_cut=s, end_cut=e, chamfer=0.018), a, z, UP)
                rail['segment'] = side_posts[k][2]
                failed = rotten_rail[1] if k == rotten_rail[0] else -1
                self.rails.append((rail, [(side_posts[k][0], a), (side_posts[k + 1][0], z)], failed))
            self.attachments.append([(post, base + UP * ROPE_HEIGHT, index) for post, base, index in side_posts])

    def build_straps(self) -> None:
        supported = [Vector(s['deck']) for s in self.route['supports']]
        for node, point in enumerate(self.points):
            if not any((point - s).length < 0.01 for s in supported):
                continue
            index = min(node, len(self.segments) - 1)
            rng = core.rng(self.seed, self.rid, 'strap', node)
            side = self.edges[node].normalized()
            along = side.cross(UP).normalized()
            half = self.edges[node].length
            for l in (-1.0 + RIM_WIDTH * 0.5 / half, -INNER_STRINGER, INNER_STRINGER, 1.0 - RIM_WIDTH * 0.5 / half):
                center = point + self.edges[node] * l
                for face in (-1.0, 1.0):
                    strap = center + along * face * (STRINGER_WIDTH * 0.5 + 0.006)
                    self.straps.append((index, lambda bl, strap=strap, along=along, face=face, rng=rng: shapes.bar(
                        bl, strap - UP * (self.bottom - 0.12), strap - UP * (self.seat + 0.16), 0.07, 0.01, along * face, rng), None))

    # -- physics -----------------------------------------------------------
    def simulate(self) -> dict:
        disturb.reset()
        # Offline: far finer steps and solving than a game would afford.
        rigid.world(frame_end=900, substeps=40, iterations=60)
        rng = core.rng(self.seed, self.rid, 'joints', self.weak, self.intensity)
        for stringer in self.stringers:
            # Hulls follow the mitered ends; boxes would overhang the node line.
            rigid.body(stringer, passive=True, shape='MESH', margin=0.0002)
        disturb.kinematic(self.stringers)
        low = min(b(p).z for p in self.points) - 6.0
        # Anything knocked off lands here and counts as fallen.
        catch = piece('Catch', lambda bl: shapes.prism(bl, Vector((0, low, -200)), Vector((0, low, 200)), 400.0, 0.4, UP, rng),
                      Vector((0, low, -200)), Vector((0, low, 200)), UP)
        rigid.body(catch, passive=True, shape='BOX')
        for board, nails, _ in self.boards:
            rigid.body(board, mass=rigid.mass(board, OAK), friction=0.9, shape='CONVEX_HULL', margin=0.0002)
            for rim, at in nails:
                disturb.nail(board, rim, b(at), disturb.strength(rng, self.weak, board))
        for post, base, tangent, index, sign, rotten in self.posts:
            rigid.body(post, mass=rigid.mass(post, OAK), friction=0.8, shape='CONVEX_HULL', margin=0.0002)
            rim = self.rims[index][sign][0]
            lean = rng.uniform(0.07, 0.16) if rotten else 0.015
            disturb.hinge(post, rim, b(base - UP * (self.bottom - 0.02)), b(tangent), (-lean, lean))
            if not rotten:
                disturb.nail(post, rim, b(base - UP * 0.2), disturb.strength(rng, self.weak * 0.5, post), collide=False)
        for number, (rail, ends, failed) in enumerate(self.rails):
            rigid.body(rail, mass=rigid.mass(rail, OAK), friction=0.6, shape='CONVEX_HULL', margin=0.0002)
            collide_alone(rail, number)
            for end, (post, at) in enumerate(ends):
                if end == failed:
                    continue
                disturb.pin(rail, post, b(at), disturb.strength(rng, self.weak * 0.3, rail, (6.0, 20.0)))
                # One nailed end stops the rail spinning; two would over-tie the post loop.
                if end == 0 or failed == 0:
                    disturb.nail(rail, post, b(at), disturb.strength(rng, self.weak, rail), collide=False)
        movers = [p[0] for p in self.boards] + [p[0] for p in self.posts] + [r[0] for r in self.rails]
        self.rest = disturb.rest_pose(movers)
        tremor = disturb.shake(self.stringers, rng, self.intensity) if self.intensity > 0 else None
        ball = None
        if self.ball:
            seg = self.segments[0] if self.points[0].y >= self.points[-1].y else self.segments[-1]
            start = seg.a if self.points[0].y >= self.points[-1].y else seg.b
            toward = (seg.b - seg.a).normalized() if start is seg.a else (seg.a - seg.b).normalized()
            ball = disturb.roll(b(start + toward * 1.2 + UP * 0.3), b(toward) * rng.uniform(2.0, 3.5))
        settled = rigid.settle(movers, threshold=0.005, min_frames=disturb.quiet_frame(), max_frames=900)
        self.movers = movers
        self.catch, self.ball_obj = catch, ball
        return {'tremor': tremor, 'ball': self.ball, 'settled': settled['settled'], 'frames': settled['frame'],
                'residual_speed_m_s': round(settled['residual_speed_m_s'], 4)}

    # -- measurement -------------------------------------------------------
    def measure(self) -> dict:
        moved = disturb.displacements(self.movers, self.rest)
        fallen = [o for o in self.movers if o.matrix_world.translation.z < self.rest[o.name].translation.z - 1.0]
        fallen_names = {o.name for o in fallen}
        for board, _, footprint in self.boards:
            if board.name in fallen_names:
                self.missing.append(footprint)
        boards = [p[0] for p in self.boards if p[0].name not in fallen_names]
        loose = [o for o in boards if moved[o.name][0] > 0.005 or moved[o.name][1] > 1.0]
        leaning = [p[0] for p in self.posts if moved[p[0].name][1] > 2.0 and p[0].name not in fallen_names]
        hanging = [r[0] for r in self.rails if moved[r[0].name][0] > 0.1]
        deviation, samples = self.lane_deviation(boards)
        blocked = self.lane_blocked([p[0] for p in self.posts] + [r[0] for r in self.rails], moved)
        return {'boards': len(self.boards), 'loose': len(loose), 'loose_share': round(len(loose) / max(len(self.boards), 1), 3),
                'missing': len(self.missing), 'fallen': len(fallen), 'leaning_posts': len(leaning), 'hanging_rails': len(hanging),
                'max_board_move_m': round(max((moved[o.name][0] for o in boards), default=0.0), 4),
                'max_post_lean_deg': round(max((moved[p[0].name][1] for p in self.posts), default=0.0), 2),
                'lane_max_deviation_m': round(deviation, 4), 'lane_samples': samples, 'lane_blocked': blocked}

    def inside_missing(self, point: Vector) -> bool:
        from mathutils.geometry import intersect_point_quad_2d
        q = Vector((point.x, point.z))
        return any(intersect_point_quad_2d(q, *(Vector(c) for c in quad)) for quad in self.missing)

    def lane_deviation(self, boards) -> tuple:
        verts, polys = [], []
        for obj in boards:
            base = len(verts)
            verts += [obj.matrix_world @ v.co for v in obj.data.vertices]
            polys += [[base + i for i in p.vertices] for p in obj.data.polygons]
        tree = BVHTree.FromPolygons(verts, polys)
        worst, samples = 0.0, 0
        for seg in self.segments:
            steps = max(2, int(flat(seg.b - seg.a).length / 0.4))
            for i in range(1, steps):
                s = i / steps
                half = seg.ea.lerp(seg.eb, s).length
                for offset in (-LANE, 0.0, LANE):
                    best = None
                    # Three rays 10 cm apart: at least one lands on a board, not a gap.
                    for shift in (0.0, 0.1, 0.2):
                        at = seg.point(min(1.0, s + shift / flat(seg.b - seg.a).length), offset / half)
                        if self.inside_missing(at):
                            continue
                        hit = tree.ray_cast(b(at) + Vector((0, 0, 0.5)), Vector((0, 0, -1)), 1.0)
                        if hit[0] is not None:
                            gap = abs(hit[0].z - b(at).z)
                            best = gap if best is None else min(best, gap)
                    if best is not None:
                        samples += 1
                        worst = max(worst, best)
        return worst, samples

    def lane_blocked(self, pieces, moved) -> int:
        """Moved posts or rails reaching into the walking corridor above the deck."""
        blocked = 0
        for obj in pieces:
            if moved[obj.name][0] < 0.02 and moved[obj.name][1] < 1.0:
                continue
            for v in list(obj.data.vertices)[::4]:
                g = Vector(core.to_godot(obj.matrix_world @ v.co))
                for seg in self.segments:
                    ab = flat(seg.b - seg.a)
                    t = max(0.0, min(1.0, flat(g - seg.a).dot(ab) / ab.length_squared))
                    centre = seg.a.lerp(seg.b, t)
                    if flat(g - centre).length < LANE + 0.4 and 0.05 < g.y - centre.y < 1.9:
                        blocked += 1
                        break
                else:
                    continue
                break
        return blocked

    # -- output ------------------------------------------------------------
    def finish(self) -> list:
        """Ropes from the posts' settled positions, then freeze, merge and name."""
        ropes = {}
        for side in self.attachments:
            for k in range(len(side) - 1):
                (post_a, at_a, index), (post_b, at_b, _) = side[k], side[k + 1]
                rng = core.rng(self.seed, self.rid, 'rope', post_a.name)
                a = post_a.matrix_world @ (self.rest[post_a.name].inverted() @ b(at_a))
                z = post_b.matrix_world @ (self.rest[post_b.name].inverted() @ b(at_b))
                if (a - b(at_a)).length > 0.5 or (z - b(at_b)).length > 0.5:
                    continue
                builder = ropes.setdefault(index, shapes.Builder(f'Rope_{index}'))
                # Ropes stretch unevenly: most hang taut, a few sag noticeably.
                slack = rng.choice([0.003, 0.005, 0.008, 0.012, 0.025])
                curves.tube(builder, curves.catenary(a, z, slack, 12), 0.022, sides=8, color=(1.0, rng.random(), 0.0, 1.0), twist=9.0)
        for obj in (self.catch, self.ball_obj):
            if obj is not None:
                bpy.data.objects.remove(obj, do_unlink=True)
        fallen = {o.name for o in self.movers if o.matrix_world.translation.z < self.rest[o.name].translation.z - 1.0}
        kept = [o for o in self.movers if o.name not in fallen] + self.stringers
        for obj in [o for o in self.movers if o.name in fallen]:
            bpy.data.objects.remove(obj, do_unlink=True)
        matrices = {o.name: o.matrix_world.copy() for o in kept}
        if bpy.context.scene.rigidbody_world is not None:
            bpy.ops.rigidbody.world_remove()
        for obj in list(bpy.data.objects):
            if obj.type == 'EMPTY':
                bpy.data.objects.remove(obj, do_unlink=True)
        for obj in kept:
            obj.animation_data_clear()
            obj.data.transform(matrices[obj.name])
            obj.matrix_world = Matrix.Identity(4)
        groups = {}
        for obj in kept:
            groups.setdefault(('Wood', obj['segment']), []).append(obj)
        irons = {}
        for index, build, post in self.straps:
            if post is not None and post not in matrices:
                continue
            builder = shapes.Builder(f'Iron_{index}')
            build(builder)
            obj = builder.to_object()
            obj.data.transform(GODOT_TO_BLENDER)
            if post is not None:
                # Bolt heads ride on their post when it leans.
                obj.data.transform(matrices[post] @ self.rest[post].inverted())
            irons.setdefault(index, []).append(obj)
        result = []
        for (kind, index), objects in sorted(groups.items()):
            result.append(join(objects, f'{kind}_{index}'))
        for index, objects in sorted(irons.items()):
            result.append(join(objects, f'Iron_{index}'))
        for index, builder in sorted(ropes.items()):
            result.append(builder.to_object(smooth_angle=180.0))
        for obj in result:
            obj['layout_hash'] = self.route['layout_hash']
            obj['route'] = self.rid
        return result

    def transom_proxies(self) -> list:
        objects = []
        for node, point in enumerate(self.points):
            if not any((point - Vector(s['deck'])).length < 0.01 for s in self.route['supports']):
                continue
            seat = point - UP * self.seat
            side = self.edges[node].normalized()
            half = self.edges[node].length
            obj = piece('TransomProxy', lambda bl: shapes.prism(bl, seat - side * (half + 0.25), seat + side * (half + 0.25), 0.40, 0.44, UP,
                                                                core.rng(0, 'proxy'), chamfer=0.01, wear=0.0, segment=1.0),
                        seat - side * (half + 0.25), seat + side * (half + 0.25), UP)
            objects.append(obj)
        return objects


def join(objects, name: str) -> bpy.types.Object:
    core.select_only(objects)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def classify(m: dict) -> tuple:
    """Class and score: prefer visibly aged but safe and walkable."""
    if m['lane_max_deviation_m'] > LANE_TOLERANCE or m['lane_blocked'] or m['fallen'] > 3:
        return 'unwalkable', -100.0
    if m['loose_share'] < 0.02 and not (m['leaning_posts'] or m['hanging_rails'] or m['missing']):
        return 'untouched', 0.0
    if m['loose_share'] > 0.35 or m['hanging_rails'] > 3 or m['leaning_posts'] > 4:
        return 'collapsed', -50.0
    if m['loose_share'] <= 0.16 and m['leaning_posts'] <= 2 and m['hanging_rails'] <= 1:
        score = 10.0 - abs(m['loose_share'] - 0.08) * 60 - abs(m['leaning_posts'] - 1) - abs(m['hanging_rails'] - 0.5) * 2 - abs(m['missing'] - 1)
        return 'aged', round(score, 3)
    return 'damaged', round(-10.0 - m['loose_share'] * 20, 3)


def preview_materials(objects) -> None:
    for obj in objects:
        material = bpy.data.materials.get('Preview' + obj.name[:4]) or bpy.data.materials.new('Preview' + obj.name[:4])
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        tone = {'Wood': (0.33, 0.22, 0.13), 'Iron': (0.08, 0.08, 0.085), 'Rope': (0.36, 0.29, 0.2)}.get(obj.name[:4], (0.3, 0.3, 0.3))
        if not any(n.type == 'ATTRIBUTE' for n in nodes):
            source = nodes.new('ShaderNodeAttribute')
            source.attribute_name = 'Color'
            mix = nodes.new('ShaderNodeVectorMath')
            mix.operation = 'MULTIPLY'
            mix.inputs[1].default_value = tone
            links.new(source.outputs['Color'], mix.inputs[0])
            links.new(mix.outputs['Vector'], shader.inputs['Base Color'])
        obj.data.materials.clear()
        obj.data.materials.append(material)


def views(points) -> list:
    """Two review cameras per route in Blender space: a broadside and a deck view."""
    pts = [b(p) for p in points]
    middle = sum(pts, Vector()) / len(pts)
    span = (pts[-1] - pts[0])
    span.z = 0
    side = Vector((-span.y, span.x, 0)).normalized()
    quarter = pts[len(pts) // 3]
    return [(middle + side * span.length * 0.55 + Vector((0, 0, 5.0)), middle - Vector((0, 0, 1.0))),
            (quarter + Vector((0, 0, 1.7)) - (pts[len(pts) // 3 + 1] - quarter).normalized() * 0.5, pts[len(pts) // 3 + 1] + Vector((0, 0, 0.6)))]


def run_attempt(route: dict, layout: dict, options: dict, number: int, setting: tuple) -> tuple:
    """Build, disturb and measure one attempt; optionally render its review views."""
    core.empty_scene()
    bridge = Bridge(route, layout, options['seed'] + number, setting)
    bridge.build()
    physics = bridge.simulate()
    metrics = bridge.measure()
    kind, score = classify(metrics)
    attempt = {'attempt': number, 'intensity': setting[0], 'weak_share': setting[1], 'class': kind, 'score': score,
               **metrics, **{k: v for k, v in physics.items() if k != 'tremor'}, 'tremor': physics['tremor']}
    print('BRIDGE_ATTEMPT', route['id'], json.dumps({k: attempt[k] for k in ('attempt', 'class', 'score', 'loose', 'missing', 'leaning_posts',
                                                                             'hanging_rails', 'lane_max_deviation_m', 'frames')}), flush=True)
    images = []
    if options['review']:
        objects = bridge.finish()
        preview_materials(objects)
        images = [disturb.render(eye, target, samples=12) for eye, target in views(bridge.points)]
    return attempt, images


def assemble(route: dict, layout: dict, layout_path: Path, out: Path, options: dict, settings: list, attempts: list, sheet: list) -> None:
    """Rebuild the chosen attempt deterministically, bake AO, export and report."""
    rid = route['id']
    if rid in options['pick']:
        chosen = options['pick'][rid]
    else:
        chosen = max(attempts, key=lambda a: ({'aged': 3, 'damaged': 2, 'untouched': 1}.get(a['class'], 0), a['score']))['attempt']
    core.empty_scene()
    bridge = Bridge(route, layout, options['seed'] + chosen, settings[chosen])
    bridge.build()
    bridge.simulate()
    final = bridge.measure()
    objects = bridge.finish()
    occluders = bridge.transom_proxies()
    ao = bake.ao_to_color(objects, samples=options['samples'], distance=0.6)
    for obj in occluders:
        bpy.data.objects.remove(obj, do_unlink=True)
    path = export.glb(objects, out / (rid + '.glb'))
    if options['review'] and sheet and all(sheet):
        rows = [numpy.concatenate([disturb.frame_border(view, i == chosen) for view in row], axis=1) for i, row in enumerate(sheet)]
        disturb.write_png(options['review'] / f'{rid}_attempts.png', numpy.concatenate(rows, axis=0))
    data = {'method': 'deck follows the walking ribbon; every board, post and rail a rigid body with nails, hinges and pins of '
                      'random strength; seeded tremor and rolling-ball attempts; most believable walkable attempt kept; Cycles AO in Color.R',
            'layout_source': core.relative(layout_path), 'seed': options['seed'], 'samples': options['samples'],
            'seat_depth': layout['baked_seat_depth'], 'stringer_bottom': layout['baked_stringer_bottom'],
            'layout_hash': route['layout_hash'], 'chosen_attempt': chosen, 'picked_by': 'flag' if rid in options['pick'] else 'score',
            'final': final, 'missing_boards_godot_xz': bridge.missing, 'attempts': attempts, 'ao': ao,
            'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects), 'objects': len(objects)}
    core.write_report(out / (rid + '.json'), data, [path])
    print('BRIDGE_BAKE_OK', rid, json.dumps({'chosen': chosen, 'class': attempts[chosen]['class'], 'triangles': data['triangles']}), flush=True)


def main():
    layout_path, out, options = parse()
    layout = json.loads(layout_path.read_text())
    out.mkdir(parents=True, exist_ok=True)
    settings = [(0.0, 0.0, False)] if options['ideal'] else ATTEMPTS[:options['attempts']]
    work = options['work']
    for route in layout['routes']:
        if not route['wood'] or route['enclosed'] or (options['routes'] and route['id'] not in options['routes']):
            continue
        rid = route['id']
        if options['only'] is not None:
            # One attempt per process (scripts/art/bake_bridges.py runs them in parallel).
            attempt, images = run_attempt(route, layout, options, options['only'], settings[options['only']])
            work.mkdir(parents=True, exist_ok=True)
            (work / f'{rid}_{options["only"]}.json').write_text(json.dumps(attempt))
            for k, image in enumerate(images):
                numpy.save(work / f'{rid}_{options["only"]}_view{k}.npy', image)
            continue
        if options['assemble']:
            attempts = [json.loads((work / f'{rid}_{n}.json').read_text()) for n in range(len(settings))]
            sheet = [[numpy.load(f) for f in sorted(work.glob(f'{rid}_{n}_view*.npy'))] for n in range(len(settings))]
        else:
            attempts, sheet = [], []
            for number, setting in enumerate(settings):
                attempt, images = run_attempt(route, layout, options, number, setting)
                attempts.append(attempt)
                sheet.append(images)
        assemble(route, layout, layout_path, out, options, settings, attempts, sheet)


if __name__ == '__main__':
    main()
