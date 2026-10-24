"""Blender background: rubble, gravel and grime at the wall bases of every
stone room of Red Descent, dropped with rigid-body physics against the real
stone builds and baked for the game (board task T-179).

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_room_rubble.py -- \\
        [--arch content/environments/procedural_architecture_v1] \\
        [--layout content/environments/procedural_bridge_v1/layout.json] \\
        [--rooms antechamber,entry] [--seed 179] \\
        [--out content/environments/procedural_rubble_v1/rooms] [--no-review]

Per room (every id in <arch>/index.json "rooms" unless --rooms is given):

1. The room's stone build (<arch>/rooms/<id>.glb: Stone_*, Mortar_*) is
   imported. Rays measure the real wall foot every 10 cm along the plan
   outline, and find the doorways (rays that pass through the wall).
2. A density along the wall foot says where material has fallen: corners,
   door jambs and a few collapse spots, sparse elsewhere, broken up by noise.
   Walking ribbons (layout routes, width/2 + 0.3 m, at the floor height) get
   nothing taller than 4 cm.
3. Wall-like stones (procgen.stones) are shattered by Voronoi fracture around
   an impact corner into 2-35 cm fragments with chipped corners and rough
   fresh breaks; fragments of one stone land together. Angular rocks
   (3.5-9 cm) and grit (down to about 1.5 cm) fill the rest of about 20k
   triangles. A grime bed (dust and crushed mortar, up to 5.5 cm deep) lies
   along the heaps and fades into the floor.
4. Pieces are deposited big first: each is tried at several spots, lowered
   onto what is there, and the spot furthest below a talus wedge (34 deg)
   wins, so big pieces sit at the foot and grit runs out as a skirt. Bullet
   then settles everything against the wall meshes (MESH), the bed (convex
   patches) and the floor, 40 substeps and 60 iterations, in short runs that
   hold pieces once they are still (Bullet hulls lack static friction and
   creep otherwise). Finally every piece is let go again from the exported
   pose and measured (the stability check in the report).
5. Anything that ends inside a walking ribbon above 4 cm, leaves the room,
   does not settle or floats is discarded; the rest is merged (Rubble_*),
   AO-baked against the walls and floor and exported with convex collision
   hulls for pieces over 25 cm.

Outputs: <out>/<id>.glb, <out>/<id>.json and Cycles review renders under
<out>/review/. Everything is in Godot world coordinates, like the room GLBs.
"""
import argparse
import bisect
import json
import math
import sys
import tempfile
import time
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
import numpy
from mathutils import Matrix, Quaternion, Vector, noise
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from procgen import bake, core, disturb, export, fracture, rigid, stones

ARCH = core.ROOT / 'content/environments/procedural_architecture_v1'
LAYOUT = core.ROOT / 'content/environments/procedural_bridge_v1/layout.json'
OUT = core.ROOT / 'content/environments/procedural_rubble_v1/rooms'
ROCK = core.ROOT / 'content/environments/dungeon_pbr_v2/marble_rock_03'
RUBBLE_ROCK = core.ROOT / 'content/environments/dungeon_pbr_v2/Rocks025'

SEED = 179
TRI_BUDGET = 20000          # per room, all visual meshes
ROUTE_PAD = 0.3             # clear beyond half the route width
ROUTE_HEIGHT = 0.04         # nothing above floor + this may stay on a walking ribbon
ROUTE_LEVEL = 24.0          # any walk the room carries counts: stairs and galleries above the floor too (T-185)
HULL_SIZE = 0.25            # pieces longer than this get a Godot convex hull
PIECE_MAX = 0.35
PIECE_MIN = 0.02
TONE = (0.7, 1.15)          # per-piece grey multiplier
TONE_STORE = 1.2            # Color.G holds tone / TONE_STORE until the AO bake
FRESH = 1.07                # fresh break faces a shade lighter than weathered faces
GRIME_TONE = (0.5, 1.0)     # deep grime at the wall .. bare edge (blends into the floor)
BED_HEIGHT = 0.055          # grime and grit at the wall foot under the biggest heaps
BED_CELL = 0.11
DENSITY = 2300.0
PIECE_MARGIN = 0.002
GRAVEL_MARGIN = 0.0015
STATIC_MARGIN = 0.002
CROP = 1.6                  # wall geometry above floor + CROP takes no part in the drop
FOOT_STEP = 0.1
HEAP_HEIGHT = 0.55          # tallest talus wedge (corners)
REPOSE = math.radians(34.0)
SETTLE_SPEED = 0.01         # m/s, bound-box corners
MAX_GAP = 0.01
AO_DISTANCE = 0.35
DOWN = Vector((0.0, 0.0, -1.0))
KINDS = (('squared_rubble', 0.45), ('ashlar', 0.3), ('rubble', 0.25))


# ---------------------------------------------------------------- plan helpers

def plan(godot_xz) -> Vector:
    """Godot (x, z) plan point -> Blender (x, y, 0)."""
    return Vector((godot_xz[0], -godot_xz[1], 0.0))


def ccw(points: list) -> list:
    area = sum(a.x * b.y - b.x * a.y for a, b in zip(points, points[1:] + points[:1]))
    return points if area > 0 else list(reversed(points))


def contains(points: list, at: Vector) -> bool:
    result = False
    for a, b in zip(points, points[1:] + points[:1]):
        if (a.y > at.y) != (b.y > at.y) and at.x < a.x + (at.y - a.y) * (b.x - a.x) / (b.y - a.y):
            result = not result
    return result


def inset(points: list, distance: float) -> list:
    """Convex counter-clockwise polygon moved inward by `distance`."""
    lines = []
    for a, b in zip(points, points[1:] + points[:1]):
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0.0))
        lines.append((a + n * distance, d))
    result = []
    for (p, d), (q, e) in zip(lines[-1:] + lines[:-1], lines):
        denom = d.x * e.y - d.y * e.x
        if abs(denom) < 1e-9:
            result.append(q.copy())
            continue
        w = q - p
        t = (w.x * e.y - w.y * e.x) / denom
        result.append(p + d * t)
    return result


class Routes:
    """Walking ribbons of the layout near one room's floor."""

    def __init__(self, layout: dict, floor: float):
        self.floor = floor
        self.segments = []
        for route in layout['routes']:
            radius = route['width'] * 0.5 + ROUTE_PAD
            for p, q in zip(route['points'], route['points'][1:]):
                if min(abs(p[1] - floor), abs(q[1] - floor)) > ROUTE_LEVEL + 6.0:
                    continue
                self.segments.append((plan((p[0], p[2])), plan((q[0], q[2])), p[1], q[1], radius, route['id']))

    def clearance(self, x: float, y: float) -> float:
        """Plan distance outside the nearest ribbon at floor height (negative inside)."""
        best = math.inf
        at = Vector((x, y, 0.0))
        for a, b, ya, yb, radius, _ in self.segments:
            ab = b - a
            length2 = ab.length_squared
            t = 0.0 if length2 < 1e-12 else max(0.0, min(1.0, (at - a).dot(ab) / length2))
            if abs(ya + (yb - ya) * t - self.floor) > ROUTE_LEVEL:
                continue
            best = min(best, (at - (a + ab * t)).length - radius)
        return best

    def ribbons(self) -> list:
        return [{'route': rid, 'from': [round(a.x, 3), round(-a.y, 3)], 'to': [round(b.x, 3), round(-b.y, 3)],
                 'clear_radius_m': round(r, 3)}
                for a, b, ya, yb, r, rid in self.segments
                if min(abs(ya - self.floor), abs(yb - self.floor)) <= ROUTE_LEVEL]


# ---------------------------------------------------------------- room import

def import_room(path: Path) -> list:
    """Stone_* and Mortar_* meshes of a room build, transforms applied."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    walls = []
    for obj in [o for o in bpy.data.objects if o not in before]:
        if obj.type == 'MESH' and obj.name.startswith(('Stone_', 'Mortar_')) and 'colonly' not in obj.name:
            walls.append(obj)
        else:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in walls:
        obj.parent = None
    bpy.context.view_layer.update()
    for obj in walls:
        if obj.matrix_world != Matrix.Identity(4):
            obj.data.transform(obj.matrix_world)
            obj.matrix_world = Matrix.Identity(4)
        obj.data.update()
    return walls


def crop_walls(walls: list, floor: float) -> bpy.types.Object:
    """One mesh of all wall geometry below floor + CROP: the drop's static collider."""
    bm = bmesh.new()
    for obj in walls:
        bm.from_mesh(obj.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                           plane_co=(0.0, 0.0, floor + CROP), plane_no=(0.0, 0.0, 1.0), clear_outer=True)
    mesh = bpy.data.meshes.new('WallLow')
    bm.to_mesh(mesh)
    bm.free()
    return core.link(bpy.data.objects.new('WallLow', mesh))


def bvh_of(objects) -> BVHTree:
    verts, polys = [], []
    for obj in objects:
        base = len(verts)
        verts += [obj.matrix_world @ v.co for v in obj.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in obj.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


# ---------------------------------------------------------------- wall foot and density

class Foot:
    __slots__ = ('p', 'n', 't', 's', 'edge', 'opening', 'rho', 'H', 'R', 'valid', 'mass', 'heap', 'top')


def wall_feet(outline: list, walls: BVHTree, floor: float) -> tuple:
    """Samples every FOOT_STEP along the outline: the most protruding wall
    surface up to 1 m above the floor (the foot) and doorway flags."""
    feet, corners, s0 = [], [], 0.0
    for edge, (a, b) in enumerate(zip(outline, outline[1:] + outline[:1])):
        corners.append(s0)
        length = (b - a).length
        d = (b - a) / length
        n = Vector((-d.y, d.x, 0.0))
        count = max(2, int(round(length / FOOT_STEP)))
        for k in range(count):
            u = (k + 0.5) / count
            p = a + (b - a) * u
            origin = p + n * 2.5
            hits = []
            for h in (0.03, 0.15, 0.4, 0.7, 1.0):
                hit = walls.ray_cast(Vector((origin.x, origin.y, floor + h)), -n, 4.0)
                if hit[0] is not None:
                    hits.append(hit[3])
            through = 0
            for h in (1.3, 1.8):
                hit = walls.ray_cast(Vector((origin.x, origin.y, floor + h)), -n, 4.2)
                through += hit[0] is None
            foot = Foot()
            foot.opening = through == 2 or not hits
            face = 2.5 - min(hits) if hits else 0.45
            foot.p, foot.n, foot.t = p + n * face, n, d
            foot.s, foot.edge = s0 + u * length, edge
            feet.append(foot)
        s0 += length
    return feet, corners, s0


def arc(a: float, b: float, perimeter: float) -> float:
    d = abs(a - b) % perimeter
    return min(d, perimeter - d)


def density(feet: list, corners: list, perimeter: float, routes: Routes, rng) -> dict:
    """Where material has come down: corners, door jambs and collapse spots,
    sparse elsewhere, broken up by noise along the wall."""
    for foot in feet:
        probe = foot.p + foot.n * 0.25
        foot.valid = not foot.opening and routes.clearance(probe.x, probe.y) > 0.12
    jambs = []
    for prev, foot in zip(feet[-1:] + feet[:-1], feet):
        if prev.opening != foot.opening:
            jambs.append(foot.s if not foot.opening else prev.s)
    valid = [f for f in feet if f.valid]
    falls = []
    for _ in range(rng.randint(1, 2)):
        if valid:
            falls.append((rng.choice(valid).s, rng.uniform(0.7, 1.15), rng.uniform(0.5, 0.9)))
    # Not every corner caught the same: some hold a real heap, some a little.
    heaps = [(s, rng.choices((rng.uniform(0.95, 1.3), rng.uniform(0.35, 0.6), rng.uniform(0.05, 0.2)),
                             weights=(0.35, 0.3, 0.35))[0], 0.8) for s in corners]
    heaps += [(s, rng.uniform(0.35, 0.75), 0.45) for s in jambs]
    heaps += falls
    offset = Vector((rng.uniform(0, 500), rng.uniform(0, 500), 0.0))
    for foot in feet:
        if not foot.valid:
            foot.rho, foot.H, foot.R = 0.0, 0.0, 0.2
            continue
        rho = 0.06 + sum(a * math.exp(-(arc(foot.s, s, perimeter) / w) ** 2) for s, a, w in heaps)
        wobble = noise.noise(offset + Vector((foot.s * 0.6, 0.0, 0.0)), noise_basis='PERLIN_ORIGINAL')
        foot.rho = rho * max(0.2, 1.0 + 0.5 * wobble)
        foot.H = HEAP_HEIGHT * min(1.0, foot.rho) ** 0.85
        foot.R = 0.18 + foot.H / math.tan(REPOSE)
    return {'corners': len(corners), 'jambs': len(jambs), 'collapse_spots': len(falls)}


class Field:
    """Nearest-foot lookups, the talus profile and spot sampling per size class."""

    def __init__(self, feet: list):
        self.feet = feet
        self.kd = KDTree(len(feet))
        for i, f in enumerate(feet):
            self.kd.insert(f.p, i)
        self.kd.balance()
        self.s = [f.s for f in feet]
        self.cumulative = {}

    def nearest(self, x: float, y: float) -> Foot:
        return self.feet[self.kd.find(Vector((x, y, 0.0)))[1]]

    def depth(self, x: float, y: float) -> tuple:
        foot = self.nearest(x, y)
        return foot, (Vector((x, y, 0.0)) - foot.p).dot(foot.n)

    def profile(self, x: float, y: float) -> float:
        foot, d = self.depth(x, y)
        if d <= 0.0:
            return foot.H
        return foot.H * max(0.0, 1.0 - d / foot.R)

    def pick(self, rng, gamma: float) -> Foot:
        if gamma not in self.cumulative:
            total, cum = 0.0, []
            for f in self.feet:
                total += f.rho ** gamma if f.valid else 0.0
                cum.append(total)
            self.cumulative[gamma] = cum
        cum = self.cumulative[gamma]
        return self.feet[min(len(cum) - 1, bisect.bisect_left(cum, rng.uniform(0.0, cum[-1])))]

    def near(self, s: float, perimeter: float) -> Foot:
        s %= perimeter
        i = min(len(self.s) - 1, bisect.bisect_left(self.s, s))
        return self.feet[i]


# ---------------------------------------------------------------- pieces

def diameter(points) -> float:
    """Longest chord between any two points: the honest size of a piece."""
    a = numpy.array([tuple(p) for p in points], dtype=numpy.float64)
    if len(a) < 2:
        return 0.0
    d = a[:, None, :] - a[None, :, :]
    return float(numpy.sqrt((d * d).sum(axis=2).max()))


class Bit:
    def __init__(self, obj: bpy.types.Object, cls: str, tone: float, source: int):
        self.obj, self.cls, self.tone, self.source = obj, cls, tone, source
        co = [v.co for v in obj.data.vertices]
        bm = bmesh.new()
        for c in co:
            bm.verts.new(c)
        hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
        drop = {g for g in hull['geom_interior'] + hull['geom_unused'] if isinstance(g, bmesh.types.BMVert)}
        bmesh.ops.delete(bm, geom=list(drop), context='VERTS')
        bm.verts.index_update()
        self.hull = [v.co.copy() for v in bm.verts]
        self.hull_faces = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        self.size = diameter(self.hull)
        self.foot = None


def tris(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def unit(rng) -> Vector:
    while True:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length > 1e-3:
            return v.normalized()


def random_rotation(rng) -> Quaternion:
    u1, u2, u3 = rng.random(), rng.random(), rng.random()
    return Quaternion((math.sqrt(u1) * math.cos(math.tau * u3), math.sqrt(1 - u1) * math.sin(math.tau * u2),
                       math.sqrt(1 - u1) * math.cos(math.tau * u2), math.sqrt(u1) * math.sin(math.tau * u3)))


def triangle_target(size: float) -> int:
    return int(min(170, max(16, 16 + 1300 * size * size)))


def is_break(face, color) -> bool:
    """Voronoi caps carry Color (1, 0.5, 1, 1) from procgen.fracture."""
    return all(abs(loop[color][1] - 0.5) < 1e-6 and loop[color][2] > 0.99 for loop in face.loops)


def chip(obj: bpy.types.Object, rng, size: float) -> None:
    """Knock one or two corners off a Voronoi cell, so big pieces lose the
    boxy silhouette of a cell; the new faces are fresh breaks."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    color = bm.loops.layers.float_color.get('Color')
    for _ in range(rng.randint(1, 2)):
        corner = rng.choice(list(bm.verts)).co.copy()
        if corner.length < 1e-6:
            continue
        normal = (corner.normalized() + unit(rng) * 0.45).normalized()
        point = corner - normal * size * rng.uniform(0.1, 0.22)
        result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                        plane_co=point, plane_no=normal, clear_outer=True)
        edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            for face in bmesh.ops.edgeloop_fill(bm, edges=edges)['faces']:
                for loop in face.loops:
                    if color is not None:
                        loop[color] = (1.0, 0.5, 1.0, 1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def roughen(obj: bpy.types.Object, rng, size: float) -> None:
    """Fracture caps come out flat: subdivide and displace them so a fresh
    break reads rough and conchoidal, not sawn."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    color = bm.loops.layers.float_color.get('Color')
    caps = [f for f in bm.faces if is_break(f, color)]
    if caps:
        bmesh.ops.triangulate(bm, faces=caps, quad_method='BEAUTY', ngon_method='BEAUTY')
        target = max(0.014, size * 0.17)
        for _ in range(3):
            caps = [f for f in bm.faces if is_break(f, color)]
            long = list({e for f in caps for e in f.edges if e.calc_length() > target})
            if not long:
                break
            bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=False)
            bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method='BEAUTY', ngon_method='BEAUTY')
        bm.normal_update()
        offset = Vector((rng.uniform(-80, 80), rng.uniform(-80, 80), rng.uniform(-80, 80)))
        amplitude = 0.075 * size
        moves = []
        for v in bm.verts:
            faces = v.link_faces
            on = [f for f in faces if is_break(f, color)]
            if not on:
                continue
            normal = sum((f.normal for f in on), Vector()).normalized()
            value = noise.fractal(v.co * (2.6 / size) + offset, 0.75, 2.1, 3, noise_basis='PERLIN_ORIGINAL')
            share = 1.0 if len(on) == len(faces) else 0.3
            moves.append((v, normal * max(-1.3, min(1.3, value)) * amplitude * share))
        for v, delta in moves:
            v.co += delta
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def reduce(obj: bpy.types.Object, target: int) -> None:
    now = tris(obj)
    if now <= target:
        return
    modifier = obj.modifiers.new('Budget', 'DECIMATE')
    modifier.ratio = max(0.02, target / now)
    modifier.use_collapse_triangulate = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
    obj.modifiers.clear()
    old = obj.data
    obj.data = mesh
    mesh.name = obj.name
    bpy.data.meshes.remove(old)


def finish(obj: bpy.types.Object, tone: float, sharp: float) -> None:
    """Box-projected metre UVs, Color = (1, tone / TONE_STORE, fresh, 1),
    smooth shading split at edges sharper than `sharp` degrees."""
    mesh = obj.data
    disturb.centre(obj)
    color = mesh.color_attributes.get('Color') or mesh.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uv = mesh.uv_layers.get('UVMap') or mesh.uv_layers.new(name='UVMap')
    fresh = [0.0] * len(mesh.loops)
    values = [0.0] * (len(mesh.loops) * 4)
    color.data.foreach_get('color', values)
    for i in range(len(mesh.loops)):
        fresh[i] = 1.0 if values[i * 4 + 2] > 0.5 else 0.0
    g = tone / TONE_STORE
    for polygon in mesh.polygons:
        axis = max(range(3), key=lambda k: abs(polygon.normal[k]))
        a, b = [k for k in range(3) if k != axis]
        for index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[index].vertex_index].co
            uv.data[index].uv = (co[a], co[b])
            color.data[index].color = (1.0, g, fresh[index], 1.0)
    mesh.color_attributes.active_color = color
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(sharp))


def shattered(room_id: str, seed: int, index: int) -> list:
    """One wall stone broken by its fall: Voronoi cells crowded around the
    impact corner, so it leaves a few big chunks and a spray of chips."""
    rng = core.rng(seed, room_id, 'source', index)
    kinds = [(k, w) for k, w in KINDS if k in stones.LOOKS] or [('rubble', 1.0)]
    kind = rng.choices([k for k, _ in kinds], weights=[w for _, w in kinds])[0]
    dims = Vector((rng.uniform(0.26, 0.46), rng.uniform(0.17, 0.28), rng.uniform(0.14, 0.24)))
    source = stones.make(kind, rng, dims, name=f'Src{index:03d}', triangles=int(500 + 900 * dims.x))
    count = rng.choices((2, 4, 7, 10, 14, 18), weights=(0.08, 0.12, 0.2, 0.25, 0.2, 0.15))[0]
    corner = source.data.vertices[rng.randrange(len(source.data.vertices))].co.copy()
    points = fracture.seeds(source, rng, count, focus=corner * 0.8, spread=dims.length * 0.35)
    cells = fracture.voronoi(source, points, name=f'Cell{index:03d}')
    bpy.data.objects.remove(source, do_unlink=True)
    result, queue = [], list(cells)
    while queue:
        cell = queue.pop()
        size = diameter(v.co for v in cell.data.vertices)
        if size > PIECE_MAX:
            halves = fracture.voronoi(cell, fracture.seeds(cell, rng, 2), name=cell.name + 's')
            bpy.data.objects.remove(cell, do_unlink=True)
            queue += halves
        elif size < PIECE_MIN:
            bpy.data.objects.remove(cell, do_unlink=True)
        else:
            result.append(cell)
    tone = rng.uniform(*TONE)
    cells = []
    for k, cell in enumerate(sorted(result, key=lambda c: c.name)):
        size = diameter(v.co for v in cell.data.vertices)
        cell.name = f'Chunk{index:03d}_{k:02d}'
        if size > 0.1:
            chip(cell, rng, size)
        roughen(cell, rng, size)
        piece_tone = min(TONE[1], max(TONE[0], tone * rng.uniform(0.95, 1.05)))
        cells.append((cell, size, piece_tone, index))
    return cells


def budgeted(cells: list, budget: int) -> list:
    """Decimate fragments to share `budget` triangles in proportion to their
    surface (size squared), then finish them as pieces."""
    weights = [triangle_target(size) for _, size, _, _ in cells]
    factor = min(1.0, budget / max(1, sum(weights)))
    bits = []
    for (cell, size, tone, index), weight in zip(cells, weights):
        reduce(cell, max(12, int(weight * factor)))
        finish(cell, tone, 38.0)
        bits.append(Bit(cell, size_class(size), tone, index))
    return bits


def size_class(size: float) -> str:
    return 'big' if size >= 0.2 else 'medium' if size >= 0.08 else 'small' if size >= 0.035 else 'gravel'


def hull_rock(name: str, rng, size: float, points: int, flat: tuple) -> bpy.types.Object:
    """Angular chip or pebble: convex hull of points on a squashed ellipsoid,
    with one flat break."""
    radii = Vector((0.5, 0.5 * rng.uniform(0.5, 0.95), 0.5 * rng.uniform(*flat))) * size
    bm = bmesh.new()
    for _ in range(points):
        d = unit(rng)
        bm.verts.new(Vector((d.x * radii.x, d.y * radii.y, d.z * radii.z)) * rng.uniform(0.72, 1.0))
    hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    drop = {g for g in hull['geom_interior'] + hull['geom_unused'] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(drop), context='VERTS')
    normal = unit(rng)
    reach = abs(normal.x) * radii.x + abs(normal.y) * radii.y + abs(normal.z) * radii.z
    result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                    plane_co=normal * reach * rng.uniform(0.35, 0.7), plane_no=normal, clear_outer=True)
    edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    cap = []
    if edges:
        cap = bmesh.ops.edgeloop_fill(bm, edges=edges)['faces']
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    color = bm.loops.layers.float_color.new('Color')
    bm.loops.layers.uv.new('UVMap')
    weathered = rng.random() < 0.5
    for face in bm.faces:
        for loop in face.loops:
            loop[color] = (1.0, 0.5, 0.0 if weathered else 1.0, 1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return core.link(bpy.data.objects.new(name, mesh))


def loose(room_id: str, seed: int, kind: str, count: int) -> list:
    bits = []
    for i in range(count):
        rng = core.rng(seed, room_id, kind, i)
        if kind == 'small':
            size = min(rng.uniform(0.035, 0.09), rng.uniform(0.035, 0.09))
            obj = hull_rock(f'Rock{i:03d}', rng, size, rng.randint(10, 15), (0.35, 0.75))
        else:
            size = min(rng.uniform(0.024, 0.07), rng.uniform(0.024, 0.08))
            obj = hull_rock(f'Grit{i:03d}', rng, size, rng.randint(6, 9), (0.25, 0.7))
        # Grit is freshly crushed stone: on the light side of the tone range.
        tone = rng.uniform(*TONE) if kind == 'small' else rng.uniform(0.9, TONE[1])
        finish(obj, tone, 25.0)
        bits.append(Bit(obj, kind if kind == 'small' else 'gravel', tone, -1))
    return bits


# ---------------------------------------------------------------- grime bed

def grime_bed(room_id: str, outline: list, field: Field, routes: Routes, floor: float, seed: int) -> tuple:
    """Dust, crushed mortar and grit banked against the wall where material
    has come down: the fine core of each heap, up to BED_HEIGHT deep at the
    wall foot. A heightfield that dips 1.2 cm under the floor at its edge, so
    it meets the floor along a frayed contour instead of a seam; its grey
    fades to 1 there, so with the floor's material it blends into the floor.
    Returns the visual mesh, its triangles and convex physics patches (a thin
    triangle shell lets small pieces tunnel under it)."""
    rng = core.rng(seed, room_id, 'grime')
    cell = BED_CELL
    xs = [p.x for p in outline]
    ys = [p.y for p in outline]
    x0, y0 = min(xs) - 0.2, min(ys) - 0.2
    nx, ny = int((max(xs) - x0 + 0.2) / cell) + 2, int((max(ys) - y0 + 0.2) / cell) + 2
    offset = Vector((rng.uniform(0, 300), rng.uniform(0, 300), 0.0))
    sink = 0.012
    height = numpy.full((nx, ny), -1.0)
    shade = numpy.ones((nx, ny))
    for i in range(nx):
        for j in range(ny):
            x, y = x0 + i * cell, y0 + j * cell
            foot, d = field.depth(x, y)
            if not foot.valid or d < -0.22 or d > 2.2:
                continue
            p = Vector((x, y, 0.0)) + offset
            meander = 0.5 + 0.5 * noise.noise(p * 0.9, noise_basis='PERLIN_ORIGINAL')
            reach = (0.3 + 1.3 * min(1.0, foot.rho)) * (0.7 + 0.6 * meander)
            top = BED_HEIGHT * min(1.0, foot.rho) ** 0.8
            g = top if d <= 0.0 else top * max(0.0, 1.0 - d / reach) ** 1.2
            # Lumps scale with the depth; the thin edge frays into islands.
            g *= 0.7 + 0.6 * (0.5 + 0.5 * noise.noise(p * 2.5, noise_basis='PERLIN_ORIGINAL'))
            g += 0.009 * noise.fractal(p * 3.5, 0.6, 2.0, 3, noise_basis='PERLIN_ORIGINAL')
            clear = routes.clearance(x, y)
            g *= max(0.0, min(1.0, (clear - 0.05) / 0.45))
            height[i, j] = g - sink
            wet = 0.5 + 0.5 * noise.noise(p * 0.6 + Vector((7.0, 3.0, 0.0)), noise_basis='PERLIN_ORIGINAL')
            shade[i, j] = 1.0 - min(1.0, max(0.0, (g + 0.006) / 0.05)) * (0.6 + 0.4 * wet)
    used = numpy.zeros((nx, ny), dtype=bool)
    bm = bmesh.new()
    color = bm.loops.layers.float_color.new('Color')
    uv = bm.loops.layers.uv.new('UVMap')
    verts = {}

    def vert(i, j):
        if (i, j) not in verts:
            verts[(i, j)] = bm.verts.new((x0 + i * cell, y0 + j * cell, floor + max(height[i, j], -sink)))
        return verts[(i, j)]
    for i in range(nx - 1):
        for j in range(ny - 1):
            quad = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            if any(height[a, b] <= -1.0 for a, b in quad) or max(height[a, b] for a, b in quad) < 0.003:
                continue
            used[i, j] = True
            face = bm.faces.new([vert(a, b) for a, b in quad])
            for loop, (a, b) in zip(face.loops, quad):
                tone = GRIME_TONE[0] + (GRIME_TONE[1] - GRIME_TONE[0]) * max(0.0, shade[a, b])
                loop[color] = (1.0, tone / TONE_STORE, 0.0, 1.0)
                loop[uv].uv = (loop.vert.co.x, loop.vert.co.y)
    if not bm.faces:
        bm.free()
        return None, 0, []
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    mesh = bpy.data.meshes.new(f'Rubble_{room_id}_grime')
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.color_attributes.active_color = mesh.color_attributes['Color']
    obj = core.link(bpy.data.objects.new(mesh.name, mesh))
    reduce(obj, int(len(mesh.polygons) * 0.6))
    obj.data.shade_smooth()
    # Physics: one convex prism per 2 x 2 cells, from the undecimated heights
    # down to below the floor. Neighbours share their edge vertices.
    patches = []
    for i in range(0, nx - 1, 2):
        for j in range(0, ny - 1, 2):
            if not used[i:i + 2, j:j + 2].any():
                continue
            top = [(a, b) for a in range(i, min(i + 3, nx)) for b in range(j, min(j + 3, ny)) if height[a, b] > -1.0]
            if len(top) < 3:
                continue
            pm = bmesh.new()
            for a, b in top:
                x, y = x0 + a * cell, y0 + b * cell
                pm.verts.new((x, y, floor + max(height[a, b], -sink)))
                pm.verts.new((x, y, floor - 0.06))
            hull = bmesh.ops.convex_hull(pm, input=pm.verts[:])
            drop = {g for g in hull['geom_interior'] + hull['geom_unused'] if isinstance(g, bmesh.types.BMVert)}
            bmesh.ops.delete(pm, geom=list(drop), context='VERTS')
            if len(pm.faces) < 4:
                pm.free()
                continue
            centre = sum((v.co for v in pm.verts), Vector()) / len(pm.verts)
            bmesh.ops.translate(pm, vec=-centre, verts=pm.verts[:])
            patch_mesh = bpy.data.meshes.new('BedPatch')
            pm.to_mesh(patch_mesh)
            pm.free()
            patch = core.link(bpy.data.objects.new('BedPatch', patch_mesh))
            patch.location = centre
            patch.hide_render = True
            patches.append(patch)
    if patches:
        tree = bvh_of(patches)
        for v in obj.data.vertices:
            hit = tree.ray_cast(Vector((v.co.x, v.co.y, floor + 1.0)), DOWN, 1.2)
            if hit[0] is not None and hit[0].z > v.co.z:
                v.co.z = hit[0].z
        obj.data.update()
    return obj, tris(obj), patches


# ---------------------------------------------------------------- deposit

def spot(bit: Bit, field: Field, rng, perimeter: float, sources: dict) -> tuple:
    """A candidate (x, y, foot) for a piece, by size class."""
    reach = max(Vector((p.x, p.y, 0.0)).length for p in bit.hull)
    if bit.source >= 0:
        s0 = sources[bit.source]
        spread = 0.25 + 0.5 * (1.0 - min(1.0, bit.size / PIECE_MAX))
        foot = field.near(s0 + rng.gauss(0.0, spread), perimeter)
    else:
        foot = field.pick(rng, {'small': 1.6, 'gravel': 1.7}[bit.cls])
    if not foot.valid:
        return None
    R = foot.R
    if bit.cls == 'big':
        d = R * rng.uniform(0.0, 0.25)
    elif bit.cls == 'medium':
        d = R * abs(rng.gauss(0.0, 0.45))
    elif bit.cls == 'small':
        d = R * rng.uniform(0.2, 1.1) + (rng.uniform(0.3, 1.2) if rng.random() < 0.07 else 0.0)
    elif rng.random() < 0.3:
        d = R * rng.uniform(0.0, 0.7)          # grit trickled into the heap
    else:
        # The skirt: grit runs out past the foot of the heap.
        d = R * rng.uniform(0.6, 1.2) + abs(rng.gauss(0.0, 0.22)) + (rng.uniform(0.3, 1.2) if rng.random() < 0.08 else 0.0)
    at = foot.p + foot.n * (reach + 0.012 + d) + foot.t * rng.uniform(-0.06, 0.06)
    return at.x, at.y, foot


def deposit(bits: list, field: Field, walls: BVHTree, bed: BVHTree, routes: Routes, room_inner: list,
            floor: float, seed: int, room_id: str, perimeter: float) -> dict:
    """Lower pieces one at a time onto what is already there, at the spot
    furthest below the talus wedge, clear of the walls and of other pieces."""
    rng = core.rng(seed, room_id, 'deposit')
    sources = {}
    for bit in bits:
        if bit.source >= 0 and bit.source not in sources:
            sources[bit.source] = field.pick(rng, 1.25).s
    verts, polys, placed = [], [], None
    top = floor + 1.2
    skipped = []
    tries = {'big': 14, 'medium': 10, 'small': 5, 'gravel': 3}
    for bit in bits:
        turn = random_rotation(rng).to_matrix()
        local = [turn @ p for p in bit.hull]
        low = min(o.z for o in local)
        best = None
        for _ in range(tries[bit.cls]):
            candidate = spot(bit, field, rng, perimeter, sources)
            if candidate is None:
                continue
            x, y, foot = candidate
            if not contains(room_inner, Vector((x, y, 0.0))):
                continue
            reach = max(Vector((o.x, o.y, 0.0)).length for o in local)
            clear = routes.clearance(x, y)
            if bit.cls == 'gravel':
                if clear < -0.35:
                    continue
            elif clear < reach + 0.05:
                continue
            z = rest(x, y, local, low, (walls, bed, placed), floor, top)
            room = field.profile(x, y) - (z + low - floor)
            score = room + rng.uniform(0.0, 0.015)
            if best is None or score > best[0]:
                best = (score, x, y, z, foot)
        if best is None:
            skipped.append(bit)
            continue
        _, x, y, z, foot = best
        ok = False
        for _ in range(40):
            moved = [Vector((x, y, z)) + o for o in local]
            mine = BVHTree.FromPolygons(moved, bit.hull_faces)
            if walls.overlap(mine):
                x, y = x + foot.n.x * 0.01, y + foot.n.y * 0.01
                z = rest(x, y, local, low, (walls, bed, placed), floor, top)
                continue
            if (bed is not None and bed.overlap(mine)) or (placed is not None and placed.overlap(mine)):
                z += 0.004
                continue
            ok = True
            break
        if not ok:
            skipped.append(bit)
            continue
        z += rng.uniform(0.003, 0.012)
        bit.obj.location = (x, y, z)
        bit.obj.rotation_mode = 'QUATERNION'
        bit.obj.rotation_quaternion = turn.to_quaternion()
        bit.foot = foot
        base = len(verts)
        verts += [Vector((x, y, z)) + o for o in local]
        polys += [tuple(base + i for i in f) for f in bit.hull_faces]
        placed = BVHTree.FromPolygons(verts, polys)
    for bit in skipped:
        bits.remove(bit)
        bpy.data.objects.remove(bit.obj, do_unlink=True)
    return {'no_spot': len(skipped)}


def rest(x: float, y: float, local: list, low: float, trees, floor: float, top: float) -> float:
    """Height of the piece origin when its hull comes down at (x, y) onto the
    floor or the first surface below `top`."""
    z = floor - low
    for o in local:
        origin = Vector((x + o.x, y + o.y, top))
        for tree in trees:
            if tree is None:
                continue
            hit = tree.ray_cast(origin, DOWN, top - floor + 0.3)
            if hit[0] is not None:
                z = max(z, hit[0].z - o.z)
    return z


# ---------------------------------------------------------------- physics

def simulate(bits: list, statics: list, patches: list, floor_box, max_frames: int, min_frames: int = 45,
             resting: list = ()) -> dict:
    """One Bullet run of `bits` against the walls (MESH), the grime bed's
    convex patches, the floor (BOX) and `resting` pieces held still."""
    rigid.world(fps=30, substeps=40, iterations=60, frame_end=max_frames + 5)
    core.select_only([b.obj for b in bits])
    bpy.ops.rigidbody.objects_add(type='ACTIVE')
    for bit in bits:
        rb = bit.obj.rigid_body
        gravel = bit.cls in ('gravel', 'small')
        rb.collision_shape = 'CONVEX_HULL'
        rb.mass = max(0.004, rigid.volume(bit.obj) * DENSITY)
        rb.friction = 0.95
        rb.restitution = 0.0
        rb.use_margin = True
        rb.collision_margin = GRAVEL_MARGIN if bit.cls == 'gravel' else PIECE_MARGIN
        # Angular damping stands in for the rolling resistance of rough,
        # angular stone, which Bullet's hulls lack.
        rb.linear_damping, rb.angular_damping = (0.45, 0.97) if gravel else (0.4, 0.95)
        rb.use_deactivation = True
        rb.deactivate_linear_velocity = 0.025
        rb.deactivate_angular_velocity = 0.06
    for obj in statics:
        rigid.body(obj, passive=True, shape='MESH', friction=0.85, margin=STATIC_MARGIN)
    if patches:
        core.select_only(patches)
        bpy.ops.rigidbody.objects_add(type='PASSIVE')
        for patch in patches:
            rb = patch.rigid_body
            rb.collision_shape = 'CONVEX_HULL'
            rb.friction = 0.9
            rb.use_margin = True
            rb.collision_margin = STATIC_MARGIN
    if resting:
        core.select_only([b.obj for b in resting])
        bpy.ops.rigidbody.objects_add(type='PASSIVE')
        for bit in resting:
            rb = bit.obj.rigid_body
            rb.collision_shape = 'CONVEX_HULL'
            rb.friction = 0.95
            rb.use_margin = True
            rb.collision_margin = GRAVEL_MARGIN if bit.cls == 'gravel' else PIECE_MARGIN
    rigid.body(floor_box, passive=True, shape='BOX', friction=0.85, margin=STATIC_MARGIN)
    return settle(bits, SETTLE_SPEED, 15, min_frames, max_frames)


def release(bits: list, statics: list, patches: list, floor_box, frames: int = 45) -> list:
    """Let every piece go from its current pose for `frames` and measure how
    far each moves; the pose itself is left untouched. Returns
    [(metres, degrees, name)] sorted, largest first."""
    bpy.context.view_layer.update()
    for bit in bits:
        disturb.centre(bit.obj)
    result = simulate(bits, statics, patches, floor_box, max_frames=frames, min_frames=frames)
    bpy.context.scene.frame_set(1)
    core.select_only([b.obj for b in bits] + statics + patches + [floor_box])
    bpy.ops.rigidbody.objects_remove()
    if bpy.context.scene.rigidbody_world is not None:
        bpy.ops.rigidbody.world_remove()
    bpy.context.view_layer.update()
    for bit in bits:
        bit.obj.data.transform(bit.obj.matrix_world)
        bit.obj.matrix_world = Matrix.Identity(4)
        bit.obj.data.update()
    return sorted(((m[0], m[1], name) for name, m in result['moved'].items()), reverse=True)


def progressive(bits: list, statics: list, patches: list, floor_box, first: int, segment: int, segments: int) -> dict:
    """Settle in short runs. After each run, pieces whose net travel stayed
    under SETTLE_SPEED for its last 15 frames are held still for the next
    runs. This is the static friction Bullet's hulls lack: left alone, a heap
    of hulls keeps creeping a few cm per second however long it runs (tested
    with 150 iterations, 80 substeps, heavier damping and higher friction).
    Pieces still moving after the last run are returned in 'moving'."""
    held, log, frames, first_moves = set(), [], 0, None
    for k in range(segments):
        active = [b for b in bits if b.obj.name not in held]
        if not active:
            break
        # matrix_world must be current before centring (deposit sets
        # location and rotation without a depsgraph update).
        bpy.context.view_layer.update()
        for bit in bits:
            disturb.centre(bit.obj)
        length = first if k == 0 else segment
        result = simulate(active, statics, patches, floor_box, max_frames=length, min_frames=min(length, 30),
                          resting=[b for b in bits if b.obj.name in held])
        freeze(bits, statics + patches + [floor_box])
        frames += result['frame']
        if first_moves is None:
            first_moves = result['moved']
        calm = [b for b in active if result['speed'][b.obj.name] < SETTLE_SPEED]
        held.update(b.obj.name for b in calm)
        log.append({'run': k, 'frames': result['frame'], 'active': len(active), 'stilled': len(calm),
                    'peak_speed_m_s': round(result['peak_speed_m_s'], 3)})
    moving = [b for b in bits if b.obj.name not in held]
    return {'runs': log, 'frames': frames, 'moving': moving, 'first_moves': first_moves,
            'speed': {b.obj.name: SETTLE_SPEED for b in moving}}


def settle(bits: list, threshold: float, hold: int, min_frames: int, max_frames: int) -> dict:
    """Step until every piece is still. A piece's speed is the net travel of
    its fastest bound-box corner over the last `hold` frames divided by that
    time, so sub-millimetre contact jitter does not count as motion but slow
    creep does. Settled when every piece stays below `threshold` for `hold`
    more frames. Per-frame jitter is reported separately."""
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    objects = [b.obj for b in bits]
    probes = {o.name: [Vector(c) for c in o.bound_box] for o in objects}
    scene.frame_set(1)
    start = {o.name: o.matrix_world.copy() for o in objects}
    history = {o.name: deque([[o.matrix_world @ p for p in probes[o.name]]], maxlen=hold + 1) for o in objects}
    recent = {o.name: deque(maxlen=hold) for o in objects}
    calm, frame, peak, last, jitter = 0, 1, 0.0, None, 0.0
    for frame in range(2, max_frames + 1):
        scene.frame_set(frame)
        fastest, last, frame_jitter = 0.0, None, 0.0
        for o in objects:
            current = [o.matrix_world @ p for p in probes[o.name]]
            past = history[o.name]
            step = max((a - b).length for a, b in zip(current, past[-1])) * fps
            speed = max((a - b).length for a, b in zip(current, past[0])) * fps / len(past)
            past.append(current)
            recent[o.name].append(speed)
            frame_jitter = max(frame_jitter, step)
            if speed > fastest:
                fastest, last = speed, o.name
        peak = max(peak, frame_jitter)
        calm = calm + 1 if fastest < threshold and frame > hold else 0
        if calm:
            jitter = max(jitter, frame_jitter)
        if frame >= min_frames and calm >= hold:
            break
    moved = {}
    for o in objects:
        a, b = start[o.name], o.matrix_world
        delta = a.to_quaternion().rotation_difference(b.to_quaternion())
        moved[o.name] = ((b.translation - a.translation).length, math.degrees(min(delta.angle, math.tau - delta.angle)))
    return {'settled': calm >= hold, 'frame': frame, 'seconds': round(frame / fps, 2),
            'residual_speed_m_s': max(recent[o.name][-1] for o in objects) if objects else 0.0,
            'last_mover': last, 'peak_speed_m_s': peak, 'residual_jitter_m_s': jitter,
            'speed': {o.name: max(recent[o.name]) for o in objects}, 'moved': moved}


def freeze(bits: list, statics: list) -> None:
    """Bake the simulated pose into the meshes and remove all rigid bodies."""
    matrices = {b.obj.name: b.obj.matrix_world.copy() for b in bits}
    core.select_only([b.obj for b in bits] + statics)
    bpy.ops.rigidbody.objects_remove()
    if bpy.context.scene.rigidbody_world is not None:
        bpy.ops.rigidbody.world_remove()
    for bit in bits:
        bit.obj.rotation_mode = 'XYZ'
        bit.obj.data.transform(matrices[bit.obj.name])
        bit.obj.matrix_world = Matrix.Identity(4)
        bit.obj.data.update()
    bpy.context.scene.frame_set(1)


# ---------------------------------------------------------------- checks

def world_verts(obj) -> list:
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def route_height(bit: Bit, routes: Routes, floor: float) -> float:
    """Highest point of the piece above the floor inside a walking ribbon (0 if none)."""
    verts = world_verts(bit.obj)
    centre = sum(verts, Vector()) / len(verts)
    reach = max((v - centre).xy.length for v in verts)
    if routes.clearance(centre.x, centre.y) > reach + 0.02:
        return 0.0
    worst = 0.0
    for v in verts:
        if v.z - floor > worst and routes.clearance(v.x, v.y) < 0.0:
            worst = v.z - floor
    return worst


def discard(bits: list, routes: Routes, room_inner: list, floor: float, speeds: dict, log: dict) -> None:
    for bit in list(bits):
        verts = world_verts(bit.obj)
        centre = sum(verts, Vector()) / len(verts)
        reason = None
        if not contains(room_inner, centre) or centre.z < floor - 0.05:
            reason = 'left_room'
        elif speeds.get(bit.obj.name, 0.0) >= SETTLE_SPEED:
            reason = 'not_settled'
        elif route_height(bit, routes, floor) > ROUTE_HEIGHT:
            reason = 'route'
        if reason:
            log[reason] = log.get(reason, 0) + 1
            bits.remove(bit)
            bpy.data.objects.remove(bit.obj, do_unlink=True)


class Solid:
    def __init__(self, obj):
        self.name = obj.name
        self.verts = world_verts(obj)
        self.bvh = BVHTree.FromPolygons(self.verts, [tuple(p.vertices) for p in obj.data.polygons])
        self.low = Vector(tuple(min(v[k] for v in self.verts) for k in range(3)))
        self.high = Vector(tuple(max(v[k] for v in self.verts) for k in range(3)))

    def near(self, other, pad: float) -> bool:
        return all(self.low[k] - pad <= other.high[k] and other.low[k] - pad <= self.high[k] for k in range(3))

    def inside(self, co: Vector) -> bool:
        count, origin = 0, co.copy()
        for _ in range(64):
            hit = self.bvh.ray_cast(origin, rigid.SKEW)
            if hit[0] is None:
                break
            count += 1
            origin = hit[0] + rigid.SKEW * 1e-6
        return count % 2 == 1


def contacts(bits: list, wall, bed, floor: float) -> dict:
    """Per piece: gap to its nearest support (floor, wall, grime bed or
    another piece) and the deepest interpenetration found, from vertices.
    Wall stones are open at the back, so a vertex counts as inside the wall
    when it lies behind the nearest wall face; the grime bed is a heightfield,
    so a vertex is under it when a ray straight up meets its top side."""
    solids = [Solid(b.obj) for b in bits]
    wall_tree = BVHTree.FromPolygons(world_verts(wall), [tuple(p.vertices) for p in wall.data.polygons])
    bed_tree = BVHTree.FromPolygons(world_verts(bed), [tuple(p.vertices) for p in bed.data.polygons]) if bed else None
    up = Vector((0.0, 0.0, 1.0))
    gaps, depth, pair = {}, 0.0, None
    for a in solids:
        best = max(0.0, min(v.z for v in a.verts) - floor)
        depth_floor = max(0.0, floor - min(v.z for v in a.verts))
        if depth_floor > depth:
            depth, pair = depth_floor, [a.name, 'floor']
        for v in a.verts:
            hit = wall_tree.find_nearest(v, 0.05)
            if hit[0] is not None:
                best = min(best, hit[3])
                if (v - hit[0]).dot(hit[1]) < -1e-4 and hit[3] < 0.03 and hit[3] > depth:
                    depth, pair = hit[3], [a.name, wall.name]
            if bed_tree is None:
                continue
            hit = bed_tree.find_nearest(v, 0.05)
            if hit[0] is not None:
                best = min(best, hit[3])
            hit = bed_tree.ray_cast(v, up, 0.2)
            if hit[0] is not None and hit[1].z > 0.0 and hit[3] > depth:
                depth, pair = hit[3], [a.name, bed.name]
        for b in solids:
            if b is a or not a.near(b, best):
                continue
            for v in a.verts:
                hit = b.bvh.find_nearest(v, best)
                if hit[0] is not None and hit[3] < best:
                    best = hit[3]
            for v in b.verts:
                hit = a.bvh.find_nearest(v, best)
                if hit[0] is not None and hit[3] < best:
                    best = hit[3]
            if a.name < b.name and a.near(b, 0.0) and a.bvh.overlap(b.bvh):
                for source, target in ((a, b), (b, a)):
                    for v in source.verts:
                        if all(target.low[k] <= v[k] <= target.high[k] for k in range(3)) and target.inside(v):
                            hit = target.bvh.find_nearest(v)
                            if hit[0] is not None and hit[3] > depth:
                                depth, pair = hit[3], [source.name, target.name]
        gaps[a.name] = best
    return {'gaps': gaps, 'max_penetration_m': depth, 'deepest_pair': pair}


# ---------------------------------------------------------------- bake and export

def merge(objects: list, name: str) -> bpy.types.Object:
    bm = bmesh.new()
    for obj in objects:
        mesh = obj.data.copy()
        mesh.transform(obj.matrix_world)
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color = mesh.color_attributes['Color']
    return core.link(bpy.data.objects.new(name, mesh))


def hull_mesh(obj: bpy.types.Object, name: str) -> bpy.types.Mesh:
    bm = bmesh.new()
    for v in world_verts(obj):
        bm.verts.new(v)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    drop = {g for g in hull['geom_interior'] + hull['geom_unused'] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(drop), context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def grey(obj: bpy.types.Object) -> dict:
    """Color.rgb = baked AO x tone (x FRESH on break faces), neutral grey: the
    dungeon shader multiplies albedo by COLOR. glTF stores normalized
    colours, so values above 1 are clipped; the share is reported."""
    color = obj.data.color_attributes['Color']
    values = numpy.empty(len(color.data) * 4, dtype=numpy.float32)
    color.data.foreach_get('color', values)
    rgba = values.reshape(-1, 4)
    grey_value = rgba[:, 0] * rgba[:, 1] * TONE_STORE * numpy.where(rgba[:, 2] > 0.5, FRESH, 1.0)
    clipped = float(numpy.mean(grey_value > 1.0))
    grey_value = numpy.clip(grey_value, 0.0, 1.0)
    rgba[:, 0] = rgba[:, 1] = rgba[:, 2] = grey_value
    rgba[:, 3] = 1.0
    color.data.foreach_set('color', rgba.ravel())
    return {'mean': round(float(grey_value.mean()), 3), 'min': round(float(grey_value.min()), 3),
            'clipped_share': round(clipped, 4)}


# ---------------------------------------------------------------- review renders

def textured(name: str, folder: Path, value: float, use_color: bool, scale: float) -> bpy.types.Material:
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
        node.image = bpy.data.images.load(str(folder / f'{key}.png'), check_existing=True)
        node.image.colorspace_settings.name = space
        node.projection = 'BOX'
        node.projection_blend = 0.3
        links.new(mapping.outputs['Vector'], node.inputs['Vector'])
        images[key] = node
    grade = nodes.new('ShaderNodeHueSaturation')
    grade.inputs['Saturation'].default_value = 0.4
    grade.inputs['Value'].default_value = value
    links.new(images['albedo'].outputs['Color'], grade.inputs['Color'])
    if use_color:
        attribute = nodes.new('ShaderNodeAttribute')
        attribute.attribute_name = 'Color'
        multiply = nodes.new('ShaderNodeMix')
        multiply.data_type = 'RGBA'
        multiply.blend_type = 'MULTIPLY'
        multiply.inputs['Factor'].default_value = 1.0
        links.new(grade.outputs['Color'], multiply.inputs['A'])
        links.new(attribute.outputs['Color'], multiply.inputs['B'])
        links.new(multiply.outputs['Result'], shader.inputs['Base Color'])
    else:
        links.new(grade.outputs['Color'], shader.inputs['Base Color'])
    bump = nodes.new('ShaderNodeNormalMap')
    links.new(images['normal_gl'].outputs['Color'], bump.inputs['Color'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    links.new(images['roughness'].outputs['Color'], shader.inputs['Roughness'])
    return material


def use_gpu() -> str:
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        bpy.context.scene.cycles.device = 'GPU'
        return 'METAL'
    except Exception:  # noqa: BLE001 - CPU rendering is a fine fallback
        bpy.context.scene.cycles.device = 'CPU'
        return 'CPU'


def render(eye: Vector, target: Vector, path: Path, size=(1280, 800), samples: int = 96, lens: float = 22.0,
           ortho: float = 0.0) -> None:
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.view_settings.view_transform = 'AgX'
    camera = bpy.data.objects.get('ReviewCamera') or core.link(bpy.data.objects.new('ReviewCamera', bpy.data.cameras.new('ReviewCamera')))
    camera.data.lens = lens
    camera.data.clip_start = 0.02
    camera.data.type = 'ORTHO' if ortho else 'PERSP'
    if ortho:
        camera.data.ortho_scale = ortho
    camera.location = eye
    # Plans look straight down with Blender +y (Godot -z, north) up the image.
    camera.rotation_euler = (0.0, 0.0, 0.0) if ortho else (target - eye).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    with tempfile.TemporaryDirectory() as folder:
        temp = Path(folder) / 'view.png'
        scene.render.filepath = str(temp)
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(str(temp))
        pixels = numpy.empty(size[0] * size[1] * 4, dtype=numpy.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
    rgb = pixels.reshape(size[1], size[0], 4)[::-1, :, :3]
    disturb.write_png(path, numpy.clip(rgb * 255.0 + 0.5, 0, 255).astype(numpy.uint8))


def segment_distance(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - (a + ab * t)).xy.length


def review(room: dict, outline: list, walls: list, rubble: list, floor_box, feet: list, routes: Routes,
           folder: Path) -> list:
    """Torch-lit Cycles views of the biggest heaps at eye height, plus a plan."""
    floor = room['floor']
    folder.mkdir(parents=True, exist_ok=True)
    (folder / '.gdignore').touch()  # review frames are not game assets
    device = use_gpu()
    wall_material = textured('ReviewWall', ROCK, 0.55, False, 1.2)
    rubble_material = textured('ReviewRubble', ROCK, 0.62, True, 2.2)
    floor_material = textured('ReviewFloor', RUBBLE_ROCK, 0.4, True, 0.7)
    for obj in walls:
        obj.data.materials.clear()
        obj.data.materials.append(wall_material)
    for obj in rubble:
        obj.data.materials.clear()
        obj.data.materials.append(floor_material if obj.name.endswith('_grime') else rubble_material)
    floor_box.data.materials.clear()
    floor_box.data.materials.append(floor_material)
    white = floor_box.data.color_attributes.get('Color') or floor_box.data.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    for item in white.data:
        item.color = (1.0, 1.0, 1.0, 1.0)
    floor_box.hide_render = False
    scene = bpy.context.scene
    scene.world = scene.world or bpy.data.worlds.new('Dark')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value = (0.006, 0.008, 0.012, 1.0)
    background.inputs['Strength'].default_value = 1.0
    scene.world.light_settings.distance = 10.0
    centre = sum(outline, Vector()) / len(outline)
    torches = []

    def torch(at: Vector, energy: float) -> None:
        light = core.link(bpy.data.objects.new(f'Torch{len(torches)}', bpy.data.lights.new(f'Torch{len(torches)}', 'POINT')))
        light.data.energy = energy
        light.data.color = (1.0, 0.56, 0.26)
        light.data.shadow_soft_size = 0.08
        light.location = at
        torches.append(light)
    for p in outline[::2]:
        spot_at = centre.lerp(p, 0.8)
        torch(Vector((spot_at.x, spot_at.y, floor + 2.3)), 260.0)
    peaks = []
    for foot in sorted([f for f in feet if f.valid], key=lambda f: -f.heap):
        if all((foot.p - q.p).length > 3.5 for q in peaks):
            peaks.append(foot)
        if len(peaks) == 3:
            break
    inner = inset(outline, 0.7)
    paths = []
    for k, foot in enumerate(peaks):
        side = 1.0 if k % 2 == 0 else -1.0
        torch(Vector((*(foot.p + foot.n * 0.35 - foot.t * side * 1.7).xy, floor + 2.0)), 180.0)
        # Eye height view from 2-3.4 m, turned off the wall normal, placed
        # where it keeps furthest from the other walls.
        best = None
        for angle in (-45, -30, -15, 0, 15, 30, 45):
            direction = Matrix.Rotation(math.radians(angle * side), 3, 'Z') @ foot.n
            for distance in (3.4, 3.0, 2.6, 2.2):
                eye = foot.p + direction * distance
                if not contains(inner, eye):
                    continue
                clear = min(segment_distance(eye, a, b) for a, b in zip(outline, outline[1:] + outline[:1]))
                score = min(clear, 2.0) + 0.3 * distance - 0.004 * abs(angle)
                if best is None or score > best[0]:
                    best = (score, eye)
        eye = best[1] if best else foot.p + foot.n * 1.5
        target = foot.p + foot.n * 0.55
        path = folder / f'{room["id"]}_view{k + 1}.png'
        render(Vector((eye.x, eye.y, floor + 1.6)), Vector((target.x, target.y, floor + 0.2)), path)
        paths.append(path)
    # Plan: route ribbons in dull red under a soft top light, torches off.
    for light in torches:
        light.hide_render = True
    ribbon = bpy.data.materials.new('ReviewRibbon')
    ribbon.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.35, 0.05, 0.04, 1.0)
    marks = []
    for a, b, ya, yb, radius, _ in routes.segments:
        if min(abs(ya - floor), abs(yb - floor)) > ROUTE_LEVEL:
            continue
        bm = bmesh.new()
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0.0)) * radius
        quad = [a + n, b + n, b - n, a - n]
        bm.faces.new([bm.verts.new((p.x, p.y, floor + 0.0005)) for p in quad])
        mesh = bpy.data.meshes.new('Ribbon')
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(ribbon)
        marks.append(core.link(bpy.data.objects.new('Ribbon', mesh)))
    sun = core.link(bpy.data.objects.new('PlanSun', bpy.data.lights.new('PlanSun', 'SUN')))
    sun.data.energy = 2.5
    sun.data.angle = math.radians(25.0)
    sun.rotation_euler = Vector((0.25, -0.35, -1.0)).to_track_quat('-Z', 'Y').to_euler()
    xs, ys = [p.x for p in outline], [p.y for p in outline]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) + 2.0
    middle = Vector(((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, 0.0))
    cut = [o for o in walls]
    for obj in cut:
        obj.hide_render = True
    low = bpy.data.objects.get('WallLowReview')
    if low:
        low.hide_render = False
        low.data.materials.clear()
        low.data.materials.append(wall_material)
    path = folder / f'{room["id"]}_plan.png'
    render(Vector((middle.x, middle.y + 0.001, floor + 30.0)), Vector((middle.x, middle.y, floor)), path,
           size=(1100, 1100), samples=48, ortho=span)
    paths.append(path)
    print('ROOM_RUBBLE_RENDERED', device, [p.name for p in paths], flush=True)
    return paths


# ---------------------------------------------------------------- room

def build(room: dict, layout: dict, arch: Path, out: Path, seed: int, with_review: bool) -> dict:
    started = time.time()
    room_id, floor = room['id'], room['floor']
    source_path = arch / 'rooms' / f'{room_id}.glb'
    core.empty_scene()
    walls = import_room(source_path)
    if not walls:
        raise SystemExit(f'{room_id}: no Stone_/Mortar_ meshes in {source_path}')
    low = crop_walls(walls, floor)
    wall_tree = bvh_of([low])
    outline = ccw([plan(p) for p in room['points']])
    routes = Routes(layout, floor)
    feet, corners, perimeter = wall_feet(outline, wall_tree, floor)
    heaps = density(feet, corners, perimeter, routes, core.rng(seed, room_id, 'density'))
    field = Field(feet)
    usable = sum(FOOT_STEP for f in feet if f.valid)
    room_inner = inset(outline, 0.3)
    timings = {'setup': round(time.time() - started, 1)}

    bed, bed_tris, patches = grime_bed(room_id, outline, field, routes, floor, seed)
    scale = max(0.4, usable / 36.0)
    loose_bits = (loose(room_id, seed, 'small', min(140, round(110 * scale)))
                  + loose(room_id, seed, 'gravel', min(420, round(380 * scale))))
    cells = []
    for index in range(max(10, round(32 * scale))):
        cells += shattered(room_id, seed, index)
    budget = int(TRI_BUDGET * 0.96) - bed_tris - sum(tris(b.obj) for b in loose_bits)
    bits = budgeted(cells, budget)
    chunk_tris = sum(tris(b.obj) for b in bits)
    bits += loose_bits
    spent = bed_tris + sum(tris(b.obj) for b in bits)
    while spent > TRI_BUDGET * 0.97:
        grit = next(b for b in reversed(bits) if b.cls == 'gravel')
        spent -= tris(grit.obj)
        bits.remove(grit)
        bpy.data.objects.remove(grit.obj, do_unlink=True)
    gravel = []
    generated = {}
    for bit in bits:
        generated[bit.cls] = generated.get(bit.cls, 0) + 1
    timings['pieces'] = round(time.time() - started - sum(timings.values()), 1)
    print('ROOM_RUBBLE_PIECES', room_id, generated, 'tris', spent + sum(tris(b.obj) for b in gravel),
          'chunks', chunk_tris, 'grime', bed_tris, flush=True)

    order = core.rng(seed, room_id, 'order')
    rank = {'big': 0, 'medium': 1, 'small': 2, 'gravel': 3}
    bits.sort(key=lambda b: (rank[b.cls] + order.random() * 0.9, -b.size))
    floor_box = core.link(bpy.data.objects.new('Floor', bpy.data.meshes.new('Floor')))
    fb = bmesh.new()
    bmesh.ops.create_cube(fb, size=1.0)
    xs, ys = [p.x for p in outline], [p.y for p in outline]
    bmesh.ops.scale(fb, vec=(max(xs) - min(xs) + 8.0, max(ys) - min(ys) + 8.0, 0.5), verts=fb.verts[:])
    fb.to_mesh(floor_box.data)
    fb.free()
    floor_box.location = ((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, floor - 0.25)
    statics = [low]
    bed_tree = bvh_of(patches) if patches else None
    removed = deposit(bits, field, wall_tree, bed_tree, routes, room_inner, floor, seed, room_id, perimeter)
    timings['deposit'] = round(time.time() - started - sum(timings.values()), 1)

    first = progressive(bits, statics, patches, floor_box, first=90, segment=45, segments=10)
    discard(bits, routes, room_inner, floor, first['speed'], removed)
    timings['physics_1'] = round(time.time() - started - sum(timings.values()), 1)
    print('ROOM_RUBBLE_PASS1', room_id, 'frames', first['frames'], 'runs', first['runs'], 'kept', len(bits),
          'removed', removed, flush=True)

    # Stability check: everything is let go again from the settled pose (the
    # discards may have taken a support away). The first run's movement is
    # the measure; pieces still moving after three runs go.
    # Stability check of the exported pose: every kept piece is let go again
    # for 1.5 s and measured, without keeping the result. If something still
    # moves (a support was discarded, or a piece was held mid-topple), the
    # pose is settled again and checked again.
    for attempt in range(4):
        moved = release(bits, statics, patches, floor_box)
        over1 = sum(1 for m in moved if m[0] > 0.01)
        print('ROOM_RUBBLE_CHECK', room_id, attempt, 'max_move', round(moved[0][0], 4) if moved else 0.0,
              'moved>1cm', over1, 'moved>3cm', sum(1 for m in moved if m[0] > 0.03), 'top', [(round(m[0], 3), m[2]) for m in moved[:3]],
              flush=True)
        if not moved or (moved[0][0] <= 0.03 and over1 <= max(3, len(bits) // 200)) or attempt == 3:
            break
        second = progressive(bits, statics, patches, floor_box, first=45, segment=45, segments=3)
        discard(bits, routes, room_inner, floor, second['speed'], removed)
        print('ROOM_RUBBLE_PASS2', room_id, attempt, 'runs', second['runs'], 'kept', len(bits), removed, flush=True)
    timings['physics_2'] = round(time.time() - started - sum(timings.values()), 1)

    # Floating pieces (a support was discarded) are removed, then all re-measured.
    floating = []
    for _ in range(4):
        found = contacts(bits, low, bed, floor)
        lost = [b for b in bits if found['gaps'][b.obj.name] > MAX_GAP]
        if not lost:
            break
        for bit in lost:
            floating.append([bit.obj.name, round(found['gaps'][bit.obj.name], 4)])
            bits.remove(bit)
            bpy.data.objects.remove(bit.obj, do_unlink=True)
    removed['floating'] = len(floating)
    route_worst = max((route_height(b, routes, floor) for b in bits), default=0.0)
    max_gap = max(found['gaps'].values())
    assert max_gap <= MAX_GAP, (room_id, 'floating', max_gap)
    assert route_worst <= ROUTE_HEIGHT, (room_id, 'route', route_worst)
    timings['checks'] = round(time.time() - started - sum(timings.values()), 1)

    # Where the material actually ended up: volume and top height per wall
    # foot, summed over 0.8 m of wall either side (report and review views).
    for foot in feet:
        foot.mass, foot.top = 0.0, 0.0
    for bit in bits:
        verts = world_verts(bit.obj)
        c = sum(verts, Vector()) / len(verts)
        foot = field.nearest(c.x, c.y)
        foot.mass += rigid.volume(bit.obj)
        foot.top = max(foot.top, max(v.z for v in verts) - floor)
    for foot in feet:
        near = [f for f in feet if arc(f.s, foot.s, perimeter) < 0.8]
        foot.heap = sum(f.mass for f in near)
    heap_report = []
    for foot in sorted(feet, key=lambda f: -f.heap):
        if foot.heap <= 0.0 or not all((foot.p - q.p).length > 1.6 for q in heap_report):
            continue
        heap_report.append(foot)
    heap_report = [{'godot_xz': [round(f.p.x, 2), round(-f.p.y, 2)], 'stone_volume_m3': round(f.heap, 4),
                    'top_m': round(max(g.top for g in feet if arc(g.s, f.s, perimeter) < 0.8), 3)}
                   for f in heap_report[:8]]

    # Merge by quarter of the room so Godot can cull, hulls for big pieces.
    centre = sum(outline, Vector()) / len(outline)
    groups = {}
    for bit in bits:
        c = sum(world_verts(bit.obj), Vector()) / len(bit.obj.data.vertices)
        quarter = int(((math.atan2(c.y - centre.y, c.x - centre.x) + math.pi) / math.tau) * 4) % 4
        groups.setdefault(quarter, []).append(bit)
    hulls = [hull_mesh(b.obj, f'RubbleCollision_{room_id}_{i:02d}-convcolonly')
             for i, b in enumerate(sorted([b for b in bits if b.size > HULL_SIZE], key=lambda b: b.obj.name))]
    kept = {}
    for bit in bits:
        kept[bit.cls] = kept.get(bit.cls, 0) + 1
    sizes = sorted(b.size for b in bits)
    meshes = []
    for quarter in sorted(groups):
        meshes.append(merge([b.obj for b in groups[quarter]], f'Rubble_{room_id}_{quarter}'))
        for bit in groups[quarter]:
            bpy.data.objects.remove(bit.obj, do_unlink=True)
    if bed:
        meshes.append(bed)
    bpy.data.objects.remove(low, do_unlink=True)
    for patch in patches:
        bpy.data.objects.remove(patch, do_unlink=True)
    # Stones take occlusion from walls, floor and each other. The grime bed is
    # baked without the floor: it lies on it, and near its thin edge the floor
    # would darken it into a hard rim.
    ao = bake.ao_to_color([m for m in meshes if m is not bed], samples=64, distance=AO_DISTANCE)
    if bed:
        floor_box.hide_render = True
        ao.update(bake.ao_to_color([bed], samples=64, distance=AO_DISTANCE))
        floor_box.hide_render = False
    colours = {obj.name: grey(obj) for obj in meshes}
    timings['bake'] = round(time.time() - started - sum(timings.values()), 1)
    hull_objects = [core.link(bpy.data.objects.new(mesh.name, mesh)) for mesh in hulls]
    for obj in hull_objects:
        obj.hide_render = True
    out.mkdir(parents=True, exist_ok=True)
    glb = export.glb(meshes + hull_objects, out / f'{room_id}.glb')
    total = sum(tris(m) for m in meshes)
    assert total <= TRI_BUDGET, (room_id, total)

    renders = []
    if with_review:
        review_low = crop_walls(walls, floor)
        review_low.name = 'WallLowReview'
        review_low.hide_render = True
        renders = review(room, outline, walls, meshes, floor_box, feet, routes, out / 'review')
    timings['review'] = round(time.time() - started - sum(timings.values()), 1)

    peaks = []
    for foot in sorted([f for f in feet if f.valid], key=lambda f: -f.H):
        if all((foot.p - q.p).length > 1.5 for q in peaks):
            peaks.append(foot)
    data = {
        'id': room_id, 'seed': seed, 'task': 'T-179',
        'generator': 'scripts/art/build_room_rubble.py',
        'command': 'blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_room_rubble.py -- '
                   + ' '.join(core.args()),
        'source': {'room_glb': core.relative(source_path), 'room_glb_sha256': core.sha256(source_path),
                   'layout': core.relative(LAYOUT), 'layout_sha256': core.sha256(LAYOUT)},
        'axes': 'Godot world coordinates, metres, Y up: place at the origin like the room GLB',
        'floor_y': floor,
        'pieces': {'generated': generated, 'kept': kept, 'kept_total': len(bits),
                   'discarded': removed, 'floating_removed': floating,
                   'size_m': {'min': round(sizes[0], 3), 'median': round(sizes[len(sizes) // 2], 3),
                              'max': round(sizes[-1], 3)}},
        'triangles': {'total': total, 'budget': TRI_BUDGET, 'meshes': {m.name: tris(m) for m in meshes}},
        'collision': {'convex_hulls': len(hulls), 'min_piece_size_m': HULL_SIZE,
                      'hull_vertices': sum(len(h.vertices) for h in hulls)},
        'settle': {
            'rule': (f'a piece is still when the net travel of its fastest bound-box corner over 15 frames '
                     f'(30 fps) is under {SETTLE_SPEED} m/s; still pieces are held for later runs'),
            'drop': {'frames': first['frames'], 'runs': first['runs'], 'never_still': len(first['moving'])},
            'stability_check': {
                'what': 'every kept piece let go again from the exported pose for 1.5 s (measured, not kept)',
                'max_move_m': round(moved[0][0], 4) if moved else 0.0,
                'max_turn_deg': round(max((m[1] for m in moved), default=0.0), 2),
                'pieces_moved_over_1cm': sum(1 for m in moved if m[0] > 0.01),
                'pieces_moved_over_3cm': sum(1 for m in moved if m[0] > 0.03),
                'resettled': attempt},
            'max_contact_gap_m': round(max_gap, 4),
            'max_interpenetration_m': round(found['max_penetration_m'], 4),
            'deepest_pair': found['deepest_pair'],
        },
        'routes': {'clear_height_m': ROUTE_HEIGHT, 'pad_m': ROUTE_PAD, 'level_m': ROUTE_LEVEL,
                   'max_height_in_ribbons_m': round(route_worst, 4), 'ribbons': routes.ribbons()},
        'physics': {'engine': 'Blender rigid body (Bullet)', 'fps': 30, 'substeps_per_frame': 40,
                    'solver_iterations': 60, 'pieces': 'CONVEX_HULL', 'walls': 'MESH (Stone_* and Mortar_* below 1.6 m)',
                    'grime_bed': 'CONVEX_HULL patches of 2 x 2 cells', 'floor': 'BOX',
                    'damping': {'stone': [0.4, 0.95], 'grit': [0.45, 0.97]}, 'friction': 0.95,
                    'margins_m': {'piece': PIECE_MARGIN, 'gravel': GRAVEL_MARGIN, 'static': STATIC_MARGIN},
                    'density_kg_m3': DENSITY},
        'heaps': dict(heaps, usable_wall_m=round(usable, 1), perimeter_m=round(perimeter, 1),
                      target_heaps=[{'godot_xz': [round(f.p.x, 2), round(-f.p.y, 2)], 'wedge_height_m': round(f.H, 2)}
                                    for f in peaks if f.H > 0.15],
                      settled_heaps=heap_report),
        'color': f'Color.rgb = baked AO ({AO_DISTANCE} m) x per-piece tone {TONE} (x {FRESH} on fresh breaks); '
                 f'grime bed tone {GRIME_TONE}; grey, clipped to 1 by glTF',
        'ao': ao, 'vertex_color': colours,
        'review': [core.relative(p) for p in renders],
        'seconds': timings, 'build_seconds': round(time.time() - started, 1),
    }
    core.write_report(out / f'{room_id}.json', data, [glb])
    print('ROOM_RUBBLE', room_id, 'kept', len(bits), kept, 'tris', total, 'hulls', len(hulls),
          'gap', round(max_gap, 4), 'pen', round(found['max_penetration_m'], 4), 'route', round(route_worst, 4),
          'removed', removed, f"{data['build_seconds']}s", flush=True)
    return data


def main() -> None:
    parser = argparse.ArgumentParser(prog='build_room_rubble.py')
    parser.add_argument('--arch', default=str(ARCH), help='procedural_architecture_v1 folder (index.json, rooms/)')
    parser.add_argument('--layout', default=str(LAYOUT))
    parser.add_argument('--rooms', help='comma-separated room ids (default: index.json rooms)')
    parser.add_argument('--seed', type=int, default=SEED)
    parser.add_argument('--out', default=str(OUT))
    parser.add_argument('--no-review', action='store_true', help='skip the Cycles review renders')
    options = parser.parse_args(core.args())
    arch = Path(options.arch).resolve()
    layout = json.loads(Path(options.layout).read_text())
    index = json.loads((arch / 'index.json').read_text())
    wanted = options.rooms.split(',') if options.rooms else index['rooms']
    rooms = {r['id']: r for r in layout['rooms']}
    for room_id in wanted:
        if room_id not in rooms:
            raise SystemExit(f'{room_id}: not in the layout')
        build(rooms[room_id], layout, arch, Path(options.out).resolve(), options.seed, not options.no_review)
    print('ROOM_RUBBLE_OK', len(wanted), flush=True)


if __name__ == '__main__':
    main()
