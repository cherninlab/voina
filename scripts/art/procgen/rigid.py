"""Rigid-body drops baked into static meshes (Blender's Bullet world).

    world = rigid.world()
    for obj in pieces:
        rigid.body(obj, mass=rigid.mass(obj, 2400.0))
    for obj in floor_and_walls:
        rigid.body(obj, passive=True, shape='BOX')
    result = rigid.settle(pieces)          # steps frames until every piece is still
    rigid.apply(pieces)                    # bake the settled pose into mesh data
    gaps = rigid.contact_gaps(pieces, floor_and_walls)
    depth = rigid.penetration(pieces, floor_and_walls)

Moving pieces use their mesh's convex hull, so a closed piece cannot sink into
a neighbour by more than the solver tolerance even where the mesh is concave.
Bullet keeps hulls `margin` apart; that shows as a gap under every stone, so the
default margin is 2 mm. Passive boxes keep their margin inside the box.

Settling is measured, not assumed: every frame the eight bound-box corners of
each piece are moved through its new world matrix and compared with the last
frame, so rotation counts as well as translation. The checks after `apply` are
measured on the final meshes with BVH trees.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import core

SKEW = Vector((0.1234, 0.3417, 0.9316)).normalized()


def world(fps: int = 30, substeps: int = 20, iterations: int = 40, frame_end: int = 1800):
    """Bullet world stepping fps * substeps times per second (600 Hz by default)."""
    scene = bpy.context.scene
    if scene.rigidbody_world is None:
        bpy.ops.rigidbody.world_add()
    rbw = scene.rigidbody_world
    scene.render.fps, scene.render.fps_base = fps, 1.0
    rbw.substeps_per_frame = substeps
    rbw.solver_iterations = iterations
    rbw.use_split_impulse = True  # penetration recovery without added bounce
    rbw.point_cache.frame_start = 1
    rbw.point_cache.frame_end = frame_end
    scene.frame_start, scene.frame_end = 1, frame_end
    scene.frame_set(1)
    return rbw


def volume(obj: bpy.types.Object) -> float:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    value = abs(bm.calc_volume(signed=False))
    bm.free()
    return value


def mass(obj: bpy.types.Object, density: float) -> float:
    """Mass in kg from the closed mesh volume (density in kg/m^3)."""
    return max(0.05, volume(obj) * density)


def body(obj: bpy.types.Object, passive: bool = False, mass: float = 1.0, friction: float = 0.8,
         restitution: float = 0.0, margin: float = 0.002, damping=(0.1, 0.35), shape: str = 'CONVEX_HULL'):
    """Add a rigid body. Moving bodies sleep only below 1 cm/s and 0.02 rad/s."""
    core.select_only([obj])
    bpy.ops.rigidbody.object_add(type='PASSIVE' if passive else 'ACTIVE')
    rb = obj.rigid_body
    rb.collision_shape = shape
    rb.friction = friction
    rb.restitution = restitution
    rb.use_margin = True
    rb.collision_margin = margin
    if not passive:
        rb.mass = mass
        rb.linear_damping, rb.angular_damping = damping
        rb.use_deactivation = True
        rb.deactivate_linear_velocity = 0.01
        rb.deactivate_angular_velocity = 0.02
    return rb


def _probes(obj: bpy.types.Object) -> list:
    return [Vector(corner) for corner in obj.bound_box]


def settle(objects, threshold: float = 0.01, hold: int = 15, min_frames: int = 45, max_frames: int = 1500) -> dict:
    """Step the simulation from frame 1 until the fastest bound-box corner of any
    piece moves slower than `threshold` m/s for `hold` consecutive frames.
    Returns the frame, residual speed and the per-frame maximum speeds."""
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    probes = {obj.name: _probes(obj) for obj in objects}
    scene.frame_set(1)
    previous = {obj.name: [obj.matrix_world @ p for p in probes[obj.name]] for obj in objects}
    speeds, calm, frame, speed, fastest = [], 0, 1, math.inf, None
    for frame in range(2, max_frames + 1):
        scene.frame_set(frame)
        speed, fastest = 0.0, None
        for obj in objects:
            current = [obj.matrix_world @ p for p in probes[obj.name]]
            moved = max((a - b).length for a, b in zip(current, previous[obj.name])) * fps
            if moved > speed:
                speed, fastest = moved, obj.name
            previous[obj.name] = current
        speeds.append(round(speed, 5))
        calm = calm + 1 if speed < threshold else 0
        if frame >= min_frames and calm >= hold:
            break
    return {'settled': calm >= hold, 'frame': frame, 'seconds': round(frame / fps, 3),
            'residual_speed_m_s': speed, 'last_mover': fastest, 'threshold_m_s': threshold,
            'max_speed_per_frame': speeds}


def apply(objects) -> None:
    """Freeze the current simulated pose into each mesh (world space, identity
    object transform) and remove the rigid-body world."""
    matrices = {obj.name: obj.matrix_world.copy() for obj in objects}
    if bpy.context.scene.rigidbody_world is not None:
        bpy.ops.rigidbody.world_remove()
    for obj in objects:
        obj.data.transform(matrices[obj.name])
        obj.matrix_world = Matrix.Identity(4)
        obj.data.update()


def _world_points(obj: bpy.types.Object) -> list:
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


class Shape:
    """World-space BVH, AABB and sample points (vertices, edge midpoints, face centres)."""

    def __init__(self, obj: bpy.types.Object):
        self.name = obj.name
        verts = _world_points(obj)
        polys = [tuple(p.vertices) for p in obj.data.polygons]
        self.bvh = BVHTree.FromPolygons(verts, polys)
        self.samples = list(verts)
        self.samples += [(verts[e.vertices[0]] + verts[e.vertices[1]]) * 0.5 for e in obj.data.edges]
        self.samples += [sum((verts[i] for i in p), Vector()) / len(p) for p in polys]
        self.low = Vector(tuple(min(v[k] for v in verts) for k in range(3)))
        self.high = Vector(tuple(max(v[k] for v in verts) for k in range(3)))

    def near(self, other: 'Shape', pad: float) -> bool:
        return all(self.low[k] - pad <= other.high[k] and other.low[k] - pad <= self.high[k] for k in range(3))

    def inside(self, co: Vector) -> bool:
        """Ray parity along a skewed direction; the mesh must be closed."""
        count, origin = 0, co.copy()
        for _ in range(256):
            hit = self.bvh.ray_cast(origin, SKEW)
            if hit[0] is None:
                break
            count += 1
            origin = hit[0] + SKEW * 1e-6
        return count % 2 == 1


def _gap(a: Shape, b: Shape, limit: float) -> float:
    """Closest sample-to-surface distance between two shapes that do not overlap."""
    best = limit
    for source, target in ((a, b), (b, a)):
        for co in source.samples:
            hit = target.bvh.find_nearest(co, best)
            if hit[0] is not None and hit[3] < best:
                best = hit[3]
    return best


def contact_gaps(objects, supports=(), limit: float = 0.25) -> dict:
    """Distance from each piece to its nearest neighbour or support (0 if they
    touch or overlap). A resting piece should be within a few millimetres of
    something. Values are upper bounds: only sample points are measured."""
    bpy.context.view_layer.update()
    shapes = [Shape(obj) for obj in objects]
    others = shapes + [Shape(obj) for obj in supports]
    gaps = {}
    for a in shapes:
        best = limit
        for b in others:
            if b is a or not a.near(b, best):
                continue
            if a.bvh.overlap(b.bvh):
                best = 0.0
                break
            best = min(best, _gap(a, b, best))
        gaps[a.name] = best
    return gaps


def penetration(objects, supports=()) -> dict:
    """Deepest sample point of one piece inside another piece or support, in metres.
    Returns {'max_m': depth, 'pair': [a, b], 'pairs_touching': n}."""
    bpy.context.view_layer.update()
    shapes = [Shape(obj) for obj in objects]
    fixed = [Shape(obj) for obj in supports]
    deepest, pair, touching = 0.0, None, 0
    for i, a in enumerate(shapes):
        for b in shapes[i + 1:] + fixed:
            if not a.near(b, 0.0) or not a.bvh.overlap(b.bvh):
                continue
            touching += 1
            for source, target in ((a, b), (b, a)):
                for co in source.samples:
                    if target.inside(co):
                        hit = target.bvh.find_nearest(co)
                        if hit[0] is not None and hit[3] > deepest:
                            deepest, pair = hit[3], [source.name, target.name]
    return {'max_m': deepest, 'pair': pair, 'pairs_touching': touching}
