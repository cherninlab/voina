"""Blender background: clean local generated meshes and export three LODs.

blender -b --python scripts/art/prepare_dungeon_kit.py -- manifest.json output_dir
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bmesh
import numpy as np
import bpy
from mathutils import Vector


def paint_reference(obj, reference: str) -> None:
    # Reuse the reconstruction view's colour, with physical detail normals added in Godot.
    # ponytail: frontal projection also colours hidden faces; multi-view baking is a later art pass.
    image = bpy.data.images.load(reference, check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    pixels = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(image.size[1], image.size[0], 4)
    rows, columns = np.nonzero(pixels[:, :, 3] > 0.2)
    xyz = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float32)
    xy = xyz[:, [0, 2]]
    xy = (xy - xy.min(axis=0)) / np.maximum(xy.max(axis=0) - xy.min(axis=0), 0.0001)
    xs = np.rint(columns.min() + xy[:, 0] * (columns.max()-columns.min())).astype(int)
    ys = np.rint(rows.min() + xy[:, 1] * (rows.max()-rows.min())).astype(int)
    # Read broad source-colour variation; projecting studio highlights as full albedo
    # produces false edges on reconstructed surfaces, so preserve the calibrated PBR.
    colors = np.zeros((len(xs), 4), dtype=np.float32)
    weights = np.zeros(len(xs), dtype=np.float32)
    radius = max(2, int(min(image.size) * 0.025))
    for dx, dy in [(0,0),(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,1),(-1,1),(1,-1)]:
        samples = pixels[np.clip(ys + dy*radius, 0, image.size[1]-1), np.clip(xs + dx*radius, 0, image.size[0]-1)]
        colors[:, :3] += samples[:, :3] * samples[:, 3:4]
        weights += samples[:, 3]
    opaque = pixels[:, :, 3] > 0.8
    median = np.median(pixels[opaque, :3], axis=0)
    colors[:, :3] /= np.maximum(weights[:, None], 0.01)
    colors[weights < 0.1, :3] = median
    colors[:, :3] = np.clip(colors[:, :3] / np.maximum(median, 0.05), 0.75, 1.12) * 0.88
    colors[:, 3] = 1
    for attribute in list(obj.data.color_attributes):
        obj.data.color_attributes.remove(attribute)
    layer = obj.data.color_attributes.new(name='ReferenceColor', type='FLOAT_COLOR', domain='POINT')
    layer.data.foreach_set('color', colors.ravel())
    obj.data.color_attributes.active_color = layer
    obj.data.color_attributes.render_color_index = 0
    if Path(reference).stem == 'window_bay':
        # The reference looks at the left face; match that view instead of flattening its colour.
        yaw, pitch = math.radians(38), math.radians(7)
        projected = np.column_stack((xyz[:, 0]*math.cos(yaw)-xyz[:, 1]*math.sin(yaw),
            xyz[:, 0]*math.sin(pitch)*math.sin(yaw)+xyz[:, 2]*math.cos(pitch)+xyz[:, 1]*math.sin(pitch)*math.cos(yaw)))
        projected = (projected-projected.min(axis=0))/np.maximum(projected.max(axis=0)-projected.min(axis=0), 0.0001)
        projected[:, 0] = (columns.min()+projected[:, 0]*(columns.max()-columns.min()))/image.size[0]
        projected[:, 1] = (rows.min()+projected[:, 1]*(rows.max()-rows.min()))/image.size[1]
        loop_vertices = np.array([loop.vertex_index for loop in obj.data.loops])
        layer_uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name='ReferenceView')
        layer_uv.data.foreach_set('uv', projected[loop_vertices].astype(np.float32).ravel())
    bpy.data.images.remove(image)


def prepare(item: dict, output: Path) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=item['output'])
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    assert meshes, item['id']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    source_triangles = len(obj.data.polygons)

    # Remove tiny disconnected extraction islands, keeping meaningful rubble pieces.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    unvisited = set(bm.verts)
    components = []
    while unvisited:
        pending = [unvisited.pop()]
        component = []
        while pending:
            vertex = pending.pop()
            component.append(vertex)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other in unvisited:
                    unvisited.remove(other)
                    pending.append(other)
        components.append(component)
    cutoff = max(len(group) for group in components) * 0.01
    discarded = [v for group in components if len(group) < cutoff for v in group]
    if discarded:
        bmesh.ops.delete(bm, geom=discarded, context='VERTS')
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()

    coords = [vertex.co.copy() for vertex in obj.data.vertices]
    low = Vector(tuple(min(p[i] for p in coords) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in coords) for i in range(3)))
    factor = item['height_m'] / (high.z-low.z)
    center = Vector(((low.x+high.x)*0.5, (low.y+high.y)*0.5, low.z))
    for vertex in obj.data.vertices:
        vertex.co = (vertex.co-center)*factor
    obj.name = item['id']
    obj.data.materials.clear()
    material = bpy.data.materials.new(item['material'])
    material.diffuse_color = (0.55, 0.52, 0.47, 1)
    material.roughness = 0.8
    obj.data.materials.append(material)

    paint_reference(obj, item['input'])
    paths = []
    for level, target in enumerate([item['faces'], max(5000, item['faces']//3), 2500]):
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new('Simplify', 'DECIMATE')
        modifier.ratio = min(1.0, target/max(1,len(obj.data.polygons)))
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.set_sharp_from_angle(angle=math.radians(42))
        path = output/f"{item['id']}_lod{level}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
            use_selection=True, export_normals=True, export_materials='EXPORT', export_vertex_color='NAME', export_vertex_color_name='ReferenceColor', export_all_vertex_colors=False)
        paths.append({'path': path.name, 'triangles': len(obj.data.polygons),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return dict(id=item['id'], material=item['material'], height_m=item['height_m'],
        source_triangles=source_triangles, removed_island_vertices=len(discarded),
        lods=paths)


parser = argparse.ArgumentParser()
parser.add_argument('manifest',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--only', default='')
parser.add_argument('--paint-only', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
args.output.mkdir(parents=True,exist_ok=True)
manifest = json.loads(args.manifest.read_text())
selected = set(args.only.split(',')) if args.only else None
report = []
for item in manifest:
    if (selected is None or item['id'] in selected) and Path(item['output']).is_file():
        if args.paint_only:
            result = next(entry for entry in json.loads((args.output.parent/'preparation.json').read_text()) if entry['id'] == item['id'])
            for lod in result['lods']:
                path = args.output/lod['path']
                bpy.ops.wm.read_factory_settings(use_empty=True)
                bpy.ops.import_scene.gltf(filepath=str(path))
                obj = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
                paint_reference(obj, item['input'])
                bpy.ops.object.select_all(action='DESELECT')
                obj.select_set(True)
                bpy.context.view_layer.objects.active = obj
                bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_normals=True, export_materials='EXPORT', export_vertex_color='NAME', export_vertex_color_name='ReferenceColor', export_all_vertex_colors=False)
                lod['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            result = prepare(item,args.output)
        report.append(result)
        print('KIT_ASSET_PREPARED '+json.dumps(result),flush=True)
report_path = args.output.parent/'preparation.json'
existing = json.loads(report_path.read_text()) if report_path.exists() else []
merged = {item['id']:item for item in existing}
merged.update({item['id']:item for item in report})
report_path.write_text(json.dumps(list(merged.values()),indent=2)+'\n')
