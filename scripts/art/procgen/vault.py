"""Cloister vaults over rooms, built course by course (Blender world space, z up).

    parts = vault.cloister(lib, rng, inner, spring_z, rise, 'antechamber_vault')

`inner` is the room's inner outline (the faces of its walls), counter-clockwise
in plan. From every wall a web rises on a circular arc. The arc springs from
the wall top at `spring_z` and flattens to the crown `rise` above it, at the
room's inradius from the walls. Each point of the vault belongs to the web of
its nearest wall, so the webs meet on the bisectors between walls, as a mason's
cloister (domical) vault does: groins rise from the corners and a ridge runs
along a long room.

Each web is laid in courses parallel to its wall, with every stone's face
turned to the curve, and has a thin mortar shell behind. Returns the parts:
stones carry 'tone' and 'frame'; the shell carries tone -1.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import core, masonry

UP = Vector((0.0, 0.0, 1.0))


def inradius(inner: list) -> float:
    """Largest distance from the walls reachable inside the polygon (sampled)."""
    xs, ys = [p.x for p in inner], [p.y for p in inner]
    normals = _normals(inner)
    best = 0.0
    for i in range(41):
        for j in range(41):
            p = Vector((min(xs) + (max(xs) - min(xs)) * i / 40, min(ys) + (max(ys) - min(ys)) * j / 40))
            d = min((p - a).dot(n) for a, n in zip(inner, normals))
            best = max(best, d)
    return best


def _normals(inner: list) -> list:
    """Inward unit normals of a counter-clockwise outline's edges."""
    result = []
    for a, b in zip(inner, inner[1:] + inner[:1]):
        e = (b - a).normalized()
        result.append(Vector((-e.y, e.x)))
    return result


def cloister(lib, rng, inner: list, spring_z: float, rise: float, name: str, course=(0.24, 0.4), lengths=(0.3, 0.9)) -> list:
    normals = _normals(inner)
    reach = inradius(inner)
    radius = (reach * reach + rise * rise) / (2.0 * rise)
    centre_h = rise - radius  # the arc's centre, below the crown by its radius
    start = math.atan2(-centre_h, -reach)  # angle of the springing point seen from the centre
    sweep = start - math.pi * 0.5
    length = radius * sweep

    def at(s: float):
        phi = start - s / radius
        return reach + radius * math.cos(phi), centre_h + radius * math.sin(phi)

    # Every wall's region: nearer to it than to any other wall line.
    regions = []
    for i, (a, n) in enumerate(zip(inner, normals)):
        planes = []
        for j, (b, m) in enumerate(zip(inner, normals)):
            if i == j:
                continue
            k = Vector((n.x - m.x, n.y - m.y, 0.0))
            c = a.dot(n) - b.dot(m)
            if k.length < 1e-6:
                continue
            # Distance to wall i exceeds that to wall j where p.k > c: cut that away.
            point = k * (c / k.length_squared)
            planes.append((Vector((point.x, point.y, 0.0)), k.normalized()))
        regions.append(planes)

    parts = []
    for i, (a, n) in enumerate(zip(inner, normals)):
        b = inner[(i + 1) % len(inner)]
        along2 = (b - a).normalized()
        span = (b - a).length + 2.0 * reach + 2.0
        origin = a - along2 * (reach + 1.0)
        s = 0.0
        row = 0
        while length - s > 0.05:
            h = rng.uniform(*course)
            if length - (s + h) < course[0] * 0.6:
                h = length - s
            u0, z0 = at(s)
            u1, z1 = at(s + h)
            um, zm = at(s + h * 0.5)
            tangent = Vector((n.x * (u1 - u0), n.y * (u1 - u0), z1 - z0)).normalized()
            inward = Vector((n.x, n.y, 0.0))
            face = (inward * (reach - um) + UP * (centre_h - zm)).normalized()
            along = Vector((along2.x, along2.y, 0.0))
            if along.cross(tangent).dot(face) < 0:
                along = -along
            base = Vector((origin.x, origin.y, spring_z)) + inward * um + UP * zm
            if along.dot(Vector((along2.x, along2.y, 0.0))) < 0:
                base = base + Vector((along2.x, along2.y, 0.0)) * span
            frame = Matrix((along, tangent, face)).transposed().to_4x4()
            frame.translation = base
            x = 0.0
            while span - x > 0.05:
                stone_length = rng.uniform(*lengths)
                if span - (x + stone_length) < 0.2:
                    stone_length = span - x
                joint = rng.uniform(0.006, 0.016)
                stone = lib.place(rng, stone_length - joint, h - joint, rng.uniform(0.24, 0.32), f'{name}_{i}_{row}_{len(parts)}')
                stone.matrix_world = frame @ Matrix.Translation((x + stone_length * 0.5, 0.0, rng.uniform(-0.006, 0.014))) @ stone.matrix_world
                stone['frame'] = [*along, *tangent, *face]
                if all(masonry.clip(stone, point, normal) for point, normal in regions[i]):
                    parts.append(stone)
                else:
                    core.discard(stone)
                x += stone_length
            s += h
            row += 1
        parts.append(_shell(inner, i, n, at, length, spring_z, reach, centre_h, regions[i], f'{name}_shell{i}'))
    return parts


def _shell(inner, i, n, at, length, spring_z, reach, centre_h, planes, name) -> bpy.types.Object:
    """Mortar behind web i: its arc surface pushed back a few centimetres."""
    a, b = inner[i], inner[(i + 1) % len(inner)]
    along2 = (b - a).normalized()
    start = a - along2 * (reach + 1.0)
    end = b + along2 * (reach + 1.0)
    bm = bmesh.new()
    rows = []
    steps = 24
    inward = Vector((n.x, n.y, 0.0))
    # Down behind the wall's top course first, so no gap shows at the springing.
    rows.append([bm.verts.new(Vector((p.x, p.y, spring_z - 0.3)) - inward * 0.04) for p in (start, end)])
    for k in range(steps + 1):
        u, z = at(length * k / steps)
        back = -(inward * (reach - u) + UP * (centre_h - z)).normalized() * 0.04
        rows.append([bm.verts.new(Vector((p.x, p.y, spring_z)) + inward * u + UP * z + back) for p in (start, end)])
    for k in range(steps + 1):
        bm.faces.new((rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj['tone'] = -1.0
    for point, normal in planes:
        masonry.clip(obj, point, normal, fill=False)
    return obj
