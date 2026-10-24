"""Prepare approved CL3D prop sources and render their actual geometry.

blender --factory-startup -b -t 2 --python-exit-code 1 \
  --python scripts/art/build_scattered_props.py -- --only 01-table
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from procgen import core, disturb, rigid, fracture, export as mesh_export

OUT = Path('content/environments/procedural_props_aged_v1')
REVIEW = Path('content/environments/red_descent/review/props_aged_v1/cl3d_v1')
SET_REVIEW = REVIEW.parent / 'physics_v1'
FAMILIES = {
    'refectory': [('01-table', -0.4, 0.8, None), ('02-bench', -0.4, -0.15, None), ('04-barrel', 1.15, 0.8, None)],
    'mortuary': [('05-coffin-body', -0.3, 0.75, None), ('06-coffin-lid', -0.3, -0.15, None),
                 ('07-skull', 1.0, 0.05, None), ('08-femur', 1.15, 0.65, None)],
    'ossuary': [('03-shelf', 0.0, 0.9, None), ('09-pot', -0.15, 0.82, '03-shelf'),
                ('07-skull', 0.23, 0.82, '03-shelf'), ('08-femur', -0.4, -0.1, None)],
    'votive': [('04-barrel', -0.6, 0.6, None), ('09-pot', 0.6, 0.6, None), ('10-candle-holder', 0.0, -0.1, None)],
}


def bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return (Vector(tuple(min(p[i] for p in points) for i in range(3))),
            Vector(tuple(max(p[i] for p in points) for i in range(3))))


def clean(obj: bpy.types.Object) -> dict:
    """Same connected-island cleanup rule as prepare_dungeon_kit.py."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    pending = set(bm.verts)
    groups = []
    while pending:
        stack = [pending.pop()]
        group = []
        while stack:
            vertex = stack.pop()
            group.append(vertex)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other in pending:
                    pending.remove(other)
                    stack.append(other)
        groups.append(group)
    cutoff = max(len(group) for group in groups) * 0.01
    discarded = [v for group in groups if len(group) < cutoff for v in group]
    bmesh.ops.delete(bm, geom=discarded, context='VERTS')
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    report = {'source_components': len(groups), 'discarded_vertices': len(discarded),
              'boundary_edges_after_cleanup': sum(e.is_boundary for e in bm.edges),
              'nonmanifold_edges_after_cleanup': sum(not e.is_manifold for e in bm.edges)}
    bm.to_mesh(obj.data)
    bm.free()
    return report


def clay(obj: bpy.types.Object) -> None:
    material = bpy.data.materials.get('ReviewClay') or bpy.data.materials.new('ReviewClay')
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (0.42, 0.39, 0.35, 1.0)
    shader.inputs['Roughness'].default_value = 0.78
    obj.data.materials.clear()
    obj.data.materials.append(material)


def export(obj: bpy.types.Object, path: Path) -> None:
    core.select_only([obj])
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_yup=True, export_apply=True, export_normals=True,
        export_materials='EXPORT', export_animations=False, export_extras=True)
    assert path.stat().st_size > 1000, path


def interior_probe(obj: bpy.types.Object, asset_id: str) -> dict:
    if asset_id not in {'05-coffin-body', '09-pot'}:
        return {}
    low, high = bounds(obj)
    start = Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, high.z + 0.1))
    bpy.context.view_layer.update()
    hit, point, _normal, _face = obj.ray_cast(start, Vector((0, 0, -1)))
    depth = high.z - point.z if hit else 0.0
    return {'method': 'downward centre ray on actual simplified mesh', 'hit': hit,
            'depth_m': depth, 'height_m': high.z - low.z,
            'open_interior_candidate': bool(hit and depth > (high.z - low.z) * 0.2)}


def preview(objects: list, asset_id: str, folder: Path = REVIEW) -> list[str]:
    boxes = [bounds(obj) for obj in objects]
    lo = Vector(tuple(min(box[0][i] for box in boxes) for i in range(3)))
    hi = Vector(tuple(max(box[1][i] for box in boxes) for i in range(3)))
    target = (lo + hi) * 0.5
    span = max(hi - lo)
    radius = (hi - lo).length * 0.5
    distance = radius * 1.25 / math.sin(math.atan(18.0 / 45.0))
    bpy.ops.mesh.primitive_plane_add(size=span * 30, location=(0, 0, -0.004))
    plane = bpy.context.object
    plane.name = 'ReviewFloor'
    clay(plane)
    images = []
    for name, direction in [('front', Vector((1.4, -2.0, 1.35))),
                            ('back', Vector((-1.3, 1.8, 1.7)))]:
        eye = target + direction.normalized() * distance
        rgb = disturb.render(eye, target, size=(640, 480), samples=16, lens=45.0)
        path = folder / f'{asset_id}-{name}.png'
        disturb.write_png(path, rgb)
        images.append(core.relative(path))
    bpy.data.objects.remove(plane, do_unlink=True)
    return images


def prepare(job: dict, render: bool) -> dict:
    core.empty_scene()
    raw = Path(job['output'])
    assert raw.with_suffix('.json').is_file(), f'Generation not finished: {raw}'
    bpy.ops.import_scene.gltf(filepath=str(raw.resolve()))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert meshes, raw
    core.select_only(meshes)
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    cleanup = clean(obj)
    lo, hi = bounds(obj)
    scale = max(job['target_dims_xyz_m']) / max(hi - lo)
    center = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    for vertex in obj.data.vertices:
        vertex.co = (vertex.co - center) * scale
        assert all(math.isfinite(c) for c in vertex.co), job['id']
    obj.data.update()
    obj.name = job['id']
    approved = job.get('approved_input', job['input'])
    obj['source_image_sha256'] = core.sha256(approved)
    obj['cl3d_source_sha256'] = core.sha256(raw)
    obj['review_material_only'] = True
    clay(obj)
    prepared = OUT / 'sources'
    prepared.mkdir(parents=True, exist_ok=True)
    levels = []
    for level, target in enumerate([job['faces'], max(500, job['faces'] // 3), max(250, job['faces'] // 8)]):
        modifier = obj.modifiers.new('Simplify', 'DECIMATE')
        modifier.ratio = min(1.0, target / max(1, len(obj.data.polygons)))
        modifier.use_collapse_triangulate = True
        core.select_only([obj])
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.set_sharp_from_angle(angle=math.radians(42))
        obj.name = f"{job['id']}_lod{level}"
        path = prepared / f'{obj.name}.glb'
        export(obj, path)
        low, high = bounds(obj)
        assert len(obj.data.polygons) > 0
        assert abs(low.z) < 0.015, (job['id'], low.z)
        assert max(high - low) <= max(job['target_dims_xyz_m']) * 1.02
        levels.append({'path': core.relative(path), 'triangles': len(obj.data.polygons),
                       'sha256': core.sha256(path),
                       'dimensions_godot_m': [high.x - low.x, high.z - low.z, high.y - low.y]})
        if level == 0:
            interior = interior_probe(obj, job['id'])
            lod0 = obj.copy()
            lod0.data = obj.data.copy()
    bpy.data.objects.remove(obj, do_unlink=True)
    core.link(lod0)
    images = preview([lod0], job['id']) if render else []
    report = {'id': job['id'], 'raw': core.relative(raw), 'raw_sha256': core.sha256(raw),
              'approved_image': approved, 'approved_image_sha256': core.sha256(approved),
              'conditioning_image': job['input'], 'conditioning_image_sha256': core.sha256(job['input']),
              'scale_policy': 'uniform; longest dimension matches approved target; origin at ground centre',
              'uniform_scale': scale, 'cleanup': cleanup, 'lods': levels, 'review_images': images,
              'interior_probe': interior,
              'materials': 'neutral review clay; no inferred textures or UVs',
              'status': 'mesh_review_pending'}
    print('PROP_SOURCE_READY', json.dumps(report), flush=True)
    return report


def import_source(asset_id: str, x: float, y: float, support=None) -> bpy.types.Object:
    path = OUT / 'sources' / f'{asset_id}_lod0.glb'
    assert path.is_file(), path
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    obj = next(o for o in bpy.context.scene.objects if o not in before and o.type == 'MESH')
    obj.name = asset_id
    obj.location.x, obj.location.y = x, y
    obj.location.z = 0.004
    bpy.context.view_layer.update()
    if support:
        start = support.matrix_world.inverted() @ Vector((x, y, 4.0))
        direction = support.matrix_world.inverted().to_3x3() @ Vector((0, 0, -1))
        hit, point, _normal, _face = support.ray_cast(start, direction.normalized())
        assert hit, (asset_id, 'missed shelf support')
        obj.location.z = (support.matrix_world @ point).z + 0.004
    return obj


def add_bodies(objects: list, floor: bpy.types.Object) -> None:
    rigid.world(substeps=30, iterations=80, frame_end=1440)
    for obj in objects:
        disturb.centre(obj)
        density = 1800.0 if obj.name.startswith(('07-', '08-', '09-')) else 650.0
        shelf = obj.name.startswith('03-shelf')
        # Fixed shelving uses actual concave surfaces; movable clutter uses stable hulls.
        rigid.body(obj, passive=shelf, mass=rigid.mass(obj, density),
                   shape='MESH' if shelf else 'CONVEX_HULL', margin=0.001,
                   friction=0.7, damping=(0.3, 0.5))
    disturb.centre(floor)
    rigid.body(floor, passive=True, shape='BOX', margin=0.001)


def freeze_scene(objects: list) -> list:
    """Bake evaluated world geometry into a fresh scene without stale Bullet caches."""
    frozen = [(obj.name, [tuple(obj.matrix_world @ v.co) for v in obj.data.vertices],
               [tuple(p.vertices) for p in obj.data.polygons]) for obj in objects]
    core.empty_scene()
    disturb.reset()
    result = []
    for name, vertices, faces in frozen:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = core.link(bpy.data.objects.new(name, mesh))
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        clay(obj)
        result.append(obj)
    return result


def scatter(family: str, variant: int, seed: int, render: bool) -> dict:
    core.empty_scene()
    disturb.reset()
    movers = []
    by_id = {}
    for asset_id, x, y, support in FAMILIES[family]:
        obj = import_source(asset_id, x, y, by_id.get(support))
        movers.append(obj)
        by_id[asset_id] = obj
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    floor = bpy.context.object
    floor.name = 'SimulationFloor'
    floor.dimensions = (20, 20, 0.2)
    core.select_only([floor])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    add_bodies(movers, floor)
    baseline = rigid.settle(movers, threshold=0.005, hold=20, max_frames=1440)
    assert baseline['settled'], (family, 'baseline not settled', baseline)
    frozen = freeze_scene(movers + [floor])
    movers, floor = frozen[:-1], frozen[-1]
    cells = []
    pots = [obj for obj in movers if obj.name == '09-pot']
    if variant == 2 and pots:
        pot = pots[0]
        low, high = bounds(pot)
        center = (low + high) * 0.5
        radius = min(high.x - low.x, high.y - low.y) * 0.3
        points = [center + Vector((radius * math.cos(a), radius * math.sin(a), 0))
                  for a in (0, math.tau / 3, math.tau * 2 / 3)]
        cells = fracture.voronoi(pot, points, name='09-pot')
        assert len(cells) == 3, family
        movers.remove(pot)
        bpy.data.objects.remove(pot, do_unlink=True)
        for cell in cells:
            clay(cell)
        movers.extend(cells)
    add_bodies(movers, floor)
    rest = disturb.rest_pose(movers)
    intensity = (0.0, 1.2, 2.0)[variant]
    rng = core.rng(seed, family, variant)
    fracture.glue(cells, rng, 'plaster', weakness=0.5)
    disturb.arm()
    supports = [floor] + [obj for obj in movers if obj.name.startswith('03-shelf')]
    disturb.kinematic(supports)
    tremor = disturb.shake(supports, rng, intensity) if intensity else None
    ball = disturb.roll(Vector((-2.0, 0.75, 0.25)), Vector((1.8, 0, 0)), radius=0.22) if variant == 2 else None
    settled = rigid.settle(movers, threshold=0.005, hold=20,
                           min_frames=disturb.quiet_frame(), max_frames=1440)
    moved = disturb.displacements(movers, rest)
    frozen = freeze_scene(movers + [floor])
    movers, floor = frozen[:-1], frozen[-1]
    gaps = rigid.contact_gaps(movers, [floor], limit=0.03)
    penetration = rigid.penetration(movers, [floor])
    boxes = [bounds(obj) for obj in movers]
    lo = Vector(tuple(min(b[0][i] for b in boxes) for i in range(3)))
    hi = Vector(tuple(max(b[1][i] for b in boxes) for i in range(3)))
    lane_clearance = lo.y + 1.0
    max_move = max(d for d, _angle in moved.values())
    max_turn = max(angle for _d, angle in moved.values())
    calm_ok = variant != 0 or (max_move <= 0.01 and max_turn <= 1.0)
    distinct = variant == 0 or max_move > (0.0, 0.01, 0.05)[variant] or max_turn > (0.0, 1.0, 5.0)[variant]
    valid = (settled['settled'] and max(gaps.values()) <= 0.01 and penetration['max_m'] <= 0.01
             and lane_clearance >= 0.05 and max(abs(c) for c in (*lo, *hi)) < 5.0 and calm_ok and distinct)
    result = {'id': f'{family}_v{variant}', 'family': family, 'variant': variant, 'seed': seed,
              'intensity': intensity, 'rolling_ball': ball is not None, 'baseline': baseline,
              'offline_collision': 'convex movers; concave kinematic shelving',
              'fractured_pot_cells': len(cells),
              'settled': settled, 'movement': moved, 'max_translation_m': max_move,
              'max_rotation_deg': max_turn, 'calm_unchanged': calm_ok if variant == 0 else None,
              'contact_gaps_m': gaps, 'max_contact_gap_m': max(gaps.values()),
              'penetration': penetration, 'lane_clearance_m': lane_clearance,
              'reserved_lane_blender_y_m': [-2.2, -1.0],
              'bounds_godot': {'min': [lo.x, lo.z, -hi.y], 'max': [hi.x, hi.z, -lo.y]},
              'tremor': tremor, 'valid': valid}
    if valid:
        hulls = []
        for obj in movers:
            if max(obj.dimensions) >= 0.4 and rigid.volume(obj) >= 0.004:
                hulls.append(mesh_export.collision_copy(obj, 'convcolonly'))
        target = OUT / 'sets' / f"{result['id']}.glb"
        target.parent.mkdir(parents=True, exist_ok=True)
        core.select_only(movers + hulls)
        bpy.ops.export_scene.gltf(filepath=str(target.resolve()), export_format='GLB', use_selection=True,
            export_yup=True, export_apply=True, export_normals=True, export_materials='EXPORT',
            export_animations=False, export_extras=True)
        for obj in hulls:
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.objects.remove(floor, do_unlink=True)
        result['glb'] = core.relative(target)
        result['sha256'] = core.sha256(target)
        result['collision_hulls'] = len(hulls)
        result['review_images'] = preview(movers, result['id'], SET_REVIEW) if render else []
    print('PROP_SCATTER_ATTEMPT', json.dumps({k: result[k] for k in
          ('id', 'seed', 'valid', 'max_contact_gap_m', 'lane_clearance_m', 'max_translation_m', 'max_rotation_deg')}), flush=True)
    return result


def build_sets(families: list[str], variants: list[int], render: bool) -> None:
    SET_REVIEW.mkdir(parents=True, exist_ok=True)
    path = OUT / 'sets.json'
    report = json.loads(path.read_text()) if path.exists() else {}
    for family in families:
        for variant in variants:
            attempts = []
            for attempt in range(1 if variant == 0 else 4):
                result = scatter(family, variant, 171000 + variant * 100 + attempt, render)
                attempts.append(result)
                if result['valid']:
                    break
            (SET_REVIEW / f'{family}_v{variant}-attempts.json').write_text(json.dumps(attempts, indent=2) + '\n')
            assert result['valid'], (family, variant, 'no acceptable attempt')
            report[result['id']] = result
            path.write_text(json.dumps(report, indent=2) + '\n')
    if render:
        ids = [f'{family}_v{variant}' for variant in range(3) for family in FAMILIES]
        write_sheet(ids, SET_REVIEW, 4, 'front', 'all-sets')


def write_sheet(ids: list[str], folder: Path, columns: int, view: str, name: str = 'all-props') -> None:
    suffix = f'-{view}' if view else ''
    paths = [folder / f'{asset_id}{suffix}.png' for asset_id in ids]
    if not all(path.exists() for path in paths):
        return
    tiles = []
    for path in paths:
        frame = bpy.data.images.load(str(path.resolve()), check_existing=False)
        # Contact sheets preserve the rendered PNG bytes rather than linearising sRGB.
        frame.colorspace_settings.name = 'Non-Color'
        width, height = frame.size
        pixels = np.empty(len(frame.pixels), dtype=np.float32)
        frame.pixels.foreach_get(pixels)
        tiles.append(np.clip(pixels.reshape(height, width, 4)[::-1, :, :3] * 255 + 0.5, 0, 255).astype(np.uint8))
        bpy.data.images.remove(frame)
    rows = [np.concatenate(tiles[n:n + columns], axis=1) for n in range(0, len(tiles), columns)]
    disturb.write_png(folder / f'{name}{suffix}.png', np.concatenate(rows, axis=0))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', default='')
    parser.add_argument('--no-render', action='store_true')
    parser.add_argument('--sets', action='store_true')
    parser.add_argument('--variants', default='0,1,2')
    args = parser.parse_args(core.args())
    if args.sets:
        families = args.only.split(',') if args.only else list(FAMILIES)
        assert all(family in FAMILIES for family in families), families
        variants = [int(v) for v in args.variants.split(',')]
        assert variants and all(v in (0, 1, 2) for v in variants), variants
        build_sets(families, variants, not args.no_render)
        return
    jobs = json.loads((OUT / 'source_jobs.json').read_text())
    selected = set(args.only.split(',')) if args.only else {j['id'] for j in jobs}
    REVIEW.mkdir(parents=True, exist_ok=True)
    path = OUT / 'sources.json'
    report = json.loads(path.read_text()) if path.exists() else {}
    for job in jobs:
        if job['id'] in selected:
            report[job['id']] = prepare(job, not args.no_render)
            path.write_text(json.dumps(report, indent=2) + '\n')
    for view in ('front', 'back'):
        write_sheet([job['id'] for job in jobs], REVIEW, 5, view)


if __name__ == '__main__':
    main()
