"""Masonry walls built stone by stone, with honest openings.

    wall = masonry.Wall(length=8.0, height=5.0, thickness=0.9,
                        openings=[masonry.Opening(3.0, 5.4, sill=0.0, spring=2.4)])   # a doorway
    parts = wall.build(lib, rng, quoins=quoin_lib)          # objects in wall-local space
    masonry.place(parts, origin, along, up)                  # into the world

Wall-local axes: x along the wall from its left end, y up from the floor, z
out of the face (the face is z = 0, the wall body runs to z = -thickness).

Rules, so every element has a reason to be there:
- courses run the full wall; their joints line up with sills and springing
  lines, as a mason sets them out;
- an opening exists only where the caller asks for one (a passage or a
  window into a real space); its sides get alternating long and short jamb
  stones through the full wall thickness, a window gets a sill stone, the
  head gets an arch ring of voussoirs with a keystone (through stones, so the
  reveal and soffit are stone, not plaster);
- course stones beside the arch ring are cut to its curve (spandrels), so
  nothing overlaps and no gap is left;
- behind the stones a mortar core, set back `recess`, with true holes at the
  openings, fills the joints.
"""
import math
from dataclasses import dataclass

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import core, stones


@dataclass
class Opening:
    x0: float          # left edge of the clear opening, along the wall
    x1: float          # right edge
    sill: float = 0.0  # 0 for a doorway
    spring: float = 2.4
    window: bool = False
    rise: float = None  # crown above the springing; None = semicircle, less = segmental

    @property
    def half(self) -> float:
        return (self.x1 - self.x0) * 0.5

    @property
    def centre(self) -> float:
        return (self.x0 + self.x1) * 0.5

    @property
    def radius(self) -> float:
        """Radius of the intrados circle."""
        rise = self.half if self.rise is None else min(self.rise, self.half)
        return (self.half ** 2 + rise ** 2) / (2.0 * rise)

    @property
    def cy(self) -> float:
        """Height of the intrados circle's centre (below the springing for a segmental arch)."""
        rise = self.half if self.rise is None else min(self.rise, self.half)
        return self.spring + rise - self.radius

    @property
    def a0(self) -> float:
        """Angle of the springing on the intrados circle (0 for a semicircle)."""
        return math.atan2(self.spring - self.cy, self.half)

    @property
    def crown(self) -> float:
        return self.cy + self.radius


class Wall:
    def __init__(self, length: float, height: float, thickness: float = 0.9, openings=(), course=(0.2, 0.44),
                 stone=(0.3, 0.95), joint=(0.006, 0.016), proud=(-0.006, 0.018), recess=0.034, ring=0.4):
        self.length, self.height, self.thickness = length, height, thickness
        self.openings = list(openings)
        self.course, self.stone, self.joint, self.proud = course, stone, joint, proud
        self.recess, self.ring = recess, ring

    # -- setting out -------------------------------------------------------
    def courses(self, rng, keys=None) -> list:
        """(y0, height) rows; joints fall on sills and springing lines. Pass the
        same `keys` (and rng state) for every wall of a room so courses run on
        round the corners."""
        if keys is None:
            keys = {0.0, self.height}
            for o in self.openings:
                keys.update({o.sill, o.spring} if o.sill > 0 else {o.spring})
        keys = sorted(k for k in set(keys) | {0.0, self.height} if 0.0 <= k <= self.height)
        rows = []
        for a, b in zip(keys, keys[1:]):
            span = b - a
            count = max(1, round(span / ((self.course[0] + self.course[1]) * 0.5)))
            weights = [rng.uniform(0.75, 1.25) for _ in range(count)]
            y = a
            for w in weights:
                h = span * w / sum(weights)
                rows.append((y, h))
                y += h
        return rows

    def blocked(self, y0: float, h: float, row: int) -> list:
        """x intervals a course row may not fill: openings, jambs, arch rings."""
        result = []
        for o in self.openings:
            jamb = 0.34 if row % 2 else 0.5
            top = o.crown + self.ring
            if y0 + h <= o.sill - 0.13 or y0 >= top:
                continue
            if y0 < o.spring:
                result.append((o.x0 - jamb, o.x1 + jamb, 'jamb', o, jamb))
            else:
                # Widest extent of the ring's outer circle within this band.
                dy = max(0.0, y0 - o.cy)
                outer = o.radius + self.ring
                half = math.sqrt(max(outer * outer - dy * dy, 0.0))
                result.append((o.centre - half, o.centre + half, 'ring', o, 0.0))
        return sorted(result, key=lambda r: r[0])

    # -- building ----------------------------------------------------------
    def build(self, lib, rng, quoins=None, name: str = 'Wall', rows=None, interlock: float = 0.0, core: bool = True,
              dress: bool = True) -> list:
        """`interlock` > 0 alternates the wall ends by course: on even courses
        this wall runs on past its start corner and stops short of its end,
        on odd courses the other way, so neighbouring walls bond at corners.
        `dress` False leaves the openings' jambs and arch rings out (the
        second face of a wall whose through-stones another face supplies)."""
        parts = []
        rows = rows or self.courses(rng)
        for row, (y0, h) in enumerate(rows):
            sign = 1.0 if row % 2 == 0 else -1.0
            spans = [(-interlock * sign, self.length - interlock * sign)]
            for x0, x1, kind, o, jamb in self.blocked(y0, h, row):
                spans = [piece for a, b in spans for piece in ((a, min(b, x0)), (max(a, x1), b)) if piece[1] - piece[0] > 0.02]
                if kind == 'jamb' and y0 + h > o.sill and dress:
                    for side, (a, b) in ((-1, (o.x0 - jamb, o.x0)), (1, (o.x1, o.x1 + jamb))):
                        stone = self.stone_in(quoins or lib, rng, a, b, max(y0, o.sill), y0 + h, self.thickness + 0.02, f'{name}_jamb_{row}_{side}')
                        parts.append(stone)
                if kind == 'jamb' and o.window and y0 < o.sill <= y0 + h and dress:
                    parts.append(self.stone_in(quoins or lib, rng, o.x0 - 0.12, o.x1 + 0.12, o.sill - 0.13, o.sill,
                                               self.thickness + 0.04, f'{name}_sill_{row}'))
            for a, b in spans:
                parts += self.fill(lib, rng, a, b, y0, h, row, name)
        for number, o in enumerate(self.openings if dress else ()):
            parts += self.arch(rng, o, f'{name}_arch{number}')
        if core:
            parts.append(self.core(name))
        return parts

    def fill(self, lib, rng, a: float, b: float, y0: float, h: float, row: int, name: str) -> list:
        """Course stones between a and b, the last ones sized to close the run;
        stones touching an arch ring are cut to its curve."""
        lengths, x = [], a
        while b - x > 1e-6:
            length = rng.uniform(*self.stone)
            if b - (x + length) < self.stone[0] * 0.6:
                length = b - x
            lengths.append(length)
            x += length
        result, x = [], a
        for k, length in enumerate(lengths):
            stone = self.stone_in(lib, rng, x, x + length, y0, y0 + h, rng.uniform(0.24, 0.36), f'{name}_{row}_{k}')
            for o in self.openings:
                self.cut_to_ring(stone, o)
            result.append(stone)
            x += length
        return result

    def stone_in(self, lib, rng, x0: float, x1: float, y0: float, y1: float, depth: float, name: str) -> bpy.types.Object:
        joint = rng.uniform(*self.joint)
        stone = lib.place(rng, x1 - x0 - joint, y1 - y0 - joint, depth, name)
        lean = Matrix.Rotation(math.radians(rng.uniform(-1.2, 1.2)), 4, 'Z') @ Matrix.Rotation(math.radians(rng.uniform(-1.0, 1.0)), 4, 'X')
        stone.matrix_world = Matrix.Translation(((x0 + x1) * 0.5, (y0 + y1) * 0.5, rng.uniform(*self.proud))) @ lean @ stone.matrix_world
        return stone

    def cut_to_ring(self, stone: bpy.types.Object, o: Opening) -> None:
        """Trim a course stone that reaches into an arch ring along the ring's
        outer circle (a tangent plane at the stone's nearest point)."""
        outer = o.radius + self.ring + 0.006
        centre = Vector((o.centre, o.cy, 0.0))
        position = stone.matrix_world.translation
        if position.y < o.spring - 0.01:
            return
        offset = Vector((position.x - centre.x, position.y - centre.y, 0.0))
        if offset.length > outer + 0.9:
            return
        direction = offset.normalized() if offset.length > 1e-6 else Vector((0, 1, 0))
        world = [stone.matrix_world @ v.co for v in stone.data.vertices]
        if min((Vector((p.x - centre.x, p.y - centre.y, 0.0))).length for p in world) >= outer:
            return
        stone.data = stone.data.copy()
        bm = bmesh.new()
        bm.from_mesh(stone.data)
        inverse = stone.matrix_world.inverted()
        point = inverse @ (centre + direction * outer)
        normal = (inverse.to_3x3().transposed().inverted() @ -direction).normalized()
        result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=point, plane_no=normal, clear_outer=True)
        edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.edgeloop_fill(bm, edges=edges)
        bm.to_mesh(stone.data)
        bm.free()

    def arch(self, rng, o: Opening, name: str) -> list:
        """Voussoirs round the opening's head, keystone at the crown, through
        the full wall thickness."""
        result = []
        for piece in ring(rng, o, self.ring, self.thickness + 0.02, name):
            # Voussoir axes: arch in x-z, thickness on y. Wall: arch in x-y, depth on -z.
            piece.data.transform(piece.matrix_world)
            piece.data.transform(Matrix.Rotation(math.radians(-90), 4, 'X'))
            piece.matrix_world = Matrix.Translation((o.centre, o.cy, -(self.thickness + 0.02) * 0.5 + 0.012))
            piece['tone'] = rng.uniform(0.8, 1.15)
            result.append(piece)
        return result

    def core(self, name: str) -> bpy.types.Object:
        """Mortar core behind the face with true holes at the openings."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(self.length, self.height, self.thickness - self.recess), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(self.length * 0.5, self.height * 0.5, -(self.thickness + self.recess) * 0.5), verts=bm.verts)
        mesh = bpy.data.meshes.new(f'{name}_core')
        bm.to_mesh(mesh)
        bm.free()
        obj = core.link(bpy.data.objects.new(f'{name}_core', mesh))
        obj['tone'] = -1.0
        for number, o in enumerate(self.openings):
            # The hole stands back by the recess too, so the reveal and soffit
            # show the jamb stones and voussoirs, not the mortar behind them.
            r = self.recess
            o = Opening(o.x0 - r, o.x1 + r, sill=o.sill - r if o.sill > 0 else o.sill, spring=o.spring,
                        rise=o.crown - o.spring + r)
            cutter = bpy.data.meshes.new('cut')
            bm = bmesh.new()
            outline = [Vector((o.x0, o.sill)), Vector((o.x1, o.sill))]
            steps = 24
            for k in range(steps + 1):
                angle = o.a0 + (math.pi - 2.0 * o.a0) * k / steps
                outline.append(Vector((o.centre + math.cos(angle) * o.radius, o.cy + math.sin(angle) * o.radius)))
            outline.append(Vector((o.x0, o.sill)))
            front = [bm.verts.new((p.x, p.y, 0.5)) for p in outline[:-1]]
            back = [bm.verts.new((p.x, p.y, -self.thickness - 0.5)) for p in outline[:-1]]
            bm.faces.new(front)
            bm.faces.new(list(reversed(back)))
            for i in range(len(front)):
                j = (i + 1) % len(front)
                bm.faces.new((front[i], back[i], back[j], front[j]))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bm.to_mesh(cutter)
            bm.free()
            tool = core.link(bpy.data.objects.new(f'{name}_cut{number}', cutter))
            boolean = obj.modifiers.new(f'cut{number}', 'BOOLEAN')
            boolean.operation = 'DIFFERENCE'
            boolean.solver = 'EXACT'
            boolean.object = tool
        if obj.modifiers:
            depsgraph = bpy.context.evaluated_depsgraph_get()
            baked = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
            obj.modifiers.clear()
            obj.data = baked
            for tool in [o for o in bpy.data.objects if o.name.startswith(f'{name}_cut')]:
                bpy.data.objects.remove(tool, do_unlink=True)
        return obj


def clip(obj: bpy.types.Object, point: Vector, normal: Vector) -> bool:
    """Cut away the part of a placed object on the `normal` side of the plane
    (world space) and cap it. False when nothing is left."""
    world = [obj.matrix_world @ v.co for v in obj.data.vertices]
    side = [(p - point).dot(normal) for p in world]
    if max(side) <= 0.0:
        return True
    if min(side) >= 0.0:
        return False
    obj.data = obj.data.copy()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    inverse = obj.matrix_world.inverted()
    result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=inverse @ point,
                                    plane_no=(inverse.to_3x3().transposed().inverted() @ normal).normalized(), clear_outer=True)
    edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.edgeloop_fill(bm, edges=edges)
    bm.to_mesh(obj.data)
    bm.free()
    return True


def ring(rng, o: Opening, depth: float, thickness: float, name: str, stagger: bool = False, triangles: int = 450) -> list:
    """One ring of voussoirs over `o`, an odd count with a keystone at the
    crown, in voussoir axes (arch in x-z about the intrados centre, thickness
    on y). `stagger` uses one stone more, so neighbouring rings of a barrel
    vault break joint."""
    sweep = math.pi - 2.0 * o.a0
    count = max(5, round(sweep * (o.radius + depth * 0.5) / 0.32))
    count += 1 - count % 2
    if stagger:
        count += 2 if count > 5 else 1
        count += 1 - count % 2
    result = []
    for k in range(count):
        result.append(stones.voussoir(rng, inner=o.radius, depth=depth, angle=sweep / count * 0.955, thickness=thickness,
                                      start=o.a0 + k * sweep / count, keystone=(k == count // 2), name=f'{name}_{k}',
                                      triangles=triangles))
    return result


def place(parts: list, origin: Vector, along: Vector, up: Vector) -> None:
    """Move wall-local parts into the world: x -> along, y -> up, z -> out of
    the face (along x up, so a wall runs with its face on the caller's left)."""
    x = along.normalized()
    y = up.normalized()
    z = x.cross(y).normalized()
    frame = Matrix((x, y, z)).transposed().to_4x4()
    frame.translation = origin
    for obj in parts:
        obj.matrix_world = frame @ obj.matrix_world
        obj['frame'] = [*x, *y, *z]
