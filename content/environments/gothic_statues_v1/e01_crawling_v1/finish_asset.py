"""Create static LODs and bake portable marble PBR maps from the selected high mesh."""
import argparse
import json
from pathlib import Path
import sys
import time

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--mesh', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--triangles', type=int, default=80000)
parser.add_argument('--texture-size', type=int, default=2048)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
started = time.monotonic()
args.out.mkdir(parents=True, exist_ok=True)
textures = args.out / 'textures'; textures.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(args.mesh.resolve()))
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
assert len(objects) == 1, 'Cleanup must select one reviewed connected statue'
high = objects[0]; high.name = 'E01_High'
high.select_set(True); bpy.context.view_layer.objects.active = high
world = high.matrix_world.copy(); high.parent = None; high.matrix_world = world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
points = [high.matrix_world @ Vector(c) for c in high.bound_box]
lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
scale = 2.2 / max(hi-lo)
for vertex in high.data.vertices:
    vertex.co = (vertex.co - Vector(((lo.x+hi.x)/2, (lo.y+hi.y)/2, lo.z))) * scale
high.location = (0,0,0)
for poly in high.data.polygons: poly.use_smooth = True
high.data.update()
low = high.copy(); low.data = high.data.copy(); low.name = 'E01_Crawling_LOD0'
bpy.context.collection.objects.link(low)
high.select_set(False); low.select_set(True); bpy.context.view_layer.objects.active = low
dec = low.modifiers.new('Quadric silhouette preserving reduction', 'DECIMATE')
dec.ratio = min(1.0, args.triangles / len(high.data.polygons))
dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=dec.name)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.151917, island_margin=.008)
bpy.ops.object.mode_set(mode='OBJECT')
print('LOD0 triangles', len(low.data.polygons), flush=True)

scene = bpy.context.scene; scene.render.engine = 'CYCLES'
scene.cycles.samples = 16; scene.cycles.device = 'CPU'
scene.render.threads_mode = 'FIXED'; scene.render.threads = 6
scene.render.bake.margin = 12
material = bpy.data.materials.new('E01 Warm aged marble'); material.use_nodes = True
nodes = material.node_tree.nodes; links = material.node_tree.links
nodes.clear()
output = nodes.new('ShaderNodeOutputMaterial')
bsdf = nodes.new('ShaderNodeBsdfPrincipled'); links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
coords = nodes.new('ShaderNodeTexCoord')
noise = nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 3.8
noise.inputs['Detail'].default_value = 5; noise.inputs['Roughness'].default_value = .72
links.new(coords.outputs['Object'], noise.inputs['Vector'])
ramp = nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = .28
ramp.color_ramp.elements[0].color = (.34,.285,.22,1)
ramp.color_ramp.elements[1].position = .66
ramp.color_ramp.elements[1].color = (.72,.665,.565,1)
links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
fine = nodes.new('ShaderNodeTexNoise'); fine.inputs['Scale'].default_value = 85
fine.inputs['Detail'].default_value = 2
links.new(coords.outputs['Object'], fine.inputs['Vector'])
rough = nodes.new('ShaderNodeMapRange')
rough.inputs['To Min'].default_value = .48; rough.inputs['To Max'].default_value = .72
links.new(fine.outputs['Fac'], rough.inputs['Value'])
links.new(rough.outputs['Result'], bsdf.inputs['Roughness'])
low.data.materials.clear(); low.data.materials.append(material)
high.data.materials.clear(); high.data.materials.append(material)
images = {}

def target_image(name, color, srgb=False):
    image = bpy.data.images.new(name, width=args.texture_size, height=args.texture_size, alpha=False)
    image.generated_color = color
    image.colorspace_settings.name = 'sRGB' if srgb else 'Non-Color'
    image.filepath_raw = str((textures / f'{name}.png').resolve()); image.file_format = 'PNG'
    node = nodes.new('ShaderNodeTexImage'); node.image = image; nodes.active = node
    images[name] = (image,node)
    return image

# Bake the procedural surface as portable textures; the normal map captures real high-to-low geometry.
emission = nodes.new('ShaderNodeEmission')
links.new(emission.outputs[0], output.inputs['Surface'])
target_image('e01_albedo', (.7,.65,.55,1), True)
links.new(ramp.outputs['Color'], emission.inputs['Color'])
bpy.ops.object.bake(type='EMIT', use_selected_to_active=False)
images['e01_albedo'][0].save()
target_image('e01_roughness', (.6,.6,.6,1))
links.new(rough.outputs['Result'], emission.inputs['Color'])
bpy.ops.object.bake(type='EMIT', use_selected_to_active=False)
images['e01_roughness'][0].save()
links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
target_image('e01_normal', (.5,.5,1,1))
high.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
bpy.ops.object.bake(type='NORMAL', use_selected_to_active=True,
                    cage_extrusion=.008, max_ray_distance=.04)
images['e01_normal'][0].save()
high.select_set(False); high.hide_render = True
target_image('e01_ao', (1,1,1,1))
scene.world.color = (.05,.05,.05)
bpy.ops.object.bake(type='AO', use_selected_to_active=False)
images['e01_ao'][0].save()

# Final standard glTF material uses the baked color, roughness and OpenGL tangent normal.
links.new(images['e01_albedo'][1].outputs['Color'], bsdf.inputs['Base Color'])
links.new(images['e01_roughness'][1].outputs['Color'], bsdf.inputs['Roughness'])
normal = nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value = 1
links.new(images['e01_normal'][1].outputs['Color'], normal.inputs['Color'])
links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
# glTF exporter recognizes an occlusion texture via the standard settings group.
group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
settings = nodes.new('ShaderNodeGroup'); settings.node_tree = group
links.new(images['e01_ao'][1].outputs['Color'], settings.inputs['Occlusion'])

def export(obj, name):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str((args.out/name).resolve()), export_format='GLB',
        use_selection=True, export_normals=True, export_tangents=True, export_materials='EXPORT')

export(low, 'e01_crawling_lod0.glb')
lod1 = low.copy(); lod1.data = low.data.copy(); lod1.name = 'E01_Crawling_LOD1'
bpy.context.collection.objects.link(lod1); bpy.context.view_layer.objects.active = lod1
dec = lod1.modifiers.new('LOD1 quadric reduction', 'DECIMATE')
dec.ratio = .375; dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=dec.name)
export(lod1, 'e01_crawling_lod1.glb')
lod1.hide_render = True; lod1.hide_set(True); high.hide_set(True)
low.hide_set(False); low.select_set(True); bpy.context.view_layer.objects.active = low
for image, _node in images.values():
    image.filepath = '//textures/' + image.name + '.png'
    image.pack()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str((args.out/'e01_crawling.blend').resolve()), compress=True)
report = {'source_mesh':str(args.mesh.resolve()), 'source_triangles':len(high.data.polygons),
    'lod0_triangles':len(low.data.polygons), 'lod1_triangles':len(lod1.data.polygons),
    'texture_size':args.texture_size, 'maps':list(images), 'max_dimension_meters':2.2,
    'origin':'centered horizontally at lowest point', 'normal_convention':'OpenGL tangent space +Y',
    'material':'procedural warm marble baked to UVs; no projected image detail',
    'operations':['keep reviewed main shell','uniform scale','quadric decimation','smart UV unwrap','high-to-low normal bake','AO bake'],
    'blender_version':bpy.app.version_string, 'elapsed_seconds':time.monotonic()-started}
(args.out/'asset_build.json').write_text(json.dumps(report,indent=2)+'\n')
print('ASSET_BUILD_OK', json.dumps(report), flush=True)
