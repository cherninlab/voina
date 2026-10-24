"""Unique stones: each block is cut, split, dressed and weathered on its own,
the way stone comes from a quarry and a mason's hands, never a scaled copy.

    stone = stones.make('ashlar', rng, size=(0.48, 0.30, 0.24), name='S1')
    wedge = stones.make('wedge', rng, size=(0.12, 0.10, 0.05))
    voussoir = stones.voussoir(rng, inner=1.2, depth=0.3, angle=0.16, thickness=0.32)

Kinds (local x = length along the wall, y = bed depth into it, z = height):
    ashlar    dressed block: faces 1-2 deg out of square, rock-faced front with
              pitched bumps, chipped arrises, corners worn round
    rubble    split stone: a block broken by several random splitting planes,
              flat-ish fresh facets, weathered edges
    field     rounded cobble or boulder, wind and water worn
    wedge     trapezoid pinning stone, thin end first, driven into joints
    voussoir  arch stone between two radial planes; `keystone=True` makes it
              larger and slightly proud

Construction: a convex core from jittered half-spaces (planes), chip cuts,
then a dense remesh, displacement (pitching, pock marks) and smoothing that
rounds corners more than faces, decimated to a triangle budget. The convex
core stays convex enough for hull collision. Colour attribute: R = 1 (AO
later), G = per-stone tone, B = fresh break or chip (1) vs weathered face (0).
Blender space, centred at the origin.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import core

LOOKS = {
    # out-of-square (deg), face offset (m), chips (count range, depth m), splits, displacement (share of size):
    # lumps (broad), pitch (rock-faced dressing), grain (fine), pock (pits, m), wear (smoothing passes before detail)
    'ashlar': {'square': 2.0, 'offset': 0.008, 'chips': (4, 10, 0.012, 0.045), 'splits': (0, 0),
               'lumps': 0.018, 'pitch': 0.014, 'grain': 0.003, 'pock': 0.003, 'wear': 4},
    'rubble': {'square': 12.0, 'offset': 0.05, 'chips': (5, 12, 0.02, 0.08), 'splits': (3, 6),
               'lumps': 0.03, 'pitch': 0.018, 'grain': 0.004, 'pock': 0.004, 'wear': 5},
    # Walling stone: an irregular broken outline but a front face (local y) kept
    # within a couple of degrees of the wall, as a waller sets it.
    # Squared and fitted by the mason: near-rectangular beds and joints so
    # courses close tight, rock-faced and worn round at the arrises.
    'squared_rubble': {'square': 4.0, 'face': 1.5, 'offset': 0.015, 'chips': (3, 8, 0.01, 0.035), 'splits': (0, 2),
                       'lumps': 0.028, 'pitch': 0.018, 'grain': 0.004, 'pock': 0.004, 'wear': 9},
    'field': {'square': 16.0, 'offset': 0.06, 'chips': (3, 8, 0.03, 0.09), 'splits': (1, 3),
              'lumps': 0.05, 'pitch': 0.01, 'grain': 0.003, 'pock': 0.003, 'wear': 22},
    'wedge': {'square': 5.0, 'offset': 0.004, 'chips': (2, 5, 0.006, 0.02), 'splits': (0, 1),
              'lumps': 0.02, 'pitch': 0.012, 'grain': 0.003, 'pock': 0.0015, 'wear': 3},
    'voussoir': {'square': 1.2, 'offset': 0.005, 'chips': (4, 9, 0.012, 0.04), 'splits': (0, 0),
                 'lumps': 0.022, 'pitch': 0.018, 'grain': 0.004, 'pock': 0.004, 'wear': 7},
}


def _cut(bm, point: Vector, normal: Vector, fresh, colors) -> None:
    """Keep the half-space behind `normal`, cap the cut, mark the cap fresh."""
    result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=point,
                                    plane_no=normal, clear_outer=True)
    edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        filled = bmesh.ops.edgeloop_fill(bm, edges=edges)
        for face in filled['faces']:
            face[fresh] = 1


def _tilt(normal: Vector, rng, degrees: float) -> Vector:
    axis = normal.orthogonal().normalized()
    axis.rotate(Matrix.Rotation(rng.uniform(0, math.tau), 3, normal))
    return (Matrix.Rotation(math.radians(rng.uniform(-degrees, degrees)), 3, axis) @ normal).normalized()


def core_block(rng, size, look: dict, taper: float = 0.0, planes=()) -> bmesh.types.BMesh:
    """Convex core: a box cut by six jittered faces, optional taper (wedge),
    extra `planes` [(point, normal)] and chips on edges and corners."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size) * 1.6, verts=bm.verts)
    fresh = bm.faces.layers.int.new('fresh')
    half = Vector(size) * 0.5
    for axis in range(3):
        for sign in (-1.0, 1.0):
            normal = Vector([sign if k == axis else 0.0 for k in range(3)])
            if taper and axis == 2:
                # Wedge: top and bottom faces close towards +x (the thin, driven end).
                normal = Vector((sign * 0.0 + taper, 0.0, sign)).normalized() if sign > 0 else Vector((taper, 0.0, -1.0)).normalized()
            normal = _tilt(normal, rng, look.get('face', look['square']) if axis == 1 else look['square'])
            point = Vector([half[k] * (sign if k == axis else 0.0) for k in range(3)])
            if taper and axis == 2:
                # The nominal height is the thick (struck) end at -x.
                point.x = -half.x
            point += normal * rng.uniform(-look['offset'], look['offset'] * 0.3)
            _cut(bm, point, normal, fresh, None)
    for face in bm.faces:
        face[fresh] = 0
    for point, normal in planes:
        _cut(bm, point, normal, fresh, None)
    low, high, depth_low, depth_high = look['chips']
    verts = [v.co.copy() for v in bm.verts]
    for _ in range(rng.randint(low, high)):
        corner = verts[rng.randrange(len(verts))]
        outward = corner.normalized()
        normal = _tilt(outward, rng, 25.0)
        depth = rng.uniform(depth_low, depth_high)
        _cut(bm, corner - normal * depth, normal, fresh, None)
        verts = [v.co.copy() for v in bm.verts]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def detail(bm, rng, look: dict, name: str, triangles: int = 1200, voxel: float = None) -> bpy.types.Object:
    """Remesh, pitch, pock, wear and decimate a core into a game stone."""
    size = max((max(v.co[k] for v in bm.verts) - min(v.co[k] for v in bm.verts)) for k in range(3))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    fresh_faces = [p.index for p in mesh.polygons if mesh.attributes['fresh'].data[p.index].value]
    bm.free()
    obj = core.link(bpy.data.objects.new(name, mesh))
    # Remember which side of the core each fresh cap is on, to mark the dense mesh.
    caps = [(mesh.polygons[i].center.copy(), mesh.polygons[i].normal.copy()) for i in fresh_faces]
    remesh = obj.modifiers.new('Remesh', 'REMESH')
    remesh.mode = 'VOXEL'
    remesh.voxel_size = voxel or max(0.005, size / 55.0)
    # Weathering first rounds the arrises; the displacement after it breaks the
    # rounded edges up again, so wear is uneven like real stone.
    wear = obj.modifiers.new('Wear', 'SMOOTH')
    wear.factor = 0.7
    wear.iterations = look['wear']
    layers = []
    for label, kind, scale, strength, mid in (('lumps', 'CLOUDS', 0.35, look['lumps'] * size, 0.5),
                                               ('pitch', 'DISTORTED_NOISE', 0.09, look['pitch'] * size, 0.5),
                                               ('grain', 'CLOUDS', 0.025, look['grain'] * size, 0.5),
                                               ('pock', 'VORONOI', 0.05, -look['pock'], 1.0)):
        texture = bpy.data.textures.new(f'{name}_{label}', kind)
        texture.noise_scale = max(0.004, size * scale * rng.uniform(0.8, 1.25))
        if kind == 'CLOUDS':
            texture.noise_depth = 4
        if kind == 'DISTORTED_NOISE':
            texture.distortion = rng.uniform(0.6, 1.4)
        modifier = obj.modifiers.new(label, 'DISPLACE')
        modifier.texture = texture
        modifier.strength = strength
        modifier.mid_level = mid
        # Random texture placement per stone, so no two share a pattern.
        empty = core.link(bpy.data.objects.new(f'{name}_{label}', None))
        empty.location = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
        empty.rotation_euler = (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3))
        modifier.texture_coords = 'OBJECT'
        modifier.texture_coords_object = empty
        layers.append(texture)
    decimate = obj.modifiers.new('Budget', 'DECIMATE')
    depsgraph = bpy.context.evaluated_depsgraph_get()
    dense = len(obj.evaluated_get(depsgraph).data.polygons)
    decimate.ratio = min(1.0, triangles / max(dense * 2, 1))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    for child in [o for o in bpy.data.objects if o.name.startswith(name + '_')]:
        core.discard(child)
    for texture in layers:
        bpy.data.textures.remove(texture)
    old = obj.data
    obj.data = baked
    baked.name = name
    old.name = f'{name}_dense'  # left unused: removing meshes one by one remaps the whole file
    color = baked.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    uv = baked.uv_layers.new(name='UVMap')
    tone = rng.random()
    for polygon in baked.polygons:
        is_fresh = any((polygon.center - c).dot(n) > -0.01 and abs((polygon.center - c).dot(n)) < 0.012 and polygon.normal.dot(n) > 0.7
                       for c, n in caps)
        for index in polygon.loop_indices:
            co = baked.vertices[baked.loops[index].vertex_index].co
            color.data[index].color = (1.0, tone, 1.0 if is_fresh else 0.0, 1.0)
            # Box-projected metres: the dominant axis of the face normal picks the plane.
            n = polygon.normal
            axis = max(range(3), key=lambda k: abs(n[k]))
            uv.data[index].uv = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][axis]
    baked.color_attributes.active_color = color
    baked.shade_smooth()
    baked.set_sharp_from_angle(angle=math.radians(50))
    return obj


def make(kind: str, rng, size, name: str = 'Stone', triangles: int = 1200) -> bpy.types.Object:
    look = LOOKS[kind]
    size = Vector(size)
    planes = []
    taper = 0.0
    low, high = look['splits']
    for _ in range(rng.randint(low, high)):
        # Splitting planes through the block leave fresh, flat-ish facets.
        normal = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        if 'face' in look:
            # Walling stone: break the outline, not the face.
            normal = Vector((normal.x, normal.y * 0.12, normal.z)).normalized()
        reach = abs(normal.x) * size.x + abs(normal.y) * size.y + abs(normal.z) * size.z
        planes.append((normal * reach * rng.uniform(0.32, 0.46), normal))
    if kind == 'wedge':
        # Thin end 25-45% of the thick end over the wedge's length.
        taper = size.z * rng.uniform(0.55, 0.75) / (2.0 * size.x)
    bm = core_block(rng, size, look, taper=taper, planes=planes)
    if kind == 'field':
        triangles = max(triangles, 1500)
    return detail(bm, rng, look, name, triangles)


def voussoir(rng, inner: float, depth: float, angle: float, thickness: float, start: float = 0.0,
             keystone: bool = False, name: str = 'Voussoir', triangles: int = 1400) -> bpy.types.Object:
    """Arch stone between radial planes at `start` and `start + angle` (radians,
    0 = springing on +x, arch in the x-z plane, centre at origin), from
    radius `inner` out by `depth`, `thickness` along y. Keystones are 15%
    deeper and stand 1 cm proud of the extrados."""
    look = LOOKS['voussoir']
    outer = inner + depth * (1.15 if keystone else 1.0)
    middle = start + angle * 0.5
    radial = Vector((math.cos(middle), 0.0, math.sin(middle)))
    centre = radial * (inner + outer) * 0.5
    box = Vector((2 * outer * math.sin(angle * 0.5) + 0.1, thickness, outer - inner + 0.1))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    frame = Matrix((radial.cross(Vector((0, 1, 0))), Vector((0, 1, 0)), radial)).transposed()
    bmesh.ops.scale(bm, vec=box * 1.4, verts=bm.verts)
    bmesh.ops.transform(bm, matrix=frame.to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    fresh = bm.faces.layers.int.new('fresh')
    for theta, sign in ((start, -1.0), (start + angle, 1.0)):
        tangent = Vector((-math.sin(theta), 0.0, math.cos(theta))) * sign
        # Tilt about the joint's own middle: about the arch centre a degree
        # would swing the joint by decimetres on a wide, flat arch.
        hinge = Vector((math.cos(theta), 0.0, math.sin(theta))) * (inner + outer) * 0.5
        _cut(bm, hinge, _tilt(tangent, rng, look['square']), fresh, None)
    for y in (-thickness * 0.5, thickness * 0.5):
        normal = _tilt(Vector((0, 1.0 if y > 0 else -1.0, 0)), rng, look['square'])
        _cut(bm, Vector((0, y, 0)), normal, fresh, None)
    # Intrados and extrados approximated by facets of the arch circles.
    for radius, inward in ((inner, True), (outer, False)):
        for k in range(4):
            theta = start + angle * (k + 0.5) / 4
            n = Vector((math.cos(theta), 0.0, math.sin(theta)))
            _cut(bm, n * radius, -n if inward else n, fresh, None)
    for face in bm.faces:
        face[fresh] = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = detail(bm, rng, look, name, triangles)
    if keystone:
        obj.location += radial * 0.01
    return obj
