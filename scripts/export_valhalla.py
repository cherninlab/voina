"""Export selected, user-authorized Valhalla roots; run in Blender with source blend open.

blender --background --factory-startup --disable-autoexec SOURCE.blend --python scripts/export_valhalla.py -- OUTPUT_DIR
"""
import bpy
from pathlib import Path
from mathutils import Vector
import sys, json, tempfile

output = Path(sys.argv[sys.argv.index('--') + 1])
output.mkdir(parents=True, exist_ok=True)
source = Path(bpy.data.filepath)
texture_root = source.parent / 'KB3DTextures'
cache = tempfile.TemporaryDirectory(prefix='valka-valhalla-textures-')
for image in bpy.data.images:
    target = texture_root / Path(image.filepath.replace('\\', '/')).name
    if target.exists() and not image.packed_file:
        image.filepath = str(target)
        image.reload()
    if max(image.size) > 2048:
        factor = 2048 / max(image.size)
        image.scale(max(1, round(image.size[0] * factor)), max(1, round(image.size[1] * factor)))

    if image.source == 'FILE' and image.size[0] > 0:
        image.filepath_raw = str(Path(cache.name) / (image.name.split('.')[0] + '.png'))
        image.file_format = 'PNG'
        image.save()

roots = {
     'well': 'Well_A', 'wagon': 'Wagon_A', 'barrel': 'Barrel_A',
    'shield': 'Shield_A', 'brazier': 'Torch_A', 'dummy': 'PractiseDummy_A',
    'rock_a': 'Rock_A', 'rock_b': 'Rock_B', 'rock_c': 'Rock_C',
    'cottage_a': 'BldgSM_A', 'cottage_f': 'BldgSM_F', 'cottage_h': 'BldgSM_H',
}
if '--only-terrain' in sys.argv:
    roots = {}
report = json.loads((output / 'provenance.json').read_text())['assets'] if '--only-terrain' in sys.argv else []
for name, identifier in roots.items():
    root = bpy.data.objects['KB3D_VAL_' + identifier + '_grp']
    children = [root] + list(root.children_recursive)
    # No skeleton/skull content is included, even as building dressing.
    children = [o for o in children if not any(t in o.name.lower() for t in ('skull', 'skeleton', 'bone'))]
    meshes = [o for o in children if o.type == 'MESH']
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low = Vector([min(c[a] for c in corners) for a in range(3)])
    high = Vector([max(c[a] for c in corners) for a in range(3)])
    original = root.matrix_world.copy()
    root.location -= Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in children:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(output / (name + '.gltf')), export_format='GLTF_SEPARATE', use_selection=True, export_texture_dir='textures', export_cameras=False, export_lights=False, export_animations=False)
    report.append({'file': name + '.gltf', 'source_root': root.name, 'mesh_count': len(meshes), 'polygons': sum(len(o.data.polygons) for o in meshes)})
    root.matrix_world = original
# Shared terrain maps are saved from the same downsampled source pixels.
for image in bpy.data.images:
    if any(image.name.startswith('KB3D_VHL_' + key) for key in ('GrassGround_', 'StoneFloor_')) and any(image.name.endswith(suffix + '.png') for suffix in ('basecolor', 'normal', 'roughness')):
        target = output / 'textures' / image.name
        target.parent.mkdir(exist_ok=True)
        image.filepath_raw = str(target)
        image.save()
(output / 'provenance.json').write_text(json.dumps({
    'pack': 'KitBash3D Valhalla, user-supplied Blender source',
    'source_filename': source.name,
    'authorization': 'User explicitly authorized using, editing and integrating parts of this folder in this conversation on 2026-10-17.',
    'license_note': 'Third-party commercial assets, not CC0. No upstream license text was bundled in the supplied folder; user authorization is recorded without asserting broader redistribution rights.',
    'processing': 'Selected roots, no animations/cameras/lights/skeletons/skulls; texture dimensions capped at 2048; native glTF PBR export.',
    'assets': report,
}, indent=2) + '\n')
print('VALHALLA_EXPORTED', json.dumps(report))
