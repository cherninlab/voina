extends Node3D
## Review stage for the hanging dressing: dungeon timber (hewn_timber GLB and the crypt's wood
## material) under one warm torch light. Every asset is placed only from its bake.json sockets, the
## way an integrator would, and each placement is checked against the socket nodes in its GLB.
## Not used by the game. Capture with preview/capture.gd.

const ROOT: String = "res://content/environments/procedural_hanging_v1/"
const STRUCTURE: String = "res://content/environments/dungeon_structure_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
const BRIDGE: String = "res://content/environments/bridge_well_v1/"
const NAVE: String = "res://content/environments/red_nave_v1/"
const BEAM_Y: float = 3.0
const BEAM_SIZE: float = 0.25

var assets: Dictionary[String, Dictionary] = {}
var socket_error: float = 0.0
var placed: Array[String] = []
var views: Array[Dictionary] = []

func _ready() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "bake.json")) as Dictionary
	for entry: Variant in report["assets"]:
		var asset: Dictionary = entry as Dictionary
		assets["%s_%d" % [asset["type"], int(asset["variant"])]] = asset
	atmosphere()
	var wood: ShaderMaterial = surface(PBR + "Wood035/", 0.65, 0.65, 0.68)
	wood.set_shader_parameter("timber", true)
	wood.set_shader_parameter("relief_m", 0.009)
	wood.set_shader_parameter("dry_roughness_min", 0.75)
	wood.set_shader_parameter("wet_roughness", 0.32)
	var stone: ShaderMaterial = surface(PBR + "Bricks089/", 0.16, 0.7, 0.5)
	var floor_stone: ShaderMaterial = surface(PBR + "Rocks025/", 0.526, 0.8, 0.4)
	block(Vector3(0.0, -0.1, -0.5), Vector3(11.0, 0.2, 7.0), floor_stone)
	block(Vector3(0.0, 2.2, -2.45), Vector3(11.0, 4.4, 0.5), stone)
	block(Vector3(-4.45, 2.2, -0.5), Vector3(0.5, 4.4, 7.0), stone)
	# Two parallel cloth bearers (0.25 m, as in dungeon_structure.gd) run from the left wall to a
	# post; a batten on the back wall carries a tapestry.
	var front: float = 0.0
	var back: float = -1.51
	for z: float in [front, back]:
		timber(Vector3(-4.3, BEAM_Y, z), Vector3(3.2, BEAM_Y, z), BEAM_SIZE, BEAM_SIZE, wood)
	var post_x: float = 2.85
	timber(Vector3(post_x, 0.0, front), Vector3(post_x, BEAM_Y + 0.125, front), 0.3, 0.3, wood)
	timber(Vector3(post_x, 0.0, back), Vector3(post_x, BEAM_Y + 0.125, back), 0.3, 0.3, wood)
	# Wall batten: 0.14 m deep against the back wall, nails on its underside clear of the wall.
	timber(Vector3(-3.6, 2.6, -2.13), Vector3(-0.6, 2.6, -2.13), 0.14, 0.08, wood)
	var underside: float = BEAM_Y - BEAM_SIZE * 0.5
	var along: Basis = Basis.IDENTITY
	# Banners: the nail line lies on the beam underside.
	hang("banner_1", Vector3(-2.75, underside, front), along, "cloth_crimson")
	hang("banner_0", Vector3(-1.45, underside, front), along, "cloth_ochre")
	hang("banner_2", Vector3(-0.55, underside, front), along, "cloth_crimson")
	# Drape over the same 0.25 m bearer: the origin is the beam axis.
	hang("drape_0", Vector3(0.45, BEAM_Y, front), along, "cloth_ash")
	# Rope festooned under the bearer between two eyes, its tail hanging near the post.
	var rope_at: Vector3 = Vector3(1.15, underside, front)
	hang("rope_2", rope_at, along, "rope_hemp")
	# Corner web where the back bearer meets its post: apex in the corner, edges along -X and -Y.
	var web_at: Vector3 = Vector3(post_x - 0.15, underside, back)
	hang("web_corner_2", web_at, Basis(Vector3.UP, PI), "cobweb_corner")
	# Sheet web slung between the two bearers' inner bottom arrises.
	var gap: float = float(assets["web_sheet_0"]["gap_m"])
	assert(is_equal_approx(gap, absf(back - front) - BEAM_SIZE), "web_sheet_0 gap does not match the bearer spacing")
	var sheet_at: Vector3 = Vector3(1.75, underside, (front + back) * 0.5)
	hang("web_sheet_0", sheet_at, Basis(Vector3.UP, PI), "cobweb_sheet")
	# Tapestry on the batten.
	hang("tapestry_0", Vector3(-2.1, 2.56, -2.08), along, "cloth_crimson")
	var torch: OmniLight3D = OmniLight3D.new()
	torch.position = Vector3(0.6, 1.7, 1.3)
	torch.light_color = Color(1.0, 0.63, 0.3)
	torch.light_energy = 3.6
	torch.omni_range = 10.5
	torch.omni_attenuation = 1.25
	torch.shadow_enabled = true
	add_child(torch)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.position = Vector3(-3.2, 0.8, 0.8)
	glow.light_color = Color(0.55, 0.13, 0.065)
	glow.light_energy = 1.2
	glow.omni_range = 7.0
	add_child(glow)
	var rope_b: Vector3 = rope_at + array3((assets["rope_2"]["sockets_godot"] as Dictionary)["b"])
	views = [
		{"name": "01-overview", "from": Vector3(-0.3, 1.55, 5.2), "to": Vector3(-0.3, 2.0, -0.8), "fov": 62.0},
		{"name": "02-banner-on-beam", "from": Vector3(-1.75, 2.1, 1.5), "to": Vector3(-1.75, 2.4, 0.0), "fov": 50.0},
		{"name": "03-drape-and-rope", "from": Vector3(1.0, 2.0, 2.2), "to": rope_b.lerp(Vector3(0.45, BEAM_Y, front), 0.5) + Vector3(0.0, -0.35, 0.0), "fov": 52.0},
		{"name": "04-sheet-web-from-below", "from": Vector3(2.55, 1.55, 0.75), "to": sheet_at + Vector3(-0.1, -0.15, 0.0), "fov": 58.0},
		{"name": "05-corner-web", "from": web_at + Vector3(-0.6, -0.55, 0.8), "to": web_at + Vector3(-0.25, -0.3, 0.0), "fov": 50.0},
	]
	print("HANGING_PREVIEW placed=%s socket_error_m=%.6f" % [str(placed), socket_error])

func hang(id: String, origin: Vector3, basis: Basis, material: String) -> void:
	var asset: Dictionary = assets[id]
	var scene: Node3D = (load(ROOT + id + ".glb") as PackedScene).instantiate() as Node3D
	scene.transform = Transform3D(basis, origin)
	add_child(scene)
	var override: Material = load(ROOT + material + ".tres") as Material
	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 1, id + " should hold exactly one mesh")
	(meshes[0] as MeshInstance3D).material_override = override
	assert(scene.find_children("*", "CollisionShape3D", true, false).is_empty(), id + " must not import collision")
	# The GLB's socket nodes and bake.json must agree.
	var sockets: Dictionary = asset["sockets_godot"] as Dictionary
	for socket: String in sockets:
		var node: Node3D = scene.find_child("socket_" + socket, true, false) as Node3D
		assert(node != null, id + " lacks socket node " + socket)
		socket_error = maxf(socket_error, node.position.distance_to(array3(sockets[socket])))
	placed.append(id)

func array3(value: Variant) -> Vector3:
	var list: Array = value as Array
	return Vector3(float(list[0]), float(list[1]), float(list[2]))

func timber(a: Vector3, b: Vector3, width: float, depth: float, material: Material) -> void:
	# Same fitting as DungeonStructure.timber: unit hewn timber scaled to the member.
	var up: Vector3 = Vector3.FORWARD if absf((b - a).normalized().y) > 0.98 else Vector3.UP
	var basis: Basis = Basis.looking_at(b - a, up) * Basis.from_scale(Vector3(width, depth, a.distance_to(b)))
	var source: Node3D = (load(STRUCTURE + "hewn_timber_0.glb") as PackedScene).instantiate() as Node3D
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = (source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	source.free()
	visual.transform = Transform3D(basis, (a + b) * 0.5)
	visual.material_override = material
	add_child(visual)

func block(center: Vector3, size: Vector3, material: Material) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = box
	visual.position = center
	visual.material_override = material
	add_child(visual)

func surface(folder: String, density: float, relief: float, damp: float = 0.0) -> ShaderMaterial:
	# Mirrors RedDescentDungeon.surface() so the stage uses the crypt's own materials.
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://content/environments/red_descent/dungeon_surface.gdshader")
	var albedo: Texture2D = load(folder + "albedo.png") as Texture2D
	material.set_shader_parameter("albedo_map", albedo)
	material.set_shader_parameter("aspect", float(albedo.get_width()) / float(albedo.get_height()))
	material.set_shader_parameter("normal_map", load(folder + "normal_gl.png"))
	material.set_shader_parameter("roughness_map", load(folder + "roughness.png"))
	if ResourceLoader.exists(folder + "ao.png"):
		material.set_shader_parameter("ao_map", load(folder + "ao.png"))
	material.set_shader_parameter("wet_map", load(BRIDGE + "masks/wet_patches.png"))
	material.set_shader_parameter("height_map", load(folder + "height.png"))
	material.set_shader_parameter("peel_map", load(NAVE + "masks/plaster_peel.png"))
	material.set_shader_parameter("algae_map", load(BRIDGE + "masks/algae_coverage.png"))
	material.set_shader_parameter("scale", density)
	material.set_shader_parameter("normal_strength", relief)
	material.set_shader_parameter("wetness", damp)
	return material

func atmosphere() -> void:
	# The crypt's environment (RedDescentDungeon.atmosphere) without its water.
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.009, 0.005, 0.005)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.43, 0.46)
	environment.ambient_light_energy = 0.36
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.009, 0.005)
	environment.fog_light_energy = 0.8
	environment.fog_density = 0.009
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
