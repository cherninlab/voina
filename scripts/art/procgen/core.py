"""Arguments, version pin, scene reset, seeded randomness, axes and reports."""
import hashlib
import json
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

BLENDER_VERSION = (5, 2)
ROOT = Path(__file__).resolve().parents[3]


def args() -> list:
    """Arguments after `--` on the Blender command line."""
    return sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []


def require_blender() -> None:
    found = tuple(bpy.app.version[:2])
    if found != BLENDER_VERSION:
        raise SystemExit(f'procgen: Blender {BLENDER_VERSION[0]}.{BLENDER_VERSION[1]} required, found {bpy.app.version_string}')


def empty_scene() -> bpy.types.Scene:
    """Factory-empty scene in metres. Call once at the top of a generator."""
    require_blender()
    sys.dont_write_bytecode = True
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    return scene


def rng(seed: int, *keys) -> random.Random:
    """Independent stream per (seed, keys); stable across runs and Python versions."""
    digest = hashlib.sha256(json.dumps([seed, *keys], default=str).encode()).digest()
    return random.Random(int.from_bytes(digest[:8], 'little'))


def to_blender(godot) -> Vector:
    """Godot (x, y up, z) -> Blender (x, y, z up). The glTF exporter applies the inverse."""
    return Vector((godot[0], -godot[2], godot[1]))


def to_godot(blender) -> list:
    return [blender[0], blender[2], -blender[1]]


def relative(path) -> str:
    """Repo-relative POSIX path for reports; absolute paths leak worktrees."""
    path = Path(path).resolve()
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def sha256(path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_report(path, data: dict, files=()) -> dict:
    """JSON report with Blender version, relative paths and file hashes."""
    report = {'blender': bpy.app.version_string, **data,
              'files': {relative(f): sha256(f) for f in sorted(Path(p) for p in files)}}
    Path(path).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    return report


TRASH = []


def discard(obj: bpy.types.Object) -> None:
    """Take an object out of the scene now and delete it later in one batch:
    bpy.data.objects.remove remaps every ID in the file, so removing objects
    one by one from a scene of tens of thousands of stones is quadratic."""
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    TRASH.append(obj)


def flush_trash() -> None:
    if TRASH:
        bpy.data.batch_remove(TRASH)
        TRASH.clear()


def link(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(obj)
    return obj


def select_only(objects) -> None:
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
