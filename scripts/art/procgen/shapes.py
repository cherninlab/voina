"""Hewn timber, planks and iron bar stock as prisms with metre UVs.

Pieces are added to a Builder (one mesh per material). Each piece is a
chamfered rectangular prism between two points, subdivided along its length so
baked AO and warping have vertices to work with. U runs along the grain in
metres, V around the section, so a UV-sampling material shows real grain.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import core


class Builder:
    """Accumulates pieces into one bmesh with UVs and a corner colour attribute."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.color = self.bm.loops.layers.float_color.new('Color')
        self.pieces = 0

    def face(self, verts, uvs, color) -> None:
        face = self.bm.faces.new(verts)
        for loop, uv in zip(face.loops, uvs):
            loop[self.uv].uv = uv
            loop[self.color] = color

    def to_object(self, smooth_angle: float = 35.0) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.color_attributes.active_color = mesh.color_attributes['Color']
        obj = core.link(bpy.data.objects.new(self.name, mesh))
        # Chamfers stay crisp; long faces shade smoothly.
        obj.data.shade_smooth_by_angle(angle=math.radians(smooth_angle)) if hasattr(obj.data, 'shade_smooth_by_angle') else None
        return obj


def frame(a: Vector, b: Vector, up: Vector) -> Matrix:
    """Columns: x = width, y = depth (towards `up`), z = length axis a->b."""
    z = (b - a).normalized()
    x = up.cross(z)
    if x.length < 1e-6:
        x = Vector((1, 0, 0)).cross(z)
    x.normalize()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def section(width: float, depth: float, chamfer: float, rng, wear: float) -> list:
    """Chamfered rectangle, counter-clockwise, with slightly uneven arrises."""
    w, d = width * 0.5, depth * 0.5
    c = min(chamfer, w * 0.45, d * 0.45)
    points = [(-w + c, -d), (w - c, -d), (w, -d + c), (w, d - c),
              (w - c, d), (-w + c, d), (-w, d - c), (-w, -d + c)]
    return [(x * (1 - rng.uniform(0, wear)), y * (1 - rng.uniform(0, wear))) for x, y in points]


def prism(builder: Builder, a: Vector, b: Vector, width: float, depth: float, up: Vector, rng,
          chamfer: float = 0.015, wear: float = 0.03, bow: float = 0.0, crook: float = 0.0,
          twist: float = 0.0, segment: float = 0.25, variation: float = None, roughen: float = 0.0) -> None:
    """One piece from a to b. bow/crook are mid-length offsets along depth/width
    (metres), twist is end rotation (radians), roughen is per-ring jitter."""
    basis = frame(a, b, up)
    length = (b - a).length
    rings = max(1, math.ceil(length / segment))
    profile = section(width, depth, chamfer, rng, wear)
    perimeter = [0.0]
    for i in range(len(profile)):
        p, q = profile[i], profile[(i + 1) % len(profile)]
        perimeter.append(perimeter[-1] + math.dist(p, q))
    shade = rng.random() if variation is None else variation
    color = (1.0, shade, 0.0, 1.0)
    offset = Vector((rng.uniform(0, 4), rng.uniform(0, 4)))
    ring_verts = []
    for ring in range(rings + 1):
        t = ring / rings
        arch = math.sin(math.pi * t)
        angle = twist * (t - 0.5)
        jitter = roughen * (rng.random() - 0.5) if 0 < ring < rings else 0.0
        ca, sa = math.cos(angle), math.sin(angle)
        verts = []
        for x, y in profile:
            local = Vector((x * ca - y * sa + crook * arch + jitter, x * sa + y * ca + bow * arch + jitter, t * length))
            verts.append(builder.bm.verts.new(a + basis @ local))
        ring_verts.append(verts)
    count = len(profile)
    for ring in range(rings):
        u0, u1 = ring / rings * length, (ring + 1) / rings * length
        for k in range(count):
            v0, v1 = perimeter[k], perimeter[k + 1]
            quad = [ring_verts[ring][k], ring_verts[ring][(k + 1) % count],
                    ring_verts[ring + 1][(k + 1) % count], ring_verts[ring + 1][k]]
            builder.face(quad, [offset + Vector((u0, v0)), offset + Vector((u0, v1)),
                                offset + Vector((u1, v1)), offset + Vector((u1, v0))], color)
    # End grain: planar UVs in metres.
    builder.face(list(reversed(ring_verts[0])), [offset + Vector(p) for p in reversed(profile)], color)
    builder.face(ring_verts[-1], [offset + Vector(p) for p in profile], color)
    builder.pieces += 1


def timber(builder: Builder, a: Vector, b: Vector, width: float, depth: float, up: Vector, rng, **options) -> None:
    """Adzed structural member: generous chamfer, slight twist and bow."""
    length = (b - a).length
    defaults = dict(chamfer=min(width, depth) * 0.12, wear=0.05,
                    bow=rng.uniform(-1, 1) * min(0.012, length * 0.002),
                    crook=rng.uniform(-1, 1) * min(0.01, length * 0.0015),
                    twist=rng.uniform(-1, 1) * 0.02)
    defaults.update(options)
    prism(builder, a, b, width, depth, up, rng, **defaults)


def plank(builder: Builder, a: Vector, b: Vector, width: float, thickness: float, up: Vector, rng, **options) -> None:
    """Sawn board laid flat (`up` is its face normal): small chamfer, cup-free,
    gentle bow and twist that stay within a few millimetres of the bearers."""
    length = (b - a).length
    defaults = dict(chamfer=0.006, wear=0.08, bow=rng.uniform(-0.004, 0.003),
                    crook=rng.uniform(-1, 1) * 0.006, twist=rng.uniform(-1, 1) * 0.012,
                    segment=min(0.25, length / 4), roughen=0.002)
    defaults.update(options)
    prism(builder, a, b, width, thickness, up, rng, **defaults)


def bar(builder: Builder, a: Vector, b: Vector, width: float, thickness: float, up: Vector, rng, **options) -> None:
    """Forged iron strap or flat bar: crisp, almost straight."""
    defaults = dict(chamfer=0.002, wear=0.02, segment=0.5)
    defaults.update(options)
    prism(builder, a, b, width, thickness, up, rng, **defaults)
