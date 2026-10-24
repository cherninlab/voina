"""Material fracture: split a closed mesh into Voronoi chunks and glue them
with breakable joints, so physics can chip, crack, topple or splinter it.

    cells = fracture.voronoi(column, fracture.seeds(column, rng, 30, focus=impact))
    glue = fracture.glue(cells, rng, 'stone')
    # ...rigid bodies, shake/roll from disturb.py, rigid.settle...

Materials differ in how cells are shaped and how strongly they hold:
    stone   compact cells, strong glue with little spread (brittle chunks)
    brick   cells flattened into courses, weaker glue across bed joints
    plaster thin skin cells, weak glue (flakes)
    wood    cells stretched 6x along the grain, weak across it (splinters)
Glue thresholds are multiples of the lighter chunk's weight per substep, like
disturb.strength, so a glued piece holds at rest and fails only under load.
Cut faces get Color.B = 1 (fresh break) for shaders that show raw stone/wood.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import core, disturb, rigid

CRACK = 0.0015

MATERIALS = {
    # grain scale (local x, y, z), glue strength range in chunk weights, seed bias
    'stone': {'grain': (1.0, 1.0, 1.0), 'glue': (60.0, 140.0)},
    'brick': {'grain': (1.0, 1.0, 0.45), 'glue': (25.0, 70.0)},
    'plaster': {'grain': (1.0, 1.0, 1.0), 'glue': (8.0, 25.0)},
    'wood': {'grain': (1.0, 1.0, 6.0), 'glue': (12.0, 40.0)},
}


def seeds(obj: bpy.types.Object, rng, count: int, focus: Vector = None, spread: float = None) -> list:
    """`count` points inside the closed mesh. With `focus`, points crowd around
    it (an impact makes small chips near the hit and big chunks far away)."""
    shape = rigid.Shape(obj)
    low, high = shape.low, shape.high
    points = []
    tries = 0
    while len(points) < count and tries < count * 400:
        tries += 1
        if focus is not None and rng.random() < 0.65:
            radius = spread or (high - low).length * 0.25
            p = focus + Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))) * radius * 0.5
        else:
            p = Vector(tuple(rng.uniform(low[k], high[k]) for k in range(3)))
        if all(low[k] <= p[k] <= high[k] for k in range(3)) and shape.inside(p):
            points.append(p)
    return points


def voronoi(obj: bpy.types.Object, points: list, grain: Matrix = None, name: str = None) -> list:
    """Voronoi cells of `obj` (world space mesh) around `points`. `grain` maps
    world to a metric space (scale > 1 along an axis stretches cells along it).
    Returns centred cell objects; the source object is left untouched."""
    grain = grain or Matrix.Identity(3)
    inverse = grain.inverted()
    mapped = [grain @ p for p in points]
    source = obj.data.copy()
    source.transform(obj.matrix_world)
    cells = []
    for i, p in enumerate(points):
        bm = bmesh.new()
        bm.from_mesh(source)
        colors = bm.loops.layers.float_color.get('Color')
        for j, q in enumerate(points):
            if i == j or not bm.verts:
                continue
            middle = (mapped[i] + mapped[j]) * 0.5
            normal = grain.transposed() @ (mapped[j] - mapped[i])
            if normal.length < 1e-9:
                continue
            result = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                            plane_co=inverse @ middle, plane_no=normal.normalized(), clear_outer=True)
            cut = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
            if cut:
                filled = bmesh.ops.edgeloop_fill(bm, edges=cut)
                for face in filled['faces']:
                    for loop in face.loops:
                        if colors is not None:
                            loop[colors] = (1.0, 0.5, 1.0, 1.0)
        if len(bm.verts) < 4:
            bm.free()
            continue
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        # A hairline crack between cells: touching hulls would start overlapped
        # and blast apart; glue holds them, collisions take over once it breaks.
        middle = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        for v in bm.verts:
            offset = v.co - middle
            if offset.length > CRACK * 2:
                v.co -= offset.normalized() * CRACK
        mesh = bpy.data.meshes.new(f'{name or obj.name}_cell{i}')
        bm.to_mesh(mesh)
        bm.free()
        cell = core.link(bpy.data.objects.new(mesh.name, mesh))
        disturb.centre(cell)
        cells.append(cell)
    bpy.data.meshes.remove(source)
    return cells


def neighbours(cells: list, gap: float = 0.006) -> list:
    """Pairs of cells whose surfaces touch (shared cut faces)."""
    bpy.context.view_layer.update()
    shapes = [rigid.Shape(c) for c in cells]
    pairs = []
    for a in range(len(cells)):
        for b in range(a + 1, len(cells)):
            if not shapes[a].near(shapes[b], gap):
                continue
            touching = 0
            for co in shapes[a].samples[::3]:
                hit = shapes[b].bvh.find_nearest(co, gap)
                if hit[0] is not None:
                    touching += 1
                    if touching >= 3:
                        pairs.append((cells[a], cells[b]))
                        break
    return pairs


def glue(cells: list, rng, material: str, weakness: float = 1.0) -> list:
    """Breakable FIXED joints between touching cells (cells must already be
    rigid bodies). `weakness` > 1 divides strength (rot, frost, old mortar)."""
    low, high = MATERIALS[material]['glue']
    joints = []
    for a, b in neighbours(cells):
        lighter = a if a.rigid_body.mass < b.rigid_body.mass else b
        threshold = disturb.load(lighter) * rng.uniform(low, high) / weakness
        at = (a.matrix_world.translation + b.matrix_world.translation) * 0.5
        joints.append(disturb.nail(a, b, at, threshold, collide=True))
    return joints


def grain(material: str, axis: Vector = Vector((0, 0, 1))) -> Matrix:
    """World-to-metric matrix stretching cells along `axis` for the material."""
    scale = MATERIALS[material]['grain']
    z = axis.normalized()
    x = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    y = z.cross(x).normalized()
    x = y.cross(z)
    frame = Matrix((x, y, z))  # rows: world -> local
    # Distances along a stretched axis count less, so cells grow long that way.
    shrink = Matrix.Diagonal(Vector((1.0 / scale[0], 1.0 / scale[1], 1.0 / scale[2])))
    return frame.transposed() @ shrink @ frame
