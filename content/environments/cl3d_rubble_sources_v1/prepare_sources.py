"""Clean T-167 CL3D chunks, enforce closed meshes and export three centred LODs.

Run in Blender at the repository root, after generate_sources.py.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
sys.path.insert(0, str(ROOT / 'scripts/art'))
from procgen import core
import build_scattered_props as props
import build_stone_surface as surface


def topology(obj: bpy.types.Object) -> dict:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    result = {'boundary_edges': sum(e.is_boundary for e in bm.edges),
              'nonmanifold_edges': sum(not e.is_manifold for e in bm.edges),
              'triangles': sum(len(f.verts) - 2 for f in bm.faces)}
    bm.free()
    return result


def largest_component(obj: bpy.types.Object) -> int:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    todo = set(bm.verts)
    groups = []
    while todo:
        pending = [todo.pop()]
        group = []
        while pending:
            vertex = pending.pop()
            group.append(vertex)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other in todo:
                    todo.remove(other)
                    pending.append(other)
        groups.append(group)
    keep = max(groups, key=len)
    removed = [v for group in groups if group is not keep for v in group]
    bmesh.ops.delete(bm, geom=removed, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    return len(removed)


def prepare(job: dict) -> dict:
    core.empty_scene()
    raw = ROOT / job['output']
    generation = json.loads(raw.with_suffix('.json').read_text())
    bpy.ops.import_scene.gltf(filepath=str(raw))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert meshes
    core.select_only(meshes)
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    cleanup = props.clean(obj)
    cleanup['extra_component_vertices_removed'] = largest_component(obj)
    raw_topology = topology(obj)
    remeshed = raw_topology['nonmanifold_edges'] > 0
    if remeshed:
        low, high = props.bounds(obj)
        remesh = obj.modifiers.new('CloseSource', 'REMESH')
        remesh.mode = 'VOXEL'
        remesh.voxel_size = max(high - low) / 120.0
        remesh.use_smooth_shade = True
        core.select_only([obj])
        bpy.ops.object.modifier_apply(modifier=remesh.name)
        props.clean(obj)
        largest_component(obj)
    low, high = props.bounds(obj)
    scale = float(job['target_span_m']) / max(high - low)
    centre = (low + high) * 0.5
    for vertex in obj.data.vertices:
        vertex.co = (vertex.co - centre) * scale
    obj.data.update()
    obj.name = job['id']
    props.clay(obj)
    levels = []
    review = []
    for level, budget in enumerate([1500, 600, 200]):
        modifier = obj.modifiers.new('Budget', 'DECIMATE')
        modifier.ratio = min(1.0, budget / max(1, len(obj.data.polygons)))
        modifier.use_collapse_triangulate = True
        core.select_only([obj])
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        low, high = props.bounds(obj)
        centre = (low + high) * 0.5
        for vertex in obj.data.vertices:
            vertex.co -= centre
            assert all(math.isfinite(x) for x in vertex.co)
        obj.data.update()
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.set_sharp_from_angle(angle=math.radians(42))
        if obj.data.uv_layers:
            obj.data.uv_layers.remove(obj.data.uv_layers.active)
        surface.DENSITY = 1.0
        surface.project_uvs(obj.data, obj.matrix_world)
        stats = topology(obj)
        assert stats['nonmanifold_edges'] == 0 and stats['boundary_edges'] == 0, (job['id'], level, stats)
        assert stats['triangles'] <= budget and stats['triangles'] > 20, (job['id'], level, stats)
        path = OUT / 'sources' / f'{job["id"]}_lod{level}.glb'
        path.parent.mkdir(exist_ok=True)
        props.export(obj, path)
        low, high = props.bounds(obj)
        dimensions = high - low
        levels.append({'path': str(path.relative_to(OUT)), 'triangles': stats['triangles'],
                       'dims_m': [dimensions.x, dimensions.z, dimensions.y],
                       'topology': stats, 'sha256': core.sha256(path)})
        if level == 0:
            obj.location.z = -low.z
            bpy.context.view_layer.update()
            review = props.preview([obj], job['id'], OUT / 'review')
            obj.location.z = 0.0
            bpy.context.view_layer.update()
    material = '04-old-terracotta-brick' if job['kind'] == 'brick_clump' else '02-split-bedded-stone' if job['kind'] == 'rock' else '01-chisel-limestone'
    reference = ROOT / job['approved_input']
    receipt = json.loads(reference.with_suffix('.receipt.json').read_text())
    return {'id': job['id'], 'kind': job['kind'], 'dims_m': levels[0]['dims_m'],
        'origin_rule': 'exact bounding-box centre, Y up, metres, uniform scale baked',
        'seed': generation['seed'], 'inference_seconds': generation['inference_seconds'],
        'prompt': f'prompts/{reference.stem}-v2.txt' if (OUT / 'prompts' / f'{reference.stem}-v2.txt').exists() else f'prompts/{reference.stem}.txt',
        'reference': str(reference.relative_to(OUT)), 'input_sha256': core.sha256(reference),
        'conditioning_sha256': core.sha256(ROOT / job['input']), 'raw': str(raw.relative_to(OUT)),
        'raw_sha256': core.sha256(raw), 'cleanup': cleanup, 'voxel_repair_used': remeshed,
        'lods': levels, 'review_images': [str(Path(p).relative_to(OUT.relative_to(ROOT))) for p in review],
        'material_hint': f'res://content/environments/stone_brick_materials_v1/materials/{material}/surface.tres',
        'material_finish': 'Neutral review clay embedded; paired map candidate available via material_hint. Brick/mortar segmentation not baked.',
        'generator': 'CL3D/2mini, local Tencent Hunyuan3D-2mini build', 'status': 'technical_review_pending'}


def main() -> None:
    jobs = json.loads((OUT / 'generation_jobs.json').read_text())
    selected = set(core.args())
    manifest = json.loads((OUT / 'manifest.json').read_text()) if (OUT / 'manifest.json').exists() else {'task': 'T-167', 'assets': []}
    records = {item['id']: item for item in manifest['assets']}
    for job in jobs:
        if selected and job['id'] not in selected:
            continue
        assert (ROOT / job['output']).with_suffix('.json').exists(), job['id']
        records[job['id']] = prepare(job)
        manifest['assets'] = [records[j['id']] for j in jobs if j['id'] in records]
        (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print('RUBBLE_SOURCE_READY', job['id'], flush=True)
    if len(records) == 18:
        props.write_sheet([j['id'] for j in jobs], OUT / 'review', 6, 'front', 'all-chunks')
        props.write_sheet([j['id'] for j in jobs], OUT / 'review', 6, 'back', 'all-chunks')
    print('RUBBLE_PREPARATION_OK', len(records), flush=True)


if __name__ == '__main__':
    main()
