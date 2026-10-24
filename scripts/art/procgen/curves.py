"""Hanging curves between two attachment points: catenary, rope tube, chain."""
import math

from mathutils import Matrix, Vector

from .shapes import Builder


def catenary(a: Vector, b: Vector, slack: float, count: int = 24) -> list:
    """Points of a hanging cable from a to b (Blender, z up) whose length is the
    chord times (1 + slack). Both end points are exact."""
    span = Vector((b.x - a.x, b.y - a.y, 0.0))
    horizontal = span.length
    rise = b.z - a.z
    length = (b - a).length * (1.0 + max(slack, 1e-4))
    if horizontal < 1e-4:
        return [a.lerp(b, i / count) for i in range(count + 1)]
    target = math.sqrt(max(length * length - rise * rise, horizontal * horizontal * (1 + 1e-6)))
    # Solve 2 c sinh(h / 2c) = target for the catenary parameter c.
    low, high = 1e-4, 1e6
    for _ in range(200):
        c = math.sqrt(low * high)
        if 2 * c * math.sinh(min(horizontal / (2 * c), 700)) > target:
            low = c
        else:
            high = c
    c = math.sqrt(low * high)
    # Lowest point offset so the curve passes through both ends.
    x0 = horizontal * 0.5 - c * math.asinh(rise / (2 * c * math.sinh(horizontal / (2 * c))))
    z0 = a.z - c * math.cosh(-x0 / c)
    direction = span.normalized()
    points = []
    for i in range(count + 1):
        x = horizontal * i / count
        points.append(Vector((a.x, a.y, 0.0)) + direction * x + Vector((0, 0, z0 + c * math.cosh((x - x0) / c))))
    points[0], points[-1] = a.copy(), b.copy()
    return points


def sag(points: list) -> float:
    """Deepest drop below the straight chord, in metres."""
    a, b = points[0], points[-1]
    return max((a.lerp(b, i / (len(points) - 1)).z - p.z) for i, p in enumerate(points))


def tube(builder: Builder, points: list, radius: float, sides: int = 6, color=(1.0, 0.5, 0.0, 1.0), twist: float = 0.0) -> None:
    """Rope or cable along a polyline. U runs along the length in metres; `twist`
    turns the section per metre so a rope texture spirals."""
    rings = []
    distance = 0.0
    normal = None
    for i, p in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        if normal is None:
            normal = Vector((0, 0, 1)).cross(tangent)
            if normal.length < 1e-6:
                normal = Vector((1, 0, 0)).cross(tangent)
        # Parallel transport keeps the section from flipping on steep curves.
        normal = (normal - tangent * normal.dot(tangent)).normalized()
        binormal = tangent.cross(normal)
        if i:
            distance += (p - points[i - 1]).length
        ring = []
        for k in range(sides):
            angle = 2 * math.pi * k / sides + twist * distance
            ring.append(builder.bm.verts.new(p + (normal * math.cos(angle) + binormal * math.sin(angle)) * radius))
        rings.append((ring, distance))
    circumference = 2 * math.pi * radius
    for (ring, u0), (next_ring, u1) in zip(rings, rings[1:]):
        for k in range(sides):
            v0, v1 = circumference * k / sides, circumference * (k + 1) / sides
            builder.face([ring[k], ring[(k + 1) % sides], next_ring[(k + 1) % sides], next_ring[k]],
                         [Vector((u0, v0)), Vector((u0, v1)), Vector((u1, v1)), Vector((u1, v0))], color)
    builder.pieces += 1


def chain(builder: Builder, points: list, link_length: float = 0.11, wire: float = 0.013,
          color=(1.0, 0.5, 0.0, 1.0), ring_steps: int = 10, wire_sides: int = 5) -> int:
    """Interlocking oval links along a polyline, alternating 90 degrees. The
    pitch is the inner length, so neighbouring links touch. Returns link count."""
    pitch = link_length - 2 * wire
    width = link_length * 0.62
    lengths = [0.0]
    for p, q in zip(points, points[1:]):
        lengths.append(lengths[-1] + (q - p).length)
    total = lengths[-1]
    count = max(1, int(total / pitch))
    start = (total - count * pitch) * 0.5
    up = Vector((0, 0, 1))

    def at(distance: float):
        for i in range(len(points) - 1):
            if distance <= lengths[i + 1] or i == len(points) - 2:
                t = (distance - lengths[i]) / max(lengths[i + 1] - lengths[i], 1e-9)
                return points[i].lerp(points[i + 1], min(max(t, 0.0), 1.0))

    radius = width * 0.5 - wire
    straight = max(link_length - width, 0.0)
    for index in range(count):
        a = at(start + index * pitch)
        b = at(start + (index + 1) * pitch)
        axis = (b - a).normalized()
        side = up.cross(axis)
        if side.length < 1e-6:
            side = Vector((1, 0, 0)).cross(axis)
        side.normalize()
        if index % 2:
            side = axis.cross(side)
        normal = axis.cross(side)
        center = (a + b) * 0.5
        # Stadium centreline: two half circles joined by straight sides.
        path = []
        for k in range(ring_steps):
            angle = 2 * math.pi * k / ring_steps
            x = math.cos(angle) * radius
            y = math.sin(angle) * radius + math.copysign(straight * 0.5, math.sin(angle) if abs(math.sin(angle)) > 1e-9 else 1)
            path.append(center + side * x + axis * y)
        rings = []
        for k, p in enumerate(path):
            tangent = (path[(k + 1) % ring_steps] - path[k - 1]).normalized()
            n = normal
            b2 = tangent.cross(n).normalized()
            rings.append([builder.bm.verts.new(p + (n * math.cos(2 * math.pi * s / wire_sides) + b2 * math.sin(2 * math.pi * s / wire_sides)) * wire)
                          for s in range(wire_sides)])
        for k in range(ring_steps):
            ring, next_ring = rings[k], rings[(k + 1) % ring_steps]
            for s in range(wire_sides):
                builder.face([ring[s], ring[(s + 1) % wire_sides], next_ring[(s + 1) % wire_sides], next_ring[s]],
                             [Vector((k * 0.02, s * 0.01)), Vector((k * 0.02, (s + 1) * 0.01)),
                              Vector(((k + 1) * 0.02, (s + 1) * 0.01)), Vector(((k + 1) * 0.02, s * 0.01))], color)
    builder.pieces += count
    return count
