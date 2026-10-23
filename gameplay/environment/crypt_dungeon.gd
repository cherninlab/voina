class_name RedDescentDungeon
extends Node3D
## First playable Red Descent. The village remains the default map.

const TEXTURES: String = "res://content/environments/valhalla/textures/KB3D_VHL_"
const GENERATED: String = "res://content/environments/red_descent/"
var architecture: RedDescentGeometry
var objective: Label = Label.new()
var fires: Array[OmniLight3D] = []
var light_timer: float = 0.0

func _ready() -> void:
	name = "CinderCrypt"
	atmosphere()
	architecture = RedDescentGeometry.new()
	var wood: ShaderMaterial = masonry("StoneGeneric", Color(0.68, 0.64, 0.57))
	wood.set_shader_parameter("albedo_map", load(GENERATED + "wood_albedo.png"))
	wood.set_shader_parameter("normal_map", load(GENERATED + "wood_normal.png"))
	wood.set_shader_parameter("scale", 0.5)
	wood.set_shader_parameter("normal_strength", 0.45)
	wood.set_shader_parameter("moss", 0.0)
	wood.set_shader_parameter("ash", 0.0)
	var iron: StandardMaterial3D = StandardMaterial3D.new()
	iron.albedo_color = Color(0.075, 0.065, 0.055)
	iron.metallic = 0.5
	iron.roughness = 0.85
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.031, 0.029)
	dark.roughness = 1.0
	architecture.materials = {"stone": masonry("StoneGeneric", Color(0.65, 0.66, 0.62)), "trim": masonry("StoneGeneric", Color(0.73, 0.69, 0.59)), "floor": masonry("StoneFloor", Color(0.58, 0.58, 0.54)), "wood": wood, "iron": iron, "dark": dark}
	add_child(architecture)
	architecture.build()
	# Practical lights remain sparse along the route; the side halls supply landmarks.
	for at: Vector3 in architecture.torch_posts:
		torch(at)
	build_landmarks()
	architecture.flush()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_left = 300
	objective.offset_right = -24
	objective.offset_top = 24
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.86, 0.78, 0.64))
	objective.add_theme_color_override("font_outline_color", Color.BLACK)
	objective.add_theme_constant_override("outline_size", 5)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(objective)

func masonry(family: String, tint: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://content/environments/church/church_stone.gdshader")
	material.set_shader_parameter("albedo_map", load(TEXTURES + family + "_basecolor.png"))
	material.set_shader_parameter("normal_map", load(TEXTURES + family + "_normal.png"))
	material.set_shader_parameter("roughness_map", load(TEXTURES + family + "_roughness.png"))
	if family == "StoneGeneric" and ResourceLoader.exists(GENERATED + "stone_albedo.png"):
		material.set_shader_parameter("albedo_map", load(GENERATED + "stone_albedo.png"))
	if family == "StoneGeneric" and ResourceLoader.exists(GENERATED + "stone_normal.png"):
		material.set_shader_parameter("normal_map", load(GENERATED + "stone_normal.png"))
	if family == "StoneGeneric" and ResourceLoader.exists(GENERATED + "stone_roughness.png"):
		material.set_shader_parameter("roughness_map", load(GENERATED + "stone_roughness.png"))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("scale", 0.25 if family == "StoneGeneric" else 0.55)
	material.set_shader_parameter("normal_strength", 0.6)
	material.set_shader_parameter("moss", 0.035)
	material.set_shader_parameter("ash", 0.12)
	material.set_shader_parameter("grime", 0.3)
	return material

func atmosphere() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.009, 0.005, 0.005)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.43, 0.45, 0.46)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.009, 0.005)
	environment.fog_light_energy = 0.8
	environment.fog_density = 0.009
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	# Faint reflected light in the depths lets crossings read against the dark walls.
	for at: Vector3 in [Vector3(0, -34, -8), Vector3(14, -43, 9), Vector3(0, -20, 0), Vector3(14, -31, 4)]:
		var glow: OmniLight3D = OmniLight3D.new()
		glow.position = at
		glow.light_color = Color(0.9, 0.075, 0.018)
		glow.light_energy = 5.5
		glow.omni_range = 36
		glow.omni_attenuation = 1.3
		add_child(glow)

func torch(at: Vector3) -> void:
	architecture.piece(Vector3(0.16, 1.45, 0.16), at + Vector3.UP * 0.72, "wood")
	architecture.piece(Vector3(0.36, 0.25, 0.36), at + Vector3.UP * 1.48, "iron")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://content/environments/church_road/torch_flame.gdshader")
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.38, 0.65)
	var flame: MeshInstance3D = MeshInstance3D.new()
	flame.mesh = quad
	flame.material_override = material
	flame.position = at + Vector3.UP * 1.95
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_instance_shader_parameter("seed", float(fires.size()) * 0.137)
	add_child(flame)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = at + Vector3.UP * 2.1
	light.light_color = Color(1.0, 0.63, 0.3)
	light.light_energy = 3.6
	light.omni_range = 10.5
	light.omni_attenuation = 1.25
	add_child(light)
	fires.append(light)

func build_landmarks() -> void:
	# Cold light at the entrance keeps the forest world perceptible behind the descent.
	var entrance: OmniLight3D = OmniLight3D.new()
	entrance.position = RedDescentLayout.at(Vector3(6, 3, 24))
	entrance.light_color = Color(0.32, 0.47, 0.62)
	entrance.light_energy = 4.0
	entrance.omni_range = 16
	add_child(entrance)
	# A simple physical restraint frame in the upper hall, set clear of the walking line.
	var frame: Vector3 = RedDescentLayout.at(Vector3(90, -4, 37))
	for side: float in [-1.0, 1.0]:
		architecture.piece(Vector3(0.34, 3.7, 0.34), frame + Vector3(side * 1.1, 1.85, 0), "wood", Basis.IDENTITY, true)
	architecture.piece(Vector3(2.8, 0.36, 0.4), frame + Vector3.UP * 3.1, "wood")
	var altar: Vector3 = RedDescentLayout.at(Vector3(88, -28, 41))
	architecture.piece(Vector3(3.4, 1.1, 1.6), altar + Vector3.UP * 0.55, "stone", Basis.IDENTITY, true)
	architecture.piece(Vector3(3.8, 0.25, 2), altar + Vector3.UP * 1.2, "trim", Basis.IDENTITY, true)
	# Distinct side-hall silhouettes: rough coffins, nave rafters and an iron bell.
	for design: Vector3 in [Vector3(17, -10, 13), Vector3(21, -10, 13), Vector3(12, -10, 31), Vector3(23, -10, 31), Vector3(46, -18, 94), Vector3(54, -18, 94)]:
		var at: Vector3 = RedDescentLayout.at(design)
		architecture.piece(Vector3(1.0, 0.65, 2.4), at + Vector3.UP * 0.35, "wood", Basis.IDENTITY, true)
		architecture.piece(Vector3(1.14, 0.12, 2.55), at + Vector3.UP * 0.72, "wood")
		for offset: float in [-0.75, 0.75]:
			architecture.piece(Vector3(1.15, 0.05, 0.08), at + Vector3(0, 0.8, offset), "iron")
	for z: float in [82, 88, 94]:
		var at: Vector3 = RedDescentLayout.at(Vector3(50, -8, z))
		architecture.beam(at + Vector3(-13, 0, 0), at + Vector3(13, 0, 0), 0.35, "wood")
		architecture.beam(at + Vector3(-13, -2, 0), at + Vector3(0, 1, 0), 0.24, "wood")
		architecture.beam(at + Vector3(0, 1, 0), at + Vector3(13, -2, 0), 0.24, "wood")
	var bell_at: Vector3 = RedDescentLayout.at(Vector3(82, -12, 88))
	architecture.beam(bell_at + Vector3(-5, 2, 0), bell_at + Vector3(5, 2, 0), 0.4, "wood")
	architecture.beam(bell_at + Vector3.UP * 2, bell_at, 0.07, "iron")
	var bell: CylinderMesh = CylinderMesh.new()
	bell.top_radius = 0.38
	bell.bottom_radius = 1.35
	bell.height = 2.2
	bell.radial_segments = 16
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = bell
	visual.material_override = architecture.materials["iron"]
	visual.position = bell_at - Vector3.UP * 1.1
	add_child(visual)
	architecture.beam(bell_at - Vector3.UP, bell_at - Vector3.UP * 3, 0.18, "iron")
	# Ragged remnants hang below the crossings, with enough room above the next route.
	var cloth: StandardMaterial3D = StandardMaterial3D.new()
	cloth.albedo_color = Color(0.18, 0.115, 0.075)
	cloth.roughness = 1.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index: int in [2, 5, 9]:
		var path: Dictionary = RedDescentLayout.routes()[index]
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for node: int in range(1, points.size() - 1, 2):
			var point: Vector3 = points[node] + Vector3(float(path["width"]) * 0.45, -0.2, 0)
			var vertices: PackedVector3Array = PackedVector3Array([point, point + Vector3(0.2, -0.1, 0), point + Vector3(0.08, -1.6, 0.25)])
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var remnant: MeshInstance3D = MeshInstance3D.new()
			remnant.mesh = mesh
			remnant.material_override = cloth
			add_child(remnant)

func player_spawn(slot: int) -> Vector3:
	return RedDescentLayout.player_spawn(slot)

func _process(delta: float) -> void:
	light_timer -= delta
	if light_timer <= 0.0:
		light_timer = 0.3
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			var ordered: Array[OmniLight3D] = fires.duplicate()
			ordered.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(camera.global_position) < b.global_position.distance_squared_to(camera.global_position))
			for index: int in range(ordered.size()):
				ordered[index].shadow_enabled = index < 6 and ordered[index].global_position.distance_to(camera.global_position) < 20.0
	var world: Node3D = get_parent() as Node3D
	var players: Node3D = world.get("players") as Node3D
	if players == null:
		return
	var local: Node3D = players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	objective.visible = local != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if local == null:
		return
	var mobs: Node = world.get("mobs") as Node
	var remaining: int = int(mobs.get("remaining")) if mobs != null else 5
	objective.text = "RED DESCENT  ·  %d / 5 cultists remain\nFind the deep choir below the crossings." % remaining
	if remaining == 0 and local.position.distance_to(RedDescentLayout.finish_point()) < 4.0:
		objective.text = "RED DESCENT  ·  CLEARED\nThe eastern stair leads back to the entrance route."
