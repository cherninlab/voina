"""Vaulted passages built stone by stone, in Blender world space (z up).

A passage has one cross-section: a masonry.Opening centred on x = 0, with
its clear width, springing and rise. It is built from three kinds of piece:

    groups = passage.run(lib, rng, o, a, b, 'P1', ext=(0.4, 0.0), planes=[(point, normal)])
    groups = passage.bay(lib, rng, quoins, o, centre, axis, {0: o, 3: o}, 'B1')   # an L bend
    groups = passage.portal(lib, rng, quoins, o, mouth, outward, 'M1')

- run: a straight stretch, level or sloped, between two centre-line floor
  points. Side walls have horizontal courses cut to the floor and springing
  lines. The barrel vault is made of staggered voussoir rings sheared to the
  slope, and a mortar mass surrounds it with the profile as its hole.
  `planes` trim the run to whatever it meets; `normal` points to the part
  that is cut away.
- bay: a square bay where runs meet (a bend, a T or a crossing). Runs arrive
  through its sides and a groin vault covers it: the two barrel vaults meet
  on the diagonals. A side without a run is a wall with a lunette under the
  vault; a narrower run gets its own arch in that wall.
- portal: a face wall with the passage's arch, where a run opens onto the
  shaft (a bridge or ledge starts there).

Every piece returns {group: [objects]}. Stones carry 'tone' and 'frame'; mortar
carries tone -1. The bake merges groups and takes collision from the mortar.
"""
import math

import bpy
from mathutils import Matrix, Vector

from . import core, masonry

UP = Vector((0.0, 0.0, 1.0))
PAVING = None  # a floor-flag library for passage floors, if the caller has one
THICKNESS = 0.9
RING = 0.4
RECESS = 0.034


def _bake_transform(obj) -> None:
    obj.data = obj.data.copy()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def _shear(obj, origin: Vector, d: Vector, slope: float) -> None:
    """Lift every vertex by slope x its distance along d from origin."""
    _bake_transform(obj)
    for v in obj.data.vertices:
        v.co.z += slope * (v.co - origin).dot(d)


def clip_groups(groups: dict, planes) -> None:
    for key in groups:
        kept = []
        for obj in groups[key]:
            if all(masonry.clip(obj, point, normal) for point, normal in planes):
                kept.append(obj)
            else:
                core.discard(obj)
        groups[key] = kept


def _mass(o: masonry.Opening, length: float, name: str, top: float = None) -> bpy.types.Object:
    """Mortar block around the profile, wall-local: x across (0 .. width),
    y up, extruded along -z for `length`; the hole is the profile grown by
    the recess so the stones' faces show."""
    width = o.half * 2.0 + 2.0 * THICKNESS
    hole = masonry.Opening(THICKNESS - RECESS, THICKNESS + o.half * 2.0 + RECESS, 0.0, o.spring, o.crown - o.spring + RECESS)
    wall = masonry.Wall(width, top or o.crown + RING + 0.3, length + RECESS, [hole], recess=RECESS)
    return wall.core(name)


RING_WIDTH = 0.42
_RINGS = {}


def _ring_variants(rng, o: masonry.Opening, stagger: bool, triangles: int, count: int = 3) -> list:
    """A few sculpted rings per profile, reused down a vault: every ring of a
    long tunnel sculpted anew would take hours, and real vault stones are cut
    to a handful of templates anyway. Each variant is [(mesh)] in voussoir
    axes (arch in x-z about the intrados centre, RING_WIDTH thick on y)."""
    key = (round(o.radius, 3), round(o.a0, 4), stagger, triangles)
    if key not in _RINGS:
        variants = []
        for number in range(count):
            meshes = []
            for piece in masonry.ring(rng, o, RING, RING_WIDTH, f'vault_template_{len(_RINGS)}_{number}', stagger=stagger,
                                      triangles=triangles):
                piece.data.transform(piece.matrix_world)
                meshes.append(piece.data)
                core.discard(piece)
            variants.append(meshes)
        _RINGS[key] = variants
    return _RINGS[key]


def _vault(rng, o: masonry.Opening, start: Vector, d: Vector, length: float, name: str, slope: float = 0.0,
           triangles: int = 140) -> list:
    """Barrel vault rings along d from `start` (centre-line floor point)."""
    side = d.cross(UP)
    frame = Matrix((side, d, UP)).transposed().to_4x4()
    result = []
    s, number = 0.0, 0
    while length - s > 1e-6:
        width = rng.uniform(0.34, 0.48)
        if length - (s + width) < 0.25:
            width = length - s
        joint = rng.uniform(0.008, 0.02)
        centre = start + d * (s + width * 0.5) + UP * (o.cy + slope * (s + width * 0.5))
        variant = rng.choice(_ring_variants(rng, o, number % 2 == 1, triangles))
        mirror = -1.0 if rng.random() < 0.5 else 1.0
        scale = Matrix.Diagonal((mirror, (width - joint) / RING_WIDTH, 1.0, 1.0))
        for k, mesh in enumerate(variant):
            piece = core.link(bpy.data.objects.new(f'{name}_ring{number}_{k}', mesh))
            piece.matrix_world = Matrix.Translation(centre) @ frame @ scale
            if slope:
                _shear(piece, centre, d, slope)
            piece['tone'] = rng.uniform(0.8, 1.15)
            piece['frame'] = [*d, *UP, *side]
            result.append(piece)
        s += width
        number += 1
    return result


def pave(lib, rng, start: Vector, d: Vector, length: float, half: float, slope: float, name: str) -> list:
    """Stone floor along d from `start` (centre-line floor point), wall to
    wall: flags laid in rows on the level, treads stepping up a ramp. The
    walking collision stays the game's smooth ribbon; the stones sit on it."""
    side = d.cross(UP)
    frame_rot = Matrix((side, d, UP)).transposed().to_4x4()
    result, s = [], 0.0
    stepped = abs(slope) > 0.06
    while length - s > 0.05:
        depth = min(0.34 if stepped else rng.uniform(0.45, 0.85), length - s)
        top = start.z + slope * ((s + depth) if slope > 0 else s) + 0.015
        x = -half
        while half - x > 0.05:
            width = rng.uniform(0.6, 1.3)
            if half - (x + width) < 0.35:
                width = half - x
            joint = rng.uniform(0.006, 0.014)
            stone = (PAVING or lib).place(rng, width - joint, depth - joint, 0.14, f'{name}_flag')
            frame = frame_rot.copy()
            frame.translation = Vector((start.x, start.y, top)) + d * (s + depth * 0.5) + side * (x + width * 0.5)
            stone.matrix_world = frame @ stone.matrix_world
            stone['frame'] = [*side, *d, *UP]
            result.append(stone)
            x += width
        s += depth
    return result


def run(lib, rng, o: masonry.Opening, a: Vector, b: Vector, name: str, ext=(0.0, 0.0), planes=(),
        triangles: int = 140) -> dict:
    """A straight stretch from floor point a to floor point b (3D), extended
    by ext beyond each end and trimmed by planes."""
    flat = Vector((b.x - a.x, b.y - a.y, 0.0))
    d = flat.normalized()
    side = d.cross(UP)
    slope = (b.z - a.z) / flat.length
    s0, s1 = -ext[0], flat.length + ext[1]
    length = s1 - s0

    def at(s: float) -> Vector:
        return a + d * s + UP * slope * s

    start, end = at(s0), at(s1)
    low = min(start.z, end.z)
    climb = abs(end.z - start.z)
    height = o.spring + climb
    groups = {0: [], 1: [], 2: [], 3: [], 4: []}
    rows = masonry.Wall(1.0, height).courses(rng, {0.0, height} if climb > 0.05 else {0.0, o.spring})
    for number, (origin, along) in enumerate((((start.x, start.y), d), ((end.x, end.y), -d))):
        base = Vector((origin[0], origin[1], low)) + (-side if number == 0 else side) * o.half
        wall = masonry.Wall(length, height, THICKNESS)
        pieces = wall.build(lib, rng, name=f'{name}_side{number}', rows=rows, core=False)
        masonry.place(pieces, base, along, UP)
        groups[number] = pieces
    if climb > 0.05:
        # Horizontal courses, cut along the slope at the floor and the springing.
        floor_normal = (UP - d * slope).normalized()
        cuts = [(start, -floor_normal), (start + UP * o.spring, floor_normal)]
        sides = {0: groups[0], 1: groups[1]}
        clip_groups(sides, cuts)
        groups[0], groups[1] = sides[0], sides[1]
    groups[2] = _vault(rng, o, start, d, length, name, slope, triangles)
    groups[4] = pave(lib, rng, start, d, length, o.half, slope, name)
    mass = _mass(o, length, f'{name}_mass')
    masonry.place([mass], start - d * RECESS - side * (o.half + THICKNESS), side, UP)
    if slope:
        _shear(mass, start, d, slope)
    groups[3] = [mass]
    clip_groups(groups, planes)
    return groups


def _keep_under_arc(obj, o: masonry.Opening, centre_x: float) -> bool:
    """Wall-local: trim a lunette wall stone to below the vault's intrados
    (centred at x = centre_x). False when nothing is left."""
    position = obj.matrix_world.translation
    u = position.x - centre_x
    if position.y <= o.spring:
        return True
    if abs(u) >= o.half:
        return False
    hub = Vector((centre_x, o.cy, 0.0))
    offset = Vector((u, position.y - o.cy, 0.0))
    direction = offset.normalized() if offset.length > 1e-6 else Vector((0.0, 1.0, 0.0))
    return masonry.clip(obj, hub + direction * (o.radius + 0.004), direction)


def bay(lib, rng, quoins, o: masonry.Opening, centre: Vector, axis: Vector, sides: dict, name: str) -> dict:
    """A square bay of half-size o.half on floor point `centre`. `axis` is
    the bay's horizontal x; `sides` maps 0 (+x), 1 (+y), 2 (-x), 3 (-y) to
    the profile of the run arriving there (absent: a solid wall)."""
    x = Vector((axis.x, axis.y, 0.0)).normalized()
    y = UP.cross(x)
    h = o.half
    directions = [x, y, -x, -y]
    groups = {}
    top = o.crown + RING + 0.3
    for k, outward in enumerate(directions):
        arriving = sides.get(k)
        if arriving is not None and abs(arriving.half - h) < 0.05:
            continue  # the run continues the bay's vault through this side
        along = outward.cross(UP)
        # Run on past the corners where the neighbouring side is walled too, so corners bond.
        start_side, end_side = ((k + 1) % 4, (k + 3) % 4) if along.dot(directions[(k + 1) % 4]) < 0 else ((k + 3) % 4, (k + 1) % 4)
        before = THICKNESS if sides.get(start_side) is None else 0.0
        after = THICKNESS if sides.get(end_side) is None else 0.0
        length = 2.0 * h + before + after
        openings = []
        if arriving is not None:
            openings.append(masonry.Opening(before + h - arriving.half, before + h + arriving.half, 0.0, arriving.spring,
                                            rise=arriving.crown - arriving.spring))
        wall = masonry.Wall(length, o.crown + 0.05, THICKNESS, openings)
        pieces = wall.build(lib, rng, quoins=quoins, name=f'{name}_wall{k}')
        kept = []
        for piece in pieces:
            if piece.get('tone', 1.0) < 0 or _keep_under_arc(piece, o, before + h):
                kept.append(piece)
            else:
                core.discard(piece)
        masonry.place(kept, centre + outward * h - along * (before + h), along, UP)
        groups[k] = kept
    # Groin vault: the vault along x keeps the triangles over the +-x sides,
    # the vault along y those over +-y; they meet on the diagonals.
    for number, (direction, other) in enumerate(((x, y), (y, x))):
        rings = _vault(rng, o, centre - direction * h, direction, 2.0 * h, f'{name}_vault{number}')
        kept = []
        for piece in rings:
            world = [piece.matrix_world @ v.co for v in piece.data.vertices]
            mean = sum(world, Vector()) / max(len(world), 1)
            sign = 1.0 if (mean - centre).dot(direction) >= 0 else -1.0
            planes = [(centre, (-direction * sign + other).normalized()), (centre, (-direction * sign - other).normalized())]
            if all(masonry.clip(piece, point, normal) for point, normal in planes):
                kept.append(piece)
            else:
                core.discard(piece)
        groups[4 + number] = kept
    groups[7] = pave(lib, rng, centre - x * h, x, 2.0 * h, h, 0.0, f'{name}_floor')
    # Mass: a block over the bay and its walls, holed by both vaults' profiles.
    # Block A: across y, extruded along x (local -z runs along -(y x up) = -x from its origin).
    mass = _mass(o, 2.0 * (h + THICKNESS) + 1.0, f'{name}_mass', top)
    masonry.place([mass], centre + x * (h + THICKNESS + 0.5 + RECESS) - y * (h + THICKNESS), y, UP)
    _bake_transform(mass)
    # Block B: across x, extruded along y.
    cutter = _mass(o, 2.0 * (h + THICKNESS) + 1.0, f'{name}_cut', top + 1.0)
    masonry.place([cutter], centre - x * (h + THICKNESS) - y * (h + THICKNESS + 0.5 + RECESS), x, UP)
    _bake_transform(cutter)
    # The second block's material is what both holes leave: intersect.
    boolean = mass.modifiers.new('groin', 'BOOLEAN')
    boolean.operation = 'INTERSECT'
    boolean.solver = 'EXACT'
    boolean.object = cutter
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(mass.evaluated_get(depsgraph))
    mass.modifiers.clear()
    mass.data = baked
    core.discard(cutter)
    mass['tone'] = -1.0
    groups[6] = [mass]
    return groups


def portal(lib, rng, quoins, o: masonry.Opening, mouth: Vector, outward: Vector, name: str) -> dict:
    """A face wall with the passage's arch, its face through `mouth` (the
    floor centre where the open crossing starts), facing `outward`."""
    flank = 1.4
    outward = Vector((outward.x, outward.y, 0.0)).normalized()
    along = UP.cross(outward)
    opening = masonry.Opening(flank, flank + 2.0 * o.half, 0.0, o.spring, rise=o.crown - o.spring)
    wall = masonry.Wall(2.0 * (flank + o.half), o.crown + RING + 0.9, THICKNESS, [opening])
    pieces = wall.build(lib, rng, quoins=quoins, name=name)
    masonry.place(pieces, mouth - along * (flank + o.half), along, UP)
    return {0: pieces}
