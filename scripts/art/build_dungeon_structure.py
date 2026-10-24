"""Blender background: shaped timber and pinned cloth -> static metre-unit GLBs.

blender -b --python scripts/art/build_dungeon_structure.py -- output_directory
No simulation runs in the game. Re-run this file to reproduce the baked assets.
"""
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def export(obj, name):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')),
        export_format='GLB', use_selection=True, export_materials='NONE',
        export_animations=False)


# End planes stay exactly at +/-0.5: fitting cannot introduce gaps at joints.
# Broad hewn planes replace the uniformly chamfered primitive beam silhouette.
for variant in range(3):
    verts, faces = [], []
    for ring, y in enumerate([-.5, -.43, -.12, .19, .43, .5]):
        for x, z in [(-.46,-.5),(.44,-.5),(.5,-.43),(.5,.44),
                     (.44,.5),(-.43,.5),(-.5,.43),(-.5,-.44)]:
            wear = .008 * math.sin(ring * 4.2 + len(verts) * 1.7 + variant)
            verts.append((x * (1 + wear), y, z * (1 + wear)))
    for ring in range(5):
        for k in range(8):
            a, b = ring * 8 + k, ring * 8 + (k+1)%8
            faces.append((a, b, b+8, a+8))
    faces += [tuple(reversed(range(8))), tuple(range(40,48))]
    mesh = bpy.data.meshes.new('HewnTimber')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('HewnTimber', mesh)
    bpy.context.collection.objects.link(obj)
    # Blender Y is the length axis; glTF exports it as Godot -Z.
    export(obj, f'hewn_timber_{variant}')
    bpy.data.objects.remove(obj, do_unlink=True)

# A ragged strip suspended at two upper corners, initially almost horizontal.
# Gravity determines its folds and hanging depth. Those exact pins become the
# attachment sockets used by the level; there are no free-floating cloth pieces.
cols, rows = 32, 22
verts, faces = [], []
for row in range(rows+1):
    v = row/rows
    for col in range(cols+1):
        u = col/cols
        rag = 1 + .11 * math.sin(u*37) * v**5
        verts.append(((u-.5)*2.4, v*1.6*rag,
                      -.035 + .018*math.sin(u*25)*math.sin(v*9)))
for row in range(rows):
    for col in range(cols):
        if row > rows-3 and (col*7)%13 < 3:
            continue
        a = row*(cols+1)+col
        faces.append((a,a+1,a+cols+2,a+cols+1))
mesh = bpy.data.meshes.new('PinnedCloth')
mesh.from_pydata(verts, [], faces)
mesh.update()
cloth = bpy.data.objects.new('PinnedCloth', mesh)
bpy.context.collection.objects.link(cloth)
bpy.context.view_layer.objects.active = cloth
pins = cloth.vertex_groups.new(name='BeamAttachments')
pin_ids = [0, cols]
pins.add(pin_ids, 1, 'REPLACE')
mod = cloth.modifiers.new('GravityDrape', 'CLOTH')
mod.settings.quality = 20
mod.settings.mass = .08
mod.settings.vertex_group_mass = pins.name
mod.settings.tension_stiffness = 80
mod.settings.compression_stiffness = 80
mod.settings.shear_stiffness = 40
mod.settings.bending_stiffness = .12
mod.settings.air_damping = 10
mod.point_cache.frame_start = 1
mod.point_cache.frame_end = 110
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_end = 110
start = [Vector(v) for v in verts]
for frame in range(1,111):
    scene.frame_set(frame)
evaluated = cloth.evaluated_get(bpy.context.evaluated_depsgraph_get())
baked = bpy.data.meshes.new_from_object(evaluated)
final = [v.co.copy() for v in baked.vertices]
pin_error = max((final[i]-start[i]).length for i in pin_ids)
drop = min(v.z for v in final)
stretch = max((final[e.vertices[0]]-final[e.vertices[1]]).length /
              (start[e.vertices[0]]-start[e.vertices[1]]).length for e in mesh.edges)
assert pin_error < .005, pin_error
assert -2.5 < drop < -.7 and stretch < 1.35, (drop, stretch)
assert all(math.isfinite(c) for v in final for c in v)
cloth.modifiers.clear()
cloth.data = baked
solid = cloth.modifiers.new('FabricThickness', 'SOLIDIFY')
solid.thickness = .004
bpy.context.view_layer.objects.active = cloth
bpy.ops.object.modifier_apply(modifier=solid.name)
for p in cloth.data.polygons:
    p.use_smooth = True
export(cloth, 'cloth_drape')
report = {'method':'Blender cloth modifier, gravity, two pinned corners, evaluated frame baked to static mesh',
    'frames':110,'fps':30,'max_pin_error_m':pin_error,'lowest_z_m':drop,'max_edge_stretch':stretch,
    'attachment_sockets_godot':[[-1.2,-.035,0],[1.2,-.035,0]],
    'realtime_physics':False,'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb')}}
(OUT/'bake.json').write_text(json.dumps(report,indent=2)+'\n')
print('STRUCTURE_BAKE_OK '+json.dumps(report),flush=True)
