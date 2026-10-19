"""Prepare the CC-BY "Collapsed Gothic Chapel Ruin" (Pigcraft, Sketchfab) for the church site.

blender --background --factory-startup --python scripts/process_chapel_ruin.py -- SOURCE/scene.gltf OUTPUT_DIR

The download is 22 chunks of one 1.8M-triangle mesh about 1 m across, with three identical UV sets
and 4096 px maps. This joins and welds the chunks, keeps one UV set, decimates to about 180k
triangles, bakes a uniform x12 real-world scale with the origin on the ground at the centre of the
collapsed front arch (the front faces +Z in Godot), adds a low-poly "-colonly" collision copy for
Godot's importer, and caps the maps at 2048 px PNG (JPEG is not tracked by LFS here).
"""
import bpy
import bmesh
import json
import sys
import tempfile
from pathlib import Path
from mathutils import Matrix, Vector

SCALE = 12.0
VISUAL_TRIANGLES = 180000
COLLISION_TRIANGLES = 8000
MAX_TEXTURE = 2048

source, output = (Path(argument) for argument in sys.argv[sys.argv.index('--') + 1:][:2])
output.mkdir(parents=True, exist_ok=True)
cache = tempfile.TemporaryDirectory(prefix='chapel-ruin-textures-')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))

meshes = [item for item in bpy.context.scene.objects if item.type == 'MESH']
source_triangles = sum(sum(len(polygon.vertices) - 2 for polygon in item.data.polygons) for item in meshes)
bpy.ops.object.select_all(action='DESELECT')
for item in meshes:
    item.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
ruin = bpy.context.view_layer.objects.active
ruin.name = 'ChapelRuin'
for item in [item for item in bpy.context.scene.objects if item.type != 'MESH']:
    bpy.data.objects.remove(item, do_unlink=True)

# The chunks repeat their border vertices; weld them so decimation cannot open seams.
mesh = bmesh.new()
mesh.from_mesh(ruin.data)
bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=1e-5)
mesh.to_mesh(ruin.data)
mesh.free()

# All three UV sets hold the same coordinates; the normal map pointed at the second one.
first = ruin.data.uv_layers[0].name
for material in ruin.data.materials:
    for node in material.node_tree.nodes:
        if node.type == 'UVMAP':
            node.uv_map = first
while len(ruin.data.uv_layers) > 1:
    ruin.data.uv_layers.remove(ruin.data.uv_layers[-1])

# Real-world size, origin on the ground under the middle of the front (Blender -Y) face.
corners = [Vector(corner) for corner in ruin.bound_box]
low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
anchor = Vector(((low.x + high.x) * 0.5, low.y, low.z))
ruin.data.transform(Matrix.Scale(SCALE, 4) @ Matrix.Translation(-anchor))
ruin.data.update()

def triangles(item: bpy.types.Object) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in item.data.polygons)

collision = ruin.copy()
collision.data = ruin.data.copy()
collision.data.materials.clear()
collision.name = 'ChapelRuinCollision-colonly'
bpy.context.scene.collection.objects.link(collision)

for item, target in ((ruin, VISUAL_TRIANGLES), (collision, COLLISION_TRIANGLES)):
    modifier = item.modifiers.new('Decimate', 'DECIMATE')
    modifier.decimate_type = 'COLLAPSE'
    modifier.ratio = min(1.0, target / triangles(item))
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = item
    bpy.ops.object.modifier_apply(modifier=modifier.name)
while len(collision.data.uv_layers) > 0:
    collision.data.uv_layers.remove(collision.data.uv_layers[0])

for image in bpy.data.images:
    # The importer packs the maps; reloads and the exporter would read the packed originals.
    image.reload()
    if image.size[0] == 0:
        continue
    if max(image.size) > MAX_TEXTURE:
        factor = MAX_TEXTURE / max(image.size)
        image.scale(round(image.size[0] * factor), round(image.size[1] * factor))
    resized = Path(cache.name) / (Path(image.filepath).stem.replace('tripo_mat_f45cd38f', 'chapel_ruin') + '.png')
    image.file_format = 'PNG'
    image.save(filepath=str(resized))
    if image.packed_file:
        image.unpack(method='REMOVE')
    image.filepath = str(resized)
    image.reload()

corners = [Vector(corner) for corner in ruin.bound_box]
size = Vector((max(c.x for c in corners) - min(c.x for c in corners), max(c.y for c in corners) - min(c.y for c in corners), max(c.z for c in corners) - min(c.z for c in corners)))
bpy.ops.export_scene.gltf(
    filepath=str(output / 'chapel_ruin.gltf'), export_format='GLTF_SEPARATE', export_texture_dir='textures',
    export_image_format='AUTO', export_yup=True, export_apply=True, export_tangents=False,
    export_animations=False, export_cameras=False, export_lights=False)
summary = {
    'source_triangles': source_triangles,
    'visual_triangles': triangles(ruin),
    'collision_triangles': triangles(collision),
    'scale': SCALE,
    # Godot axes: x across the front, y up, z depth (the front is the +Z face at z = 0).
    'size_m': [round(size.x, 2), round(size.z, 2), round(size.y, 2)],
    'textures': sorted(f'{image.name} {image.size[0]}x{image.size[1]}' for image in bpy.data.images if image.size[0] > 0),
}
print('CHAPEL_RUIN', json.dumps(summary))
(output / 'processing.json').write_text(json.dumps(summary, indent=2) + '\n')
