"""Seamless stone floors on a torus: layouts, stone solids and periodic clipping.

A floor module is the rectangle [0, P] x [0, Q] in Blender XY (z up, metres).
Layouts are lists of `Piece`s whose foot outlines live in *unwrapped*
coordinates: a stone near the right edge may extend past x = P. `Floor.emit`
builds each piece once and places copies shifted by whole periods wherever
they overlap the module; `clip_module` then cuts everything at the borders.
Opposite borders carry the same cut of the same stones, so modules tile
without seams. Randomness is seeded per stone and evaluated before the shift,
so a copy equals its original apart from the translation.

Families (`voronoi_family`, `coursed_family`, `kerb_family`) return several
variants that share every stone touching a periodic border: same outline where
it crosses the border, same height plane, joint, bevel, UVs and colour.
Only interior stones differ, so any variant tiles with any other variant of
its family and a floor can mix them to hide repetition.

Stone geometry (LOD0): a top cap with interior points, a two-step rounded
arris, near-vertical sides down to a dark bedding plane, per-stone height and
tilt within +/-2 cm of z = 0. Chips notch the arris; cracks split a stone into
pieces that keep the parent's colour and UVs; missing stones and broken
corners leave a lumpy dirt fill with a few loose fragments.

Colour attribute "Color" follows the procgen convention: R = AO (baked later),
G = per-stone variation, B = edge wear (1 on arrises and chips, 0 on the worn
top). UVs are metres, rotated and offset per stone so a tiling texture never
lines up across neighbouring stones; dirt and bedding use plain module metres.
"""
import math
from dataclasses import dataclass, field

import bmesh
from mathutils import Vector, geometry

from . import core

JOINT, CRACK, BREAK, FINISH = 'joint', 'crack', 'break', 'finish'
FOOT_Z = -0.021       # stone sides end just under the bedding
BED_Z = -0.019        # dark bedding seen through joints
DIRT_EDGE_Z = -0.017  # dirt fill meets the neighbouring stones here
LIMIT_Z = 0.02        # visual surface stays within +/-2 cm of the walking plane


# --------------------------------------------------------------------------- noise

def hash01(*keys) -> float:
    """Deterministic float in [0, 1) from integers (FNV-1a plus avalanche)."""
    h = 2166136261
    for k in keys:
        h = ((h ^ (int(k) & 0xffffffff)) * 16777619) & 0xffffffff
    h ^= h >> 15
    h = (h * 2246822519) & 0xffffffff
    h ^= h >> 13
    h = (h * 3266489917) & 0xffffffff
    h ^= h >> 16
    return (h & 0xffffff) / float(1 << 24)


def pnoise(x: float, y: float, cells: int, period: float, seed: int = 0) -> float:
    """Smooth value noise in [0, 1] with `cells` lattice cells per period; periodic."""
    fx, fy = x / period * cells, y / period * cells
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)

    def h(i, j):
        return hash01(seed, i % cells, j % cells)
    a = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * tx
    b = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * tx
    return a + (b - a) * ty


def fbm(x: float, y: float, period: float, seed: int, base: int = 4) -> float:
    """Three periodic octaves, roughly in [-1, 1]."""
    total = 0.0
    for octave, weight in enumerate((1.0, 0.5, 0.25)):
        total += weight * (2 * pnoise(x, y, base * 2 ** octave + octave, period, seed + octave) - 1)
    return total / 1.75


# --------------------------------------------------------------------------- 2D polygons

def area(poly) -> float:
    s = 0.0
    for i, (x0, y0) in enumerate(poly):
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def centroid(poly) -> tuple:
    a = area(poly)
    if abs(a) < 1e-12:
        return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))
    cx = cy = 0.0
    for i, (x0, y0) in enumerate(poly):
        x1, y1 = poly[(i + 1) % len(poly)]
        c = x0 * y1 - x1 * y0
        cx += (x0 + x1) * c
        cy += (y0 + y1) * c
    return (cx / (6 * a), cy / (6 * a))


def bounds(poly) -> tuple:
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def _dedupe(points, kinds, eps=1e-7):
    out, out_kinds = [], []
    for p, k in zip(points, kinds):
        if out and abs(p[0] - out[-1][0]) < eps and abs(p[1] - out[-1][1]) < eps:
            out_kinds[-1] = k
            continue
        out.append(p)
        out_kinds.append(k)
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
        out_kinds.pop()
    return out, out_kinds


def clip(poly, kinds, n, d, kind):
    """Keep the part of `poly` with n . p <= d (Sutherland-Hodgman). kinds[i]
    labels edge poly[i] -> poly[i + 1]; the new edge along the cut gets `kind`."""
    out, out_kinds = [], []
    count = len(poly)
    for i in range(count):
        a, b = poly[i], poly[(i + 1) % count]
        da = n[0] * a[0] + n[1] * a[1] - d
        db = n[0] * b[0] + n[1] * b[1] - d
        a_in, b_in = da <= 0, db <= 0
        if a_in:
            out.append(a)
            out_kinds.append(kinds[i])
        if a_in != b_in:
            t = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            out_kinds.append(kind if a_in else kinds[i])
    return _dedupe(out, out_kinds)


def inside(p, poly) -> bool:
    x, y = p
    hit = False
    for i, (x0, y0) in enumerate(poly):
        x1, y1 = poly[(i + 1) % len(poly)]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def segment_distance(p, a, b) -> float:
    ax, ay = b[0] - a[0], b[1] - a[1]
    length2 = ax * ax + ay * ay
    t = 0.0 if length2 < 1e-18 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / length2))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - ay * t)


def edge_distance(p, poly) -> float:
    return min(segment_distance(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def _cross(o, a, b) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def simple(poly) -> bool:
    """True when no two non-adjacent edges intersect and the winding is CCW."""
    n = len(poly)
    if n < 3 or area(poly) <= 0:
        return False
    boxes = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        boxes.append((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])))
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        bi = boxes[i]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            bj = boxes[j]
            if bi[2] < bj[0] or bj[2] < bi[0] or bi[3] < bj[1] or bj[3] < bi[1]:
                continue
            c, d = poly[j], poly[(j + 1) % n]
            d1, d2 = _cross(a, b, c), _cross(a, b, d)
            d3, d4 = _cross(c, d, a), _cross(c, d, b)
            if ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)):
                return False
    return True


def min_angle(poly) -> float:
    """Smallest interior angle in degrees."""
    n = len(poly)
    smallest = 180.0
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        u = (a[0] - b[0], a[1] - b[1])
        v = (c[0] - b[0], c[1] - b[1])
        lu, lv = math.hypot(*u), math.hypot(*v)
        if lu < 1e-9 or lv < 1e-9:
            continue
        cos = max(-1.0, min(1.0, (u[0] * v[0] + u[1] * v[1]) / (lu * lv)))
        angle = math.degrees(math.acos(cos))
        if _cross(a, b, c) < 0:  # reflex vertex of a CCW polygon
            angle = 360 - angle
        smallest = min(smallest, angle)
    return smallest


def collapse_short_edges(poly, kinds, min_length: float) -> tuple:
    """Remove edges shorter than `min_length` so inset rings cannot fold over.
    The neighbouring edges are extended to meet, which keeps their lines
    exact: a long edge crossing a module border must not move when a tiny edge
    at its far end differs between family variants. Nearly parallel
    neighbours fall back to merging at the midpoint."""
    poly, kinds = list(poly), list(kinds)
    while len(poly) > 3:
        n = len(poly)
        shortest, i = min((math.dist(poly[k], poly[(k + 1) % n]), k) for k in range(n))
        if shortest >= min_length:
            break
        j = (i + 1) % n
        p0, p1, p2, p3 = poly[i - 1], poly[i], poly[j], poly[(j + 1) % n]
        d0 = (p1[0] - p0[0], p1[1] - p0[1])
        d1 = (p3[0] - p2[0], p3[1] - p2[1])
        cross = d0[0] * d1[1] - d0[1] * d1[0]
        merged = ((p1[0] + p2[0]) * 0.5, (p1[1] + p2[1]) * 0.5)
        if abs(cross) > 0.35 * math.hypot(*d0) * math.hypot(*d1):
            t = ((p2[0] - p0[0]) * d1[1] - (p2[1] - p0[1]) * d1[0]) / cross
            meet = (p0[0] + d0[0] * t, p0[1] + d0[1] * t)
            if math.dist(meet, merged) < 2 * min_length:
                merged = meet
        poly[i] = merged
        kinds[i] = kinds[j]
        del poly[j]
        del kinds[j]
    return poly, kinds


# --------------------------------------------------------------------------- pieces

@dataclass
class Piece:
    """One stone, stone fragment or dirt patch. `poly` is the foot outline (CCW,
    unwrapped metres); `key` seeds everything about it; `origin` anchors its
    height plane and UVs and is shared by all pieces of a cracked stone."""
    poly: list
    kinds: list
    key: tuple
    origin: tuple
    role: str = 'stone'          # stone | fragment | dirt
    border: bool = False         # crosses a periodic border: identical across a family
    height: float = 0.0
    tilt: tuple = (0.0, 0.0)
    joint: float = 0.004         # half joint width
    bevel: tuple = (0.012, 0.005)
    variation: float = 0.5
    uv: tuple = (0.0, 0.0, 0.0)  # angle, u offset, v offset
    chips: list = field(default_factory=list)  # (x, y, radius, depth, drop)
    warp: float = 0.0
    jitter: float = 0.0
    sink: float = 0.0            # extra drop of a settled crack piece

    def copy(self, **changes) -> 'Piece':
        values = dict(self.__dict__)
        values['chips'] = list(self.chips)
        values.update(changes)
        return Piece(**values)


STYLE = dict(
    lift=0.003, height=0.006, tilt=0.009, joint=(0.003, 0.0075),
    bevel_w=(0.008, 0.016), bevel_d=(0.003, 0.007), chips=(0, 2), warp=0.0015,
    jitter=0.0012, crack=0.1, crack_lines=(1, 1), broken=0.05, missing=0.03,
    fragments=(1, 3), sink=0.004,
)


def near_border(p, period, periodic, margin) -> bool:
    for axis in (0, 1):
        if periodic[axis]:
            r = p[axis] % period[axis]
            if min(r, period[axis] - r) < margin:
                return True
    return False


def dress(piece: Piece, rng, style: dict, period, periodic) -> Piece:
    """Height, tilt, joint, bevel, colour, UVs and chips from the piece's own RNG.
    Border pieces never warp or jitter and keep chips away from the border, so
    their geometry at the cut is a pure function of key and position."""
    piece.height = style['lift'] + rng.uniform(-1, 1) * style['height']
    slope = style['tilt'] * math.sqrt(rng.random())
    angle = rng.uniform(0, 2 * math.pi)
    piece.tilt = (slope * math.cos(angle), slope * math.sin(angle))
    piece.joint = rng.uniform(*style['joint'])
    piece.bevel = (rng.uniform(*style['bevel_w']), rng.uniform(*style['bevel_d']))
    piece.variation = rng.random()
    piece.uv = (rng.uniform(0, 2 * math.pi), rng.uniform(0, 16), rng.uniform(0, 16))
    piece.warp = 0.0 if piece.border else style['warp']
    piece.jitter = 0.0 if piece.border else style['jitter']
    piece.chips = []
    edges = [(piece.poly[i], piece.poly[(i + 1) % len(piece.poly)]) for i, k in enumerate(piece.kinds) if k != CRACK]
    lengths = [math.dist(a, b) for a, b in edges]
    for _ in range(rng.randint(*style['chips'])):
        if not edges:
            break
        pick = rng.uniform(0, sum(lengths))
        for (a, b), length in zip(edges, lengths):
            if pick <= length:
                break
            pick -= length
        t = rng.uniform(0.08, 0.92)
        nx, ny = -(b[1] - a[1]) / length, (b[0] - a[0]) / length
        inset = piece.joint + 0.004
        c = (a[0] + (b[0] - a[0]) * t + nx * inset, a[1] + (b[1] - a[1]) * t + ny * inset)
        chip = (c[0], c[1], rng.uniform(0.025, 0.07), rng.uniform(0.006, 0.02), rng.uniform(0.003, 0.009))
        if piece.border and near_border(c, period, periodic, 0.2):
            continue
        piece.chips.append(chip)
    return piece


def _jag_points(a, b, amp, step, seed):
    """Interior points of a ragged crack from a to b; identical (reversed) for b to a."""
    flip = (round(b[0], 6), round(b[1], 6)) < (round(a[0], 6), round(a[1], 6))
    p, q = (b, a) if flip else (a, b)
    length = math.dist(p, q)
    count = max(1, round(length / step))
    nx, ny = -(q[1] - p[1]) / length, (q[0] - p[0]) / length
    key = (round(p[0] * 1e5), round(p[1] * 1e5), round(q[0] * 1e5), round(q[1] * 1e5))
    points = []
    for i in range(1, count):
        t = (i + (hash01(seed, *key, i, 7) - 0.5) * 0.5) / count
        offset = amp * (2 * hash01(seed, *key, i) - 1) * math.sqrt(math.sin(math.pi * t))
        points.append((p[0] + (q[0] - p[0]) * t + nx * offset, p[1] + (q[1] - p[1]) * t + ny * offset))
    return points[::-1] if flip else points


def jag(pieces, seed: int) -> None:
    """Replace straight crack and break edges with ragged polylines, consistently
    on both sides of each edge."""
    for piece in pieces:
        poly, kinds = [], []
        for i, kind in enumerate(piece.kinds):
            a, b = piece.poly[i], piece.poly[(i + 1) % len(piece.poly)]
            poly.append(a)
            kinds.append(kind)
            if kind in (CRACK, BREAK) and math.dist(a, b) > 0.03:
                amp, step = (0.004, 0.028) if kind == CRACK else (0.012, 0.035)
                for p in _jag_points(a, b, amp, step, seed):
                    poly.append(p)
                    kinds.append(kind)
        piece.poly, piece.kinds = poly, kinds


def _split(poly, kinds, n, d, kind):
    a = clip(poly, kinds, n, d, kind)
    b = clip(poly, kinds, (-n[0], -n[1]), -d, kind)
    return a, b


def _valid(poly, min_area=0.02, angle=28.0) -> bool:
    return len(poly) >= 3 and area(poly) >= min_area and min_angle(poly) >= angle


def crack(piece: Piece, rng, lines: int, style: dict) -> list:
    """Split a convex stone by full-length straight cracks (jagged later)."""
    parts = [(piece.poly, piece.kinds)]
    for _ in range(lines):
        for _attempt in range(8):
            cx, cy = centroid(piece.poly)
            x0, y0, x1, y1 = bounds(piece.poly)
            c = (cx + rng.uniform(-0.2, 0.2) * (x1 - x0), cy + rng.uniform(-0.2, 0.2) * (y1 - y0))
            angle = rng.uniform(0, math.pi)
            n = (math.cos(angle), math.sin(angle))
            d = n[0] * c[0] + n[1] * c[1]
            trial = []
            for poly, kinds in parts:
                for part in _split(poly, kinds, n, d, CRACK):
                    if len(part[0]) >= 3 and area(part[0]) > 1e-6:
                        trial.append(part)
            if len(trial) > len(parts) and all(_valid(p, 0.025, 25.0) for p, _ in trial):
                parts = trial
                break
    pieces = []
    for index, (poly, kinds) in enumerate(parts):
        r = core.rng(style.get('seed', 0), 'crack', *piece.key, index)
        tilt = (piece.tilt[0] + r.uniform(-0.006, 0.006), piece.tilt[1] + r.uniform(-0.006, 0.006))
        sink = r.uniform(0.0, style['sink']) if index else r.uniform(0.0, style['sink'] * 0.4)
        pieces.append(piece.copy(poly=poly, kinds=kinds, key=piece.key + (index,), tilt=tilt, sink=sink,
                                 chips=[c for c in piece.chips if inside(c[:2], poly)]))
    return pieces


def break_corner(piece: Piece, rng) -> tuple:
    """Knock a corner off: returns (remaining stone, corner outline) or (piece, None)."""
    poly = piece.poly
    n = len(poly)
    for _attempt in range(10):
        i = rng.randrange(n)
        v, nxt, prv = poly[i], poly[(i + 1) % n], poly[i - 1]
        ln, lp = math.dist(v, nxt), math.dist(v, prv)
        if ln < 0.2 or lp < 0.2:
            continue
        d1 = rng.uniform(0.09, min(0.3, ln * 0.45))
        d2 = rng.uniform(0.09, min(0.3, lp * 0.45))
        p1 = (v[0] + (nxt[0] - v[0]) * d1 / ln, v[1] + (nxt[1] - v[1]) * d1 / ln)
        p2 = (v[0] + (prv[0] - v[0]) * d2 / lp, v[1] + (prv[1] - v[1]) * d2 / lp)
        # Normal of the cut pointing towards the corner.
        nx, ny = -(p2[1] - p1[1]), p2[0] - p1[0]
        if nx * (v[0] - p1[0]) + ny * (v[1] - p1[1]) < 0:
            nx, ny = -nx, -ny
        length = math.hypot(nx, ny)
        nn = (nx / length, ny / length)
        d = nn[0] * p1[0] + nn[1] * p1[1]
        rest, corner = _split(poly, piece.kinds, nn, d, BREAK)
        if _valid(rest[0], 0.05, 25.0) and len(corner[0]) >= 3 and area(corner[0]) > 0.003:
            stone = piece.copy(poly=rest[0], kinds=rest[1], chips=[c for c in piece.chips if inside(c[:2], rest[0])])
            return stone, corner
    return piece, None


def fragments(dirt: Piece, rng, count: int, style: dict, period, periodic, parent: Piece = None) -> list:
    """Loose shards lying in a dirt patch."""
    result = []
    x0, y0, x1, y1 = bounds(dirt.poly)
    for k in range(count):
        for _attempt in range(25):
            radius = rng.uniform(0.045, 0.12)
            c = (rng.uniform(x0, x1), rng.uniform(y0, y1))
            if not inside(c, dirt.poly) or edge_distance(c, dirt.poly) < radius + 0.02:
                continue
            if any(math.dist(c, f.origin) < radius + 0.1 for f in result):
                continue
            sides = rng.randint(5, 7)
            start = rng.uniform(0, 2 * math.pi)
            angles = sorted(start + (j + rng.uniform(-0.3, 0.3)) * 2 * math.pi / sides for j in range(sides))
            poly = [(c[0] + math.cos(a) * radius * rng.uniform(0.7, 1.1), c[1] + math.sin(a) * radius * rng.uniform(0.55, 1.0))
                    for a in angles]
            if not simple(poly):
                continue
            shard = Piece(poly=poly, kinds=[JOINT] * len(poly), key=dirt.key + ('shard', k), origin=c, role='fragment')
            r = core.rng(style.get('seed', 0), 'shard', *shard.key)
            dress(shard, r, dict(style, chips=(0, 1), warp=0.0, jitter=0.0, joint=(0.0006, 0.0012),
                                 bevel_w=(0.004, 0.008), bevel_d=(0.002, 0.004)), period, periodic)
            shard.height = -0.007 + r.uniform(-0.003, 0.003)
            slope = r.uniform(0.02, 0.06)
            angle = r.uniform(0, 2 * math.pi)
            shard.tilt = (slope * math.cos(angle), slope * math.sin(angle))
            if parent is not None:
                shard.variation = min(1.0, max(0.0, parent.variation + r.uniform(-0.08, 0.08)))
            result.append(shard)
            break
    return result


def damage(pieces, seed: int, variant: str, style: dict, period, periodic) -> list:
    """Cracks, broken corners and missing stones on interior (non-border) stones."""
    out = []
    for piece in pieces:
        if piece.border or piece.role != 'stone':
            out.append(piece)
            continue
        r = core.rng(seed, 'damage', variant, *piece.key)
        u = r.random()
        if u < style['missing']:
            dirt = piece.copy(role='dirt', chips=[])
            out.append(dirt)
            out.extend(fragments(dirt, r, r.randint(*style['fragments']), style, period, periodic, piece))
        elif u < style['missing'] + style['broken']:
            stone, corner = break_corner(piece, r)
            out.append(stone)
            if corner is not None:
                dirt = piece.copy(poly=corner[0], kinds=corner[1], key=piece.key + ('corner',), role='dirt', chips=[])
                out.append(dirt)
                out.extend(fragments(dirt, r, r.randint(0, 1), style, period, periodic, piece))
        elif u < style['missing'] + style['broken'] + style['crack']:
            out.extend(crack(piece, r, r.randint(*style['crack_lines']), style))
        else:
            out.append(piece)
    jag(out, seed)
    return out


# --------------------------------------------------------------------------- layouts

def _torus_images(points, period):
    px, py = period
    return [((x + dx, y + dy), j) for j, (x, y) in enumerate(points)
            for dx in (-px, 0.0, px) for dy in (-py, 0.0, py)]


def torus_cells(sites, period) -> list:
    """Voronoi cell of each site on the torus, around the site's own position."""
    images = _torus_images(sites, period)
    cells = []
    for i, s in enumerate(sites):
        reach = 2.0
        poly = [(s[0] - reach, s[1] - reach), (s[0] + reach, s[1] - reach),
                (s[0] + reach, s[1] + reach), (s[0] - reach, s[1] + reach)]
        kinds = [JOINT] * 4
        near = sorted(((q[0] - s[0]) ** 2 + (q[1] - s[1]) ** 2, q) for q, j in images
                      if not (j == i and abs(q[0] - s[0]) < 1e-12 and abs(q[1] - s[1]) < 1e-12))
        radius = reach * math.sqrt(2)
        for d2, q in near:
            if d2 > 4 * radius * radius:
                break
            n = (q[0] - s[0], q[1] - s[1])
            d = (q[0] ** 2 + q[1] ** 2 - s[0] ** 2 - s[1] ** 2) * 0.5
            poly, kinds = clip(poly, kinds, n, d, JOINT)
            radius = max(math.dist(s, v) for v in poly)
        cells.append(poly)
    return cells


def _torus_distance2(a, b, period) -> float:
    dx = abs(a[0] - b[0]) % period[0]
    dy = abs(a[1] - b[1]) % period[1]
    dx, dy = min(dx, period[0] - dx), min(dy, period[1] - dy)
    return dx * dx + dy * dy


def poisson(rng, period, radius, count, valid=None, existing=()) -> list:
    """Dart throwing on the torus with a minimum spacing."""
    points = []
    tries = 0
    while len(points) < count and tries < count * 200:
        tries += 1
        p = (rng.uniform(0, period[0]), rng.uniform(0, period[1]))
        if valid is not None and not valid(p):
            continue
        if any(_torus_distance2(p, q, period) < radius * radius for q in points):
            continue
        if any(_torus_distance2(p, q, period) < (radius * 0.85) ** 2 for q in existing):
            continue
        points.append(p)
    return points


def lloyd(sites, period, iterations, movable=None, valid=None) -> list:
    sites = list(sites)
    for _ in range(iterations):
        cells = torus_cells(sites, period)
        for i, cell in enumerate(cells):
            if movable is not None and not movable[i]:
                continue
            c = centroid(cell)
            c = (c[0] % period[0], c[1] % period[1])
            if valid is None or valid(c):
                sites[i] = c
    return sites


class BorderGuard:
    """Which sites own the periodic border lines, and where other sites may go
    without changing any cell where it crosses a border."""

    def __init__(self, sites, period, margin=0.05, step=0.02):
        self.period = period
        images = _torus_images(sites, period)
        self.samples = []  # (edge point, owner distance)
        owners = set()
        px, py = period
        for axis, length in ((0, py), (1, px)):
            count = int(round(length / step))
            for k in range(count):
                e = (0.0, k * step) if axis == 0 else (k * step, 0.0)
                dists = sorted((math.dist(q, e), j) for q, j in images)
                best = dists[0][0]
                for dist, j in dists:
                    if dist > best + margin:
                        break
                    owners.add(j)
                self.samples.append((e, best))
        self.owners = owners

    def allows(self, p, margin=0.12) -> bool:
        px, py = self.period
        for dx in (-px, 0.0, px):
            for dy in (-py, 0.0, py):
                q = (p[0] + dx, p[1] + dy)
                if min(abs(q[0]), abs(q[1])) > 1.6:
                    continue
                for e, best in self.samples:
                    if abs(q[0] - e[0]) < best + margin and abs(q[1] - e[1]) < best + margin \
                            and math.dist(q, e) < best + margin:
                        return False
        return True


def _wrap_piece(poly, origin, period):
    """Shift an outline so its origin lies in [0, period)."""
    dx = -math.floor(origin[0] / period[0]) * period[0]
    dy = -math.floor(origin[1] / period[1]) * period[1]
    return [(x + dx, y + dy) for x, y in poly], (origin[0] + dx, origin[1] + dy)


def voronoi_family(seed: int, period, spacing: float, variants: dict) -> dict:
    """Irregular flagstones. Border-owning sites come from one relaxed base
    layout; each variant re-seeds the interior with its own spacing."""
    base_rng = core.rng(seed, 'voronoi', 'base')
    count = int(period[0] * period[1] / (spacing * spacing * 0.866))
    sites = poisson(base_rng, period, spacing * 0.78, count)
    sites = lloyd(sites, period, 2)
    guard = BorderGuard(sites, period)
    border = [s for j, s in enumerate(sites) if j in guard.owners]
    result = {}
    for name, options in variants.items():
        r = core.rng(seed, 'voronoi', name)
        inner_spacing = spacing * options.get('density', 1.0)
        inner_count = int((period[0] * period[1] - len(border) * spacing * spacing * 0.7) / (inner_spacing * inner_spacing * 0.866))
        inner = poisson(r, period, inner_spacing * 0.8, inner_count, guard.allows, border)
        all_sites = border + inner
        movable = [False] * len(border) + [True] * len(inner)
        all_sites = lloyd(all_sites, period, 2, movable, guard.allows)
        pieces = []
        for j, (site, cell) in enumerate(zip(all_sites, torus_cells(all_sites, period))):
            is_border = j < len(border)
            key = ('border', j) if is_border else ('inner', name, j)
            pieces.append(Piece(poly=cell, kinds=[JOINT] * len(cell), key=key, origin=site, border=is_border))
        result[name] = pieces
    return result


def _split_lengths(rng, total, low, high) -> list:
    lengths = []
    while sum(lengths) < total - low * 0.5:
        lengths.append(rng.uniform(low, high))
    scale = total / sum(lengths)
    return [length * scale for length in lengths]


def coursed_family(seed: int, period, depth: tuple, length: tuple, variants: dict,
                   skew: float = 0.018, wobble: float = 0.006) -> dict:
    """Random rectangular flags laid in courses along X. Course lines, the
    stone crossing x = 0 in every course and the whole course crossing y = 0 are
    shared by the family; other joints are per variant."""
    px, py = period
    r = core.rng(seed, 'coursed', 'base')
    depths = _split_lengths(r, py, *depth)
    y0 = r.uniform(0, py)
    # Keep every course line clear of y = 0 so exactly one course crosses it.
    while any(min((y0 + sum(depths[:k])) % py, py - (y0 + sum(depths[:k])) % py) < 0.06 for k in range(len(depths))):
        y0 = (y0 + 0.07) % py
    lines = [y0]
    for d in depths:
        lines.append(lines[-1] + d)
    phases = [[(r.uniform(0, 2 * math.pi), a) for a in (wobble, wobble * 0.6, wobble * 0.3)] for _ in depths]
    phases.append(phases[0])  # the last line is the first one again, one period up

    def line_y(k, x):
        return lines[k] + sum(a * math.sin(2 * math.pi * (f + 1) * x / px + ph) for f, (ph, a) in enumerate(phases[k]))

    def boundary(k, xa, xb):
        """Points along course line k from x = xa to xb (either direction)."""
        step = 0.25
        lo, hi = sorted((xa, xb))
        xs = [xa] + [g * step for g in range(math.floor(lo / step) + 1, math.ceil(hi / step)) if lo + 0.01 < g * step < hi - 0.01] + [xb]
        if xa > xb:
            xs = [xa] + sorted(xs[1:-1], reverse=True) + [xb]
        return [(x, line_y(k, x)) for x in xs]

    crossing_course = next(k for k in range(len(depths)) if (lines[k] % py) > (lines[k + 1] % py) or (lines[k] % py) < 1e-9)
    shared = {}
    for k in range(len(depths)):
        rk = core.rng(seed, 'coursed', 'course', k)
        first = rk.uniform(length[0], length[1])
        start = -rk.uniform(0.15, first - 0.15)
        joints = [(start + rk.uniform(-skew, skew), start + rk.uniform(-skew, skew))]
        end = start + first
        joints.append((end + rk.uniform(-skew, skew), end + rk.uniform(-skew, skew)))
        if k == crossing_course:
            for piece_length in _split_lengths(rk, px - first, *length)[:-1]:
                end += piece_length
                joints.append((end + rk.uniform(-skew, skew), end + rk.uniform(-skew, skew)))
            joints.append((joints[0][0] + px, joints[0][1] + px))
        shared[k] = joints
    result = {}
    for name, options in variants.items():
        rv = core.rng(seed, 'coursed', name)
        pieces = []
        for k in range(len(depths)):
            joints = list(shared[k])
            if k != crossing_course:
                end = joints[-1][0]
                scale = options.get('length_scale', 1.0)
                lengths = _split_lengths(rv, joints[0][0] + px - end, length[0] * scale, length[1] * scale)
                for piece_length in lengths[:-1]:
                    end += piece_length
                    joints.append((end + rv.uniform(-skew, skew), end + rv.uniform(-skew, skew)))
                joints.append((joints[0][0] + px, joints[0][1] + px))
            for s in range(len(joints) - 1):
                (b0, t0), (b1, t1) = joints[s], joints[s + 1]
                poly = boundary(k, b0, b1) + boundary(k + 1, t1, t0)
                origin = ((b0 + b1 + t0 + t1) * 0.25, (lines[k] + lines[k + 1]) * 0.5)
                is_border = k == crossing_course or s == 0
                poly, origin = _wrap_piece(poly, origin, period)
                key = ('course', k, s) if is_border else ('course', name, k, s)
                pieces.append(Piece(poly=poly, kinds=[JOINT] * len(poly), key=key, origin=origin, border=is_border))
        result[name] = pieces
    return result


def kerb_family(seed: int, length_period: float, width: float, length: tuple, variants: dict,
                skew: float = 0.012) -> dict:
    """A single course of kerb stones in [0, P] x [0, width], periodic along X,
    finished on both long sides. The stone crossing x = 0 is shared."""
    r = core.rng(seed, 'kerb', 'base')
    first = r.uniform(*length)
    start = -r.uniform(0.15, first - 0.15)
    shared = [(start + r.uniform(-skew, skew), start + r.uniform(-skew, skew)),
              (start + first + r.uniform(-skew, skew), start + first + r.uniform(-skew, skew))]
    result = {}
    for name, options in variants.items():
        rv = core.rng(seed, 'kerb', name)
        joints = list(shared)
        end = start + first
        for piece_length in _split_lengths(rv, length_period - first, *length)[:-1]:
            end += piece_length
            joints.append((end + rv.uniform(-skew, skew), end + rv.uniform(-skew, skew)))
        joints.append((shared[0][0] + length_period, shared[0][1] + length_period))
        pieces = []
        for s in range(len(joints) - 1):
            (b0, t0), (b1, t1) = joints[s], joints[s + 1]
            poly = [(b0, 0.0), (b1, 0.0), (t1, width), (t0, width)]
            origin = ((b0 + b1 + t0 + t1) * 0.25, width * 0.5)
            poly, origin = _wrap_piece(poly, origin, (length_period, 1e9))
            key = ('kerb', s) if s == 0 else ('kerb', name, s)
            pieces.append(Piece(poly=poly, kinds=[FINISH, JOINT, FINISH, JOINT], key=key, origin=origin, border=s == 0))
        result[name] = pieces
    return result


# --------------------------------------------------------------------------- geometry

LODS = (
    dict(step=0.075, chip_step=0.018, grid=0.22, profile='round', sides=True, dirt_step=0.06, dirt_grid=0.085),
    dict(step=0.16, chip_step=0.045, grid=None, profile='chamfer', sides=True, dirt_step=0.12, dirt_grid=0.16),
    dict(step=0.6, chip_step=None, grid=None, profile='flat', sides=False, dirt_step=0.3, dirt_grid=None),
)


def _edge_params(piece: Piece, kind: str) -> tuple:
    """(arris inset, bevel width, bevel drop, foot inset) for one edge."""
    if kind == CRACK:
        return 0.0015, 0.0025, 0.001, 0.0
    if kind == BREAK:
        return 0.0025, 0.007, 0.006, 0.0
    j = piece.joint
    bw, bd = piece.bevel
    return j, bw, bd, (j if kind == FINISH else 0.25 * j)


class Floor:
    """Emits pieces into a stone Builder and a dirt Builder for one module and LOD."""

    def __init__(self, stones, dirt, period, periodic, lod: int, seed: int):
        self.stones, self.dirt = stones, dirt
        self.period, self.periodic = period, periodic
        self.lod = LODS[lod]
        self.level = lod
        self.seed = seed
        self.counts = dict(stones=0, fragments=0, dirt=0, chips=0, skipped=0, simplified=0, border_fallbacks=0)
        self.top_range = [math.inf, -math.inf]  # walkable stone tops, metres

    # ---- placement on the torus
    def offsets(self, poly) -> list:
        x0, y0, x1, y1 = bounds(poly)
        px, py = self.period
        result = []
        for dx in ((-px, 0.0, px) if self.periodic[0] else (0.0,)):
            for dy in ((-py, 0.0, py) if self.periodic[1] else (0.0,)):
                if x1 + dx > 1e-6 and x0 + dx < px - 1e-6 and y1 + dy > 1e-6 and y0 + dy < py - 1e-6:
                    result.append((dx, dy))
        return result

    def emit(self, piece: Piece) -> None:
        offsets = self.offsets(piece.poly)
        if not offsets:
            return
        if piece.role == 'dirt':
            chunk = self._dirt(piece)
            target = self.dirt
            self.counts['dirt'] += 1
        else:
            simplified = self.counts['simplified']
            chunk = self._stone(piece)
            target = self.stones
            if piece.border and (chunk is None or self.counts['simplified'] != simplified):
                # A fallback changes the bevel at the cut and would break family tiling.
                self.counts['border_fallbacks'] += 1
            if chunk is None:
                self.counts['skipped'] += 1
                return
            self.counts['fragments' if piece.role == 'fragment' else 'stones'] += 1
            self.counts['chips'] += len(piece.chips)
        for dx, dy in offsets:
            self._place(target, chunk, dx, dy)

    @staticmethod
    def _place(builder, chunk, dx, dy) -> None:
        verts = [builder.bm.verts.new((x + dx, y + dy, z)) for x, y, z in chunk['verts']]
        for face, uvs, colors in chunk['faces']:
            try:
                f = builder.bm.faces.new([verts[i] for i in face])
            except ValueError:
                continue
            for loop, uv, color in zip(f.loops, uvs, colors):
                loop[builder.uv].uv = uv
                loop[builder.color] = color
        builder.pieces += 1

    # ---- surfaces
    def height(self, piece: Piece, x: float, y: float) -> float:
        h = piece.height - piece.sink + piece.tilt[0] * (x - piece.origin[0]) + piece.tilt[1] * (y - piece.origin[1])
        if piece.warp:
            h += piece.warp * fbm(x, y, self.period[0], self.seed + 11, 6)
        return h

    def stone_uv(self, piece: Piece, x: float, y: float) -> tuple:
        angle, u0, v0 = piece.uv
        c, s = math.cos(angle), math.sin(angle)
        dx, dy = x - piece.origin[0], y - piece.origin[1]
        return (u0 + c * dx - s * dy, v0 + s * dx + c * dy)

    def _samples(self, piece: Piece) -> list:
        poly, step = piece.poly, self.lod['step']
        chip_step = self.lod['chip_step']
        n = len(poly)
        # Inset rings fold if an edge sample lies within reach of a corner's
        # miter, so keep samples clear by (deepest inset) * cot(angle / 2).
        reach = []
        for i in range(n):
            u = (poly[i - 1][0] - poly[i][0], poly[i - 1][1] - poly[i][1])
            v = (poly[(i + 1) % n][0] - poly[i][0], poly[(i + 1) % n][1] - poly[i][1])
            angle = abs(math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1]))
            deepest = max(sum(_edge_params(piece, piece.kinds[k])[:2]) for k in (i - 1, i))
            reach.append(deepest * abs(math.cos(angle / 2) / max(math.sin(angle / 2), 0.2)) + 0.003)
        out = []
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            length = math.dist(a, b)
            if length < 1e-9:
                continue
            near_start = min(reach[i], length * 0.45) / length
            near_end = 1 - min(reach[(i + 1) % n], length * 0.45) / length
            ts = {0.0}
            # Samples sit at fixed steps along the edge's infinite line, so a
            # border edge is sampled identically whatever its far corner is.
            ex, ey = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            start = a[0] * ex + a[1] * ey
            k = math.floor(start / step) + 1
            while k * step < start + length:
                ts.add((k * step - start) / length)
                k += 1
            if chip_step:
                for cx, cy, radius, *_ in piece.chips:
                    t0 = ((cx - a[0]) * (b[0] - a[0]) + (cy - a[1]) * (b[1] - a[1])) / (length * length)
                    off = abs((cx - a[0]) * (b[1] - a[1]) - (cy - a[1]) * (b[0] - a[0])) / length
                    if off < radius:
                        half = math.sqrt(radius * radius - off * off) / length
                        t = max(0.0, t0 - half)
                        while t < min(1.0, t0 + half):
                            ts.add(t)
                            t += chip_step / length
            kept = []
            for t in sorted(ts):
                if t >= near_end:
                    break
                if t and (t < near_start or (t - kept[-1]) * length < 0.004):
                    continue
                kept.append(t)
            for t in kept:
                out.append(((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), i, t == 0.0))
        return out

    def _offset(self, piece, normals, dirs, sample, distance_of):
        p, i, corner = sample
        n = len(piece.poly)
        if not corner:
            d = distance_of(piece.kinds[i])
            return (p[0] + normals[i][0] * d, p[1] + normals[i][1] * d), normals[i]
        prev = (i - 1) % n
        d0, d1 = distance_of(piece.kinds[prev]), distance_of(piece.kinds[i])
        n0, n1, t0 = normals[prev], normals[i], dirs[prev]
        denom = t0[0] * n1[0] + t0[1] * n1[1]
        bis = (n0[0] + n1[0], n0[1] + n1[1])
        length = math.hypot(*bis)
        bis = (bis[0] / length, bis[1] / length) if length > 1e-9 else n1
        if abs(denom) < 0.08:
            d = (d0 + d1) * 0.5
            return (p[0] + bis[0] * d, p[1] + bis[1] * d), bis
        s = (d1 - d0 * (n0[0] * n1[0] + n0[1] * n1[1])) / denom
        q = (n0[0] * d0 + t0[0] * s, n0[1] * d0 + t0[1] * s)
        limit = 3.0 * max(d0, d1)
        ql = math.hypot(*q)
        if ql > limit:
            q = (bis[0] * limit, bis[1] * limit)
        return (p[0] + q[0], p[1] + q[1]), bis

    def _rings(self, piece: Piece, chips: bool, bevel_scale: float) -> tuple:
        poly = piece.poly
        n = len(poly)
        dirs, normals = [], []
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            length = max(math.dist(a, b), 1e-12)
            t = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
            dirs.append(t)
            normals.append((-t[1], t[0]))
        samples = self._samples(piece)
        params = {kind: _edge_params(piece, kind) for kind in set(piece.kinds)}
        profile = self.lod['profile']
        fractions = {'round': (0.0, 0.45, 1.0), 'chamfer': (0.0, None, 1.0), 'flat': (None, None, 0.0)}[profile]
        rings = {}
        for name, fraction in zip('AMT', fractions):
            if fraction is None:
                continue
            rings[name] = [self._offset(piece, normals, dirs, s, lambda k, f=fraction: params[k][0] + params[k][1] * f * bevel_scale)
                           for s in samples]
        rings['F'] = [self._offset(piece, normals, dirs, s, lambda k: params[k][3]) for s in samples]
        result = {name: [] for name in rings}
        wear = {name: [] for name in rings}
        for index, sample in enumerate(samples):
            p, i, corner = sample
            kind = piece.kinds[i]
            bd = params[kind][2] * bevel_scale
            f = 0.0
            if chips:
                for cx, cy, radius, *_ in piece.chips:
                    d = math.hypot(p[0] - cx, p[1] - cy)
                    if d < radius:
                        f = max(f, (1 - (d / radius) ** 2) ** 2 * (0.75 + 0.25 * hash01(self.seed, index, len(piece.chips))))
            chip = max(piece.chips, key=lambda c: -math.hypot(p[0] - c[0], p[1] - c[1])) if (f > 0) else None
            depth = chip[3] if chip else 0.0
            drop = chip[4] if chip else 0.0
            jitter = piece.jitter * (2 * pnoise(p[0], p[1], 40, self.period[0], self.seed + 3) - 1) if self.level == 0 else 0.0
            soft = 0.4 if kind == CRACK else 1.0
            for name in rings:
                (x, y), direction = rings[name][index]
                if name == 'F':
                    result[name].append((x, y, FOOT_Z))
                    wear[name].append(0.3)
                    continue
                push = {'A': 1.0, 'M': 0.9, 'T': 0.75}[name] * depth * f + jitter
                x, y = x + direction[0] * push, y + direction[1] * push
                h = self.height(piece, x, y)
                if profile == 'flat':
                    z = h
                elif name == 'T':
                    z = h  # chips break the arris only; the cap stays a clean plane
                elif name == 'M':
                    z = h - 0.3 * bd - 0.8 * drop * f
                else:
                    z = h - bd - drop * f
                z = max(z, BED_Z + 0.003)
                result[name].append((x, y, z))
                base = {'A': 1.0, 'M': 0.75, 'T': 0.25}[name] * soft
                wear[name].append(min(1.0, base + (1 - base) * f))
        return result, wear

    def _stone(self, piece: Piece):
        poly, kinds = collapse_short_edges(piece.poly, piece.kinds, 0.022)
        piece = piece.copy(poly=poly, kinds=kinds)
        for chips, bevel_scale in ((True, 1.0), (False, 0.6), (False, 0.0)):
            rings, wear = self._rings(piece, chips and self.level < 2, bevel_scale)
            top = rings['T' if 'T' in rings else 'A']
            outline = [(x, y) for x, y, _ in top]
            if simple(outline) and all(simple([(x, y) for x, y, _ in ring]) for ring in rings.values()):
                break
        else:
            return None
        if bevel_scale < 1.0:
            self.counts['simplified'] += 1
        verts, faces = [], []
        g = piece.variation

        def add(points):
            start = len(verts)
            verts.extend(points)
            return list(range(start, len(verts)))

        def color(w):
            return (1.0, g, w, 1.0)

        names = [name for name in 'TMA' if name in rings]
        ids = {name: add(rings[name]) for name in names}
        if self.lod['sides']:
            ids['F'] = add(rings['F'])
            names.append('F')
        count = len(outline)
        # Bands from the top ring outwards and down: (outer_i, outer_i+1, inner_i+1, inner_i).
        for inner, outer in zip(names, names[1:]):
            for i in range(count):
                j = (i + 1) % count
                face = [ids[outer][i], ids[outer][j], ids[inner][j], ids[inner][i]]
                uvs = [self.stone_uv(piece, *verts[v][:2]) for v in face]
                ws = [wear[outer][i], wear[outer][j], wear[inner][j], wear[inner][i]]
                if outer == 'F':
                    ws = [0.3, 0.3, 0.55, 0.55]
                faces.append((face, uvs, [color(w) for w in ws]))
        # Cap: top ring plus interior lattice points, constrained Delaunay.
        top_name = names[0]
        cap_points = list(outline)
        cap_z = [verts[v][2] for v in ids[top_name]]
        grid = self.lod['grid']
        if grid:
            x0, y0, x1, y1 = bounds(outline)
            for gx in range(math.floor(x0 / grid), math.ceil(x1 / grid) + 1):
                for gy in range(math.floor(y0 / grid), math.ceil(y1 / grid) + 1):
                    p = ((gx + 0.5) * grid, (gy + 0.5) * grid)
                    if inside(p, outline) and edge_distance(p, outline) > grid * 0.4:
                        cap_points.append(p)
        tri_verts, _, tri_faces, orig, _, _ = geometry.delaunay_2d_cdt(
            [Vector(p) for p in cap_points], [(i, (i + 1) % count) for i in range(count)],
            [list(range(count))], 1, 1e-7, True)
        index_of = {}
        for k, (v, sources) in enumerate(zip(tri_verts, orig)):
            source = sources[0] if sources else None
            if source is not None and source < count:
                index_of[k] = ids[top_name][source]
            else:
                x, y = v.x, v.y
                index_of[k] = add([(x, y, self.height(piece, x, y))])[0]
        for tri in tri_faces:
            face = [index_of[k] for k in tri]
            if len(set(face)) < 3:
                continue
            if piece.role == 'stone':
                for v in face:
                    self.top_range[0] = min(self.top_range[0], verts[v][2])
                    self.top_range[1] = max(self.top_range[1], verts[v][2])
            uvs = [self.stone_uv(piece, *verts[v][:2]) for v in face]
            ws = [wear[top_name][face_id - ids[top_name][0]] if ids[top_name][0] <= face_id < ids[top_name][0] + count else 0.0
                  for face_id in face]
            faces.append((face, uvs, [color(w) for w in ws]))
        return dict(verts=verts, faces=faces)

    def _dirt(self, piece: Piece):
        step, grid = self.lod['dirt_step'], self.lod['dirt_grid']
        poly = piece.poly
        outline = []
        for i, a in enumerate(poly):
            b = poly[(i + 1) % len(poly)]
            k = max(1, round(math.dist(a, b) / step))
            outline.extend((a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k) for j in range(k))
        count = len(outline)
        points = list(outline)
        if grid:
            x0, y0, x1, y1 = bounds(outline)
            for gx in range(math.floor(x0 / grid), math.ceil(x1 / grid) + 1):
                for gy in range(math.floor(y0 / grid), math.ceil(y1 / grid) + 1):
                    p = ((gx + 0.5) * grid, (gy + 0.5) * grid)
                    if inside(p, outline) and edge_distance(p, outline) > grid * 0.35:
                        points.append(p)
        tri_verts, _, tri_faces, _, _, _ = geometry.delaunay_2d_cdt(
            [Vector(p) for p in points], [(i, (i + 1) % count) for i in range(count)],
            [list(range(count))], 1, 1e-7, True)
        verts, colors = [], []
        for v in tri_verts:
            x, y = v.x, v.y
            rim = min(1.0, edge_distance((x, y), poly) / 0.07)
            rim = rim * rim * (3 - 2 * rim)
            lump = 0.5 + 0.5 * fbm(x, y, self.period[0], self.seed + 29, 10)
            clod = fbm(x, y, self.period[0], self.seed + 31, 28)
            z = DIRT_EDGE_Z + rim * (0.003 + 0.008 * lump + 0.0015 * clod)
            verts.append((x, y, z))
            colors.append((1.0, 0.25 + 0.5 * pnoise(x, y, 16, self.period[0], self.seed + 5), 0.0, 1.0))
        faces = [(list(t), [verts[k][:2] for k in t], [colors[k] for k in t]) for t in tri_faces]
        return dict(verts=verts, faces=faces)

    def bedding(self, cells: int) -> None:
        """Flat dark bed under the whole module, seen through joints."""
        px, py = self.period
        nx, ny = max(1, round(cells * px / max(px, py))), max(1, round(cells * py / max(px, py)))
        grid = [[self.dirt.bm.verts.new((px * i / nx, py * j / ny, BED_Z)) for j in range(ny + 1)] for i in range(nx + 1)]
        for i in range(nx):
            for j in range(ny):
                quad = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                f = self.dirt.bm.faces.new(quad)
                for loop in f.loops:
                    loop[self.dirt.uv].uv = loop.vert.co.xy
                    loop[self.dirt.color] = (1.0, 0.5, 0.0, 1.0)


def clip_module(bm, period, periodic) -> None:
    """Cut all geometry at the periodic borders of [0, P] x [0, Q]."""
    for axis in (0, 1):
        if not periodic[axis]:
            continue
        for value, sign in ((0.0, -1.0), (period[axis], 1.0)):
            co = [0.0, 0.0, 0.0]
            no = [0.0, 0.0, 0.0]
            co[axis] = value
            no[axis] = sign
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-7, plane_co=co, plane_no=no, clear_outer=True)


# --------------------------------------------------------------------------- checks

def border_profile(mesh, axis: int, value: float, tol: float = 1e-4) -> tuple:
    """Vertices and edges lying on the plane coordinate[axis] == value, as
    (u, z) points with u the other horizontal coordinate."""
    other = 1 - axis
    index = {}
    points = []
    for v in mesh.vertices:
        if abs(v.co[axis] - value) < tol:
            index[v.index] = len(points)
            points.append((v.co[other], v.co.z))
    segments = [(index[a], index[b]) for a, b in (e.vertices for e in mesh.edges) if a in index and b in index]
    return points, segments


def profile_distance(a, b, bucket: float = 0.05) -> float:
    """Largest distance (metres, in the border plane) from any border vertex of
    `a` to the border polyline of `b`."""
    points_b, segments_b = b
    buckets = {}
    for s, (i, j) in enumerate(segments_b):
        u0, u1 = sorted((points_b[i][0], points_b[j][0]))
        for k in range(math.floor(u0 / bucket), math.floor(u1 / bucket) + 1):
            buckets.setdefault(k, []).append(s)
    lone = {}
    for k, p in enumerate(points_b):
        lone.setdefault(math.floor(p[0] / bucket), []).append(k)
    worst = 0.0
    for p in a[0]:
        k = math.floor(p[0] / bucket)
        best = math.inf
        for kk in (k - 1, k, k + 1):
            for s in buckets.get(kk, ()):
                i, j = segments_b[s]
                best = min(best, segment_distance(p, points_b[i], points_b[j]))
            for q in lone.get(kk, ()):
                best = min(best, math.dist(p, points_b[q]))
        worst = max(worst, best)
    return worst


def seam_error(mesh_a, mesh_b, period, periodic) -> dict:
    """Max mismatch (mm) between the +X border of `mesh_a` and the -X border of
    `mesh_b`, both ways, and likewise for Y."""
    result = {}
    for axis, name in ((0, 'x'), (1, 'y')):
        if not periodic[axis]:
            continue
        high = border_profile(mesh_a, axis, period[axis])
        low = border_profile(mesh_b, axis, 0.0)
        if not high[0] or not low[0]:
            result[name] = {'mm': None, 'vertices': [len(high[0]), len(low[0])]}
            continue
        mm = max(profile_distance(high, low), profile_distance(low, high)) * 1000
        result[name] = {'mm': round(mm, 4), 'vertices': [len(high[0]), len(low[0])]}
    return result


def average_border_colour(mesh, period, periodic, tol: float = 1e-4) -> int:
    """Average the baked AO (Color.R) of coincident vertices on opposite
    borders so neighbouring modules shade identically at the seam."""
    color = mesh.color_attributes['Color']
    corner = color.domain == 'CORNER'
    groups = {}
    for v in mesh.vertices:
        on = [axis for axis in (0, 1) if periodic[axis] and
              (abs(v.co[axis]) < tol or abs(v.co[axis] - period[axis]) < tol)]
        if not on:
            continue
        key = [round(v.co.x / tol), round(v.co.y / tol), round(v.co.z / tol)]
        for axis in on:
            key[axis] = 0
        groups.setdefault(tuple(key), []).append(v.index)
    loops_of = {}
    if corner:
        for loop in mesh.loops:
            loops_of.setdefault(loop.vertex_index, []).append(loop.index)
    changed = 0
    for members in groups.values():
        if len(members) < 2:
            continue
        slots = [i for v in members for i in (loops_of.get(v, []) if corner else [v])]
        if not slots:
            continue
        mean = sum(color.data[i].color[0] for i in slots) / len(slots)
        for i in slots:
            c = color.data[i].color
            color.data[i].color = (mean, c[1], c[2], c[3])
        changed += 1
    return changed
