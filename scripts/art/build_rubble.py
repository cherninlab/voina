"""Blender background: rigid-body rubble and debris piles baked to static GLBs.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_rubble.py -- \\
    content/environments/procedural_rubble_v1 [--seed N | --seeds 1,2,3] [--recipes wall_spill,...] \\
    [--review content/environments/red_descent/review/rubble_v1]

Procedural stones (fractured ashlar, rough rocks, bricks and mortared brick
clumps, 0.1-0.8 m) and broken planks fall onto a floor proxy, and wall proxies
where the recipe has walls, under Bullet rigid-body physics until the fastest
piece moves slower than 1 cm/s. The settled poses are frozen, measured for
floating and interpenetration on the final meshes, merged per material,
AO-baked against the proxies (which are not exported) and written as GLBs with
Godot convex collision. Nothing is simulated in the game.
"""
import argparse
import math
import struct
import sys
import tempfile
import time
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
import numpy
from mathutils import Euler, Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

from procgen import bake, core, export, rigid, shapes

RECIPES = ('wall_spill', 'corner_heap', 'bridge_debris', 'floor_scatter')
STONE_DENSITY = 2300.0
WOOD_DENSITY = 650.0
TRI_BUDGET = 8000            # LOD0, all meshes of one pile
COLLISION_MIN_SIZE = 0.2     # pieces at least this long get a convex hull in Godot
MAX_GAP = 0.01               # metres; a piece further than this from everything floats
MAX_PENETRATION = 0.01
LOD_RATIOS = (1.0, 0.5, 0.2)
AO_DISTANCE = 0.3            # metres; rubble crevices, not room-scale occlusion
AO_STRENGTH = 0.8            # vertex colour = 1 - strength * (1 - baked AO)
BRICK = Vector((0.215, 0.1025, 0.065))
FRACTURE, DRESSED, MORTAR = 1, 0, 2
UP = Vector((0.0, 0.0, 1.0))


class Piece:
    def __init__(self, obj: bpy.types.Object, kind: str, material: str, size: float):
        self.obj, self.kind, self.material, self.size = obj, kind, material, size
        self.radius = max(v.co.length for v in obj.data.vertices)


# ---------------------------------------------------------------- geometry

def unit(rng) -> Vector:
    while True:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length > 1e-3:
            return v.normalized()


def cut(bm: bmesh.types.BMesh, co: Vector, normal: Vector, tag) -> None:
    """Remove everything in front of the plane and close each opened shell with
    a break face tagged FRACTURE."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=normal, clear_outer=True)
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        for face in bmesh.ops.holes_fill(bm, edges=boundary, sides=0)['faces']:
            face[tag] = FRACTURE


def refine(bm: bmesh.types.BMesh, target: float, passes: int = 6) -> None:
    """Triangulate and split edges longer than `target` so baked vertex AO and
    displacement have vertices to live on."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
    for _ in range(passes):
        long = [e for e in bm.edges if e.calc_length() > target]
        if not long:
            break
        bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=False)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3],
                              quad_method='BEAUTY', ngon_method='BEAUTY')
    flat = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) < math.radians(4.0)]
    bmesh.ops.beautify_fill(bm, faces=bm.faces[:], edges=flat)


def displace(bm: bmesh.types.BMesh, rng, amplitude, frequency: float, octaves: int = 3) -> None:
    """Move vertices along their normals by fractal noise times amplitude(vertex)."""
    offset = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    bm.normal_update()
    moves = []
    for v in bm.verts:
        amp = amplitude(v)
        if amp > 0.0:
            value = noise.fractal(v.co * frequency + offset, 0.9, 2.0, octaves, noise_basis='PERLIN_ORIGINAL')
            moves.append((v, v.normal * max(-1.2, min(1.2, value)) * amp))
    for v, delta in moves:
        v.co += delta


def drop_hull_leftovers(bm: bmesh.types.BMesh, hull: dict) -> None:
    """Delete the input points that did not end up on the convex hull."""
    leftovers = {g for g in hull['geom_interior'] + hull['geom_unused'] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(leftovers), context='VERTS')


def tag_share(v, tag, value) -> float:
    faces = v.link_faces
    return sum(1 for f in faces if f[tag] == value) / max(1, len(faces))


def append(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, matrix: Matrix) -> None:
    bmesh.ops.transform(src, matrix=matrix, verts=src.verts[:])
    mesh = bpy.data.meshes.new('_part')
    src.to_mesh(mesh)
    src.free()
    dst.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def block(dims: Vector, bevel: float, tag_value: int = DRESSED) -> bmesh.types.BMesh:
    bm = bmesh.new()
    tag = bm.faces.layers.int.new('part')
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=dims, verts=bm.verts[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect='EDGES',
                        profile=0.5, clamp_overlap=True)
    for face in bm.faces:
        face[tag] = tag_value
    return bm


def finish(builder: shapes.Builder, variation: float, project_uv: bool = True,
           sharp_angle: float = 40.0, fracture_angle: float = 28.0) -> bpy.types.Object:
    """Centre on the bound box, metre box-projected UVs, colour (1, variation, 0, 1),
    smooth shading split at edges sharper than `sharp_angle`."""
    bm = builder.bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    lo = Vector(tuple(min(v.co[k] for v in bm.verts) for k in range(3)))
    hi = Vector(tuple(max(v.co[k] for v in bm.verts) for k in range(3)))
    bmesh.ops.translate(bm, vec=-(lo + hi) * 0.5, verts=bm.verts[:])
    bm.normal_update()
    tag = bm.faces.layers.int.get('part')
    for face in bm.faces:
        face.smooth = True
        shade = 1.0 if tag is not None and face[tag] == MORTAR else variation
        axis = max(range(3), key=lambda k: abs(face.normal[k]))
        u, w = [k for k in range(3) if k != axis]
        for loop in face.loops:
            if project_uv:
                loop[builder.uv].uv = (loop.vert.co[u], loop.vert.co[w])
            loop[builder.color] = (1.0, shade, 0.0, 1.0)
    for edge in bm.edges:
        # Break faces shade as crisp facets, dressed faces and arrises stay soft.
        broken = tag is not None and all(f[tag] == FRACTURE for f in edge.link_faces)
        limit = math.radians(fracture_angle if broken else sharp_angle)
        edge.smooth = not edge.is_manifold or edge.calc_face_angle(0.0) < limit
    if tag is not None:
        bm.faces.layers.int.remove(tag)
    return builder.to_object()


def ashlar(name: str, size: float, rng, target: float) -> bpy.types.Object:
    """Dressed block broken by one large fracture and a few chipped corners."""
    dims = Vector((size, max(0.07, size * rng.uniform(0.42, 0.68)), max(0.06, size * rng.uniform(0.28, 0.45))))
    builder = shapes.Builder(name)
    bevel = min(dims) * rng.uniform(0.03, 0.07) if size >= 0.2 else 0.0
    append(builder.bm, block(dims, bevel), Matrix.Identity(4))
    bm = builder.bm
    tag = bm.faces.layers.int['part']
    for i in range(rng.randint(1, 3)):
        normal = unit(rng)
        reach = sum(abs(normal[k]) * dims[k] * 0.5 for k in range(3))
        depth = rng.uniform(-0.05, 0.4) if i == 0 else rng.uniform(0.45, 0.75)
        cut(bm, normal * reach * depth, normal, tag)
    refine(bm, target)
    displace(bm, rng, lambda v: 0.008 * size, 1.4 / size, 2)
    displace(bm, rng, lambda v: (0.003 + 0.05 * tag_share(v, tag, FRACTURE)) * size, 5.0 / size, 3)
    return finish(builder, rng.random())


def rough_rock(name: str, size: float, rng, target: float) -> bpy.types.Object:
    """Convex hull of points on a squashed ellipsoid: large broken facets, then roughened."""
    radii = Vector((0.5, 0.5 * rng.uniform(0.55, 0.9), 0.5 * rng.uniform(0.38, 0.7))) * size
    builder = shapes.Builder(name)
    bm = builder.bm
    tag = bm.faces.layers.int.new('part')
    for _ in range(rng.randint(12, 22)):
        d = unit(rng)
        bm.verts.new(Vector((d.x * radii.x, d.y * radii.y, d.z * radii.z)) * rng.uniform(0.8, 1.0))
    hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    drop_hull_leftovers(bm, hull)
    for face in bm.faces:
        face[tag] = FRACTURE
    refine(bm, target)
    displace(bm, rng, lambda v: 0.035 * size, 1.6 / size, 2)
    displace(bm, rng, lambda v: 0.03 * size, 5.0 / size, 3)
    return finish(builder, rng.random())


def brick(name: str, rng, target: float) -> bpy.types.Object:
    """Single brick, often a broken bat."""
    builder = shapes.Builder(name)
    dims = Vector((BRICK.x * rng.uniform(0.97, 1.02), BRICK.y * rng.uniform(0.97, 1.03), BRICK.z * rng.uniform(0.96, 1.04)))
    append(builder.bm, block(dims, 0.006), Matrix.Identity(4))
    bm = builder.bm
    tag = bm.faces.layers.int['part']
    if rng.random() < 0.65:
        normal = (Vector((1.0, 0.0, 0.0)) + unit(rng) * 0.45).normalized()
        cut(bm, Vector((rng.uniform(-0.06, 0.05), 0.0, 0.0)), normal, tag)
    refine(bm, target)
    displace(bm, rng, lambda v: 0.0015 + 0.007 * tag_share(v, tag, FRACTURE), 25.0, 3)
    return finish(builder, rng.random())


def brick_clump(name: str, rng, target: float) -> bpy.types.Object:
    """Two or three courses of bricks, one or two wide, still bonded by recessed
    mortar and broken through. Courses stay nearly aligned so the convex hull
    used by the physics hugs the visible shape."""
    builder = shapes.Builder(name)
    courses, columns, joint = rng.randint(2, 3), rng.choice((1, 2, 2)), 0.011
    width = columns * BRICK.x + (columns - 1) * joint
    for course in range(courses):
        z = course * (BRICK.z + joint)
        shift = rng.uniform(-0.02, 0.02)
        for column in range(columns):
            x = (column - (columns - 1) * 0.5) * (BRICK.x + joint) + shift
            dims = Vector((BRICK.x * rng.uniform(0.97, 1.01), BRICK.y * rng.uniform(0.97, 1.02), BRICK.z))
            place = Matrix.Translation((x, rng.uniform(-0.008, 0.008), z)) @ Matrix.Rotation(rng.uniform(-0.03, 0.03), 4, 'Z')
            append(builder.bm, block(dims, 0.0), place)
            if column:
                append(builder.bm, block(Vector((joint + 0.003, BRICK.y - 0.018, BRICK.z - 0.012)), 0.0, MORTAR),
                       Matrix.Translation((x - (BRICK.x + joint) * 0.5, 0.0, z)))
        if course < courses - 1:
            append(builder.bm, block(Vector((width - 0.024, BRICK.y - 0.018, joint + 0.003)), 0.0, MORTAR),
                   Matrix.Translation((shift, 0.0, z + (BRICK.z + joint) * 0.5)))
    bm = builder.bm
    tag = bm.faces.layers.int['part']
    height = courses * BRICK.z + (courses - 1) * joint
    centre = Vector((0.0, 0.0, (height - BRICK.z) * 0.5))
    for i in range(rng.randint(1, 2)):
        normal = (unit(rng) + Vector((rng.choice((-1, 1)), 0.0, 0.0))).normalized()
        reach = abs(normal.x) * width * 0.5 + abs(normal.y) * BRICK.y * 0.5 + abs(normal.z) * height * 0.5
        cut(bm, centre + normal * reach * rng.uniform(0.25, 0.6), normal, tag)
    refine(bm, target)
    displace(bm, rng, lambda v: 0.0015 + 0.007 * tag_share(v, tag, FRACTURE), 25.0, 3)
    return finish(builder, rng.random())


def jag(bm: bmesh.types.BMesh, start: Vector, axis: Vector, length: float, rng, depth: float) -> None:
    """Splinter the end of a prism that runs from `start` along `axis` for `length`."""
    def ring():
        return [v for v in bm.verts if (v.co - start).dot(axis) > length - 1e-4]
    end = set(ring())
    edges = [e for e in bm.edges if e.verts[0] in end and e.verts[1] in end and e.calc_length() > 0.03]
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=3, use_grid_fill=False)
    end = ring()
    members = set(end)
    cap = [f for f in bm.faces if all(v in members for v in f.verts)]
    centres = bmesh.ops.poke(bm, faces=cap)['verts']
    phase = rng.uniform(0, math.tau)
    for i, v in enumerate(end):
        wave = 0.5 + 0.5 * math.sin(phase + i * rng.uniform(1.3, 2.6))
        v.co -= axis * depth * min(1.0, 0.25 * rng.random() + 0.85 * wave)
    for v in rng.sample(end, k=min(2, len(end))):
        v.co += axis * rng.uniform(0.015, 0.06)
    for v in centres:
        v.co -= axis * depth * rng.uniform(-0.2, 0.7)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method='BEAUTY', ngon_method='BEAUTY')


def broken_board(name: str, rng, beam: bool = False) -> tuple:
    """Plank or beam snapped short: one splintered end, sometimes both."""
    builder = shapes.Builder(name)
    if beam:
        length, width, depth = rng.uniform(0.9, 1.6), rng.uniform(0.15, 0.2), rng.uniform(0.15, 0.2)
    else:
        length, width, depth = rng.uniform(0.45, 1.35), rng.uniform(0.17, 0.26), rng.uniform(0.045, 0.06)
    a, b = Vector((-length * 0.5, 0.0, 0.0)), Vector((length * 0.5, 0.0, 0.0))
    if beam:
        shapes.timber(builder, a, b, width, depth, UP, rng)
        segment = length / math.ceil(length / 0.25)
    else:
        shapes.plank(builder, a, b, width, depth, UP, rng)
        segment = length / math.ceil(length / min(0.25, length / 4))
    axis = Vector((1.0, 0.0, 0.0))
    reach = min(0.8 * segment, 0.05 + 0.5 * width)
    jag(builder.bm, a, axis, length, rng, reach)
    if rng.random() < 0.4:
        jag(builder.bm, b, -axis, length, rng, reach)
    return finish(builder, rng.random(), project_uv=False, sharp_angle=50.0), length


# ---------------------------------------------------------------- recipes

def size_class(rng, cls: str) -> float:
    return {'big': min(rng.uniform(0.4, 0.68), rng.uniform(0.4, 0.78)), 'medium': rng.uniform(0.22, 0.4), 'small': rng.uniform(0.1, 0.22)}[cls]


def make_stone(index: int, cls: str, kinds: dict, seed: int, recipe: str, scale: float) -> Piece:
    rng = core.rng(seed, recipe, 'piece', index)
    kind = rng.choices(list(kinds), weights=list(kinds.values()))[0]
    if kind in ('brick', 'clump') and cls == 'big':
        kind = 'ashlar'
    size = size_class(rng, cls)
    target = min(0.13, max(0.06, 0.2 * size)) * scale
    name = f'{kind.capitalize()}{index:02d}'
    if kind == 'ashlar':
        obj = ashlar(name, size, rng, target)
    elif kind == 'rock':
        obj = rough_rock(name, size, rng, target)
    elif kind == 'brick':
        obj = brick(name, rng, max(0.11, target))
    else:
        obj = brick_clump(name, rng, max(0.12, target))
    return Piece(obj, kind, 'stone', extent(obj))


def extent(obj: bpy.types.Object) -> float:
    """Longest bound-box side of the mesh in metres."""
    co = [v.co for v in obj.data.vertices]
    return max(max(c[k] for c in co) - min(c[k] for c in co) for k in range(3))


def stones(rng, seed: int, recipe: str, counts: dict, kinds: dict, scale: float) -> list:
    pieces, index = [], 0
    for cls in ('big', 'medium', 'small'):
        for _ in range(counts.get(cls, 0)):
            pieces.append(make_stone(index, cls, kinds, seed, recipe, scale))
            index += 1
    return pieces


def box(lo, hi, name: str) -> bpy.types.Object:
    """Axis-aligned proxy box. The object origin is the box centre: Bullet centres
    BOX shapes on the origin, not on the mesh."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    lo, hi = Vector(lo), Vector(hi)
    bmesh.ops.scale(bm, vec=hi - lo, verts=bm.verts[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj.location = (lo + hi) * 0.5
    return obj


def recipe_spec(recipe: str, seed: int, scale: float) -> dict:
    """Pieces, proxies and drop pattern. Blender axes: z up; walls stand on y >= 0
    (Godot -Z after export) and, for the corner, x <= 0."""
    rng = core.rng(seed, recipe, 'layout')
    spec = {'walls': []}
    if recipe == 'wall_spill':
        spec['walls'] = [((-3.5, 0.0, 0.0), (3.5, 0.5, 3.5))]
        spec['pieces'] = stones(rng, seed, recipe, {'big': rng.randint(12, 14), 'medium': rng.randint(10, 12), 'small': rng.randint(12, 16)},
                                {'ashlar': 0.45, 'rock': 0.2, 'brick': 0.22, 'clump': 0.13}, scale)
        spec['place'] = lambda r, p: (rng.uniform(-1.25, 1.25), -(r + 0.006 + rng.uniform(0.0, 1.2)))
        # Wedge against the wall: highest at the wall, falling off forwards and sideways.
        spec['profile'] = lambda x, y: 0.95 * max(0.0, 1.0 + y / 1.35) * max(0.0, 1.0 - (x / 1.3) ** 2)
        spec['keep'] = ((0.0, -0.6), 2.3)
    elif recipe == 'corner_heap':
        spec['walls'] = [((-0.5, 0.0, 0.0), (3.5, 0.5, 3.5)), ((-0.5, -3.5, 0.0), (0.0, 0.5, 3.5))]
        spec['pieces'] = stones(rng, seed, recipe, {'big': rng.randint(10, 12), 'medium': rng.randint(9, 11), 'small': rng.randint(12, 14)},
                                {'ashlar': 0.4, 'rock': 0.35, 'brick': 0.15, 'clump': 0.1}, scale)
        spec['place'] = lambda r, p: (r + 0.006 + rng.uniform(0.0, 1.3), -(r + 0.006 + rng.uniform(0.0, 1.3)))
        # Quarter cone in the corner.
        spec['profile'] = lambda x, y: 1.05 * max(0.0, 1.0 - math.hypot(x, y) / 1.45)
        spec['keep'] = ((0.6, -0.6), 2.3)
    elif recipe == 'bridge_debris':
        boards = []
        for i in range(rng.randint(1, 2)):
            obj, length = broken_board(f'Beam{i:02d}', core.rng(seed, recipe, 'beam', i), beam=True)
            boards.append(Piece(obj, 'beam', 'wood', length))
        for i in range(rng.randint(7, 10)):
            obj, length = broken_board(f'Plank{i:02d}', core.rng(seed, recipe, 'plank', i))
            boards.append(Piece(obj, 'plank', 'wood', length))
        rocks = stones(rng, seed, recipe, {'big': rng.randint(2, 3), 'medium': rng.randint(7, 9), 'small': rng.randint(9, 12)},
                       {'ashlar': 0.5, 'rock': 0.4, 'brick': 0.1}, scale)
        late = boards[-3:]
        spec['pieces'] = boards[:-3] + rocks[:len(rocks) // 2] + late + rocks[len(rocks) // 2:]
        spec['place'] = lambda r, p: (rng.uniform(-1.3, 1.3), rng.uniform(-0.8, 0.8))
        # Low elongated mound along the fallen span (x).
        spec['profile'] = lambda x, y: 0.55 * max(0.0, 1.0 - math.hypot(x / 1.5, y / 0.95))
        spec['keep'] = ((0.0, 0.0), 2.6)
    elif recipe == 'floor_scatter':
        clusters = [Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8))) for _ in range(3)]
        spec['pieces'] = stones(rng, seed, recipe, {'big': rng.randint(0, 1), 'medium': rng.randint(7, 9), 'small': rng.randint(24, 30)},
                                {'ashlar': 0.35, 'rock': 0.4, 'brick': 0.2, 'clump': 0.05}, scale)

        def place(r, p):
            if rng.random() < 0.75:
                c = rng.choice(clusters)
                return c.x + rng.gauss(0, 0.25), c.y + rng.gauss(0, 0.25)
            return rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2)
        spec['place'] = place
        spec['keep'] = ((0.0, 0.0), 2.4)
    else:
        raise SystemExit(f'unknown recipe {recipe}')
    if recipe != 'bridge_debris':
        # Larger pieces mostly arrive first so smaller ones settle into and over them.
        order = core.rng(seed, recipe, 'order')
        spec['pieces'].sort(key=lambda p: order.random() * 0.6 - p.size)
    spec['rng'] = rng
    return spec


def spawn(spec: dict) -> None:
    """Deposit pieces one at a time onto what is already there. Each piece, in
    its random orientation, is tried at several sampled (x, y); at each it is
    lowered until a vertex rests on the floor or on the meshes below (downward
    ray casts). The spot whose resting bottom lies furthest below the recipe's
    target heap profile wins, so the packing grows into a heap instead of a
    tower. It is lifted 1-3 cm and physics then settles it into real contacts."""
    rng = spec['rng']
    profile = spec.get('profile')
    verts, polys, tree = [], [], None
    down = Vector((0.0, 0.0, -1.0))
    for piece in spec['pieces']:
        if piece.material == 'wood':
            rotation = Euler((rng.gauss(0, 0.3), rng.gauss(0, 0.2), rng.gauss(0, 0.45)), 'XYZ')
        elif piece.kind != 'rock' and rng.random() < 0.7:
            # Blocks mostly come down bedded, broad face down, and stack like a jumbled wall.
            rotation = Euler((rng.gauss(0, 0.25) + rng.choice((0.0, math.pi)), rng.gauss(0, 0.25), rng.uniform(0, math.tau)), 'XYZ')
        else:
            rotation = Euler((rng.uniform(0, math.tau), rng.uniform(0, math.tau), rng.uniform(0, math.tau)), 'XYZ')
        turn = rotation.to_matrix()
        local = [turn @ v.co for v in piece.obj.data.vertices]
        faces = [tuple(p.vertices) for p in piece.obj.data.polygons]
        reach = max(o.xy.length for o in local)
        low = min(o.z for o in local)
        best = None
        for _ in range(12 if profile else 1):
            x, y = spec['place'](reach, piece)
            z = -low
            if tree is not None:
                for o in local:
                    hit = tree.ray_cast(Vector((x + o.x, y + o.y, 50.0)), down)
                    if hit[0] is not None:
                        z = max(z, hit[0].z - o.z)
            room = profile(x, y) - (z + low) if profile else 0.0
            if best is None or room > best[0]:
                best = (room, x, y, z)
        _, x, y, z = best
        z += rng.uniform(0.01, 0.03)
        while True:
            moved = [Vector((x, y, z)) + o for o in local]
            mine = BVHTree.FromPolygons(moved, faces)
            if tree is None or not tree.overlap(mine):
                break
            z += 0.01
        piece.obj.location = (x, y, z)
        piece.obj.rotation_euler = rotation
        base = len(verts)
        verts += moved
        polys += [tuple(base + i for i in f) for f in faces]
        tree = BVHTree.FromPolygons(verts, polys)


# ---------------------------------------------------------------- pile

def tris(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def merge(objects, name: str) -> bpy.types.Object:
    bm = bmesh.new()
    for obj in objects:
        bm.from_mesh(obj.data)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color = mesh.color_attributes['Color']
    return core.link(bpy.data.objects.new(name, mesh))


def hull_of(obj: bpy.types.Object, name: str) -> bpy.types.Mesh:
    """Convex hull mesh of a piece (link it only after the AO bake: Cycles would
    treat it as an occluder wrapped tightly around the stone)."""
    bm = bmesh.new()
    for v in obj.data.vertices:
        bm.verts.new(v.co)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    drop_hull_leftovers(bm, hull)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def grey_ao(obj: bpy.types.Object, low: float, high: float) -> None:
    """Color.rgb = softened AO * per-piece tone. The dungeon shader multiplies
    albedo by COLOR.rgb, so the channels must stay neutral grey; the albedo
    multiply darkens direct light too, hence AO_STRENGTH < 1."""
    color = obj.data.color_attributes['Color']
    values = [0.0] * (len(color.data) * 4)
    color.data.foreach_get('color', values)
    for i in range(0, len(values), 4):
        v = (1.0 - AO_STRENGTH * (1.0 - values[i])) * (low + (high - low) * values[i + 1])
        values[i:i + 4] = (v, v, v, 1.0)
    color.data.foreach_set('color', values)


def decimated(obj: bpy.types.Object, ratio: float, name: str) -> bpy.types.Object:
    copy = core.link(bpy.data.objects.new(name, obj.data.copy()))
    modifier = copy.modifiers.new('Decimate', 'DECIMATE')
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(copy.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
    mesh.validate(clean_customdata=False)
    copy.modifiers.clear()
    old = copy.data
    copy.data = mesh
    mesh.name = name
    bpy.data.meshes.remove(old)
    return copy


def build_pieces(recipe: str, seed: int) -> dict:
    """Generate pieces under the triangle budget (coarser tessellation if needed)."""
    scale = 1.0
    for attempt in range(6):
        core.empty_scene()
        spec = recipe_spec(recipe, seed, scale)
        total = sum(tris(p.obj) for p in spec['pieces'])
        if total <= TRI_BUDGET * 0.96:
            spec['tessellation_scale'] = round(scale, 3)
            return spec
        scale *= 1.15
    raise SystemExit(f'{recipe} seed {seed}: {total} tris after coarsening')


def build_pile(recipe: str, seed: int, out: Path, review: Path, sheet: list) -> dict:
    started = time.time()
    pile_id = f'rubble_{recipe}_s{seed}'
    spec = build_pieces(recipe, seed)
    pieces = spec['pieces']
    walls = [box(lo, hi, f'WallProxy{i}') for i, (lo, hi) in enumerate(spec['walls'])]
    floor = box((-8.0, -8.0, -0.5), (8.0, 8.0, 0.0), 'FloorProxy')
    proxies = [floor] + walls
    spawn(spec)

    rigid.world(fps=30, substeps=20, iterations=40, frame_end=1800)
    for piece in pieces:
        stone = piece.material == 'stone'
        rigid.body(piece.obj, mass=rigid.mass(piece.obj, STONE_DENSITY if stone else WOOD_DENSITY),
                   friction=0.9 if stone else 0.75, damping=(0.1, 0.4))
    for proxy in proxies:
        rigid.body(proxy, passive=True, shape='BOX', friction=0.9)
    settle = rigid.settle([p.obj for p in pieces], threshold=0.01, hold=15, max_frames=1800)
    rigid.apply([p.obj for p in pieces])
    if not settle['settled']:
        raise SystemExit(f'{pile_id}: not settled after {settle["frame"]} frames ({settle["residual_speed_m_s"]:.4f} m/s)')

    # Pieces that rolled away from the pile are not part of it.
    centre, keep = Vector(spec['keep'][0]), spec['keep'][1]
    escaped = []
    for piece in list(pieces):
        c = sum((v.co for v in piece.obj.data.vertices), Vector()) / len(piece.obj.data.vertices)
        if (c.xy - centre).length > keep or c.z < -0.05:
            escaped.append(piece.obj.name)
            bpy.data.objects.remove(piece.obj)
            pieces.remove(piece)
    # Anything left without a support within MAX_GAP (only possible after a removal
    # or on a hull face over a concavity) is removed too, then everything is re-measured.
    floating_removed = []
    for _ in range(4):
        gaps = rigid.contact_gaps([p.obj for p in pieces], proxies)
        floating = [p for p in pieces if gaps[p.obj.name] > MAX_GAP]
        if not floating:
            break
        for piece in floating:
            floating_removed.append([piece.obj.name, round(gaps[piece.obj.name], 4)])
            bpy.data.objects.remove(piece.obj)
            pieces.remove(piece)
    gaps = rigid.contact_gaps([p.obj for p in pieces], proxies)
    penetration = rigid.penetration([p.obj for p in pieces], proxies)
    max_gap = max(gaps.values())
    assert max_gap <= MAX_GAP, (pile_id, 'floating', max_gap)
    assert penetration['max_m'] <= MAX_PENETRATION, (pile_id, 'interpenetration', penetration)

    # Origin at the ground centre of the footprint.
    points = [v.co for p in pieces for v in p.obj.data.vertices]
    lo = Vector(tuple(min(v[k] for v in points) for k in range(3)))
    hi = Vector(tuple(max(v[k] for v in points) for k in range(3)))
    shift = Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, 0.0))
    for obj in [p.obj for p in pieces] + proxies:
        obj.data.transform(shift)
        obj.data.update()
    # Wall faces: the back wall is the plane y = 0 facing -y, the corner's side
    # wall the plane x = 0 facing +x (Blender, before the shift).
    walls_godot = []
    for index, normal in zip(range(len(spec['walls'])), (Vector((0.0, -1.0, 0.0)), Vector((1.0, 0.0, 0.0)))):
        moved = shift @ Vector((0.0, 0.0, 0.0))
        face = Vector((0.0, moved.y, 0.0)) if index == 0 else Vector((moved.x, 0.0, 0.0))
        walls_godot.append({'normal': [round(c, 6) + 0.0 for c in core.to_godot(normal)],
                            'point': [round(c, 4) + 0.0 for c in core.to_godot(face)]})

    hulls = [hull_of(p.obj, f'{p.obj.name}-convcolonly') for p in pieces if p.size >= COLLISION_MIN_SIZE]
    groups = {}
    for piece in pieces:
        groups.setdefault(piece.material, []).append(piece)
    meshes = []
    for material, members in sorted(groups.items(), reverse=True):
        meshes.append(merge([p.obj for p in members], material.capitalize()))
        for p in members:
            bpy.data.objects.remove(p.obj)
    ao = bake.ao_to_color(meshes, samples=64, distance=AO_DISTANCE)
    for obj in meshes:
        grey_ao(obj, 0.84, 1.0) if obj.name == 'Stone' else grey_ao(obj, 0.8, 1.0)
    hulls = [core.link(bpy.data.objects.new(mesh.name, mesh)) for mesh in hulls]
    for hull in hulls:
        hull.hide_render = True

    out.mkdir(parents=True, exist_ok=True)
    (out / 'lod').mkdir(exist_ok=True)
    lods, files = [], []
    for level, ratio in enumerate(LOD_RATIOS):
        if level == 0:
            objs = meshes
            path = export.glb(meshes + hulls, out / f'{pile_id}.glb')
        else:
            objs = [decimated(m, ratio, f'{m.name}_LOD{level}') for m in meshes]
            path = export.glb(objs, out / 'lod' / f'{pile_id}_lod{level}.glb')
        lods.append({'level': level, 'tris': sum(tris(o) for o in objs), 'path': core.relative(path)})
        files.append(path)
        if level:
            for o in objs:
                bpy.data.objects.remove(o)
    assert lods[0]['tris'] <= TRI_BUDGET, (pile_id, lods[0])

    if review is not None:
        sheet.append((recipe, seed, render_turntable(pile_id, recipe, meshes, proxies, hi - lo, review)))

    kinds = {}
    for material, members in groups.items():
        for p in members:
            kinds[p.kind] = kinds.get(p.kind, 0) + 1
    size = hi - lo
    return {
        'id': pile_id, 'recipe': recipe, 'seed': seed,
        'glb': core.relative(out / f'{pile_id}.glb'),
        'lods': lods,
        'pieces': kinds, 'piece_count': sum(kinds.values()),
        'removed': {'escaped': escaped, 'floating': floating_removed},
        'tessellation_scale': spec['tessellation_scale'],
        'frames': settle['frame'], 'settle_seconds': settle['seconds'],
        'residual_speed_m_s': round(settle['residual_speed_m_s'], 5),
        'peak_speed_m_s': round(max(settle['max_speed_per_frame']), 3),
        'max_contact_gap_m': round(max_gap, 4),
        'max_interpenetration_m': round(penetration['max_m'], 4),
        'deepest_pair': penetration['pair'], 'touching_pairs': penetration['pairs_touching'],
        'collision': {'convex_hulls': len(hulls), 'hull_vertices': sum(len(h.data.vertices) for h in hulls),
                      'min_piece_size_m': COLLISION_MIN_SIZE},
        'footprint_m': [round(size.x, 3), round(size.y, 3)],
        'height_m': round(hi.z, 3),
        'bounds_godot': {'min': [round(c, 3) + 0.0 for c in core.to_godot(Vector((-size.x / 2, size.y / 2, 0.0)))],
                         'max': [round(c, 3) + 0.0 for c in core.to_godot(Vector((size.x / 2, -size.y / 2, hi.z)))]},
        'walls_godot': walls_godot,
        'ao': ao,
        'build_seconds': round(time.time() - started, 1),
        '_files': files,
    }


# ---------------------------------------------------------------- review renders

VIEWS = {'wall_spill': (-55, -20, 20, 55), 'corner_heap': (10, 33, 57, 80),
         'bridge_debris': (30, 120, 210, 300), 'floor_scatter': (30, 120, 210, 300)}
SUN = {'wall_spill': -35.0, 'corner_heap': 20.0}
VIEW_SIZE = (480, 360)


def write_png(path: Path, rgb) -> None:
    """8-bit RGB PNG from a top-down HxWx3 uint8 array (stdlib + numpy only)."""
    height, width, _ = rgb.shape
    raw = b''.join(b'\x00' + rgb[y].tobytes() for y in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def preview_material(name: str, rgb, attribute: bool) -> bpy.types.Material:
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None) or nodes.new('ShaderNodeBsdfPrincipled')
    output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None) or nodes.new('ShaderNodeOutputMaterial')
    links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Roughness'].default_value = 0.88
    if attribute:
        source = nodes.new('ShaderNodeAttribute')
        source.attribute_name = 'Color'
        tint = nodes.new('ShaderNodeVectorMath')
        tint.operation = 'MULTIPLY'
        tint.inputs[1].default_value = rgb
        links.new(source.outputs['Color'], tint.inputs[0])
        links.new(tint.outputs['Vector'], shader.inputs['Base Color'])
    else:
        shader.inputs['Base Color'].default_value = (*rgb, 1.0)
    return material


def render_turntable(pile_id: str, recipe: str, meshes, proxies, size: Vector, review: Path):
    """Four Cycles views around the pile in one strip; returns the first view."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = VIEW_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    looks = {'Stone': ((0.46, 0.43, 0.39), True), 'Wood': ((0.34, 0.24, 0.15), True)}
    for obj in meshes:
        rgb, attribute = looks[obj.name]
        obj.data.materials.clear()
        obj.data.materials.append(preview_material(f'Preview{obj.name}', rgb, attribute))
    for proxy in proxies:
        proxy.data.materials.clear()
        proxy.data.materials.append(preview_material('PreviewFloor' if proxy.name == 'FloorProxy' else 'PreviewWall',
                                                     (0.1, 0.095, 0.09) if proxy.name == 'FloorProxy' else (0.16, 0.15, 0.14), False))
    background = next((n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND'), None)
    if background is not None:
        background.inputs['Color'].default_value = (0.06, 0.06, 0.065, 1.0)
        background.inputs['Strength'].default_value = 1.0
    camera = bpy.data.objects.get('PreviewCamera') or core.link(bpy.data.objects.new('PreviewCamera', bpy.data.cameras.new('PreviewCamera')))
    camera.data.lens = 35.0
    scene.camera = camera
    sun = bpy.data.objects.get('PreviewKey') or core.link(bpy.data.objects.new('PreviewKey', bpy.data.lights.new('PreviewKey', 'SUN')))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(4.0)
    target = Vector((0.0, 0.0, size.z * 0.35))
    radius = 0.5 * math.sqrt(size.x ** 2 + size.y ** 2 + size.z ** 2)
    distance = radius * 0.85 / math.sin(math.atan(13.5 / 35.0))
    views = []
    with tempfile.TemporaryDirectory() as folder:
        for i, azimuth in enumerate(VIEWS[recipe]):
            a, e = math.radians(azimuth), math.radians(30.0)
            direction = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
            camera.location = target + direction * distance
            camera.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
            # Walls hide a sun behind them: wall recipes keep a fixed front key light.
            s = math.radians(SUN.get(recipe, azimuth - 55.0))
            se = math.radians(48.0)
            toward_sun = Vector((math.sin(s) * math.cos(se), -math.cos(s) * math.cos(se), math.sin(se)))
            sun.rotation_euler = (-toward_sun).to_track_quat('-Z', 'Y').to_euler()
            path = Path(folder) / f'view{i}.png'
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            image = bpy.data.images.load(str(path))
            pixels = numpy.empty(VIEW_SIZE[0] * VIEW_SIZE[1] * 4, dtype=numpy.float32)
            image.pixels.foreach_get(pixels)
            bpy.data.images.remove(image)
            rgb = pixels.reshape(VIEW_SIZE[1], VIEW_SIZE[0], 4)[::-1, :, :3]
            views.append(numpy.clip(rgb * 255.0 + 0.5, 0, 255).astype(numpy.uint8))
    write_png(review / f'{pile_id}_turntable.png', numpy.concatenate(views, axis=1))
    return views[0]


# ---------------------------------------------------------------- main

def main() -> None:
    parser = argparse.ArgumentParser(prog='build_rubble.py')
    parser.add_argument('out', help='output folder for GLBs and rubble.json')
    parser.add_argument('--seed', type=int, help='build this seed only')
    parser.add_argument('--seeds', default='1,2,3')
    parser.add_argument('--recipes', default=','.join(RECIPES))
    parser.add_argument('--review', help='folder for Blender turntable renders and the contact sheet')
    options = parser.parse_args(core.args())
    seeds = [options.seed] if options.seed is not None else [int(s) for s in options.seeds.split(',')]
    recipes = options.recipes.split(',')
    out = Path(options.out).resolve()
    review = Path(options.review).resolve() if options.review else None
    started = time.time()
    piles, files, sheet = [], [], []
    for recipe in recipes:
        for seed in seeds:
            pile = build_pile(recipe, seed, out, review, sheet)
            files += pile.pop('_files')
            piles.append(pile)
            print('RUBBLE_PILE', pile['id'], 'pieces', pile['piece_count'], 'frames', pile['frames'],
                  'residual', pile['residual_speed_m_s'], 'gap', pile['max_contact_gap_m'],
                  'penetration', pile['max_interpenetration_m'], 'tris', [l['tris'] for l in pile['lods']],
                  'footprint', pile['footprint_m'], f"{pile['build_seconds']}s", flush=True)
    if review is not None and sheet:
        rows = []
        for seed in seeds:
            row = [image for recipe in recipes for r, s, image in sheet if r == recipe and s == seed]
            rows.append(numpy.concatenate(row, axis=1))
        write_png(review / 'contact_sheet.png', numpy.concatenate(rows, axis=0))
    data = {
        'generator': 'scripts/art/build_rubble.py',
        'command': 'blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_rubble.py -- '
                   + ' '.join(core.args()),
        'physics': {'engine': 'Blender rigid body (Bullet)', 'fps': 30, 'substeps_per_frame': 20,
                    'solver_iterations': 40, 'collision_shape': 'CONVEX_HULL', 'margin_m': 0.002,
                    'settle_rule': 'max bound-box corner speed < 0.01 m/s for 15 consecutive frames',
                    'friction': {'stone': 0.9, 'wood': 0.75}, 'density_kg_m3': {'stone': STONE_DENSITY, 'wood': WOOD_DENSITY}},
        'limits': {'lod0_tris': TRI_BUDGET, 'max_contact_gap_m': MAX_GAP, 'max_interpenetration_m': MAX_PENETRATION},
        'color': f'Color.rgb = (1 - {AO_STRENGTH} x (1 - AO baked over {AO_DISTANCE} m)) x per-piece tone (stone 0.84-1.0, wood 0.8-1.0), grey; alpha 1',
        'axes': 'GLB is Godot Y-up metres; origin at the ground centre of the footprint',
        'piles': piles,
        'seconds': round(time.time() - started, 1),
    }
    report = core.write_report(out / 'rubble.json', data, files)
    print('RUBBLE_OK', len(piles), 'piles', f"{report['seconds']}s", flush=True)


if __name__ == '__main__':
    main()
