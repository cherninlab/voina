"""Mortar: blob-shaped joint filler between neighbouring stones that is both
the visible mortar and the physical glue.

    beads = mortar.lay(stones, rng, max_gap=0.025, squeeze=0.006)   # one per joint
    for bead in beads: rigid.body(bead, mass=rigid.mass(bead, mortar.DENSITY))
    mortar.glue(beads, rng, weakness=1.0)     # stones bond as strongly as their mortar
    cracked = mortar.failed(beads, rest)      # after the simulation

Stones need not touch or be cut to fit: wherever two faces are within
`max_gap`, a bead fills the gap. It stops `CLEAR` short of each stone (so
nothing starts overlapped), bulges out where squeezed (`squeeze` > 0) or is
raked back where weathered (`recess` > 0). Each joint bonds its two stones with a
breakable joint scaled to the lighter stone's weight; the bead adheres to one
of them. When a bond breaks the bead is reported by `failed` (crumble it out,
rake it back or leave it hanging off its stone).

Let walls stand on their footing by weight. Do not also nail several stones
to a passive or kinematic body: that closes rigid loops (ground - stone -
mortar - stone - ground), numerical error builds stress around the loop and
the weakest bead snaps at rest.
Colour: R = 1 (AO later), G = per-bead variation, B = 0.35 (mortar marker).
"""
import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import core, disturb, rigid

CLEAR = 0.001
INSET = 0.003
DENSITY = 1900.0


def _surface(obj):
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in obj.data.polygons])


def joints(stones: list, max_gap: float) -> list:
    """(a, b, [(point on a, point on b), ...]) for every pair of stones whose
    surfaces come within max_gap of each other over a real area."""
    bpy.context.view_layer.update()
    shapes = [rigid.Shape(s) for s in stones]
    result = []
    for i in range(len(stones)):
        for j in range(i + 1, len(stones)):
            if not shapes[i].near(shapes[j], max_gap):
                continue
            pairs = []
            for source, target in ((shapes[i], shapes[j]), (shapes[j], shapes[i])):
                for co in source.samples:
                    hit = target.bvh.find_nearest(co, max_gap)
                    if hit[0] is not None and hit[3] > 1e-5:
                        pairs.append((co, hit[0]) if source is shapes[i] else (hit[0], co))
            for chunk in _split(pairs):
                if len(chunk) >= 6:
                    result.append((stones[i], stones[j], chunk))
    return result


def _split(pairs: list, length: float = 0.25) -> list:
    """One joint can wrap a corner (bed and head faces) and run a metre long:
    group pairs by gap direction, then cut each group into ~25 cm beads, so
    each bead is a flat slab of joint and failed mortar crumbles in pieces."""
    groups = []
    for pa, pb in pairs:
        d = (pb - pa).normalized()
        for group in groups:
            if group[0].dot(d) > 0.8:
                group[1].append((pa, pb))
                break
        else:
            groups.append([d, [(pa, pb)]])
    chunks = []
    for direction, members in groups:
        if len(members) < 6:
            continue
        # Longest extent across the gap direction decides where to cut.
        middle = sum((pa for pa, _ in members), Vector()) / len(members)
        spread = max(members, key=lambda m: ((m[0] - middle) - direction * (m[0] - middle).dot(direction)).length)[0] - middle
        axis = (spread - direction * spread.dot(direction))
        if axis.length < 1e-6:
            chunks.append(members)
            continue
        axis.normalize()
        keyed = sorted(members, key=lambda m: (m[0] - middle).dot(axis))
        low, high = (keyed[0][0] - middle).dot(axis), (keyed[-1][0] - middle).dot(axis)
        count = max(1, round((high - low) / length))
        step = (high - low) / count
        for n in range(count):
            part = [m for m in keyed if low + n * step - 1e-6 <= (m[0] - middle).dot(axis) <= low + (n + 1) * step + 1e-6]
            chunks.append(part)
    return chunks


def bead(a, b, pairs: list, rng, squeeze: float, recess: float, name: str):
    """Convex filler spanning the gap, then blobbed on its exposed faces."""
    # Fill the joint's core only: where rounded arrises open the gap into a V,
    # real mortar sits back behind them instead of filling the notch.
    widths = sorted((pb - pa).length for pa, pb in pairs)
    core_width = widths[len(widths) // 2] * 1.35 + 0.002
    pairs = [(pa, pb) for pa, pb in pairs if (pb - pa).length <= core_width]
    bm = bmesh.new()
    for pa, pb in pairs:
        across = pb - pa
        if across.length < CLEAR * 3:
            continue
        direction = across.normalized()
        bm.verts.new(pa + direction * CLEAR)
        bm.verts.new(pb - direction * CLEAR)
    if len(bm.verts) < 4:
        bm.free()
        return None
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    if len(bm.faces) < 4:
        bm.free()
        return None
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    surfaces = (_surface(a), _surface(b))
    offset = (squeeze - recess)
    for v in bm.verts:
        touching = min(s.find_nearest(v.co, 1.0)[3] or 1.0 for s in surfaces)
        if touching > CLEAR * 2.5:
            # Exposed face of the joint: squeezed out, or raked and weathered back.
            v.co += v.normal * offset * rng.uniform(0.35, 1.0)
    for _ in range(4):
        bmesh.ops.smooth_vert(bm, verts=[v for v in bm.verts if min(s.find_nearest(v.co, 1.0)[3] or 1.0 for s in surfaces) > CLEAR * 2.5],
                              factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # Beads meet at T-junctions (head joint under a bed joint). Pull each back
    # INSET from its rim within the joint plane so neighbours never overlap.
    across = sum(((pb - pa).normalized() for pa, pb in pairs), Vector()).normalized()
    middle = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    for v in bm.verts:
        rel = v.co - middle
        planar = rel - across * rel.dot(across)
        if planar.length > INSET * 2:
            v.co -= planar.normalized() * INSET
    # Shaping may tuck a rim vertex into a stone; push every vertex back to
    # CLEAR outside both faces so nothing starts overlapped in the physics.
    for v in bm.verts:
        for surface in surfaces:
            near, normal, _, distance = surface.find_nearest(v.co, 0.05)
            if near is not None and (v.co - near).dot(normal) < CLEAR:
                v.co = near + normal * CLEAR
    # Lime mortar is lumpy and grainy where it is exposed, not trowelled glass.
    for v in bm.verts:
        if min(s.find_nearest(v.co, 1.0)[3] or 1.0 for s in surfaces) > CLEAR * 2.5:
            v.co += v.normal * rng.uniform(-0.0015, 0.0015)
    colors = bm.loops.layers.float_color.new('Color')
    uv = bm.loops.layers.uv.new('UVMap')
    shade = rng.random()
    for face in bm.faces:
        for loop in face.loops:
            loop[colors] = (1.0, shade, 0.35, 1.0)
            loop[uv].uv = (loop.vert.co.x + loop.vert.co.z, loop.vert.co.y + loop.vert.co.z)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.color_attributes.active_color = mesh.color_attributes['Color']
    obj = core.link(bpy.data.objects.new(name, mesh))
    disturb.centre(obj)
    obj['joint'] = [a.name, b.name]
    return obj


def lay(stones: list, rng, max_gap: float = 0.025, squeeze: float = 0.0, recess: float = 0.008) -> list:
    """One mortar bead per joint between `stones`."""
    beads = []
    for number, (a, b, pairs) in enumerate(joints(stones, max_gap)):
        obj = bead(a, b, pairs, rng, squeeze, recess, f'Mortar_{number}')
        if obj is not None:
            beads.append(obj)
    return beads


def glue(beads: list, rng, strength=(80.0, 200.0), weakness: float = 1.0) -> list:
    """Bond the stones each bead joins (both must be rigid bodies). The bond is
    a breakable joint between the two stones, as strong as the bead's share
    of the joint: multiples of the lighter stone's weight per substep, divided
    by `weakness` (old, frost-cracked or washed-out mortar). The bead itself
    rides on the stone it adheres to; `failed` finds beads whose bond broke.
    A light bead linking two heavy stones would make the solver spongy."""
    made = []
    for obj in beads:
        a, b = (bpy.data.objects[name] for name in obj['joint'])
        lighter = a if a.rigid_body.mass < b.rigid_body.mass else b
        threshold = disturb.load(lighter) * rng.uniform(*strength) / weakness
        made.append(disturb.nail(a, b, obj.matrix_world.translation, threshold, collide=True))
        host = a if rng.random() < 0.5 else b
        obj['host'] = host.name
        made.append(disturb.nail(obj, host, obj.matrix_world.translation, collide=False))
    return made


def failed(beads: list, rest: dict, tolerance: float = 0.003) -> list:
    """Beads whose two stones moved apart by more than `tolerance` at the bead:
    the bond broke and the mortar there has cracked out."""
    result = []
    for obj in beads:
        a, b = (bpy.data.objects[name] for name in obj['joint'])
        at = rest[obj.name].translation
        move_a = a.matrix_world @ (rest[a.name].inverted() @ at)
        move_b = b.matrix_world @ (rest[b.name].inverted() @ at)
        if (move_a - move_b).length > tolerance:
            result.append(obj)
    return result
