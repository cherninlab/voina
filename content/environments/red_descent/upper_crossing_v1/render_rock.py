"""Three views of the real reduced mesh, independent of its generated source image."""
import math
from pathlib import Path

import bpy
from mathutils import Vector

root = Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root / "rock_lod0.glb"))
rock = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
material = bpy.data.materials.new("Neutral rock inspection")
material.diffuse_color = (0.29, 0.30, 0.31, 1)
material.use_nodes = True
shader = material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Base Color"].default_value = (0.29, 0.30, 0.31, 1)
shader.inputs["Roughness"].default_value = 0.87
rock.data.materials.clear()
rock.data.materials.append(material)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 20
scene.render.threads_mode = "FIXED"
scene.render.threads = 6
scene.render.resolution_x = 640
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.world = bpy.data.worlds.new("Studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.065, 0.07, 0.08, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
for name, position, energy, size in [
    ("Key", (2.5, -3, 4), 450, 3), ("Fill", (-3, -1, 1.7), 200, 3), ("Rim", (0, 3, 2.5), 350, 2)
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = position
    light.rotation_euler = (Vector((0, 0, 0.5)) - light.location).to_track_quat("-Z", "Y").to_euler()
camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.35
for name, angle in [("front", -math.pi / 2), ("side", 0), ("back", math.pi / 2)]:
    camera.location = (2.5 * math.cos(angle), 2.5 * math.sin(angle), 1.0)
    camera.rotation_euler = (Vector((0, 0, 0.5)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(root / "review" / f"rock-{name}.png")
    bpy.ops.render.render(write_still=True)
