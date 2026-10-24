"""GLB export for Godot: Y up, metres, UVs, the "Color" attribute as COLOR_0.

Node names carry Godot import hints: a mesh named "Name-colonly" becomes only a
collision shape, "Name-convcolonly" a convex one. Custom properties on
objects travel as glTF extras for sockets and metadata.
"""
from pathlib import Path

import bpy

from . import core


def collision_copy(obj: bpy.types.Object, kind: str = 'colonly') -> bpy.types.Object:
    """Duplicate `obj` as a Godot collision-only node (kind: colonly or convcolonly)."""
    copy = obj.copy()
    copy.data = obj.data.copy()
    copy.name = f'{obj.name}-{kind}'
    return core.link(copy)


def glb(objects, path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    core.select_only(list(objects))
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format='GLB', use_selection=True,
        export_yup=True, export_apply=True, export_texcoords=True, export_normals=True,
        export_vertex_color='NAME', export_vertex_color_name='Color', export_all_vertex_colors=False,
        export_materials='NONE', export_animations=False, export_extras=True)
    return path
