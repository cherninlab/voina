"""Transfer a reconstructed facial surface onto the denser body without cutting it."""
import argparse
import json
from pathlib import Path
import sys
from statistics import median

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--head', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
out = root / 'composed_face'
out.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str((root / 'body512/review.glb').resolve()))
body = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(args.head.resolve()))
heads = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
verts, faces = [], []
for obj in heads:
    offset = len(verts)
    verts.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
    faces.extend([offset + i for i in p.vertices] for p in obj.data.polygons)
surface = BVHTree.FromPolygons(verts, faces)
bm = bmesh.new()
bm.from_mesh(body.data)
bm.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)


def radius(point):
    # Imported glTF Y-up becomes Blender Z-up; front glTF +Z is Blender -Y.
    return (((point.x + .057) / .053) ** 2 + ((point.z - 1.154) / .076) ** 2) ** .5


original_vertices = len(bm.verts)
offsets = []
for v in bm.verts:
    if radius(v.co) < .65 and v.co.y < -.040:
        hit, _, _, _ = surface.ray_cast(Vector((v.co.x, -1., v.co.z)), Vector((0., 1., 0.)), 2.)
        if hit is not None:
            offsets.append(v.co.y - hit.y)
depth_offset = median(offsets)
edges = [e for e in bm.edges if radius((e.verts[0].co + e.verts[1].co) * .5) < 1.22
         and max(v.co.y for v in e.verts) < -.025]
bmesh.ops.subdivide_edges(bm, edges=edges, cuts=2, use_grid_fill=True)
changed, missed, limited, max_change = 0, 0, 0, 0.
for v in bm.verts:
    rad = radius(v.co)
    if rad >= 1.08 or v.co.y >= -.015:
        continue
    hit, normal, index, distance = surface.ray_cast(
        Vector((v.co.x, -1., v.co.z)), Vector((0., 1., 0.)), 2.)
    if hit is None:
        missed += 1
        continue
    delta = hit.y + depth_offset - v.co.y
    if abs(delta) > .020:
        limited += 1
    delta = max(-.020, min(.020, delta))
    weight = max(0., min(1., (1.08 - rad) / .25))
    weight = weight * weight * (3 - 2 * weight)
    depth_weight = max(0., min(1., (-v.co.y - .015) / .035))
    weight *= depth_weight * depth_weight * (3 - 2 * depth_weight)
    change = delta * weight
    v.co.y += change
    max_change = max(max_change, abs(change))
    changed += 1
bmesh.ops.triangulate(bm, faces=list(bm.faces))
bm.normal_update()
bm.to_mesh(body.data)
bm.free()
for p in body.data.polygons:
    p.use_smooth = True
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(filepath=str(out / 'review.glb'), export_format='GLB',
                          use_selection=True, export_normals=True, export_yup=True)
report = {'method': 'Conforming local subdivision, frontal depth transfer and smooth feather into untouched body. No cut, head replacement or voxel remesh.',
          'head': str(args.head), 'base': 'body512/review.glb', 'changed_vertices': changed,
          'missed_rays': missed, 'clamped_over_20mm': limited, 'median_depth_alignment_m': depth_offset,
          'max_displacement_m': max_change, 'original_vertices': original_vertices,
          'result_vertices': len(body.data.vertices), 'triangles': len(body.data.polygons),
          'changes': 'Facial surface only; hands remain the body512 result',
          'acceptance': 'Experimental comparison, pending visual review'}
(out / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
assert changed > 1000, 'Surface transfer did not cover the face'
print('FACE_TRANSFER_COMPLETE', json.dumps(report), flush=True)
