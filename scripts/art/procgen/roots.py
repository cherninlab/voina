"""Roots and veins grown over masonry: surface cling, gravity, pipe-model taper.

A root is a centre line grown a few centimetres at a time over a BVH of the
stone (Surface). Each step turns the heading towards gravity projected onto
the stone, wanders on smooth noise, moves, then snaps back to exactly
`radius * flat + GAP` off the nearest stone, so the tube rides over faces and
dips into joints. Running into a surface ahead (wall into floor, a proud
stone) climbs onto it; running off an edge (an arch soffit, a jamb) wraps
round it. Every move is ray-tested so a centre line never passes through
stone, and every point must satisfy the Rules (inside the room, under the
ceiling, off the walking routes).

Trees are grown depth first (crawl, then branches along it, a fan where a
root reaches the floor). Radii are assigned afterwards with the pipe model:
a point's radius follows the length of root downstream of it, so trunks are
thick where they leave the joint and taper as branches leave them; tips end
at TIP. Hanging pieces (catenary loops, tendrils) have normal None.

Then `settle` decimates, re-clings with the final radii and pushes every ring
out of the stone (rays from the centre to the ring's ellipse), and `skin`
turns the lines into flattened, bark-twisted tubes with lumps and knots,
UV u along the root in metres, Color = (AO placeholder, tone, 0, 1).
"""
import math

from mathutils import Quaternion, Vector, noise
from mathutils.bvhtree import BVHTree

from . import curves
from .shapes import Builder

WIDE, THIN = 0.75, 0.35  # a root pressed on stone spreads: semi-axes r(1 + WIDE f), r(1 - THIN f)
UP = Vector((0.0, 0.0, 1.0))
DOWN = Vector((0.0, 0.0, -1.0))
GAP = 0.003   # skin to stone, metres
TIP = 0.0025  # tip radius: veins end 5 mm across

# Per kind: step (m), gravity (turn per metre towards down), wander (rad/m),
# freq (noise per metre), seek (pull into joints), flat (pressed against the
# stone: 1 = strongly elliptical), floor run (m), branch spacing (m), children.
KINDS = {
    'trunk': dict(step=0.05, gravity=3.2, wander=2.2, freq=0.4, jitter=3.0, seek=0.25, flat=0.85, taper=0.2,
                  floor=(0.6, 1.8), every=(0.5, 1.2), angle=(0.35, 0.95), sides=8,
                  children=(('fork', 0.3), ('branch', 0.4), ('vein', 0.3))),
    'branch': dict(step=0.04, gravity=2.0, wander=4.0, freq=0.8, jitter=4.0, seek=0.45, flat=0.75, taper=0.3,
                   floor=(0.4, 1.3), every=(0.45, 1.1), angle=(0.45, 1.1), sides=6,
                   children=(('branch', 0.25), ('vein', 0.75))),
    'vein': dict(step=0.03, gravity=0.9, wander=4.5, freq=1.2, jitter=4.0, seek=0.9, flat=0.55, taper=0.2,
                 floor=(0.2, 0.7), every=(0.25, 0.6), angle=(0.5, 1.3), sides=4,
                 children=(('vein', 1.0),)),
    'loop': dict(step=0.04, gravity=1.0, wander=1.5, freq=1.0, jitter=4.0, seek=0.2, flat=0.6, taper=0.0,
                 floor=(0.2, 0.5), every=(0.4, 0.9), angle=(0.5, 1.0), sides=6,
                 children=(('vein', 1.0),)),
}


def standoff(r: float, flat: float) -> float:
    """Centre line height above the stone for radius r and flatness."""
    return r * (1.0 - THIN * flat) + GAP


def tangent(v: Vector, n: Vector) -> Vector:
    return v - n * v.dot(n)


def unit(v: Vector, fallback: Vector) -> Vector:
    return v.normalized() if v.length > 1e-9 else fallback.copy()


def turn(v: Vector, axis: Vector, angle: float) -> Vector:
    return Quaternion(axis, angle) @ v


class Surface:
    """BVH of world-space polygons with a kind per face ('stone', 'mortar', 'floor')."""

    def __init__(self):
        self.verts, self.polys, self.kinds = [], [], []
        self.tree = None

    def add_object(self, obj, kind: str) -> None:
        matrix = obj.matrix_world
        base = len(self.verts)
        self.verts.extend(matrix @ v.co for v in obj.data.vertices)
        self.polys.extend(tuple(base + i for i in p.vertices) for p in obj.data.polygons)
        self.kinds.extend([kind] * len(obj.data.polygons))

    def build(self) -> None:
        self.tree = BVHTree.FromPolygons(self.verts, self.polys, all_triangles=False)

    def kind(self, index) -> str:
        return self.kinds[index] if index is not None and 0 <= index < len(self.kinds) else ''

    def nearest(self, p: Vector, limit: float):
        loc, normal, index, dist = self.tree.find_nearest(p, limit)
        return None if loc is None else (loc, normal, index, dist)

    def cast(self, origin: Vector, direction: Vector, limit: float):
        loc, normal, index, dist = self.tree.ray_cast(origin, direction, limit)
        return None if loc is None else (loc, normal, index, dist)

    def blocked(self, a: Vector, b: Vector) -> bool:
        d = b - a
        return d.length > 1e-7 and self.cast(a, d.normalized(), d.length) is not None

    @staticmethod
    def outward(p: Vector, near) -> Vector:
        """Direction from the nearest surface point to p (smooth over edges);
        the face normal when p is on or behind the face."""
        loc, normal, _, dist = near
        v = p - loc
        if dist > 1e-6 and v.dot(normal) > -1e-6:
            return v / dist
        return normal.normalized()


class Rules:
    """Where roots may grow: inside the room's walls (outline grown by `reach`
    in plan), between floor - 0.1 and ceiling + 0.4, and clear of the walking
    routes: nothing taller than `ankle` above a route within its width / 2 +
    `margin` of its centre line, up to `headroom` above it."""

    def __init__(self, outline: list, floor: float, height: float, routes: list,
                 reach: float = 0.5, margin: float = 0.3, ankle: float = 0.03, headroom: float = 2.7):
        self.outline = [Vector((p.x, p.y)) for p in outline]
        self.floor, self.top = floor, floor + height
        self.reach, self.margin, self.ankle, self.headroom = reach, margin, ankle, headroom
        self.segments = []
        for route in routes:
            half = route['width'] * 0.5 + margin
            pts = route['points']
            for a, b in zip(pts, pts[1:]):
                self.segments.append((a, b, half))

    def plan_inside(self, p) -> bool:
        x, y = p.x, p.y
        inside = False
        pts = self.outline
        for a, b in zip(pts, pts[1:] + pts[:1]):
            if (a.y > y) != (b.y > y) and x < a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y):
                inside = not inside
        if inside:
            return True
        q = Vector((x, y))
        for a, b in zip(pts, pts[1:] + pts[:1]):
            ab = b - a
            t = max(0.0, min(1.0, (q - a).dot(ab) / max(ab.length_squared, 1e-12)))
            if (a + ab * t - q).length < self.reach:
                return True
        return False

    def route_distance(self, p: Vector):
        """(plan distance - half width, route height) of the nearest route, or None."""
        best = None
        q = Vector((p.x, p.y))
        for a, b, half in self.segments:
            a2, b2 = Vector((a.x, a.y)), Vector((b.x, b.y))
            ab = b2 - a2
            t = max(0.0, min(1.0, (q - a2).dot(ab) / max(ab.length_squared, 1e-12)))
            gap = (a2 + ab * t - q).length - half
            z = a.z + (b.z - a.z) * t
            if best is None or gap < best[0]:
                best = (gap, z)
        return best

    def route_clear(self, p: Vector, extent: float) -> bool:
        q = Vector((p.x, p.y))
        for a, b, half in self.segments:
            a2, b2 = Vector((a.x, a.y)), Vector((b.x, b.y))
            ab = b2 - a2
            t = max(0.0, min(1.0, (q - a2).dot(ab) / max(ab.length_squared, 1e-12)))
            if (a2 + ab * t - q).length > half + extent:
                continue
            z = a.z + (b.z - a.z) * t
            if p.z + extent > z + self.ankle and p.z - extent < z + self.headroom:
                return False
        return True

    def allowed(self, p: Vector, extent: float) -> bool:
        return (self.floor - 0.1 < p.z < self.top - 0.02 and self.plan_inside(p)
                and self.route_clear(p, extent))


class Occupancy:
    """Spatial hash of grown centre lines, so roots meet instead of passing
    through each other: a thinner root ends where it reaches a thicker one."""

    def __init__(self, cell: float = 0.25):
        self.cell, self.grid = cell, {}

    def _key(self, p):
        c = self.cell
        return (math.floor(p.x / c), math.floor(p.y / c), math.floor(p.z / c))

    def add(self, root, radius_at) -> None:
        s = 0.0
        for i, p in enumerate(root.points):
            if i:
                s += (p - root.points[i - 1]).length
            self.grid.setdefault(self._key(p), []).append((p, radius_at(s), root))

    def thicker(self, p: Vector, r: float, root, near_start: bool = False) -> bool:
        """True where p (radius r) touches a root at least as thick. A child
        ignores its parent only while it is still leaving it."""
        kx, ky, kz = self._key(p)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for q, rq, other in self.grid.get((kx + dx, ky + dy, kz + dz), ()):
                        if other is root or (near_start and other is root.parent):
                            continue
                        if rq >= r and (q - p).length < (r + rq) * 0.9:
                            return True
        return False


class Root:
    """One unbranched run. `normals[i]` is the stone normal under point i, or
    None where the root hangs free. Children attach at `at_s` metres along
    their parent and start inside it."""
    count = 0

    def __init__(self, kind: str, system: int, tone: float, parent=None, at_s: float = 0.0):
        Root.count += 1
        self.uid = Root.count
        self.kind, self.system, self.tone = kind, system, tone
        self.parent, self.at_s = parent, at_s
        self.points, self.normals, self.children = [], [], []
        self.radii = []
        self.floor_index = None
        self.soffit_index = None
        self.buried = False      # first point inside the stone (emerges from a joint)
        self.dived = False       # last point inside the stone (goes back into the wall)
        self.profile = None      # callable(s, L) -> radius for loops; else pipe model
        self.flat = KINDS[kind]['flat']
        self.twist = 0.0
        self.seed = 0.0
        self.group = 0

    def arc(self) -> list:
        s = [0.0]
        for a, b in zip(self.points, self.points[1:]):
            s.append(s[-1] + (b - a).length)
        return s

    def length(self) -> float:
        return self.arc()[-1]

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()


def crawl(surface: Surface, rules: Rules, occupancy: Occupancy, root: Root, start: Vector, normal: Vector,
          heading: Vector, length: float, radius_at, rng, target: Vector = None, floor_run: float = None,
          gravity: float = None) -> str:
    """Grow `root` over the surface from `start` (already placed) for up to
    `length` metres. Returns why it stopped."""
    kind = KINDS[root.kind]
    step = kind['step']
    gravity = kind['gravity'] if gravity is None else gravity
    p, n = start.copy(), normal.normalized()
    d = unit(tangent(heading, n), tangent(DOWN, n) if tangent(DOWN, n).length > 1e-3 else n.orthogonal())
    root.points.append(p.copy())
    root.normals.append(n.copy())
    seed = rng.uniform(0.0, 1000.0)
    floor_run = rng.uniform(*kind['floor']) if floor_run is None else floor_run
    s, on_floor = 0.0, 0.0
    floor_dir = None
    max_turn = {'trunk': 0.16, 'branch': 0.24, 'vein': 0.34, 'loop': 0.16}[root.kind]
    reason = 'length'
    while s < length:
        r = radius_at(s)
        off = standoff(r, root.flat)
        extent = r * (1.0 + WIDE * root.flat) * 1.15 + 0.02  # with bark relief and a settling margin
        g = tangent(DOWN, n)
        desired = d + g * (gravity * step)
        grounded = n.z > 0.85 and p.z < rules.floor + 0.25
        if floor_dir is not None and grounded:
            # On the floor nothing pulls: keep heading out from the wall.
            desired = desired + floor_dir * (gravity * step)
        if target is not None:
            to = tangent(target - p, n)
            if to.length < step * 1.5:
                reason = 'target'
                break
            desired = desired + to.normalized() * (2.5 * step / 0.05)
        desired = unit(tangent(desired, n), d)
        meander = (noise.noise(Vector((s * kind['freq'], seed, 0.37 * seed))) * kind['wander'] +
                   noise.noise(Vector((s * 7.3, seed + 17.0, 0.0))) * kind['jitter'])
        desired = turn(desired, n, meander * step)
        climb = {'trunk': -0.05, 'branch': 0.1, 'loop': 0.1}.get(root.kind)
        if climb is not None and abs(n.z) < 0.6 and desired.z > climb:
            # Thick roots hang from their source: they never climb back up.
            desired = unit(tangent(Vector((desired.x, desired.y, climb * desired.length)), n), desired)
        if desired.angle(d, 0.0) > max_turn:
            axis = d.cross(desired)
            if axis.length > 1e-9:
                desired = turn(d, axis.normalized(), max_turn)
        # Thin roots prefer the deeper of three headings: they settle into joints.
        options = (0.0, 0.3, -0.3) if kind['seek'] > 0 else (0.0,)
        best = None
        for spread in (0.0, 0.45, -0.45, 0.9, -0.9, 1.4, -1.4):
            for lean in options:
                angle = spread + lean
                moved = _move(surface, p, n, turn(desired, n, angle), step, off, grounded)
                if moved is None:
                    continue
                q, qn, depth = moved
                if not rules.allowed(q, extent):
                    continue
                score = math.cos(angle) + kind['seek'] * depth / step - abs(spread) * 0.5
                if best is None or score > best[0]:
                    best = (score, q, qn)
            if best is not None:
                break
        if best is None:
            reason = 'blocked'
            break
        _, q, qn = best
        moved_by = (q - p).length
        if occupancy is not None and s > (r + 0.03) * 3 and occupancy.thicker(q, r, root, near_start=s < 0.35 + r * 6):
            reason = 'met'
            break
        new_d = tangent(q - p, qn)
        if new_d.length < 1e-6 or new_d.normalized().dot(tangent(d, qn).normalized() if tangent(d, qn).length > 1e-6 else new_d) < -0.2:
            # Unfold the heading across the edge: concave (wall to floor) turns
            # away from the old surface, convex (over an arris) turns under it.
            fold = n if d.dot(qn) < 0 else -n
            new_d = tangent(fold, qn)
        d = unit(new_d, d)
        p, n = q, qn
        root.points.append(p.copy())
        root.normals.append(n.copy())
        s += moved_by
        if n.z > 0.85 and p.z < rules.floor + 0.25:
            if root.floor_index is None:
                root.floor_index = len(root.points) - 1
            if floor_dir is None:
                floor_dir = unit(Vector((d.x, d.y, 0.0)), Vector((1, 0, 0)))
            on_floor += moved_by
            if on_floor > floor_run:
                reason = 'floor'
                break
        if n.z < -0.6 and root.soffit_index is None:
            root.soffit_index = len(root.points) - 1
    return reason


def _move(surface: Surface, p: Vector, n: Vector, d: Vector, step: float, off: float, grounded: bool = False):
    """One step along heading d from p (off the surface along n). Returns the
    new centre, its surface normal and how much deeper the stone under it is."""
    under = p - n * off
    ahead = surface.cast(p, d, step + off)
    forced = None
    if ahead is not None:
        loc, hn, index, dist = ahead
        hn = hn.normalized()
        if hn.dot(d) > 0:
            hn = -hn
        if hn.dot(n) < 0.85:
            if grounded and hn.z < 0.5:
                return None  # roots on the floor follow the wall foot, never climb back up
            # A surface ahead at an angle: climb onto it.
            q = loc + hn * off
            forced = hn
        else:
            q = p + d * max(dist - off, step * 0.3)
    else:
        q = p + d * step
    near = surface.nearest(q, off + step * 2.5)
    if near is None:
        hit = surface.cast(q, -n, off + step * 2.5)
        if hit is None:
            return None
        near = (hit[0], hit[1], hit[2], (q - hit[0]).length)
    qn = forced if forced is not None else Surface.outward(q, near)
    if grounded and qn.z < 0.5:
        return None
    qq = near[0] + qn * off
    if forced is not None:
        # Keep clear of both surfaces at a concave corner.
        side = surface.nearest(qq, off)
        if side is not None and side[3] < off * 0.98:
            qq = side[0] + Surface.outward(qq, side) * off
            check = surface.nearest(qq, off)
            if check is not None and check[3] < off * 0.9:
                return None
    if (qq - p).length < step * 0.2:
        return None
    if surface.blocked(p, qq):
        return None
    depth = (under - near[0]).dot(n)
    return qq, qn, depth


def hang(surface: Surface, rules: Rules, root: Root, start: Vector, length: float, radius: float, rng) -> None:
    """A free tendril dropping from `start` (under a soffit), curling slightly."""
    p = start.copy()
    root.points.append(p.copy())
    root.normals.append(None)
    sway = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.0))
    sway = unit(sway, Vector((1, 0, 0)))
    s, step = 0.0, 0.04
    seed = rng.uniform(0, 1000)
    while s < length:
        bend = noise.noise(Vector((s * 2.0, seed, 0.0))) * 0.35 + (s / max(length, 1e-6)) ** 2 * rng.uniform(0.2, 0.6)
        d = unit(DOWN + sway * bend, DOWN)
        q = p + d * step
        if surface.blocked(p, q) or not rules.allowed(q, radius * 1.5 + 0.02):
            break
        near = surface.nearest(q, radius + GAP)
        if near is not None:
            break
        p = q
        root.points.append(p.copy())
        root.normals.append(None)
        s += step


def assign_radii(trunk: Root, r0: float, gamma: float, rng) -> None:
    """Pipe model: radius follows the root length downstream of each point,
    from r0 where the system emerges to TIP at every tip, with lumps along
    the length and knots where branches leave."""
    downstream = {}

    def visit(root: Root) -> float:
        arc = root.arc()
        total = arc[-1]
        attached = sorted(((c.at_s, visit(c)) for c in root.children), key=lambda x: x[0])
        values = []
        for s in arc:
            values.append((total - s) + sum(dv for cs, dv in attached if cs >= s - 1e-6))
        downstream[root.uid] = values
        return values[0] if values else 0.0

    d0 = max(visit(trunk), 1e-6)
    for root in trunk.walk():
        arc = root.arc()
        seed = rng.uniform(0, 1000)
        root.seed = seed
        bumps = [(rng.uniform(0, arc[-1]), rng.uniform(0.08, 0.24), rng.uniform(0.05, 0.16))
                 for _ in range(int(arc[-1] / 0.45) + rng.randint(0, 1))]
        taper = KINDS[root.kind]['taper']
        radii = []
        for i, s in enumerate(arc):
            if root.profile is not None:
                base = root.profile(s, arc[-1])
            else:
                base = TIP + (r0 - TIP) * (downstream[root.uid][i] / d0) ** gamma * (1.0 - taper * s / max(arc[-1], 1e-6))
            lump = 1.0 + 0.12 * noise.noise(Vector((s * 3.0, seed, 1.7)))
            for at, amount, width in bumps:
                lump += amount * math.exp(-((s - at) / width) ** 2) * min(1.0, base / 0.01) * min(1.0, s / 0.5)
            for child in root.children:
                lump += 0.12 * math.exp(-((s - child.at_s) / max(base * 2.5, 0.02)) ** 2)
            radii.append(max(TIP, base * lump))
        # Taper the last few centimetres to the tip (unless it ends in the wall).
        for i in range(len(arc) if not root.dived else 0):
            left = arc[-1] - arc[i]
            reach = max(0.08, radii[i] * 10.0)
            if left < reach:
                radii[i] = TIP + (radii[i] - TIP) * (left / reach) ** 0.7
        root.radii = radii


def simplify(root: Root, tolerance) -> None:
    """Smooth away step-scale jitter, then Douglas-Peucker on the centre line
    (keeps ends, floor and soffit entries) with a cap on segment length;
    settle() re-clings afterwards."""
    pts = root.points
    if len(pts) < 3:
        return
    fixed = {0, 1, len(pts) - 1, root.floor_index, root.soffit_index}
    for _ in range(3):
        smoothed = list(pts)
        for i in range(1, len(pts) - 1):
            if i in fixed or root.normals[i] is None or root.normals[i - 1] is None or root.normals[i + 1] is None:
                continue
            smoothed[i] = pts[i] * 0.5 + (pts[i - 1] + pts[i + 1]) * 0.25
        pts = smoothed
    root.points = pts
    keep = {0, len(pts) - 1}
    for k in (root.floor_index, root.soffit_index):
        if k is not None and 0 < k < len(pts):
            keep.add(k)
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        ab = pts[b] - pts[a]
        worst, index = -1.0, None
        for i in range(a + 1, b):
            v = pts[i] - pts[a]
            if ab.length > 1e-9:
                v = v - ab * (v.dot(ab) / ab.length_squared)
            n = root.normals[i]
            if n is not None:
                # Off-surface wobble over bumpy stone matters less than the
                # line's course across it: settle() pushes rings out again.
                across = v.dot(n)
                dist = math.sqrt(max(v.length_squared - across * across, 0.0) + (0.4 * across) ** 2)
            else:
                dist = v.length
            if dist > worst:
                worst, index = dist, i
        if worst > tolerance(root.radii[index]):
            split = index
        elif (pts[b] - pts[a]).length > min(0.4, max(0.2, root.radii[index] * 8.0)):
            split = (a + b) // 2
        else:
            continue
        keep.add(split)
        stack.append((a, split))
        stack.append((split, b))
    order = sorted(keep)
    mapping = {old: new for new, old in enumerate(order)}
    root.points = [pts[i] for i in order]
    root.normals = [root.normals[i] for i in order]
    root.radii = [root.radii[i] for i in order]
    root.floor_index = mapping.get(root.floor_index)
    root.soffit_index = mapping.get(root.soffit_index)


def ellipse(root: Root, i: int):
    """Semi-axes (across the stone, off the stone) of ring i."""
    r = root.radii[i]
    f = root.flat if root.normals[i] is not None else 0.0
    return r * (1.0 + WIDE * f), r * (1.0 - THIN * f)


def frames(root: Root) -> list:
    """(tangent, normal, binormal) per point; clinging points use the smoothed
    stone normal, hanging points parallel transport."""
    pts = root.points
    count = len(pts)
    result = []
    smooth = []
    for i in range(count):
        acc = Vector()
        for j in range(max(0, i - 1), min(count, i + 2)):
            if root.normals[j] is not None:
                acc += root.normals[j] * (2.0 if j == i else 1.0)
        smooth.append(acc.normalized() if acc.length > 1e-6 else None)
    previous = None
    for i in range(count):
        t = unit(pts[min(i + 1, count - 1)] - pts[max(i - 1, 0)], Vector((0, 0, -1)))
        n = smooth[i]
        if n is None or root.normals[i] is None:
            n = previous if previous is not None else unit(UP.cross(t), Vector((1, 0, 0)))
        n = unit(n - t * n.dot(t), t.orthogonal())
        b = t.cross(n)
        result.append((t, n, b))
        previous = n
    return result


def settle(surface: Surface, root: Root, passes: int = 4) -> int:
    """Re-cling with the final radii, smooth, and push every ring out of the
    stone. Returns how many rings still touch stone afterwards."""
    count = len(root.points)
    fixed = {0} if (root.buried or root.parent is not None) else set()
    if root.dived:
        fixed.add(count - 1)
    for _ in range(passes):
        for i in range(count):
            if i in fixed or root.normals[i] is None:
                continue
            _, off = ellipse(root, i)
            near = surface.nearest(root.points[i], off * 3 + 0.05)
            if near is None:
                continue
            n = Surface.outward(root.points[i], near)
            root.points[i] = near[0] + n * (off + GAP)
            root.normals[i] = n
        smoothed = list(root.points)
        for i in range(1, count - 1):
            if i in fixed or root.normals[i] is None:
                continue
            smoothed[i] = root.points[i] * 0.5 + (root.points[i - 1] + root.points[i + 1]) * 0.25
        root.points = smoothed
        _push(surface, root, fixed)
    for _ in range(8):
        _push(surface, root, fixed)
    touching = 0
    for i, (t, n, b) in enumerate(frames(root)):
        if i in fixed:
            continue
        a, c = ellipse(root, i)
        for k in range(8):
            angle = 2 * math.pi * k / 8
            v = b * math.cos(angle) + n * math.sin(angle)
            reach = a * c / math.hypot(c * math.cos(angle), a * math.sin(angle))
            if surface.cast(root.points[i], v, reach) is not None:
                touching += 1
                break
    return touching


RELIEF = 1.14  # skin() raises bark ridges up to 12-13 % proud of the ellipse


def _push(surface: Surface, root: Root, fixed: set) -> None:
    for i, (t, n, b) in enumerate(frames(root)):
        if i in fixed:
            continue
        a, c = ellipse(root, i)
        a, c = a * RELIEF, c * RELIEF
        push = Vector()
        for k in range(12):
            angle = 2 * math.pi * k / 12
            v = b * math.cos(angle) + n * math.sin(angle)
            reach = a * c / math.hypot(c * math.cos(angle), a * math.sin(angle)) + GAP
            hit = surface.cast(root.points[i], v, reach)
            if hit is not None:
                # Move away from the obstruction along its own normal: a proud
                # stone face beside a flattened root pushes it off the wall, not sideways.
                away = hit[1].normalized()
                if away.dot(v) > 0:
                    away = -away
                deficit = (reach - hit[3]) / max(0.6, -away.dot(v))
                if push.dot(away) < deficit:
                    push += away * (deficit - max(0.0, push.dot(away)))
        if push.length > 0:
            if push.length > c * 0.6 + GAP:
                push = push.normalized() * (c * 0.6 + GAP)
            moved = root.points[i] + push
            if not surface.blocked(root.points[i], moved):
                root.points[i] = moved


def gaps(surface: Surface, root: Root) -> list:
    """Skin-to-stone distance under every clinging ring (for the report)."""
    result = []
    for i, (t, n, b) in enumerate(frames(root)):
        if root.normals[i] is None or (i == 0 and (root.buried or root.parent is not None)) or (root.dived and i == len(root.points) - 1):
            continue
        _, c = ellipse(root, i)
        near = surface.nearest(root.points[i], 1.0)
        if near is not None:
            result.append(near[3] - c)
    return result


def sides_for(root: Root, r0: float) -> int:
    base = max(root.radii) if root.radii else TIP
    if base > 0.022:
        return 6
    if base > 0.01:
        return 5
    if base > 0.005:
        return 4
    return 3


def skin(builder: Builder, root: Root, cap: bool, audit: list = None) -> int:
    """Tube along the root: elliptical, pressed flat against the stone, with
    alternate vertices raised into ridges that spiral along the length (bark
    twist). Ends in a point. Returns triangles added."""
    count = len(root.points)
    if count < 2:
        return 0
    sides = sides_for(root, root.radii[0])
    base_r = max(root.radii)
    arc = root.arc()
    tone = (1.0, root.tone, 0.0, 1.0)
    rings = []
    for i, (t, n, b) in enumerate(frames(root)):
        a, c = ellipse(root, i)
        ridge = 0.12 if base_r > 0.03 else (0.08 if sides >= 6 else 0.0)
        ring = []
        # Pressed against stone, the back of a root is never seen: spend the
        # ring's vertices on the front (phi measured from the outward normal).
        warp = 0.42 if root.normals[i] is not None else 0.0
        for k in range(sides):
            phi = 2 * math.pi * k / sides + root.twist * arc[i]
            phi = math.atan2(math.sin(phi), math.cos(phi))
            phi = phi - warp * math.sin(phi)
            angle = phi + math.pi * 0.5
            scale = 1.0 + (ridge if k % 2 == 0 else -ridge * 0.6) if sides % 2 == 0 else 1.0 + ridge * 0.5 * math.cos(3 * phi)
            pos = root.points[i] + (b * math.cos(angle) * a + n * math.sin(angle) * c) * scale
            ring.append(builder.bm.verts.new(pos))
        rings.append(ring)
        if audit is not None:
            # Buried ends are meant to be in the stone; the ring after a buried
            # start (before a dive) is where the root comes out of (goes into) its joint.
            exempt = (i == 0 and root.buried) or (i == count - 1 and root.dived)
            joint = (i == 1 and root.buried) or (i == count - 2 and root.dived)
            audit.append((root.points[i].copy(), [v.co.copy() for v in ring], 'buried' if exempt else ('joint' if joint else '')))
    tris = 0
    for i in range(count - 1):
        r0, r1 = rings[i], rings[i + 1]
        u0, u1 = arc[i], arc[i + 1]
        for k in range(sides):
            k1 = (k + 1) % sides
            # Ring angle runs b -> n, so this order winds the quad's normal outward.
            builder.face([r0[k], r1[k], r1[k1], r0[k1]],
                         [Vector((u0, k / sides)), Vector((u1, k / sides)),
                          Vector((u1, (k + 1) / sides)), Vector((u0, (k + 1) / sides))], tone)
            tris += 2
    # Point at the tip, a little beyond the last ring.
    t_last = unit(root.points[-1] - root.points[-2], DOWN)
    tip = builder.bm.verts.new(root.points[-1] + t_last * max(root.radii[-1] * 2.0, 0.006))
    last = rings[-1]
    for k in range(sides):
        k1 = (k + 1) % sides
        builder.face([last[k1], last[k], tip], [Vector((arc[-1], (k + 1) / sides)), Vector((arc[-1], k / sides)),
                                                 Vector((arc[-1] + 0.01, 0.5))], tone)
        tris += 1
    if cap:
        first = rings[0]
        builder.face(list(first), [Vector((0.0, k / sides)) for k in range(sides)], tone)  # faces back along -t
        tris += sides - 2
    builder.pieces += 1
    return tris


def estimate_triangles(root: Root, spacing) -> int:
    sides = sides_for(root, root.radii[0] if root.radii else TIP)
    length = root.length()
    rings = max(2, int(length / max(spacing(max(root.radii) if root.radii else TIP), 0.02)) + 1)
    return rings * sides * 2


def catenary_between(a: Vector, b: Vector, slack: float, count: int = 20) -> list:
    return curves.catenary(a, b, slack, count)
