"""Physics disturbance: build things as designed, then shake, knock and load
them, over a series of seeded attempts, and keep the most believable result.

    disturb.prepare(world_pieces)                # origins at centres, rigid bodies
    disturb.nail(board, stringer, at, strength)  # breakable FIXED joint
    disturb.hinge(post, stringer, at, axis, (-0.17, 0.05), strength)
    disturb.shake(structure, rng, intensity, start=10)
    disturb.roll(at, velocity, radius=0.25)       # heavy stone ball
    result = rigid.settle(pieces, min_frames=disturb.quiet_frame())
    moved = disturb.displacements(pieces, rest)   # translation m, rotation deg

Joint strengths come from `strength(rng, weak_share, piece)`: most joints
hold; a share are rusted or rotten, scaled to the piece's own weight so they
carry it at rest and give way only when shaken. Breaking thresholds are Bullet
impulses per substep (N*s); calibrated with selftest_disturb.py.

Intensity 0 leaves everything as designed; 1 is a strong tremor (about 2 cm,
5-8 Hz for 1.5 s); 2+ tends to collapse weak work. A generator runs attempts
over a spread of intensities and seeds, measures each and picks by score, so
some outputs barely change, some age, and collapses are visible but not chosen.
"""
import math
import struct
import zlib

import bpy
from mathutils import Matrix, Vector

from . import core, rigid

STRONG = 1.0e6
_quiet = 1


def centre(obj: bpy.types.Object) -> None:
    """Move the object origin to its vertex centre so mass and rotation are real."""
    middle = sum((v.co for v in obj.data.vertices), Vector()) / max(len(obj.data.vertices), 1)
    obj.data.transform(Matrix.Translation(-middle))
    obj.matrix_world = obj.matrix_world @ Matrix.Translation(middle)


def orient(obj: bpy.types.Object, a: Vector, b: Vector, up: Vector) -> None:
    """Give a prism built from a to b its own frame (shapes.frame) as the object
    transform, so BOX collision fits the piece and keeps its margin inside;
    hull margins grow outward and push touching pieces apart at rest."""
    from .shapes import frame
    matrix = Matrix.Translation((a + b) * 0.5) @ frame(a, b, up).to_4x4()
    obj.data.transform(matrix.inverted())
    obj.matrix_world = matrix


def load(obj: bpy.types.Object) -> float:
    """The piece's own weight as an impulse per Bullet substep (N*s)."""
    scene = bpy.context.scene
    rate = scene.render.fps / scene.render.fps_base * scene.rigidbody_world.substeps_per_frame
    return obj.rigid_body.mass * 9.81 / rate


def strength(rng, weak_share: float, piece: bpy.types.Object, weak=(2.0, 12.0)) -> float:
    """Breaking impulse for one joint holding `piece`: STRONG, or, for a rusted
    or rotten share, `weak` times the piece's own weight per substep, so a weak
    joint still carries its piece at rest and gives way only when shaken."""
    return load(piece) * rng.uniform(*weak) if rng.random() < weak_share else STRONG


def _constraint(kind: str, a, b, at: Vector, axis: Vector = None, threshold: float = STRONG, collide: bool = False):
    empty = core.link(bpy.data.objects.new(f'{kind}_{a.name}_{b.name}', None))
    empty.empty_display_size = 0.05
    z = (axis or Vector((0, 0, 1))).normalized()
    x = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    y = z.cross(x).normalized()
    x = y.cross(z)
    empty.matrix_world = Matrix.Translation(at) @ Matrix((x, y, z)).transposed().to_4x4()
    core.select_only([empty])
    bpy.ops.rigidbody.constraint_add(type=kind)
    rbc = empty.rigid_body_constraint
    rbc.object1, rbc.object2 = a, b
    # Bullet keeps the pair's collision setting after a break: pieces that
    # rest on each other (board on stringer) must keep colliding.
    rbc.disable_collisions = not collide
    if threshold < STRONG:
        rbc.use_breaking = True
        rbc.breaking_threshold = threshold
    return empty


def nail(a, b, at: Vector, threshold: float = STRONG, collide: bool = True):
    """Rigid joint at `at` that breaks above `threshold`. Keep `collide` for
    pieces that bear on each other; turn it off where the pieces overlap
    (a rail end let into a post)."""
    return _constraint('FIXED', a, b, at, threshold=threshold, collide=collide)


def pin(a, b, at: Vector, threshold: float = STRONG):
    """Ball joint: the pieces stay connected at `at` but may rotate."""
    return _constraint('POINT', a, b, at, threshold=threshold)


def hinge(a, b, at: Vector, axis: Vector, limits=None, threshold: float = STRONG):
    """Hinge about `axis` through `at`, optionally limited to (lower, upper) radians."""
    empty = _constraint('HINGE', a, b, at, axis=axis, threshold=threshold)
    if limits is not None:
        rbc = empty.rigid_body_constraint
        rbc.use_limit_ang_z = True
        rbc.limit_ang_z_lower, rbc.limit_ang_z_upper = limits
    return empty


def kinematic(objects) -> None:
    """Passive bodies that follow keyframed motion (the shaken structure)."""
    for obj in objects:
        obj.rigid_body.kinematic = True


def shake(objects, rng, intensity: float, start: int = 10, seconds: float = 1.5) -> dict:
    """Keyframe a decaying tremor on kinematic `objects` (all move together).
    Returns the parameters for the report."""
    global _quiet
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    frames = int(seconds * fps)
    amplitude = 0.02 * intensity
    waves = [(rng.uniform(5.0, 8.0), rng.uniform(0, math.tau), Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 0.4))).normalized())
             for _ in range(3)]
    rest = {obj.name: obj.location.copy() for obj in objects}
    for frame in range(start - 1, start + frames + 2):
        t = max(0.0, (frame - start) / fps)
        envelope = 0.0 if frame < start or frame > start + frames else math.sin(math.pi * t / seconds) ** 2
        offset = Vector()
        for frequency, phase, direction in waves:
            offset += direction * math.sin(math.tau * frequency * t + phase) * amplitude * envelope / len(waves)
        for obj in objects:
            obj.location = rest[obj.name] + offset
            obj.keyframe_insert('location', frame=frame)
    _quiet = max(_quiet, start + frames + 2)
    return {'intensity': round(intensity, 3), 'amplitude_m': round(amplitude, 4), 'seconds': seconds,
            'frequencies_hz': [round(w[0], 2) for w in waves]}


def roll(at: Vector, velocity: Vector, radius: float = 0.25, density: float = 2400.0, start: int = 12):
    """A stone ball launched at `velocity` (m/s): kinematic for two frames to
    give Bullet its speed, then free. Remove it before export."""
    global _quiet
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=radius, location=at)
    ball = bpy.context.active_object
    ball.name = 'DisturbBall'
    rigid.body(ball, mass=4.0 / 3.0 * math.pi * radius ** 3 * density, friction=0.7, shape='SPHERE', damping=(0.02, 0.05))
    ball.rigid_body.kinematic = True
    for frame, offset in ((start - 1, 0), (start, 0), (start + 1, 1)):
        ball.location = at + velocity * (offset / fps)
        ball.keyframe_insert('location', frame=frame)
        ball.rigid_body.keyframe_insert('kinematic', frame=frame)
    ball.rigid_body.kinematic = False
    ball.rigid_body.keyframe_insert('kinematic', frame=start + 2)
    _quiet = max(_quiet, start + 2 + int(4 * fps))
    return ball


def quiet_frame() -> int:
    """First frame after every scheduled disturbance; settle no earlier than this."""
    return _quiet + 10


def reset() -> None:
    global _quiet
    _quiet = 1


def rest_pose(objects) -> dict:
    return {obj.name: obj.matrix_world.copy() for obj in objects}


def displacements(objects, rest: dict) -> dict:
    """Per object: (translation m, rotation deg) between rest and current pose."""
    result = {}
    for obj in objects:
        before, after = rest[obj.name], obj.matrix_world
        move = (after.translation - before.translation).length
        delta = before.to_quaternion().rotation_difference(after.to_quaternion())
        # q and -q are the same rotation: report the short way round.
        result[obj.name] = (move, math.degrees(min(delta.angle, math.tau - delta.angle)))
    return result


def write_png(path, rgb) -> None:
    """8-bit RGB PNG from a top-down HxWx3 uint8 numpy array."""
    height, width, _ = rgb.shape
    raw = b''.join(b'\x00' + rgb[y].tobytes() for y in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def render(eye: Vector, target: Vector, size=(480, 270), samples: int = 16, lens: float = 28.0):
    """Cycles view of the current scene as an HxWx3 uint8 array (for contact sheets)."""
    import tempfile
    from pathlib import Path

    import numpy
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    if scene.world is None:
        scene.world = bpy.data.worlds.new('DisturbWorld')
    camera = bpy.data.objects.get('DisturbCamera') or core.link(bpy.data.objects.new('DisturbCamera', bpy.data.cameras.new('DisturbCamera')))
    camera.data.lens = lens
    camera.location = eye
    camera.rotation_euler = (target - eye).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    sun = bpy.data.objects.get('DisturbKey') or core.link(bpy.data.objects.new('DisturbKey', bpy.data.lights.new('DisturbKey', 'SUN')))
    sun.data.energy = 3.0
    sun.rotation_euler = Vector((0.4, -0.5, -0.75)).to_track_quat('-Z', 'Y').to_euler()
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'view.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(str(path))
        pixels = numpy.empty(size[0] * size[1] * 4, dtype=numpy.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
    rgb = pixels.reshape(size[1], size[0], 4)[::-1, :, :3]
    return numpy.clip(rgb * 255.0 + 0.5, 0, 255).astype(numpy.uint8)


def frame_border(rgb, chosen: bool):
    """Mark the chosen attempt in a contact sheet with a 4 px bright border."""
    if chosen:
        rgb = rgb.copy()
        rgb[:4, :], rgb[-4:, :], rgb[:, :4], rgb[:, -4:] = (255, 196, 40), (255, 196, 40), (255, 196, 40), (255, 196, 40)
    return rgb
