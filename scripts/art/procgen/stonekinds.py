"""Stone kinds for the masonry engine (T-182): a family of walling, pier, arch,
vault and floor stones that sit with stones.py's squared_rubble.

    stone = stonekinds.make('dressed_ashlar', rng, size=(0.62, 0.30, 0.32), name='A1')
    pin = stonekinds.spall(rng, name='G1')                     # a galleting spall
    lib = stonekinds.Library(rng, 'thin_slab', count=80)       # like stonelib.Library
    parts = masonry.Wall(2.5, 1.8, **stonekinds.KINDS['thin_slab']['wall']).build(lib, rng)
    parts += stonekinds.gallet(parts, rng)                      # spalls into open joints

Axes and sizes, as stones.make: size = (x along the face, y depth behind the
front, z up the face) in metres, centred at the origin, the front (show) face
on local -y. stonelib-style library axes come from rotating -90 deg about x
(x along, y up, z out of the face). A floor flag uses the same axes: its
walking face is the front (-y), y is its thickness and z its width in plan.

Kinds (natural sizes in KINDS[kind]: 'height' up the face, 'aspects' =
length / height, 'depth' behind the face):
    dressed_ashlar   near-rectangular, crisp but worn arrises, small chamfers,
                     a fine tooled (batter) face
    thin_slab        long flat walling stones 6-12 cm tall, split faces,
                     broken ends, slightly wavy beds
    small_squared    brick-sized (22 x 10 x 12 cm) roughly squared units for
                     vault webs and arch rings
    big_quoin        60-120 cm blocks: heavy chamfers, a drafted margin round
                     a rock-faced, pitched boss
    galleted_rubble  irregular split rubble; spall() makes the small stones
                     wedged into its joints, gallet() places them
    floor_flag       flat paving slabs, chipped edges, dished by wear on top
Any stones.LOOKS kind (squared_rubble, ashlar, ...) passes through to stones.make.

Construction follows stones.py, so the kinds weather as one family: a convex
core cut from jittered planes (stones._cut), then a voxel remesh, wear that
rounds arrises more than faces, the same broad lumps / distorted-noise pitch /
grain relief, chips with fresh faces, and a collapse decimate to a budget of
120-320 triangles (floor flags up to ~380), weighted to keep detail on the
front. The kind's own features (chamfers, drafted margin and boss, tooling,
split facets, wavy beds, wear dish) are worked into the dense mesh before it
is decimated. Colour attribute 'Color' per corner: R = 1 (AO later), G =
per-stone tone, B = 1 on fresh breaks, 0 on weathered faces. 'UVMap' is
box-projected local metres, as in stones.detail. Everything is driven by the
rng passed in (procgen.core.rng), so a seed rebuilds the same stones.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

from . import core, stones

FRONT = Vector((0.0, -1.0, 0.0))

# Shared by every kind unless overridden: the squared_rubble family's weathering.
FAMILY = dict(square=1.0, face=0.6, offset=0.004, chamfer=None, arris=0.0, splits=(0, 0), split_face=0.12, ends=0,
              breaks=(0, 2, 0.01, 0.03), voxel=0.007, wear=0.008, wear_top=0.0, wave=None,
              lumps=0.0015, lump_scale=0.16, pitch=0.001, pitch_scale=0.05, grain=0.0004, grain_scale=0.012,
              facets=None, tool=None, boss=None, dish=None, pillow=None, patchy=0.6, fresh_splits=0.35, chips=(1, 3, 0.004, 0.012), sharp=50.0, triangles=240)

KINDS = {
    # Coursed, dressed rooms; pier and pilaster faces; arch rings and jambs.
    'dressed_ashlar': dict(
        use='walls of dressed rooms, pier and pilaster faces, jambs, arch rings',
        height=(0.24, 0.40), aspects=(1.1, 3.0), depth=(0.24, 0.36), triangles=280,
        square=0.6, face=0.4, offset=0.0025, voxel=0.0055,
        chamfer=(0.016, 0.024), arris=0.004, breaks=(0, 1, 0.012, 0.03),
        wear=0.004, patchy=0.9, lumps=0.0011, lump_scale=0.22, pitch=0.0005, grain=0.0003,
        tool=(0.003, 0.075, 0.1), chips=(1, 4, 0.004, 0.011), sharp=36.0,
        wall=dict(course=(0.28, 0.36), stone=(0.45, 0.95), joint=(0.003, 0.007), proud=(-0.002, 0.004))),
    # Long flat bedded stones split from thin beds: coursed walling, backing.
    'thin_slab': dict(
        use='coursed walling between dressed dressings, wall backs, low walls',
        height=(0.06, 0.12), aspects=(3.0, 10.0), depth=(0.18, 0.30), triangles=200,
        square=1.6, face=2.2, offset=0.004, voxel=0.0042, ends=2,
        breaks=(1, 3, 0.008, 0.03), wear=0.0035, wave=(0.006, 0.22),
        lumps=0.0016, lump_scale=0.12, pitch=0.0011, pitch_scale=0.04, grain=0.0004,
        facets=(0.003, 0.05, (2.4, 1.0, 0.55)), chips=(2, 5, 0.004, 0.01), sharp=55.0,
        wall=dict(course=(0.06, 0.12), stone=(0.3, 0.9), joint=(0.005, 0.012), proud=(-0.008, 0.012))),
    # Brick-sized roughly squared units: vault webs, arch rings, relieving arches.
    'small_squared': dict(
        use='vault webs, arch rings and relieving arches, small piers, infill panels',
        height=(0.085, 0.12), aspects=(1.6, 2.8), depth=(0.10, 0.15), triangles=150,
        square=2.4, face=1.8, offset=0.004, voxel=0.0036,
        breaks=(0, 2, 0.006, 0.018), wear=0.004, lumps=0.0014, lump_scale=0.07, pitch=0.0009, pitch_scale=0.03,
        grain=0.0003, facets=(0.002, 0.04), pillow=(0.002, 0.005), chips=(1, 3, 0.003, 0.008), sharp=50.0,
        wall=dict(course=(0.085, 0.12), stone=(0.18, 0.28), joint=(0.006, 0.012), proud=(-0.004, 0.008))),
    # Heavy blocks for plinths, piers and corners.
    'big_quoin': dict(
        use='plinths, pier bases and pier shafts, quoins at wall corners, springer blocks',
        height=(0.30, 0.55), aspects=(1.3, 3.0), length=(0.6, 1.2), depth=(0.35, 0.60), triangles=320,
        square=0.8, face=0.5, offset=0.003, voxel=0.0075,
        chamfer=(0.025, 0.038), arris=0.012, breaks=(0, 2, 0.02, 0.05),
        wear=0.007, lumps=0.0018, lump_scale=0.3, pitch=0.0008, grain=0.0004,
        boss=dict(margin=(0.045, 0.065), height=(0.028, 0.045), facets=0.0045, cell=0.15),
        chips=(2, 5, 0.006, 0.016), sharp=45.0,
        wall=dict(course=(0.32, 0.5), stone=(0.6, 1.2), joint=(0.004, 0.009), proud=(-0.003, 0.006))),
    # Irregular split rubble laid roughly to courses; joints packed with spalls.
    'galleted_rubble': dict(
        use='rough walls, cellar and tunnel walls, wall cores exposed by ruin',
        height=(0.14, 0.34), aspects=(0.8, 2.4), depth=(0.2, 0.34), triangles=220,
        square=7.0, face=3.5, offset=0.012, voxel=0.0065, splits=(1, 3), split_face=0.12,
        breaks=(1, 3, 0.015, 0.04), wear=0.0095, patchy=0.5, lumps=0.0035, lump_scale=0.15, pitch=0.0022, pitch_scale=0.05,
        grain=0.0005, facets=(0.004, 0.08), pillow=(0.008, 0.016), chips=(1, 3, 0.005, 0.014), sharp=50.0,
        wall=dict(course=(0.18, 0.34), stone=(0.2, 0.55), joint=(0.012, 0.024), proud=(-0.006, 0.02))),
    # Paving slabs; front = walking face.
    'floor_flag': dict(
        use='floors of rooms and passages, landings, hearths, thresholds',
        height=(0.30, 0.62), aspects=(1.0, 2.2), depth=(0.06, 0.10), triangles=360,
        square=1.4, face=0.5, offset=0.004, voxel=0.0065,
        breaks=(1, 3, 0.02, 0.06), wear=0.004, wear_top=0.01, lumps=0.0028, lump_scale=0.2, pitch=0.0008, grain=0.0003,
        dish=(0.005, 0.01), chips=(3, 8, 0.006, 0.016), sharp=50.0,
        wall=dict(course=(0.30, 0.62), stone=(0.38, 0.95), joint=(0.006, 0.014), proud=(-0.003, 0.003))),
}
for _look in KINDS.values():
    for _key, _value in FAMILY.items():
        _look.setdefault(_key, _value)

SPALL = dict(FAMILY, square=16.0, face=14.0, offset=0.002, voxel=0.0018, splits=(5, 8), split_face=0.25,
             breaks=(0, 0, 0.0, 0.0), wear=0.0008, patchy=0.0, lumps=0.0004, lump_scale=0.03, pitch=0.0003, pitch_scale=0.015,
             grain=0.0001, chips=(0, 0, 0.0, 0.0), sharp=40.0)


# -- small helpers -------------------------------------------------------------

def _smoothstep(e0: float, e1: float, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _offset(rng) -> Vector:
    """Random noise-space placement per stone, as stones.detail's empties."""
    return Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))


def _zscore(values: np.ndarray) -> np.ndarray:
    return (values - values.mean()) / (values.std() + 1e-9)


def _fbm(points: np.ndarray, scale: float, offset: Vector, octaves: int = 4) -> np.ndarray:
    """Broad clouds, zero mean and unit spread (stones.py's 'lumps' and 'grain')."""
    inv = 1.0 / scale
    return _zscore(np.array([noise.fractal(Vector(p) * inv + offset, 1.0, 2.0, octaves) for p in points]))


def _pitch(points: np.ndarray, scale: float, offset: Vector, distortion: float) -> np.ndarray:
    """Distorted noise: the sharper, pitched relief of rock-faced dressing."""
    inv = 1.0 / scale
    total = np.zeros(len(points))
    for octave, weight in ((1.0, 1.0), (2.1, 0.45)):
        total += weight * np.array([noise.variable_lacunarity(Vector(p) * inv * octave + offset, distortion,
                                                              noise_type1='PERLIN_ORIGINAL', noise_type2='PERLIN_ORIGINAL')
                                    for p in points])
    return _zscore(total)


def _facets(points: np.ndarray, cell: float, offset: Vector, stretch=(1.0, 1.0, 1.0)) -> np.ndarray:
    """Split and pitched scars: the lower envelope of shallow tilted dishes,
    one per Voronoi cell (as the T-180 texture's dressing scars), so dished
    facets meet in sharp ridges. The dish term keeps the nearest cells the
    minimum, so the field stays continuous. `stretch` elongates the cells
    (bedding in a slab)."""
    scale = Vector((1.0 / (cell * stretch[0]), 1.0 / (cell * stretch[1]), 1.0 / (cell * stretch[2])))
    out = np.empty(len(points))
    for i, p in enumerate(points):
        q = Vector((p[0] * scale.x, p[1] * scale.y, p[2] * scale.z)) + offset
        _, centres = noise.voronoi(q, distance_metric='DISTANCE', exponent=2.5)
        best = 1e9
        for c in centres:
            c = Vector(c)
            # Three scalar noises, not noise.noise_vector: in Blender 5.2 that one
            # differs between processes, which breaks seeded rebuilds.
            g = Vector((noise.noise(c * 3.17 + Vector((5.3, 1.1, 7.7))), noise.noise(c * 3.17 + Vector((2.9, 8.4, 0.6))),
                        noise.noise(c * 3.17 + Vector((7.1, 4.6, 3.8)))))
            base = noise.noise(c * 2.31 + Vector((1.7, 9.2, 3.3))) * 0.2
            d = q - c
            best = min(best, base + 0.35 * g.dot(d) + d.length_squared)
        out[i] = best
    return _zscore(out)


# -- convex core ---------------------------------------------------------------

def _edge_point(p1: Vector, n1: Vector, p2: Vector, n2: Vector) -> Vector:
    """Point on the intersection line of two planes nearest the origin."""
    h1, h2 = n1.dot(p1), n2.dot(p2)
    d = n1.dot(n2)
    det = 1.0 - d * d
    if det < 1e-9:
        return (p1 + p2) * 0.5
    return n1 * ((h1 - h2 * d) / det) + n2 * ((h2 - h1 * d) / det)


def _core(rng, size: Vector, look: dict, fresh_caps: list) -> bmesh.types.BMesh:
    """A box cut by six jittered faces (stones.core_block), then the kind's
    chamfers, splitting planes, broken ends and old corner breaks. Fresh caps
    are appended to `fresh_caps` as (point, normal)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size * 1.6, verts=bm.verts)
    fresh = bm.faces.layers.int.new('fresh')
    half = size * 0.5
    planes = {}
    for axis in range(3):
        for sign in (-1.0, 1.0):
            normal = Vector([sign if k == axis else 0.0 for k in range(3)])
            normal = stones._tilt(normal, rng, look['face'] if axis == 1 else look['square'])
            point = Vector([half[k] * (sign if k == axis else 0.0) for k in range(3)])
            point += normal * rng.uniform(-look['offset'], look['offset'] * 0.3)
            stones._cut(bm, point, normal, fresh, None)
            planes[(axis, sign)] = (point, normal)
    # Chamfers: the four front arrises get the kind's chamfer, the other eight
    # a small arris (a mason takes the edge off every arris before setting).
    edges = []
    for a in (0, 2):
        for sa in (-1.0, 1.0):
            edges.append(((1, -1.0), (a, sa), look['chamfer']))
            edges.append(((1, 1.0), (a, sa), (look['arris'], look['arris'] * 1.3) if look['arris'] else None))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            edges.append(((0, sx), (2, sz), (look['arris'], look['arris'] * 1.3) if look['arris'] else None))
    for f1, f2, width in edges:
        if not width:
            continue
        (p1, n1), (p2, n2) = planes[f1], planes[f2]
        m = stones._tilt((n1 + n2).normalized(), rng, 2.5)
        w = rng.uniform(*width)
        e = _edge_point(p1, n1, p2, n2)
        stones._cut(bm, e - m * w * abs(m.dot(n2)), m, fresh, None)
    # Splitting planes break the outline, not the face (stones.make's walling
    # stones); their caps are fresh, as in stones.py.
    low, high = look['splits']
    for _ in range(rng.randint(low, high)):
        normal = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        normal = Vector((normal.x, normal.y * look['split_face'], normal.z)).normalized()
        reach = abs(normal.x) * size.x + abs(normal.y) * size.y + abs(normal.z) * size.z
        point = normal * reach * rng.uniform(0.3, 0.44)
        stones._cut(bm, point, normal, fresh, None)
        if rng.random() < look['fresh_splits']:
            fresh_caps.append((point, normal))
    # Broken ends (thin slabs): one or two oblique breaks near each end.
    for sign in (-1.0, 1.0):
        for _ in range(rng.randint(0, look['ends'])):
            normal = Vector((sign, rng.uniform(-0.25, 0.25), rng.uniform(-0.65, 0.65))).normalized()
            point = Vector((sign * half.x * rng.uniform(0.8, 0.97), 0.0, rng.uniform(-1, 1) * half.z))
            stones._cut(bm, point, normal, fresh, None)
    # Corner breaks, fresh as in stones.core_block's chips.
    low, high, depth_low, depth_high = look['breaks']
    for _ in range(rng.randint(low, high)):
        verts = [v.co.copy() for v in bm.verts]
        corner = verts[rng.randrange(len(verts))]
        normal = stones._tilt(corner.normalized(), rng, 25.0)
        point = corner - normal * rng.uniform(depth_low, depth_high)
        stones._cut(bm, point, normal, fresh, None)
        if rng.random() < 0.6:
            fresh_caps.append((point, normal))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


# -- dense surface -------------------------------------------------------------

class _Dense:
    """The remeshed stone as numpy arrays: positions, edges, normals."""

    def __init__(self, bm: bmesh.types.BMesh, voxel: float, name: str):
        mesh = bpy.data.meshes.new(name + '_core')
        bm.to_mesh(mesh)
        bm.free()
        self.obj = core.link(bpy.data.objects.new(name, mesh))
        remesh = self.obj.modifiers.new('Remesh', 'REMESH')
        remesh.mode = 'VOXEL'
        remesh.voxel_size = voxel
        depsgraph = bpy.context.evaluated_depsgraph_get()
        self.mesh = bpy.data.meshes.new_from_object(self.obj.evaluated_get(depsgraph))
        self.obj.modifiers.clear()
        self.obj.data = self.mesh
        bpy.data.meshes.remove(mesh)
        n = len(self.mesh.vertices)
        co = np.empty(n * 3, np.float32)
        self.mesh.vertices.foreach_get('co', co)
        self.co = co.reshape(n, 3).astype(np.float64)
        edges = np.empty(len(self.mesh.edges) * 2, np.int32)
        self.mesh.edges.foreach_get('vertices', edges)
        self.edges = edges.reshape(-1, 2)
        self.fresh = np.zeros(n)
        self.voxel = voxel

    def normals(self) -> np.ndarray:
        self.mesh.vertices.foreach_set('co', self.co.astype(np.float32).ravel())
        self.mesh.update()
        values = np.empty(len(self.co) * 3, np.float32)
        self.mesh.vertex_normals.foreach_get('vector', values)
        return values.reshape(-1, 3).astype(np.float64)

    def smooth(self, iterations: int, factor: float = 0.7, weight: np.ndarray = None) -> None:
        """Laplacian wear (the SMOOTH modifier of stones.detail), optionally weighted."""
        a, b = self.edges[:, 0], self.edges[:, 1]
        n = len(self.co)
        degree = np.maximum(np.bincount(a, minlength=n) + np.bincount(b, minlength=n), 1)[:, None]
        w = factor if weight is None else (factor * weight)[:, None]
        co = self.co
        for _ in range(iterations):
            total = np.stack([np.bincount(a, co[b, k], n) + np.bincount(b, co[a, k], n) for k in range(3)], axis=1)
            co = co + (total / degree - co) * w
        self.co = co

    def wear(self, radius: float, weight: np.ndarray = None, patchy: float = 0.0, rng=None) -> None:
        """Round arrises to about `radius` metres (diffusion length in voxels).
        `patchy` > 0 wears unevenly: some stretches of arris stay crisp,
        others erode up to (1 + patchy) times as far."""
        boost = 1.0
        if patchy and rng is not None:
            field = _fbm(self.co, rng.uniform(0.08, 0.14), _offset(rng), 3)
            patch = 0.15 + 0.85 * _smoothstep(-0.6, 1.0, field)
            weight = patch if weight is None else weight * patch
            boost = (1.0 + patchy) ** 2
        iterations = max(1, round(2.0 * (radius / self.voxel) ** 2 / 0.7 * boost))
        self.smooth(iterations, 0.7, weight)

    def mark_caps(self, caps: list) -> None:
        normals = self.normals()
        for point, normal in caps:
            p, m = np.array(point), np.array(normal)
            distance = np.abs((self.co - p) @ m)
            self.fresh[(distance < self.voxel * 1.6) & (normals @ m > 0.6)] = 1.0


def _front_frame(co: np.ndarray, normals: np.ndarray, threshold: float = 0.8):
    """Bounds (x0, x1, z0, z1) of the flat front face and its mask."""
    facing = normals @ np.array(FRONT)
    front = co[facing > threshold]
    if len(front) < 8:
        front = co[co[:, 1] < co[:, 1].min() + 0.01]
    x0, x1 = np.percentile(front[:, 0], [0.5, 99.5])
    z0, z1 = np.percentile(front[:, 2], [0.5, 99.5])
    return (x0, x1, z0, z1), facing


def _arrises(dense: _Dense) -> tuple:
    """Front arris and corner vertices of the worn block, before any relief
    (so chips land on the arrises, not on a boss or a tooled face)."""
    normals = dense.normals()
    facing = normals @ np.array(FRONT)
    ymin = dense.co[:, 1].min()
    return np.nonzero((facing > 0.2) & (facing < 0.85) & (dense.co[:, 1] < ymin + 0.03))[0], normals


def _chips(dense: _Dense, rng, look: dict, candidates: np.ndarray, normals: np.ndarray) -> None:
    """Fresh chips on the front arrises and corners: a conchoidal scallop
    (the stone inside a sphere set just outside the arris is carved away),
    shallow and wider than deep with a crisp rim, unlike the worn arris."""
    low, high, depth_low, depth_high = look['chips']
    count = rng.randint(low, high)
    if not count or len(candidates) == 0:
        return
    for _ in range(count):
        site = int(candidates[rng.randrange(len(candidates))])
        n = np.array(stones._tilt(Vector(normals[site]).normalized(), rng, 15.0))
        depth = rng.uniform(depth_low, depth_high)
        width = depth * rng.uniform(2.4, 3.8)
        radius = (width * width + depth * depth) / (2.0 * depth)
        centre = dense.co[site] + n * (radius - depth)
        offset = dense.co - centre
        distance = np.linalg.norm(offset, axis=1)
        inside = distance < radius
        dense.co[inside] = centre + offset[inside] / distance[inside, None] * radius
        dense.fresh[inside] = 1.0


def _relief(dense: _Dense, rng, look: dict, size: Vector) -> None:
    """The kind's own surface (tooling, boss, dish, facets), then the family's
    lumps, pitch and grain along the normals."""
    normals = dense.normals()
    co = dense.co
    (x0, x1, z0, z1), facing = _front_frame(co, normals)
    front = _smoothstep(0.55, 0.85, facing)
    edge = np.minimum.reduce([co[:, 0] - x0, x1 - co[:, 0], co[:, 2] - z0, z1 - co[:, 2]])
    shift = np.zeros(len(co))  # outward along the normal
    along_front = np.zeros(len(co))  # outward along FRONT (-y)
    calm = np.ones(len(co))  # scales the family relief
    settle = 1
    if look['tool']:
        # Batter: parallel strokes of a broad chisel across the face, each a
        # flat facet a little off the face plane, meeting in fine ridges; a
        # little off true and of uneven depth stroke by stroke.
        depth, spacing_low, spacing_high = look['tool']
        spacing = rng.uniform(spacing_low, spacing_high)
        angle = math.radians(rng.choice((90.0, 90.0, 80.0, 100.0, 65.0, 115.0)) + rng.uniform(-4, 4))
        u = (co[:, 0] * math.cos(angle) + co[:, 2] * math.sin(angle)) / spacing + rng.random()
        stroke = np.floor(u)
        phase = u - stroke
        seed = _offset(rng)
        jitter = np.array([noise.noise(Vector((k * 0.73, 3.1, 0.5)) + seed) for k in stroke])
        strength = depth * (0.75 + 0.5 * np.abs(jitter))
        inside = _smoothstep(0.003, 0.01, edge)
        along_front -= strength * np.abs(2.0 * phase - 1.0) * front * inside
        # The dressed face is the strokes alone: planar facets the decimator
        # keeps as long strips, where noise would cost the whole budget.
        calm *= 1.0 - front * inside
    if look['boss']:
        boss = look['boss']
        margin_width = rng.uniform(*boss['margin'])
        high = rng.uniform(*boss['height'])
        low = high * rng.uniform(0.45, 0.65)
        wobble = _fbm(co, 0.25, _offset(rng), 2) * 0.0025
        inside = _smoothstep(margin_width + wobble, margin_width + wobble + 0.016, edge) * front
        # Rock face: a low dome of pitched scars standing proud of a flat,
        # tooled margin; the pitch line where they meet is crisp.
        span = max(min(x1 - x0, z1 - z0) * 0.5 - margin_width, 1e-3)
        rise = _smoothstep(0.0, span * 0.9, edge - margin_width)
        rough = _facets(co, boss['cell'] * rng.uniform(0.85, 1.2), _offset(rng)) * boss['facets']
        rough += _pitch(co, boss['cell'] * 0.4, _offset(rng), 1.2) * boss['facets'] * 0.3
        rough *= 0.35 + 0.65 * rise
        along_front += inside * np.maximum(low + (high - low) * rise + rough, 0.008)
        calm *= 1.0 - 0.8 * front * (1.0 - inside)
        settle = 3
    if look['dish']:
        # Wear by feet: a broad hollow, off centre along the line people walk.
        depth = rng.uniform(*look['dish'])
        cx = (x0 + x1) * 0.5 + rng.uniform(-0.2, 0.2) * (x1 - x0)
        cz = (z0 + z1) * 0.5 + rng.uniform(-0.15, 0.15) * (z1 - z0)
        r2 = ((co[:, 0] - cx) / max((x1 - x0) * 0.6, 1e-3)) ** 2 + ((co[:, 2] - cz) / max((z1 - z0) * 0.6, 1e-3)) ** 2
        hollow = np.clip(1.0 - r2, 0.0, 1.0) ** 1.4 * (1.0 + 0.35 * _fbm(co, 0.15, _offset(rng), 2).clip(-1.5, 1.5))
        along_front -= depth * hollow * front
        # The walking face is worn smooth: less relief on top than on the edges.
        calm *= 1.0 - 0.6 * front
    if look['pillow']:
        # A convex, weathered face: the middle stands out, the arrises fall back.
        span = max(min(x1 - x0, z1 - z0) * 0.5, 1e-3)
        along_front += rng.uniform(*look['pillow']) * _smoothstep(0.0, span, edge) * front
    if look['facets']:
        amplitude, cell = look['facets'][:2]
        stretch = look['facets'][2] if len(look['facets']) > 2 else (1.0, 1.0, 1.0)
        shift += _facets(co, cell * rng.uniform(0.85, 1.2), _offset(rng), stretch) * amplitude
    shift += _fbm(co, look['lump_scale'] * rng.uniform(0.8, 1.25), _offset(rng), 4) * look['lumps'] * calm
    shift += _pitch(co, look['pitch_scale'] * rng.uniform(0.8, 1.25), _offset(rng), rng.uniform(0.6, 1.4)) * look['pitch'] * calm
    shift += _fbm(co, look['grain_scale'], _offset(rng), 3) * look['grain'] * calm
    dense.co = co + normals * shift[:, None] + np.outer(along_front, np.array(FRONT))
    # A gentle pass knits the layers without rounding the new edges away.
    dense.smooth(settle, 0.35)


def _finish(dense: _Dense, rng, look: dict, name: str, triangles: int) -> bpy.types.Object:
    """Decimate to budget (front weighted), then colour, UVs and shading as stones.detail."""
    obj, mesh = dense.obj, dense.mesh
    mesh.vertices.foreach_set('co', dense.co.astype(np.float32).ravel())
    mesh.update()
    attribute = mesh.attributes.new('fresh', 'FLOAT', 'POINT')
    attribute.data.foreach_set('value', dense.fresh.astype(np.float32))
    # Keep triangles on the face and its arrises; the back is mostly hidden.
    depth = dense.co[:, 1] - dense.co[:, 1].min()
    span = max(depth.max(), 1e-3)
    group = obj.vertex_groups.new(name='budget')
    for weight, lo, hi in ((0.12, -1.0, 0.2), (0.5, 0.2, 0.45), (1.0, 0.45, 2.0)):
        index = np.nonzero((depth / span >= lo) & (depth / span < hi))[0].tolist()
        if index:
            group.add(index, weight, 'REPLACE')
    decimate = obj.modifiers.new('Budget', 'DECIMATE')
    decimate.vertex_group = 'budget'
    decimate.vertex_group_factor = 1.0
    decimate.use_collapse_triangulate = True
    decimate.ratio = min(1.0, triangles / max(len(mesh.polygons) * 2, 1))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    obj.modifiers.clear()
    obj.vertex_groups.clear()
    obj.data = baked
    bpy.data.meshes.remove(mesh)
    baked.name = name
    fresh = np.empty(len(baked.vertices), np.float32)
    baked.attributes['fresh'].data.foreach_get('value', fresh)
    baked.attributes.remove(baked.attributes['fresh'])
    color = baked.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uv = baked.uv_layers.new(name='UVMap')
    tone = rng.random()
    for polygon in baked.polygons:
        is_fresh = sum(fresh[v] for v in polygon.vertices) / len(polygon.vertices) > 0.5
        n = polygon.normal
        axis = max(range(3), key=lambda k: abs(n[k]))
        for index in polygon.loop_indices:
            co = baked.vertices[baked.loops[index].vertex_index].co
            color.data[index].color = (1.0, tone, 1.0 if is_fresh else 0.0, 1.0)
            # Box-projected metres: the dominant axis of the face normal picks the plane.
            uv.data[index].uv = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][axis]
    baked.color_attributes.active_color = color
    baked.shade_smooth()
    baked.set_sharp_from_angle(angle=math.radians(look['sharp']))
    return obj


def _build(look: dict, rng, size, name: str, triangles: int) -> bpy.types.Object:
    size = Vector(size)
    caps = []
    bm = _core(rng, size, look, caps)
    voxel = min(look['voxel'], min(size) / 9.0)
    dense = _Dense(bm, voxel, name)
    if caps:
        dense.mark_caps(caps)
    if look['wave']:
        # Wavy beds: the slab bends along its length and thickens unevenly.
        amplitude, scale = look['wave']
        co = dense.co
        line = co.copy()
        line[:, 1:] *= 0.15
        bend = _fbm(line, scale * rng.uniform(0.8, 1.3), _offset(rng), 2) * amplitude
        swell = _fbm(line, scale * rng.uniform(0.6, 1.0), _offset(rng), 2) * amplitude * 0.6
        dense.co[:, 2] += bend + swell * co[:, 2] / max(size.z * 0.5, 1e-3)
    weight = None
    if look['wear_top']:
        # Floor flags: feet round the walking face's arrises far more than the rest.
        top = _smoothstep(-0.2, 0.6, dense.normals() @ np.array(FRONT))
        weight = 0.35 + 0.65 * top
        dense.wear(look['wear_top'], weight)
    dense.wear(look['wear'], patchy=look['patchy'], rng=rng)
    face = float(dense.co[:, 1].min())
    arrises, normals = _arrises(dense)
    _relief(dense, rng, look, size)
    _chips(dense, rng, look, arrises, normals)
    obj = _finish(dense, rng, look, name, triangles)
    # How far a rock-faced boss stands proud of the stone's face plane (its
    # drafted margin): walls set the face plane, not the boss, on the wall line.
    obj['boss'] = max(0.0, face - min(v.co.y for v in obj.data.vertices)) if look['boss'] else 0.0
    return obj


# -- public API ----------------------------------------------------------------

def natural_size(kind: str, rng, aspect: float = None, height: float = None) -> Vector:
    """A size in the kind's own range: (along, depth, up the face). Lengths
    are clamped to KINDS[kind]['length'] where a kind has one."""
    look = KINDS[kind]
    height = height if height is not None else rng.uniform(*look['height'])
    low, high = look['aspects']
    aspect = aspect if aspect is not None else math.exp(rng.uniform(math.log(low), math.log(high)))
    length = height * aspect
    if 'length' in look:
        length = min(max(length, look['length'][0]), look['length'][1])
    return Vector((length, rng.uniform(*look['depth']), height))


def make(kind: str, rng, size, name: str = 'Stone', triangles: int = None) -> bpy.types.Object:
    """One unique stone of `kind`, same contract as stones.make (see module doc)."""
    if kind not in KINDS:
        return stones.make(kind, rng, size, name=name, triangles=triangles or 1200)
    look = KINDS[kind]
    return _build(look, rng, size, name, triangles or look['triangles'])


def spall(rng, size=None, name: str = 'Spall', triangles: int = 70) -> bpy.types.Object:
    """A small galleting spall: a thin, sharp flake of fresh stone (default 3-9
    cm long), front on -y like every stone here, for wedging into joints."""
    if size is None:
        length = rng.uniform(0.025, 0.065)
        size = (length, rng.uniform(0.025, 0.04), length * rng.uniform(0.35, 0.65))
    size = Vector(size)
    obj = _build(SPALL, rng, size, name, triangles)
    # Fresh from the hammer: every broken face counts as fresh except a weathered back.
    colour = obj.data.color_attributes['Color']
    for polygon in obj.data.polygons:
        if polygon.normal.y < 0.6:
            for index in polygon.loop_indices:
                r, g, _, a = colour.data[index].color
                colour.data[index].color = (r, g, 1.0, a)
    return obj


class Library:
    """stonelib.Library for these kinds: unique stones at the kind's natural
    size (stonelib builds every stone 0.25 m tall, which would stretch a 7 cm
    slab or a 1 m quoin 3-4x out of shape), picked by proportion and height
    and fitted to each slot. `place` has stonelib's contract, so masonry.Wall
    takes it as `lib` (or `quoins`): wall-local axes x along, y up, z out of
    the face, front at z = 0."""

    def __init__(self, rng, kind: str, count: int = 60, triangles: int = None, name: str = None,
                 hidden_back: float = None, heights=None, aspects=None, tone=(0.72, 1.18)):
        look = KINDS[kind] if kind in KINDS else None
        self.kind = kind
        self.tone = tone
        self.entries = []  # (aspect, height, mesh, dims)
        collection = bpy.data.collections.new(f'StoneLibrary_{name or kind}')
        bpy.context.scene.collection.children.link(collection)
        collection.hide_render = True
        collection.hide_viewport = True
        heights = heights or (look['height'] if look else (0.2, 0.44))
        low, high = aspects or (look['aspects'] if look else (0.8, 3.2))
        order = list(range(count))
        rng.shuffle(order)
        for index in range(count):
            # Stratified: proportions log-spread, heights spread independently.
            aspect = math.exp(math.log(low) + (math.log(high) - math.log(low)) * (index + rng.random()) / count)
            height = heights[0] + (heights[1] - heights[0]) * (order[index] + rng.random()) / count
            if look:
                size = natural_size(kind, rng, aspect, height)
            else:
                size = Vector((height * aspect, rng.uniform(0.26, 0.36), height))
            obj = make(kind, rng, size, name=f'{name or kind}_lib_{index}', triangles=triangles)
            # Library axes: x along, y up, z out of the face; front at z = 0.
            obj.data.transform(Matrix.Rotation(math.radians(-90), 4, 'X'))
            mesh = obj.data
            co = np.empty(len(mesh.vertices) * 3, np.float32)
            mesh.vertices.foreach_get('co', co)
            co = co.reshape(-1, 3)
            # The face plane: the front, less any boss standing proud of it.
            front = co[:, 2].max() - float(obj.get('boss', 0.0))
            # Fit by the body just behind the worn arrises (as stonelib), so
            # rounded edges close into tight joints.
            reach = min(0.11, (front - co[:, 2].min()) * 0.6)
            band = co[(co[:, 2] < front - min(0.035, reach * 0.4)) & (co[:, 2] > front - reach)]
            if len(band) < 8 or np.ptp(band[:, 0]) < 0.5 * np.ptp(co[:, 0]) or np.ptp(band[:, 1]) < 0.5 * np.ptp(co[:, 1]):
                band = co
            mid = (band[:, :2].max(axis=0) + band[:, :2].min(axis=0)) * 0.5
            mesh.transform(Matrix.Translation((-float(mid[0]), -float(mid[1]), -float(front))))
            dims = Vector((float(np.ptp(band[:, 0])), float(np.ptp(band[:, 1])), float(front - co[:, 2].min())))
            if hidden_back is not None:
                bm = bmesh.new()
                bm.from_mesh(mesh)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -hidden_back], context='FACES')
                bm.to_mesh(mesh)
                bm.free()
            self.entries.append((dims.x / dims.y, dims.y, mesh, dims))
            bpy.context.scene.collection.objects.unlink(obj)
            collection.objects.link(obj)
        self.entries.sort(key=lambda e: e[0])
        self.used = {}

    def pick(self, rng, aspect: float, height: float = None, spread: int = 6):
        """One of the `spread` stones nearest in proportion and height,
        preferring the least used."""
        def distance(entry):
            d = abs(math.log(entry[0] / aspect))
            return d + (abs(math.log(entry[1] / height)) if height else 0.0)
        nearest = sorted(self.entries, key=distance)[:spread]
        nearest.sort(key=lambda e: self.used.get(e[2].name, 0) + rng.random() * 0.9)
        chosen = nearest[0]
        self.used[chosen[2].name] = self.used.get(chosen[2].name, 0) + 1
        return chosen

    def place(self, rng, length: float, height: float, depth: float, name: str, collection=None) -> bpy.types.Object:
        """A stone filling a length x height face slot (centred on x/y, front at
        z = 0). Depth follows the stone's own proportion (within -20/+25 % of
        the face scale) rather than `depth`, so arrises keep their shape."""
        length, height = max(length, 0.02), max(height, 0.02)
        aspect, _, mesh, dims = self.pick(rng, length / height, height)
        obj = bpy.data.objects.new(name, mesh)
        sx, sy = length / dims.x, height / dims.y
        face = math.sqrt(sx * sy)
        sz = min(max(depth / dims.z, face * 0.8), face * 1.25)
        flip_x = -1.0 if rng.random() < 0.5 else 1.0
        flip_y = -1.0 if rng.random() < 0.3 else 1.0
        obj.matrix_world = Matrix.Diagonal((flip_x * sx, flip_y * sy, sz, 1.0))
        obj['tone'] = rng.uniform(*self.tone)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj


def gallet(parts: list, rng, cell: float = 0.01, deep: float = 0.04, min_gap: float = 0.022, spacing: float = 0.11,
           share: float = 0.6, name: str = 'Gallet') -> list:
    """Galleting: small spalls pressed into the open joints of a wall built in
    wall-local space (masonry.Wall.build output, before masonry.place). Rays
    from the face find where the stones fall back more than `deep` behind the
    face; spalls go at the widest points of those gaps, at least `spacing`
    apart, sized to the gap, set a few millimetres back. Returns new objects."""
    solids = [p for p in parts if p.type == 'MESH' and float(p.get('tone', 1.0)) >= 0.0]
    if not solids:
        return []
    verts, polys = [], []
    for obj in solids:
        matrix = obj.matrix_world
        base = len(verts)
        verts += [matrix @ v.co for v in obj.data.vertices]
        polys += [[base + i for i in p.vertices] for p in obj.data.polygons]
    tree = BVHTree.FromPolygons(verts, polys)
    xs = [v.x for v in verts]
    ys = [v.y for v in verts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    nx, ny = int((x1 - x0) / cell), int((y1 - y0) / cell)
    gap = np.zeros((ny, nx), bool)
    for j in range(ny):
        for i in range(nx):
            hit = tree.ray_cast(Vector((x0 + (i + 0.5) * cell, y0 + (j + 0.5) * cell, 0.3)), Vector((0, 0, -1)), 0.3 + deep)
            gap[j, i] = hit[0] is None
    # Keep away from the panel's own edges.
    gap[:3, :] = gap[-3:, :] = False
    gap[:, :3] = gap[:, -3:] = False
    # Distance (cells) to the nearest stone: a two-pass chamfer transform.
    big = 1e6
    dist = np.where(gap, big, 0.0)
    for j in range(ny):
        for i in range(nx):
            if dist[j, i]:
                best = dist[j, i]
                if j:
                    best = min(best, dist[j - 1, i] + 1.0, dist[j - 1, i - 1] + 1.414 if i else big, dist[j - 1, i + 1] + 1.414 if i + 1 < nx else big)
                if i:
                    best = min(best, dist[j, i - 1] + 1.0)
                dist[j, i] = best
    for j in range(ny - 1, -1, -1):
        for i in range(nx - 1, -1, -1):
            if dist[j, i]:
                best = dist[j, i]
                if j + 1 < ny:
                    best = min(best, dist[j + 1, i] + 1.0, dist[j + 1, i + 1] + 1.414 if i + 1 < nx else big, dist[j + 1, i - 1] + 1.414 if i else big)
                if i + 1 < nx:
                    best = min(best, dist[j, i + 1] + 1.0)
                dist[j, i] = best
    radius = dist * cell
    sites = sorted(((radius[j, i], j, i) for j in range(ny) for i in range(nx) if radius[j, i] * 2.0 >= min_gap),
                   key=lambda s: -s[0])
    chosen = []
    for r, j, i in sites:
        x, y = x0 + (i + 0.5) * cell, y0 + (j + 0.5) * cell
        if any((x - cx) ** 2 + (y - cy) ** 2 < spacing ** 2 for cx, cy, _, _ in chosen):
            continue
        if rng.random() > share:
            chosen.append((x, y, 0.0, None))  # leave this gap to the mortar
            continue
        # Direction of the joint here: principal axis of nearby gap cells.
        window = [(ii, jj) for jj in range(max(0, j - 4), min(ny, j + 5)) for ii in range(max(0, i - 4), min(nx, i + 5)) if gap[jj, ii]]
        pts = np.array(window, float) - np.array([i, j], float)
        if len(pts) > 2:
            values, vectors = np.linalg.eigh(np.cov(pts.T))
            axis = vectors[:, int(np.argmax(values))]
            angle = math.atan2(axis[1], axis[0])
        else:
            angle = 0.0
        chosen.append((x, y, angle, r))
    result = []
    for number, (x, y, angle, r) in enumerate(chosen):
        if r is None:
            continue
        width = min(max(r * 2.0 * rng.uniform(0.85, 1.1), 0.014), 0.04)
        length = min(width * rng.uniform(1.3, 2.0), 0.065)
        stone = spall(rng, (length, rng.uniform(0.025, 0.04), width), name=f'{name}_{number}')
        # Spall axes -> wall-local: front (-y) to +z, length along the joint.
        turn = Matrix.Rotation(angle + rng.uniform(-0.25, 0.25), 4, 'Z') @ Matrix.Rotation(math.radians(-90), 4, 'X')
        tilt = Matrix.Rotation(math.radians(rng.uniform(-25, 25)), 4, 'X') @ Matrix.Rotation(math.radians(rng.uniform(-15, 15)), 4, 'Z')
        back = stone.dimensions.y * 0.5 + rng.uniform(0.006, 0.016)
        stone.matrix_world = Matrix.Translation((x, y, -back)) @ turn @ tilt
        stone['tone'] = rng.uniform(0.8, 1.2)
        result.append(stone)
    return result
