class_name GeneratedDungeonKit
extends RefCounted
## Locally reconstructed modules in metre units, shared by the level and review scene.

const ROOT: String = "res://content/environments/generated_dungeon_kit_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
const IDS: Array[String] = ["arch", "round_arch", "slit_window", "gothic_window", "wall_panel", "window_bay", "curved_wall", "broken_wall", "buttress", "column", "stairs", "timber_anchor", "timber_bridge", "stone_bridge", "rock_outcrop", "rubble", "corbel"]
static var meshes: Dictionary[String, Mesh] = {}
static var surfaces: Dictionary[String, StandardMaterial3D] = {}

static func mesh(id: String, level: int = 0) -> Mesh:
	var key: String = "%s_lod%d" % [id, level]
	if not meshes.has(key):
		var scene: Node3D = (load(ROOT + "meshes/" + key + ".glb") as PackedScene).instantiate() as Node3D
		var source: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		meshes[key] = source.mesh
		scene.free()
	return meshes[key]

static func family(id: String) -> String:
	if id.begins_with("timber"):
		return "wood"
	if id == "rock_outcrop":
		return "rock"
	if id in ["arch", "gothic_window", "slit_window", "column", "corbel"]:
		return "trim"
	return "stone"

static func material(id: String) -> StandardMaterial3D:
	var key: String = id if id == "window_bay" else family(id)
	if surfaces.has(key):
		return surfaces[key]
	var folder: String = PBR + ("Wood035/" if key == "wood" else ("marble_rock_03/" if key == "rock" else "Concrete012/"))
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_texture = load(folder + "albedo.png") as Texture2D
	result.normal_enabled = true
	result.normal_texture = load(folder + "normal_gl.png") as Texture2D
	result.normal_scale = 0.7
	result.roughness_texture = load(folder + "roughness.png") as Texture2D
	result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.roughness = 0.93
	if ResourceLoader.exists(folder + "ao.png"):
		result.ao_enabled = true
		result.ao_texture = load(folder + "ao.png") as Texture2D
		result.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		result.ao_light_affect = 0.15
	result.uv1_triplanar = true
	result.uv1_world_triplanar = key != "wood"
	result.uv1_triplanar_sharpness = 4.0
	result.uv1_scale = Vector3(1.2, 0.18, 1.2) if key == "wood" else Vector3.ONE * 0.85
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.vertex_color_use_as_albedo = true
	result.albedo_color = Color(0.9, 0.9, 0.88) if key == "stone" else (Color(0.97, 0.95, 0.9) if key == "trim" else Color(0.85, 0.87, 0.85))
	if key == "wood":
		result.albedo_color = Color(0.7, 0.68, 0.63)
		result.roughness = 0.66
		result.normal_scale = 0.65
	if id == "window_bay":
		result.albedo_texture = load(ROOT + "textures/window_bay.png") as Texture2D
		result.albedo_color = Color.WHITE
		result.vertex_color_use_as_albedo = false
		result.uv1_triplanar = false
		result.normal_enabled = false
		result.detail_enabled = true
		result.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		result.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		result.detail_normal = load(folder + "normal_gl.png") as Texture2D
		result.uv2_triplanar = true
		result.uv2_world_triplanar = true
		result.uv2_scale = Vector3.ONE * 1.4
		surfaces[key] = result
	return result
