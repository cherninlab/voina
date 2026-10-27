"""VDB repair trial: fuse the replacement head and remove surface cracks."""
import json
from pathlib import Path
import time
import bpy

root=Path(__file__).resolve().parent;started=time.monotonic()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root/'oracle_head_swap.glb'))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:obj.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.object.join();obj=bpy.context.object
world=obj.matrix_world.copy();obj.parent=None;obj.matrix_world=world
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# The generated sheets are open and cannot define a reliable signed volume.
# Give every sheet a symmetric, bounded thickness before asking VDB to unite it.
shell=obj.modifiers.new('Make open sheets volumetric before VDB','SOLIDIFY')
shell.thickness=.0024;shell.offset=0;shell.use_rim=True
bpy.ops.object.modifier_apply(modifier=shell.name)
mod=obj.modifiers.new('VDB crack repair and head union','REMESH');mod.mode='VOXEL'
mod.voxel_size=.001;mod.adaptivity=.025;mod.use_smooth_shade=True
mod.use_remove_disconnected=False
bpy.ops.object.modifier_apply(modifier=mod.name)
smooth=obj.modifiers.new('Remove voxel stair stepping','SMOOTH');smooth.factor=.4;smooth.iterations=2
bpy.ops.object.modifier_apply(modifier=smooth.name)
for f in obj.data.polygons:f.use_smooth=True
mat=bpy.data.materials.new('Neutral repaired marble');mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.58,.53,.45,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.73
obj.data.materials.clear();obj.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=str(root/'oracle_repaired_high.glb'),export_format='GLB',use_selection=True)
report={'method':'Symmetric sheet thickening, then Blender OpenVDB union','sheet_thickness_m':.0024,
    'voxel_size_m':.001,'adaptivity':.025,
    'smoothing_iterations':2,'smoothing_factor':.4,'polygons':len(obj.data.polygons),
    'limitation':'Reconstructs surfaces at 1mm with a 2.4mm symmetric shell; may soften thin cloth and the smallest hair strands',
    'seconds':time.monotonic()-started}
(root/'voxel_repair.json').write_text(json.dumps(report,indent=2)+'\n')
print('VOXEL_REPAIR_OK',json.dumps(report),flush=True)
