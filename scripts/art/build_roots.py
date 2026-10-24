"""Blender background: dark red roots and veins grown over Red Descent's stone rooms.

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_roots.py -- \
        [--arch content/environments/procedural_architecture_v1] \
        [--layout content/environments/procedural_bridge_v1/layout.json] \
        [--out content/environments/procedural_roots_v1] [--rooms entry,antechamber] \
        [--seed 178] [--budget 15000] [--headroom 2.7] [--samples 96] [--no-render]

For every room in <arch>/index.json "rooms" (or --rooms): import the room's
stone build (Stone_*, Mortar_*; Collision_* dropped) and the passages that
touch it, add floor and ceiling planes where the game has them, and grow
roots over that geometry with procgen.roots:

- trunks (8-15 cm across) leave joints high on the walls or the wall head
  under the ceiling, run down the stone and fan out over the floor;
- medium roots and thin vein clusters (down to 5 mm) from upper joints;
- at every doorway, a root from the arch crown along the soffit, sagging
  loops under the arch and across the opening, and short hanging tendrils.

Nothing grows within a route's width / 2 + 0.3 m between ankle height (3 cm
above the walking surface) and --headroom, so walking routes stay clear.

Output per room: <out>/<id>.glb (Roots_<id>_<group> meshes, Color = grey:
baked AO against the stone times a per-root tone 0.75-1.15, UV u along the
root in metres; no collision), <out>/<id>.json (report with triangle and
root counts, seed, source hashes, cling and penetration checks) and Cycles
review renders under torch light in <out>/review/<id>_<n>_<view>.png.
"""
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Vector

from procgen import bake, core, export, roots
from procgen.shapes import Builder

THICKNESS = 0.9        # room walls, centred on the layout outline
ROCK = core.ROOT / 'content/environments/dungeon_pbr_v2/marble_rock_03'


def parse():
    values = core.args()
    options = {'arch': core.ROOT / 'content/environments/procedural_architecture_v1',
               'layout': core.ROOT / 'content/environments/procedural_bridge_v1/layout.json',
               'out': core.ROOT / 'content/environments/procedural_roots_v1',
               'rooms': None, 'passages': None, 'seed': 178, 'budget': 15000, 'headroom': 2.7, 'samples': 96,
               'render': True}
    i = 0
    while i < len(values):
        key = values[i]
        if key in ('--arch', '--layout', '--out'):
            options[key[2:]] = Path(values[i + 1]).resolve(); i += 2
        elif key == '--rooms':
            options['rooms'] = [v for v in values[i + 1].split(',') if v]; i += 2
        elif key == '--passages':
            options['passages'] = [v for v in values[i + 1].split(',') if v]; i += 2
        elif key in ('--seed', '--budget', '--samples'):
            options[key[2:]] = int(values[i + 1]); i += 2
        elif key == '--headroom':
            options['headroom'] = float(values[i + 1]); i += 2
        elif key == '--no-render':
            options['render'] = False; i += 1
        else:
            raise SystemExit(f'build_roots: unknown argument {key}')
    return options


def plan(points: list) -> list:
    """Godot (x, z) outline -> Blender plan, counter-clockwise."""
    pts = [Vector((p[0], -p[1], 0.0)) for p in points]
    area = sum(a.x * b.y - b.x * a.y for a, b in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else list(reversed(pts))


def outset(points: list, distance: float) -> list:
    lines = []
    for a, b in zip(points, points[1:] + points[:1]):
        d = (b - a).normalized()
        lines.append((a + Vector((d.y, -d.x, 0.0)) * distance, d))
    result = []
    for (p1, d1), (p2, d2) in zip(lines[-1:] + lines[:-1], lines):
        denom = d1.x * d2.y - d1.y * d2.x
        t = ((p2 - p1).x * d2.y - (p2 - p1).y * d2.x) / denom
        result.append(p1 + d1 * t)
    return result


def polygon_object(name: str, points: list, z: float, down: bool = False) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    verts = [(p.x, p.y, z) for p in points]
    face = list(range(len(points)))
    mesh.from_pydata(verts, [], [list(reversed(face)) if down else face])
    mesh.update()
    return core.link(bpy.data.objects.new(name, mesh))


def load_room(options: dict, room: dict, index: dict) -> dict:
    """Stone, mortar and touching passages as world-space objects, plus floor
    and ceiling planes like the game's (flagstones at floor, slab at height)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(options['arch'] / 'rooms' / f'{room["id"]}.glb'))
    room_objects = sorted(set(bpy.data.objects) - before, key=lambda o: o.name)
    outline = plan(room['points'])
    grown = outset(outline, THICKNESS + 1.0)
    lo = Vector((min(p.x for p in grown), min(p.y for p in grown)))
    hi = Vector((max(p.x for p in grown), max(p.y for p in grown)))
    passages, sources = [], [options['arch'] / 'rooms' / f'{room["id"]}.glb']
    # index.json lists passage GLBs under "files" (one per route, one per bay or
    # portal); older indexes listed them per stretch under "passages".
    for entry in index.get('files') or index.get('passages', []):
        path = options['arch'] / entry['file']
        if not path.exists():
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(path))
        new = sorted(set(bpy.data.objects) - before, key=lambda o: o.name)
        corners = [o.matrix_world @ Vector(c) for o in new if o.type == 'MESH' for c in o.bound_box]
        touches = corners and not (max(c.x for c in corners) < lo.x or min(c.x for c in corners) > hi.x or
                                   max(c.y for c in corners) < lo.y or min(c.y for c in corners) > hi.y or
                                   min(c.z for c in corners) > room['floor'] + room['height'] or
                                   max(c.z for c in corners) < room['floor'] - 0.5)
        if touches:
            passages += new
            sources.append(path)
        else:
            for obj in new:
                bpy.data.objects.remove(obj, do_unlink=True)
    stone, mortar = [], []
    for obj in room_objects + passages:
        if obj.type != 'MESH' or obj.name.startswith('Collision') or obj.name.endswith('colonly'):
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        (mortar if obj.name.startswith('Mortar') else stone).append(obj)
    floor = polygon_object('ProxyFloor', outset(outline, 2.0), room['floor'])
    ceiling = polygon_object('ProxyCeiling', outset(outline, 2.0), room['floor'] + room['height'], down=True)
    return {'stone': stone, 'mortar': mortar, 'floor': floor, 'ceiling': ceiling,
            'outline': outline, 'sources': sources}


class Walls:
    """The room's wall faces (inner face of each outline edge) and doorways."""

    def __init__(self, surface: roots.Surface, room: dict, outline: list):
        self.surface, self.room = surface, room
        self.floor, self.top = room['floor'], room['floor'] + room['height']
        self.walls = []
        for a, b in zip(outline, outline[1:] + outline[:1]):
            d = (b - a).normalized()
            inward = Vector((-d.y, d.x, 0.0))
            self.walls.append({'a': a, 'b': b, 'along': d, 'inward': inward, 'length': (b - a).length})
        self.openings = []
        for w, wall in enumerate(self.walls):
            run = []
            steps = max(2, int(wall['length'] / 0.1))
            for k in range(steps + 1):
                t = k / steps
                hit = self.face(w, t, self.floor + 1.3, reach=0.3)
                open_ = hit is None
                if open_:
                    run.append(t)
                if (not open_ or k == steps) and run:
                    width = (run[-1] - run[0]) * wall['length']
                    if width > 1.0:
                        self.openings.append(self.doorway(w, run[0], run[-1]))
                    run = []

    def face(self, w: int, t: float, z: float, depth: float = 1.2, reach: float = THICKNESS + 0.15):
        """Ray from inside the room onto wall w at (t, z): (loc, normal, kind) or
        None. `reach` is how far behind the inner face a hit still counts."""
        wall = self.walls[w]
        base = wall['a'].lerp(wall['b'], t)
        origin = Vector((base.x, base.y, z)) + wall['inward'] * (THICKNESS * 0.5 + depth)
        hit = self.surface.cast(origin, -wall['inward'], depth + reach)
        if hit is None:
            return None
        loc, normal, index, dist = hit
        normal = normal.normalized()
        if normal.dot(wall['inward']) < 0:
            normal = -normal
        return loc, normal, self.surface.kind(index)

    def doorway(self, w: int, t0: float, t1: float) -> dict:
        wall = self.walls[w]
        tc = (t0 + t1) * 0.5
        centre = wall['a'].lerp(wall['b'], tc)
        crown = None
        for depth in (0.0, 0.2, -0.2):
            origin = Vector((centre.x, centre.y, self.floor + 1.3)) + wall['inward'] * depth
            hit = self.surface.cast(origin, Vector((0, 0, 1)), self.room['height'] + 1.0)
            if hit is not None and hit[0].z < self.top - 0.05:
                crown = hit[0].z if crown is None else max(crown, hit[0].z)
        spring = None
        for t in (t0 + 0.02, t1 - 0.02):
            base = wall['a'].lerp(wall['b'], t)
            hit = self.surface.cast(Vector((base.x, base.y, self.floor + 1.3)), Vector((0, 0, 1)), self.room['height'])
            if hit is not None:
                spring = hit[0].z if spring is None else min(spring, hit[0].z)
        crown = crown if crown is not None else self.top
        print('DOORWAY', self.room['id'], w, f'{(t1 - t0) * wall["length"]:.2f} m', f'crown {crown - self.floor:.2f}',
              f'spring {(spring or crown) - self.floor:.2f}', flush=True)
        return {'wall': w, 't0': t0, 't1': t1, 'tc': tc, 'crown': crown, 'spring': spring or crown,
                'width': (t1 - t0) * wall['length']}

    def point(self, w: int, t: float) -> Vector:
        wall = self.walls[w]
        return wall['a'].lerp(wall['b'], t)


class Grower:
    """Seeds, grows and keeps the root systems of one room."""

    def __init__(self, surface, rules, walls: Walls, rng, room: dict, headroom: float):
        self.surface, self.rules, self.walls, self.rng, self.room = surface, rules, walls, rng, room
        self.headroom = headroom
        self.occupancy = roots.Occupancy()
        self.systems = []     # (trunk Root, r0, gamma, group)
        self.used = []        # seed points, to keep systems apart
        self.floor = room['floor']
        self.top = room['floor'] + room['height']
        self.seed_base = 0

    # -- seeds ---------------------------------------------------------------
    def free(self, p: Vector, spacing: float) -> bool:
        return all((p - q).length > spacing for q in self.used)

    def seed(self, w: int, t: float, z: float, want_joint: bool, tries: int = 40, spacing: float = 0.6):
        """A start on wall w near (t, z): a mortar joint when asked, else stone."""
        rng = self.rng
        wall = self.walls.walls[w]
        best = None
        for attempt in range(tries):
            tt = min(0.97, max(0.03, t + rng.gauss(0.0, 0.25 / wall['length']) * (1 + attempt * 0.1)))
            zz = min(self.top - 0.04, z + rng.gauss(0.0, 0.08) * (1 + attempt * 0.1))
            hit = self.walls.face(w, tt, zz)
            if hit is None:
                continue
            loc, normal, kind = hit
            if abs(normal.z) > 0.5 or not self.free(loc, spacing):
                continue
            if not want_joint or kind == 'mortar':
                return hit
            best = best or hit
        return best

    def start_root(self, kind: str, system: int, tone: float, hit, r0: float, heading: Vector, length: float,
                   from_top: bool = False, gravity: float = None, target: Vector = None) -> roots.Root:
        loc, normal, _ = hit
        root = roots.Root(kind, system, tone)
        root.buried = True
        root.twist = self.rng.uniform(1.5, 4.0) * self.rng.choice((-1, 1))
        off = roots.standoff(r0, root.flat)
        start = loc + normal * off
        if from_top:
            buried = Vector((start.x, start.y, self.top + 0.06))
        else:
            buried = loc - normal * (r0 * 0.8 + 0.01)
        L = max(length, 0.5)
        radius_at = (lambda s: max(roots.TIP, r0 * (1.0 - 0.55 * min(s / L, 1.0))))
        root.stop = roots.crawl(self.surface, self.rules, self.occupancy, root, start, normal, heading, length, radius_at,
                                self.rng, target=target, gravity=gravity)
        self.dive(root, root.stop, radius_at(root.length()))
        root.points.insert(0, buried)
        root.normals.insert(0, normal.copy())
        for name in ('floor_index', 'soffit_index'):
            if getattr(root, name) is not None:
                setattr(root, name, getattr(root, name) + 1)
        return root, radius_at

    # -- growth --------------------------------------------------------------
    CAP = {'trunk': (7.0, 11.0), 'branch': (2.5, 5.0), 'vein': (0.8, 2.4)}  # metres of root per system

    def branch(self, trunk: roots.Root, trunk_radius, cap: float) -> None:
        """Children breadth first (every parent gets its first children before
        any grandchildren), a fan where a root reaches the floor, a tendril
        where one turns under a soffit; stops at `cap` metres for the system."""
        rng = self.rng
        total = trunk.length()
        queue = [(trunk, trunk_radius, 0)]
        while queue:
            parent, parent_radius, depth = queue.pop(0)
            kind = roots.KINDS[parent.kind]
            arc = parent.arc()
            if parent.soffit_index is not None and rng.random() < 0.6:
                self.tendril(parent, parent.soffit_index)
            if len(parent.points) < 3 or depth > 3 or (parent.kind == 'vein' and (depth > 2 or arc[-1] < 0.5)):
                continue
            s = rng.uniform(*kind['every']) * 0.6 + 0.15
            plans = []
            while s < arc[-1] - 0.12:
                plans.append((s, None))
                s += rng.uniform(*kind['every'])
            for _ in range(getattr(parent, 'fan', 0)):
                plans.append((rng.uniform(0.2, 0.9), 'fork'))
            if parent.floor_index is not None and parent.kind in ('trunk', 'branch'):
                at = arc[parent.floor_index]
                for _ in range(rng.randint(1, 3) if parent.kind == 'trunk' else rng.randint(0, 1)):
                    plans.append((at + rng.uniform(0.0, 0.1), None))
            for at, forced in sorted(plans, key=lambda p: p[0]):
                if total > cap and forced is None:
                    return
                i = min(range(len(arc)), key=lambda k: abs(arc[k] - at))
                if i < 1 or i >= len(parent.points) - 1 or parent.normals[i] is None:
                    continue
                names, weights = zip(*kind['children'])
                child_kind = forced or rng.choices(names, weights)[0]
                fork = child_kind == 'fork'
                r_parent = parent_radius(arc[i])
                on_floor = parent.normals[i].z > 0.85
                if fork:
                    # A near-even split: the root divides and both halves run on.
                    child_kind = 'trunk' if r_parent > 0.035 else 'branch'
                    ratio = rng.uniform(0.6, 0.85)
                else:
                    ratio = rng.uniform(0.4, 0.65) if child_kind == 'branch' else rng.uniform(0.15, 0.35)
                if on_floor:
                    ratio *= 0.7
                limit = {'trunk': 0.06, 'branch': 0.03, 'vein': 0.009}[child_kind]
                r_child = max(roots.TIP * 1.5, min(r_parent * ratio, limit))
                n = parent.normals[i]
                heading = roots.unit(parent.points[min(i + 1, len(parent.points) - 1)] - parent.points[i - 1], roots.DOWN)
                angle = rng.uniform(0.25, 0.55) if fork else rng.uniform(*kind['angle'])
                heading = roots.turn(roots.tangent(heading, n), n, angle * rng.choice((-1, 1)))
                if fork:
                    length = self.room['height'] * 1.5 if child_kind == 'trunk' else rng.uniform(1.2, 2.8)
                elif child_kind == 'branch':
                    length = rng.uniform(0.6, 1.8) if not on_floor else rng.uniform(0.6, 1.6)
                else:
                    length = rng.uniform(0.2, 0.8) if not on_floor else rng.uniform(0.3, 0.9)
                child = roots.Root(child_kind, parent.system, self.tone(parent.tone, 0.06), parent, arc[i])
                child.twist = parent.twist * rng.uniform(0.8, 1.3)
                child.group = parent.group
                radius_at = (lambda s, r=r_child, L=length: max(roots.TIP, r * (1.0 - 0.6 * min(s / L, 1.0))))
                reason = roots.crawl(self.surface, self.rules, self.occupancy, child, parent.points[i], n, heading, length,
                                     radius_at, rng)
                if len(child.points) < 4:
                    continue
                self.dive(child, reason, radius_at(child.length()))
                parent.children.append(child)
                self.occupancy.add(child, radius_at)
                total += child.length()
                queue.append((child, radius_at, depth + 1))

    def dive(self, root: roots.Root, reason: str, r: float) -> None:
        """A thick root that stops on the wall goes back into the masonry at
        the nearest joint (within the last 25 cm) instead of ending in a tip."""
        if reason in ('floor', 'target') or len(root.points) < 6 or r < 0.012 or root.normals[-1] is None:
            return
        if root.normals[-1].z > 0.6:
            return  # on the floor a root tapers out
        arc = root.arc()
        best = None
        for i in range(len(root.points) - 1, 1, -1):
            if arc[-1] - arc[i] > 0.25:
                break
            n = root.normals[i]
            if n is None or n.z > 0.6:
                continue
            hit = self.surface.cast(root.points[i], -n, 0.3)
            if hit is not None and self.surface.kind(hit[2]) == 'mortar':
                best = i
                break
        if best is not None:
            del root.points[best + 1:]
            del root.normals[best + 1:]
        n = root.normals[-1]
        root.points.append(root.points[-1] - n * (r * 2.5 + 0.02) + (root.points[-1] - root.points[-2]).normalized() * r)
        root.normals.append(n.copy())
        root.dived = True

    def tendril(self, parent: roots.Root, i: int, length: float = None) -> None:
        """A small bunch (1-3) of thin rootlets hanging free from parent point i."""
        rng = self.rng
        if i >= len(parent.points) or parent.normals[i] is None:
            return
        arc = parent.arc()
        for k in range(rng.randint(1, 3)):
            j = min(len(parent.points) - 1, max(1, i + rng.randint(-2, 2)))
            if parent.normals[j] is None:
                continue
            child = roots.Root('vein', parent.system, self.tone(parent.tone, 0.05), parent, arc[j])
            child.group = parent.group
            child.twist = parent.twist
            r = rng.uniform(0.003, 0.006)
            child.profile = (lambda s, L, r=r: roots.TIP + (r - roots.TIP) * max(0.0, 1.0 - s / max(L, 1e-6)) ** 0.6)
            span = (length or rng.uniform(0.25, 0.8)) * rng.uniform(0.6, 1.0)
            roots.hang(self.surface, self.rules, child, parent.points[j], span, r, rng)
            if len(child.points) >= 4:
                parent.children.append(child)

    def tone(self, base: float, spread: float) -> float:
        return min(1.15, max(0.75, base + self.rng.uniform(-spread, spread)))

    def system(self, kind: str, hit, r0: float, heading: Vector, length: float, group: int,
               from_top: bool = False, gamma: float = None, cap: float = None, gravity: float = None,
               fan: int = 0) -> bool:
        rng = self.rng
        number = len(self.systems)
        tone = rng.uniform(0.75, 1.15)
        trunk, radius_at = self.start_root(kind, number, tone, hit, r0, heading, length, from_top, gravity=gravity)
        if len(trunk.points) < 6:
            return False
        trunk.group = group
        trunk.fan = fan
        self.occupancy.add(trunk, radius_at)
        self.branch(trunk, radius_at, cap or rng.uniform(*self.CAP[kind]))
        self.used.append(hit[0])
        if gamma is None:
            gamma = {'trunk': (0.22, 0.32), 'branch': (0.35, 0.5)}.get(kind, (0.45, 0.6))
            gamma = rng.uniform(*gamma)
        self.systems.append((trunk, r0, gamma, group))
        print('SYSTEM', number, kind, f'r0 {r0 * 100:.1f} cm', trunk.stop, f'z {trunk.points[1].z - self.floor:.1f}->{trunk.points[-1].z - self.floor:.1f}',
              f'{trunk.length():.1f}/{sum(r.length() for r in trunk.walk()):.1f} m',
              f'{sum(1 for _ in trunk.walk())} roots', flush=True)
        return True

    def soffit(self, door: dict, u: float, depth: float):
        """Point under the doorway arch: u across the opening (-1..1), depth into
        the reveal from the room-side face. (loc, downward normal) or None."""
        wall = self.walls.walls[door['wall']]
        base = self.walls.point(door['wall'], door['tc'] + u * door['width'] * 0.5 / wall['length'])
        origin = Vector((base.x, base.y, self.floor + 1.3)) + wall['inward'] * (THICKNESS * 0.5 - depth)
        hit = self.surface.cast(origin, Vector((0, 0, 1)), self.room['height'])
        if hit is None or hit[0].z > self.top - 0.05:
            return None
        n = hit[1].normalized()
        return hit[0], (n if n.z < 0 else -n)

    def loop(self, door: dict, under: bool, group: int) -> bool:
        """A root that clings, sags free in a catenary, then clings again.
        Under the arch it leaves a joint near the crown, runs along the soffit,
        drops into a loop and catches the soffit again further down; across
        the opening it comes down the wall beside the arch, swings across in
        front of it and runs on down the far side."""
        rng = self.rng
        wall = self.walls.walls[door['wall']]
        lowest = self.floor + self.headroom + 0.12
        r = rng.uniform(0.016, 0.032)
        flat = roots.KINDS['loop']['flat']
        off = roots.standoff(r, flat)
        side = rng.choice((-1, 1))
        if under:
            depth = rng.uniform(0.12, THICKNESS - 0.12)
            seed = self.soffit(door, rng.uniform(-0.2, 0.2), depth)
            a_hit = self.soffit(door, side * rng.uniform(0.15, 0.45), depth + rng.uniform(-0.1, 0.1))
            b_hit = self.soffit(door, -side * rng.uniform(0.35, 0.8), depth + rng.uniform(-0.15, 0.15))
            if seed is None or a_hit is None or b_hit is None:
                return False
            seed = (seed[0], seed[1], 'mortar')
        else:
            ts = (door['t0'], door['t1']) if side < 0 else (door['t1'], door['t0'])
            sign = (-1, 1) if side < 0 else (1, -1)
            z_a = rng.uniform(lowest + 0.45, min(self.top - 0.3, door['crown'] + 0.4))
            z_b = min(self.top - 0.3, max(lowest + 0.35, z_a + rng.uniform(-0.5, 0.3)))
            a_hit = self.walls.face(door['wall'], ts[0] + sign[0] * rng.uniform(0.1, 0.45) / wall['length'], z_a)
            b_hit = self.walls.face(door['wall'], ts[1] + sign[1] * rng.uniform(0.1, 0.45) / wall['length'], z_b)
            if a_hit is None or b_hit is None or abs(a_hit[1].z) > 0.4 or abs(b_hit[1].z) > 0.4:
                return False
            seed = self.seed(door['wall'], ts[0] + sign[0] * rng.uniform(0.1, 0.6) / wall['length'],
                             min(self.top - 0.05, z_a + rng.uniform(0.7, 1.6)), True, tries=20, spacing=0.2)
            if seed is None or seed[0].z < a_hit[0].z + 0.3:
                return False
        bow = None if under else wall['inward'] * rng.uniform(0.07, 0.16)
        return self.hang_loop(seed, a_hit, b_hit, r, group, 'under' if under else 'across', bow)

    def hang_loop(self, seed, a_hit, b_hit, r: float, group: int, label: str, bow: Vector = None) -> bool:
        """Crawl from `seed` (a joint) to a_hit, hang in a catenary to b_hit
        (lowest point above headroom, clear of the stone), cling on from b_hit
        with gravity. Hits are (location, outward normal[, kind])."""
        rng = self.rng
        lowest = self.floor + self.headroom + 0.12
        flat = roots.KINDS['loop']['flat']
        off = roots.standoff(r, flat)
        a = a_hit[0] + a_hit[1] * (off + 0.006)
        b = b_hit[0] + b_hit[1] * (off + 0.006)
        chord = (b - a).length
        if chord < 0.8:
            return False
        slack = rng.uniform(0.06, 0.22)
        for _ in range(14):
            points = roots.catenary_between(a, b, slack, max(12, int(chord / 0.1)))
            if bow is not None:
                # Draped over the proud arch stones: bowed off the wall in the middle.
                count = len(points) - 1
                points = [p + bow * max(0.0, math.sin(math.pi * min(k / count, 1.0))) ** 0.7 for k, p in enumerate(points)]
            if min(p.z for p in points) >= lowest and not any(self.surface.blocked(p, q) for p, q in zip(points, points[1:])):
                break
            slack *= 0.7
        else:
            return False
        number = len(self.systems)
        tone = rng.uniform(0.75, 1.15)
        constant = (lambda s: r)
        approach = roots.Root('loop', number, tone)
        start = seed[0] + seed[1] * off
        roots.crawl(self.surface, self.rules, None, approach, start, seed[1], a - start, 6.0, constant, rng,
                    target=a_hit[0] + a_hit[1] * off, gravity=1.2)
        if len(approach.points) < 3 or (approach.points[-1] - a).length > 0.2:
            return False
        tail = roots.Root('loop', number, tone)
        roots.crawl(self.surface, self.rules, None, tail, b_hit[0] + b_hit[1] * off, b_hit[1], b - a,
                    rng.uniform(0.6, 2.0), constant, rng, gravity=2.5)
        if len(tail.points) < 3:
            return False
        root = roots.Root('loop', number, tone)
        root.twist = rng.uniform(2.0, 5.0) * rng.choice((-1, 1))
        root.group = group
        root.points = [seed[0] - seed[1] * (r + 0.01)] + approach.points + points[1:-1] + tail.points
        root.normals = [seed[1]] + approach.normals + [None] * (len(points) - 2) + tail.normals
        root.buried = True
        hanging = [p for p, n in zip(root.points, root.normals) if n is None]
        if any(not self.rules.allowed(p, r * 1.5 + 0.02) for p in hanging):
            return False
        sag_from = len(approach.points) + 1
        root.profile = (lambda s, L, r=r: roots.TIP + (r - roots.TIP) * (1.0 - 0.25 * s / max(L, 1e-6)) *
                        min(1.0, s / 0.3, max(0.0, (L - s) / 0.8)) ** 0.6)
        self.occupancy.add(root, constant)
        for _ in range(rng.randint(0, 2)):
            if len(points) < 10:
                break
            i = rng.randint(sag_from + 2, sag_from + len(points) - 6)
            child = roots.Root('vein', number, self.tone(tone, 0.05), root, root.arc()[i])
            child.group = group
            rr = rng.uniform(0.003, 0.007)
            child.profile = (lambda s, L, rr=rr: roots.TIP + (rr - roots.TIP) * max(0.0, 1.0 - s / max(L, 1e-6)))
            roots.hang(self.surface, self.rules, child, root.points[i], rng.uniform(0.12, 0.5), rr, rng)
            if len(child.points) >= 3:
                root.children.append(child)
        self.systems.append((root, r, 1.0, group))
        print('LOOP', number, label, f'chord {chord:.2f} m',
              f'low {min(p.z for p in points) - self.floor:.2f} m', f'r {r * 100:.1f} cm', flush=True)
        return True

    COST = {'trunk': 75.0, 'branch': 110.0, 'vein': 100.0, 'loop': 100.0}  # triangles per metre, measured

    def cost(self) -> float:
        return sum(self.COST[root.kind] * root.length() for trunk, *_ in self.systems for root in trunk.walk())

    def grow(self, budget: int) -> None:
        """Doorway features; a base layer of trunks and medium roots spaced
        round the whole perimeter (thicker where a slow noise 'heat' along the
        walls is high); extra trunks clustered at two or three hot spots; then
        veins beside the roots already there until the budget is used."""
        from mathutils import noise
        rng, walls = self.rng, self.walls
        count = len(walls.walls)
        lengths = [w['length'] for w in walls.walls]
        perimeter = sum(lengths)
        height = self.room['height']
        phase = rng.uniform(0.0, 100.0)

        def at(u: float):
            """Perimeter distance -> (wall, t)."""
            u %= perimeter
            for w, length in enumerate(lengths):
                if u <= length:
                    return w, min(0.96, max(0.04, u / length))
                u -= length
            return count - 1, 0.5

        def heat(u: float) -> float:
            return 0.5 + 0.5 * noise.noise(Vector((u / 6.0 + phase, phase, 0.0)))

        def trunk_at(w: int, t: float, spacing: float = 0.8) -> bool:
            from_top = rng.random() < 0.6
            z = self.top - 0.05 if from_top else self.top - rng.uniform(0.3, min(1.4, height * 0.3))
            hit = self.seed(w, t, z, not from_top, spacing=spacing)
            if hit is None:
                return False
            foot = hit[0] + hit[1] * 0.1
            foot.z = self.floor + 0.5
            if not self.rules.route_clear(foot, 0.1):
                return False  # it could not reach the floor beside the walkway
            # Not every trunk the same: most drop fairly straight, some cross
            # the wall on a slant, some split into a fan just below the joint.
            style = rng.choices(('straight', 'slant', 'fan'), (0.45, 0.3, 0.25))[0]
            if style == 'slant':
                heading = roots.turn(roots.DOWN, hit[1], rng.uniform(0.55, 0.95) * rng.choice((-1, 1)))
            else:
                heading = roots.turn(roots.DOWN, hit[1], rng.uniform(-0.5, 0.5))
            return self.system('trunk', hit, rng.uniform(0.04, 0.065), heading, height * 1.8, w, from_top=from_top,
                               gravity=1.3 if style == 'slant' else None, fan=rng.randint(2, 3) if style == 'fan' else 0)

        def medium_at(w: int, t: float, spacing: float = 0.45) -> bool:
            z = self.top - rng.uniform(0.03, 0.35) * height
            hit = self.seed(w, t, z, True, spacing=spacing)
            if hit is None:
                return False
            heading = roots.turn(roots.DOWN, hit[1], rng.uniform(-0.7, 0.7))
            return self.system('branch', hit, rng.uniform(0.013, 0.026), heading, rng.uniform(0.4, 1.1) * height, w)

        # Doorways: a trunk from above the crown over the arch, loops, tendrils.
        for door in walls.openings:
            w = door['wall']
            for k in range(2):
                hit = walls.face(w, door['tc'] + rng.uniform(-0.3, 0.3) * door['width'] / lengths[w],
                                 min(self.top - 0.06, door['crown'] + rng.uniform(0.15, 0.8)))
                if hit is not None:
                    self.system('branch' if k else 'trunk', hit, rng.uniform(0.015, 0.025) if k else rng.uniform(0.035, 0.05),
                                roots.turn(roots.DOWN, hit[1], rng.uniform(-1.2, 1.2)), rng.uniform(2.5, 5.0), w)
            for under in (True, False, rng.random() < 0.6):
                for _ in range(16):
                    if self.loop(door, under, w):
                        break
        # Base layer round the room.
        spacing = rng.uniform(1.7, 2.3)
        slots = max(3, int(perimeter / spacing))
        offset = rng.uniform(0.0, perimeter)
        order = list(range(slots))
        rng.shuffle(order)  # if the budget runs out, the gaps fall anywhere, not on the last walls
        for k in order:
            if self.cost() > budget * 0.75:
                break
            u = offset + (k + rng.uniform(0.15, 0.85)) * perimeter / slots
            h = heat(u)
            if h < 0.18:
                continue  # a bare stretch
            w, t = at(u)
            if not (h > 0.3 and trunk_at(w, t)):
                medium_at(w, t)
        # Hot spots: a cluster of trunks each.
        for _ in range(rng.randint(2, 3)):
            u = rng.uniform(0.0, perimeter)
            for _ in range(rng.randint(2, 3) * 3):
                if self.cost() > budget * 0.88:
                    break
                w, t = at(u + rng.gauss(0.0, 0.9))
                trunk_at(w, t, spacing=0.5) or medium_at(w, t, spacing=0.4)
        # Veins beside the roots already on the walls, until the budget is used.
        anchors = [(p, n, group) for trunk, r0, g, group in self.systems for root in trunk.walk()
                   if root.kind in ('trunk', 'branch') for p, n in zip(root.points[2:-2:4], root.normals[2:-2:4])
                   if n is not None and abs(n.z) < 0.5 and p.z > self.floor + 0.6]
        for _ in range(120):
            if self.cost() > budget * 0.97 or not anchors:
                break
            p, n, group = anchors[rng.randrange(len(anchors))]
            wall = walls.walls[group]
            side = Vector((-n.y, n.x, 0.0)).normalized() * rng.choice((-1, 1))
            target = p + side * rng.uniform(0.12, 0.5) + Vector((0, 0, rng.uniform(-0.2, 0.3)))
            along = (target - Vector((wall['a'].x, wall['a'].y, target.z))).dot(wall['along']) / wall['length']
            hit = self.seed(group, min(0.97, max(0.03, along)), target.z, True, tries=12, spacing=0.12)
            if hit is None:
                continue
            heading = roots.turn(roots.DOWN, hit[1], rng.uniform(-1.6, 1.6))
            self.system('vein', hit, rng.uniform(0.004, 0.008), heading, rng.uniform(0.5, 1.6), group)

    # -- finishing -------------------------------------------------------------
    def finish(self, budget: int) -> dict:
        """Final radii, decimation and budget (thinnest leaves go first, then
        radii are recomputed so a stripped root tapers like one), settling.
        Returns QA numbers."""
        rng = self.rng

        def tolerance(r):
            return max(0.005, 0.4 * r)

        stats = {}
        for trunk, *_ in self.systems:
            for root in trunk.walk():
                entry = stats.setdefault(root.kind, [0, 0.0])
                entry[0] += 1
                entry[1] += root.length()
        print('ROOTS_GROWN', {k: (v[0], round(v[1], 1)) for k, v in stats.items()}, flush=True)
        pruned = 0
        for attempt in range(8):
            for trunk, r0, gamma, group in self.systems:
                roots.assign_radii(trunk, r0, gamma, core.rng(self.seed_base, 'radii', trunk.uid))
            if attempt == 0:
                for trunk, *_ in self.systems:
                    for root in trunk.walk():
                        roots.simplify(root, tolerance)
            total = sum(self.triangles(root) for trunk, *_ in self.systems for root in trunk.walk())
            if total <= budget:
                break
            leaves = sorted(((max(root.radii), root.length(), root.uid, root) for trunk, *_ in self.systems
                             for root in trunk.walk() if not root.children and root.parent is not None),
                            key=lambda x: x[:3])
            excess = total - budget
            for radius, length, uid, victim in leaves:
                if excess <= 0:
                    break
                victim.parent.children.remove(victim)
                excess -= self.triangles(victim)
                pruned += 1
        spent = {}
        for trunk, *_ in self.systems:
            for root in trunk.walk():
                entry = spent.setdefault(root.kind, [0.0, 0])
                entry[0] += root.length()
                entry[1] += self.triangles(root)
        print('ROOTS_SPENT', {k: (round(v[0], 1), v[1], round(v[1] / max(v[0], 1e-6))) for k, v in spent.items()}, flush=True)
        touching, rings, gaps = 0, 0, []
        clipped = 0
        for trunk, *_ in self.systems:
            for root in list(trunk.walk()):
                root.tone = min(1.15, max(0.75, root.tone))
                touching += roots.settle(self.surface, root)
                clipped += self.keep_corridor_clear(root)
                rings += len(root.points)
                gaps += roots.gaps(self.surface, root)
        gaps.sort()
        return {'pruned': pruned, 'clipped_at_corridor': clipped, 'rings': rings, 'rings_touching_stone': touching,
                'cling_gap_m': {'p50': round(gaps[len(gaps) // 2], 4) if gaps else 0,
                                'p95': round(gaps[int(len(gaps) * 0.95)], 4) if gaps else 0,
                                'max': round(gaps[-1], 4) if gaps else 0}}

    def keep_corridor_clear(self, root: roots.Root) -> int:
        """Settling can nudge a ring a few millimetres; if any ring now reaches
        into a walking corridor, end the root before it with a short taper."""
        for i, p in enumerate(root.points):
            if i == 0 and (root.buried or root.parent is not None):
                continue
            a, c = roots.ellipse(root, i)
            if not self.rules.route_clear(p, max(a, c) * roots.RELIEF):
                keep = max(2, i - 1)
                del root.points[keep:], root.normals[keep:], root.radii[keep:]
                root.dived = False
                for name in ('floor_index', 'soffit_index'):
                    if getattr(root, name) is not None and getattr(root, name) >= keep:
                        setattr(root, name, None)
                root.children = [child for child in root.children if child.at_s < root.arc()[-1]]
                arc = root.arc()
                for k in range(len(arc)):
                    left = arc[-1] - arc[k]
                    if left < 0.08:
                        root.radii[k] = roots.TIP + (root.radii[k] - roots.TIP) * (left / 0.08) ** 0.7
                return 1
        return 0

    @staticmethod
    def triangles(root: roots.Root) -> int:
        if len(root.points) < 2:
            return 0
        sides = roots.sides_for(root, root.radii[0])
        return (len(root.points) - 1) * sides * 2 + sides + (sides - 2 if root.parent is None else 0)

    def meshes(self, room_id: str) -> list:
        builders = {}
        self.audit_rings = []
        for trunk, r0, gamma, group in self.systems:
            builder = builders.get(group) or builders.setdefault(group, Builder(f'Roots_{room_id}_{group}'))
            for root in trunk.walk():
                roots.skin(builder, root, cap=root.parent is None, audit=self.audit_rings)
        objects = []
        for group in sorted(builders):
            obj = builders[group].to_object(smooth_angle=180.0)
            objects.append(obj)
        return objects


# -- review ---------------------------------------------------------------------
def rock_material(name: str, value: float, scale: float = 1.2, saturation: float = 0.35) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['Principled BSDF']
    coords = nodes.new('ShaderNodeTexCoord')
    mapping = nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = (scale, scale, scale)
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
    grade.inputs['Saturation'].default_value = saturation
    grade.inputs['Value'].default_value = value
    links.new(images['albedo'].outputs['Color'], grade.inputs['Color'])
    ao = nodes.new('ShaderNodeAttribute')
    ao.attribute_name = 'Color'
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    links.new(grade.outputs['Color'], mix.inputs['A'])
    links.new(ao.outputs['Color'], mix.inputs['B'])
    links.new(mix.outputs['Result'], shader.inputs['Base Color'])
    bump = nodes.new('ShaderNodeNormalMap')
    links.new(images['normal_gl'].outputs['Color'], bump.inputs['Color'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    links.new(images['roughness'].outputs['Color'], shader.inputs['Roughness'])
    return material


def root_material() -> bpy.types.Material:
    """Review stand-in for the game material: dark blood-red albedo times the
    vertex colour (baked AO x tone), fibres along UV u, cross wrinkles and a
    wet sheen in the grooves. In the game a normal map does the relief."""
    material = bpy.data.materials.new('ReviewRoots')
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['Principled BSDF']
    ao = nodes.new('ShaderNodeAttribute')
    ao.attribute_name = 'Color'
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'
    # u runs along the root in metres, v once round it.
    fibre_map = nodes.new('ShaderNodeMapping')
    fibre_map.inputs['Scale'].default_value = (0.8, 5.0, 1.0)
    links.new(uv.outputs['UV'], fibre_map.inputs['Vector'])
    fibres = nodes.new('ShaderNodeTexNoise')
    fibres.inputs['Scale'].default_value = 2.0
    fibres.inputs['Detail'].default_value = 8.0
    fibres.inputs['Roughness'].default_value = 0.65
    links.new(fibre_map.outputs['Vector'], fibres.inputs['Vector'])
    wrinkle_map = nodes.new('ShaderNodeMapping')
    wrinkle_map.inputs['Scale'].default_value = (9.0, 1.5, 1.0)
    links.new(uv.outputs['UV'], wrinkle_map.inputs['Vector'])
    wrinkles = nodes.new('ShaderNodeTexNoise')
    wrinkles.inputs['Scale'].default_value = 1.5
    wrinkles.inputs['Detail'].default_value = 4.0
    links.new(wrinkle_map.outputs['Vector'], wrinkles.inputs['Vector'])
    relief = nodes.new('ShaderNodeMath')
    relief.operation = 'MULTIPLY_ADD'
    relief.inputs[1].default_value = 0.6
    links.new(wrinkles.outputs['Fac'], relief.inputs[0])
    links.new(fibres.outputs['Fac'], relief.inputs[2])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.008, 0.0006, 0.0015, 1.0)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (0.036, 0.0024, 0.0045, 1.0)
    links.new(relief.outputs['Value'], ramp.inputs['Fac'])
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    links.new(ramp.outputs['Color'], mix.inputs['A'])
    links.new(ao.outputs['Color'], mix.inputs['B'])
    links.new(mix.outputs['Result'], shader.inputs['Base Color'])
    wet = nodes.new('ShaderNodeMapRange')
    wet.inputs['From Min'].default_value = 0.3
    wet.inputs['From Max'].default_value = 0.9
    wet.inputs['To Min'].default_value = 0.22
    wet.inputs['To Max'].default_value = 0.6
    links.new(relief.outputs['Value'], wet.inputs['Value'])
    links.new(wet.outputs['Result'], shader.inputs['Roughness'])
    shader.inputs['Subsurface Weight'].default_value = 0.03
    shader.inputs['Subsurface Radius'].default_value = (1.0, 0.12, 0.08)
    shader.inputs['Subsurface Scale'].default_value = 0.004
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.45
    bump.inputs['Distance'].default_value = 0.006
    links.new(relief.outputs['Value'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return material


def use_gpu() -> None:
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for device in prefs.devices:
            device.use = device.type == 'METAL'
        bpy.context.scene.cycles.device = 'GPU'
    except Exception as error:  # CPU still renders
        print('ROOTS_GPU_UNAVAILABLE', error, flush=True)
        bpy.context.scene.cycles.device = 'CPU'


def review_scene(loaded: dict, objects: list, samples: int):
    """Review materials, a dark cool world and Cycles (GPU when there is one)."""
    scene = bpy.context.scene
    stone = rock_material('ReviewStone', 0.55)
    mortar = rock_material('ReviewMortar', 0.3, 2.0, 0.2)
    floor_mat = rock_material('ReviewFloor', 0.32, 0.7, 0.25)
    ceiling_mat = rock_material('ReviewCeiling', 0.15, 0.7, 0.2)
    rootmat = root_material()
    proxies = [(loaded['floor'], floor_mat)] + ([(loaded['ceiling'], ceiling_mat)] if loaded.get('ceiling') else [])
    for obj, material in ([(o, stone) for o in loaded['stone']] + [(o, mortar) for o in loaded['mortar']] +
                          proxies + [(o, rootmat) for o in objects]):
        obj.data.materials.clear()
        obj.data.materials.append(material)
    for obj, _ in proxies:
        if 'Color' not in obj.data.color_attributes:
            attr = obj.data.color_attributes.new('Color', 'FLOAT_COLOR', 'POINT')
            for item in attr.data:
                item.color = (0.8, 0.8, 0.8, 1.0)
    scene.render.engine = 'CYCLES'
    use_gpu()
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    world = scene.world or bpy.data.worlds.new('Crypt')
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.010, 0.013, 0.016, 1.0)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0


def torch(name: str, at: Vector, energy: float = 140.0) -> bpy.types.Object:
    light = core.link(bpy.data.objects.new(name, bpy.data.lights.new(name, 'POINT')))
    light.data.energy = energy
    light.data.color = (1.0, 0.56, 0.26)
    light.data.shadow_soft_size = 0.06
    light.location = at
    return light


def shoot(views: list, lamps: dict, prefix: str, out: Path, floor: float) -> list:
    """Render (label, eye, target, lens) views to <out>/review/<prefix>_<n>_<label>.png
    with a key torch between camera and subject (or at lamps[label])."""
    scene = bpy.context.scene
    camera = bpy.data.objects.get('ReviewCamera') or core.link(bpy.data.objects.new('ReviewCamera', bpy.data.cameras.new('ReviewCamera')))
    scene.camera = camera
    key = bpy.data.objects.get('KeyTorch') or torch('KeyTorch', Vector())
    key.data.color = (1.0, 0.55, 0.25)
    key.data.shadow_soft_size = 0.05
    written = []
    for number, (label, eye, target, lens) in enumerate(views, 1):
        look = target - eye
        side = Vector((-look.y, look.x, 0.0)).normalized()
        spot = eye.lerp(target, 0.6) + side * min(1.6, look.length * 0.3)
        key.location = lamps.get(label, Vector((spot.x, spot.y, floor + 2.3)))
        key.data.energy = 120.0 + 40.0 * look.length
        camera.data.lens = lens
        camera.location = eye
        camera.rotation_euler = look.to_track_quat('-Z', 'Y').to_euler()
        path = out / 'review' / f'{prefix}_{number}_{label}.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(path)
        started = time.time()
        bpy.ops.render.render(write_still=True)
        print('ROOTS_RENDERED', path.name, f'{time.time() - started:.1f} s', flush=True)
        written.append(path)
    return written


def render_room(room: dict, loaded: dict, walls: Walls, grower: Grower, objects: list, out: Path, samples: int) -> list:
    review_scene(loaded, objects, samples)
    floor = walls.floor
    # Torches on alternate walls, like the game's wall torches.
    for k, wall in enumerate(walls.walls):
        if k % 2 == 0:
            spot = wall['a'].lerp(wall['b'], 0.5) + wall['inward'] * (THICKNESS * 0.5 + 0.45)
            torch(f'Torch{k}', Vector((spot.x, spot.y, floor + 2.3)))

    def wall_mass(w):
        return sum(len(root.points) * max(root.radii) for trunk, r0, g, group in grower.systems if group == w
                   for root in trunk.walk())

    order = sorted(range(len(walls.walls)), key=wall_mass, reverse=True)
    views, lamps = [], {}
    # 1: the most overgrown wall, whole height.
    wall = walls.walls[order[0]]
    mid = wall['a'].lerp(wall['b'], 0.5)
    eye = mid + wall['inward'] * min(5.5, wall['length'] * 0.75 + 1.5)
    views.append(('wall', Vector((eye.x, eye.y, floor + 1.6)), Vector((mid.x, mid.y, floor + room['height'] * 0.45)), 16))
    # 2: under a doorway arch with its loops, else the next wall.
    if walls.openings:
        door = max(walls.openings, key=lambda d: sum(1 for t, *_ in grower.systems if t.kind == 'loop' and t.group == d['wall']))
        wall = walls.walls[door['wall']]
        mid = walls.point(door['wall'], door['tc'])
        eye = mid + wall['inward'] * 2.6 + wall['along'] * 0.9
        crown = mid + wall['inward'] * 0.3
        views.append(('doorway', Vector((eye.x, eye.y, floor + 1.6)), Vector((crown.x, crown.y, door['crown'] - 0.25)), 17))
        under_arch = mid + wall['inward'] * 1.2 - wall['along'] * 0.8
        lamps['doorway'] = Vector((under_arch.x, under_arch.y, floor + 2.4))
    else:
        wall = walls.walls[order[1]]
        mid = wall['a'].lerp(wall['b'], 0.5)
        eye = mid + wall['inward'] * 5.0
        views.append(('wall2', Vector((eye.x, eye.y, floor + 1.6)), Vector((mid.x, mid.y, floor + room['height'] * 0.4)), 18))
    # 3: close on the thickest trunk where it meets the floor.
    trunks = sorted((s for s in grower.systems if s[0].kind == 'trunk'), key=lambda s: (s[0].floor_index is None, -s[1]))
    if trunks:
        trunk = trunks[0][0]
        k = trunk.floor_index if trunk.floor_index is not None else len(trunk.points) // 2
        base = trunk.points[k]
        n = trunk.normals[max(1, k - 3)] or Vector((1, 0, 0))
        n = Vector((n.x, n.y, 0.0)).normalized()
        side = Vector((-n.y, n.x, 0.0))
        eye = base + n * 2.2 + side * 0.9
        views.append(('close', Vector((eye.x, eye.y, floor + 1.45)), Vector((base.x, base.y, floor + 0.55)), 24))
    return shoot(views, lamps, room['id'], out, floor)


def audit(grower: Grower, rules: roots.Rules) -> dict:
    """Independent check of the final tubes: vertices whose ring centre to
    vertex segment crosses stone (the skin cuts into masonry), and vertices
    inside a walking corridor above ankle height (buried ends excluded)."""
    inside = deep = corridor = total = joint = 0
    for centre, ring, role in grower.audit_rings:
        if role == 'buried':
            continue
        for v in ring:
            total += 1
            span = v - centre
            hit = grower.surface.cast(centre, span.normalized(), span.length) if span.length > 1e-6 else None
            if hit is not None:
                if role == 'joint':
                    joint += 1
                else:
                    inside += 1
                    deep += span.length - hit[3] > 0.01
            elif not rules.route_clear(v, 0.0):
                corridor += 1
    return {'vertices': total, 'cut_into_stone': inside, 'cut_deeper_than_1cm': deep,
            'in_walking_corridor': corridor, 'emerging_from_joint': joint}


def bake_and_write(grower: Grower, rules: roots.Rules, label: str, out_dir: Path, options: dict, layout: dict,
                   sources: list, extra: dict, budget: int) -> tuple:
    """Budget, settle, skin, bake AO against everything in the scene, write
    <out_dir>/<label>.glb and .json."""
    qa = grower.finish(budget)
    objects = grower.meshes(label)
    if not objects:
        # A short stretch can leave no room for a root: nothing to write.
        print('ROOTS_EMPTY', label, flush=True)
        return [], {}
    qa['audit'] = audit(grower, rules)
    ao = bake.ao_to_color(objects, samples=64, distance=0.5, floor=0.2)
    for obj in objects:
        colour = obj.data.color_attributes['Color']
        for item in colour.data:
            r, g, _, _ = item.color
            shade = r * g   # baked AO (R) times the root's tone (G)
            item.color = (shade, shade, shade, 1.0)
    path = export.glb(objects, out_dir / f'{label}.glb')
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
    count = sum(1 for trunk, *_ in grower.systems for _ in trunk.walk())
    kinds = {}
    for trunk, r0, gamma, group in grower.systems:
        kinds[trunk.kind] = kinds.get(trunk.kind, 0) + 1
    radii = [r for trunk, *_ in grower.systems for root in trunk.walk() for r in root.radii]
    report = {
        'id': label, 'seed': options['seed'], 'triangles': tris, 'roots': count, 'systems': kinds,
        'meshes': [o.name for o in objects], 'budget': budget,
        'diameter_cm': {'max': round(max(radii) * 200, 1), 'min': round(min(radii) * 200, 1)},
        'clearance': {'route_margin_m': rules.margin, 'ankle_m': rules.ankle, 'headroom_m': rules.headroom},
        'qa': qa, 'ao': ao,
        'sources': {f'{options["arch"].name}/{Path(p).relative_to(options["arch"]).as_posix()}': core.sha256(p)
                    for p in sources},
        'layout_hash': layout['routes'][0].get('layout_hash'),
        **extra,
    }
    core.write_report(out_dir / f'{label}.json', report, [path])
    print('ROOTS_BAKED', label, tris, 'tris', count, 'roots', json.dumps(qa), flush=True)
    return objects, report


def build_room(options: dict, room: dict, layout: dict, index: dict) -> dict:
    core.empty_scene()
    roots.Root.count = 0
    loaded = load_room(options, room, index)
    surface = roots.Surface()
    for obj in loaded['stone']:
        surface.add_object(obj, 'stone')
    for obj in loaded['mortar']:
        surface.add_object(obj, 'mortar')
    surface.add_object(loaded['floor'], 'floor')
    surface.build()
    rules = roots.Rules(loaded['outline'], room['floor'], room['height'], blender_routes(layout),
                        reach=THICKNESS * 0.5 + 0.05, headroom=options['headroom'])
    walls = Walls(surface, room, loaded['outline'])
    grower = Grower(surface, rules, walls, core.rng(options['seed'], 'roots', room['id']), room, options['headroom'])
    grower.seed_base = options['seed']
    grower.grow(options['budget'])
    doorways = [{'wall': d['wall'], 'width': round(d['width'], 2), 'crown': round(d['crown'] - room['floor'], 2)}
                for d in walls.openings]
    objects, report = bake_and_write(grower, rules, room['id'], options['out'], options, layout, loaded['sources'],
                                     {'doorways': doorways}, options['budget'])
    if options['render']:
        render_room(room, loaded, walls, grower, objects, options['out'], options['samples'])
    return report


def blender_routes(layout: dict) -> list:
    return [{'width': r['width'], 'points': [core.to_blender(p) for p in r['points']]} for r in layout['routes']]


def passage_label(entry: dict) -> str:
    """One roots file per stretch of passage; the game loads it by this name."""
    if 'file' in entry and not entry['file'].endswith(f'/{entry["route"]}.glb'):
        return Path(entry['file']).stem
    return f'{entry["route"]}_{entry["segment"]}_{int(entry["t0"] * 1000.0 + 0.5)}'


def build_passage(options: dict, entry: dict, layout: dict) -> dict:
    """Roots in a vaulted passage between rooms: a few from joints at the
    vault crown creeping down the barrel to head height, loops slung across
    the vault, tendrils from the crown. Everything stays above headroom over
    the walkway, which fills the passage."""
    label = passage_label(entry)
    core.empty_scene()
    roots.Root.count = 0
    path = options['arch'] / entry['file']
    bpy.ops.import_scene.gltf(filepath=str(path))
    stone, mortar = [], []
    for obj in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if obj.type != 'MESH' or obj.name.startswith('Collision') or obj.name.endswith('colonly'):
            bpy.data.objects.remove(obj, do_unlink=True)
        else:
            (mortar if obj.name.startswith('Mortar') else stone).append(obj)
    route = next(r for r in layout['routes'] if r['id'] == entry['route'])
    p = core.to_blender(route['points'][entry['segment']])
    q = core.to_blender(route['points'][entry['segment'] + 1])
    a, b = p.lerp(q, entry['t0']), p.lerp(q, entry['t1'])
    floor = (a.z + b.z) * 0.5
    axis = Vector((b.x - a.x, b.y - a.y, 0.0)).normalized()
    across = Vector((-axis.y, axis.x, 0.0))
    corners = [o.matrix_world @ Vector(c) for o in stone + mortar for c in o.bound_box]
    top = max(c.z for c in corners)
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), 0.0))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), 0.0))
    outline = [Vector((lo.x, lo.y, 0)), Vector((hi.x, lo.y, 0)), Vector((hi.x, hi.y, 0)), Vector((lo.x, hi.y, 0))]
    floor_obj = polygon_object('ProxyFloor', outset(outline, 2.0), floor)
    surface = roots.Surface()
    for obj in stone:
        surface.add_object(obj, 'stone')
    for obj in mortar:
        surface.add_object(obj, 'mortar')
    surface.add_object(floor_obj, 'floor')
    surface.build()
    room = {'id': label, 'floor': floor, 'height': top - floor + 0.2}
    rules = roots.Rules(outline, floor, room['height'], blender_routes(layout), reach=0.02, headroom=options['headroom'])
    rng = core.rng(options['seed'], 'roots', 'passage', label)
    grower = Grower(surface, rules, None, rng, room, options['headroom'])
    grower.seed_base = options['seed']
    length = (b - a).length
    budget = int(min(options['budget'], max(4000, 1500 * length)))

    def soffit(u: float, v: float):
        """Vault soffit above the walkway: u along (0..1), v across (-1..1 of 2 m)."""
        base = a.lerp(b, u) + across * v * 2.0
        origin = Vector((base.x, base.y, floor + 1.6))
        hit = surface.cast(origin, Vector((0, 0, 1)), top - floor)
        if hit is None:
            return None
        n = hit[1].normalized()
        return hit[0], (n if n.z < 0 else -n), surface.kind(hit[2])

    lowest = floor + options['headroom'] + 0.12
    for _ in range(40):
        if grower.cost() > budget * 0.6:
            break
        hit = soffit(rng.uniform(0.08, 0.92), rng.gauss(0.0, 0.25))
        if hit is None or not grower.free(hit[0], 0.3):
            continue
        heading = across * rng.choice((-1, 1)) + axis * rng.uniform(-0.6, 0.6)
        kind = 'trunk' if rng.random() < 0.35 else 'branch'
        r0 = rng.uniform(0.035, 0.05) if kind == 'trunk' else rng.uniform(0.014, 0.026)
        if grower.system(kind, hit, r0, heading, rng.uniform(2.0, 4.0), 0, cap=rng.uniform(3.0, 6.0)):
            trunk = grower.systems[-1][0]
            for i in range(2, len(trunk.points) - 2, 6):
                n = trunk.normals[i]
                if n is not None and n.z < -0.5 and rng.random() < 0.5:
                    room_below = trunk.points[i].z - lowest
                    if room_below > 0.2:
                        grower.tendril(trunk, i, rng.uniform(0.15, min(0.9, room_below)))
    for _ in range(40):
        if grower.cost() > budget * 0.92:
            break
        u = rng.uniform(0.15, 0.85)
        side = rng.choice((-1, 1))
        seed = soffit(u + rng.uniform(-0.08, 0.08), rng.gauss(0.0, 0.1))
        a_hit = soffit(u + rng.uniform(-0.1, 0.1), side * rng.uniform(0.2, 0.45))
        b_hit = soffit(u + rng.uniform(-0.25, 0.25), -side * rng.uniform(0.5, 0.95))
        if seed is None or a_hit is None or b_hit is None:
            continue
        grower.hang_loop((seed[0], seed[1], 'mortar'), a_hit, b_hit, rng.uniform(0.016, 0.03), 0, 'vault')
    objects, report = bake_and_write(grower, rules, label, options['out'] / 'passages', options, layout, [path],
                                     {'passage': entry}, budget)
    if options['render']:
        loaded = {'stone': stone, 'mortar': mortar, 'floor': floor_obj, 'ceiling': None}
        review_scene(loaded, objects, options['samples'])
        mid = a.lerp(b, 0.5)
        for k, s in enumerate((-1, 1)):
            spot = mid + across * s * 1.9 + axis * (0.8 * s)
            torch(f'Torch{k}', Vector((spot.x, spot.y, floor + 2.0)), 110.0)
        crown = mid.copy()
        crown.z = top - 0.4
        start = a - axis * 0.6 + across * 0.8
        end = b + axis * 0.6 - across * 0.8
        views = [('along', Vector((start.x, start.y, floor + 1.6)), Vector((crown.x, crown.y, crown.z - 0.6)) + axis * 1.5, 15),
                 ('up', Vector((mid.x, mid.y, floor + 1.4)) - axis * 0.9 + across * 1.2, crown + across * 0.2 + axis * 0.4, 14),
                 ('back', Vector((end.x, end.y, floor + 1.6)), Vector((crown.x, crown.y, crown.z - 0.6)) - axis * 1.5, 15)]
        shoot(views, {}, f'passage_{label}', options['out'], floor)
    return report


def main():
    options = parse()
    layout = json.loads(options['layout'].read_text())
    index = json.loads((options['arch'] / 'index.json').read_text())
    wanted = options['rooms'] or index['rooms']
    by_id = {room['id']: room for room in layout['rooms']}
    for room_id in wanted:
        if room_id not in by_id or not (options['arch'] / 'rooms' / f'{room_id}.glb').exists():
            print('ROOTS_SKIPPED', room_id, flush=True)
            continue
        started = time.time()
        build_room(options, by_id[room_id], layout, index)
        print('ROOTS_ROOM_DONE', room_id, f'{time.time() - started:.1f} s', flush=True)
    for entry in index.get('passages', []):
        if 'file' not in entry:
            entry = dict(entry, file=f'passages/{entry["route"]}.glb')
        label = passage_label(entry)
        if options['passages'] is not None and label not in options['passages']:
            continue
        if not (options['arch'] / entry['file']).exists():
            print('ROOTS_SKIPPED', label, flush=True)
            continue
        started = time.time()
        build_passage(options, entry, layout)
        print('ROOTS_PASSAGE_DONE', label, f'{time.time() - started:.1f} s', flush=True)


if __name__ == '__main__':
    main()
