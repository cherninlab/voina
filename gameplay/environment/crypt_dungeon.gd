class_name RedDescentDungeon
extends Node3D
## First playable Red Descent. The village remains the default map.

const NAVE: String = "res://content/environments/red_nave_v1/"
const BRIDGE: String = "res://content/environments/bridge_well_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
var architecture: RedDescentGeometry
var objective: Label = Label.new()
var fires: Array[OmniLight3D] = []
var light_timer: float = 0.0

func _ready() -> void:
	name = "CinderCrypt"
	atmosphere()
	architecture = RedDescentGeometry.new()
	var iron: ShaderMaterial = surface(PBR + "Metal041B/", 1.5, 0.4)
	iron.set_shader_parameter("metallic_map", load(PBR + "Metal041B/metallic.png"))
	iron.set_shader_parameter("metallic_amount", 1.0)
	iron.set_shader_parameter("dry_roughness_min", 0.28)
	var wood: ShaderMaterial = surface(PBR + "Wood035/", 0.65, 0.65, 0.68)
	wood.set_shader_parameter("timber", true)
	wood.set_shader_parameter("relief_m", 0.009)
	wood.set_shader_parameter("dry_roughness_min", 0.75)
	wood.set_shader_parameter("wet_roughness", 0.32)
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.027, 0.027)
	dark.roughness = 1.0
	architecture.materials = {
		"stone": surface(PBR + "Bricks089/", 0.22, 0.7, 0.22),
		"wall": surface(PBR + "Bricks089/", 0.22, 0.7, 0.5),
		"plaster": surface(PBR + "Concrete012/", 0.4, 0.6, 0.25),
		"red_plaster": surface(PBR + "Concrete012/", 0.4, 0.6),
		"trim": surface(PBR + "Bricks083/", 0.33, 0.6),
		"floor": surface(PBR + "Rocks025/", 0.526, 0.8, 0.4),
		"rock": surface(PBR + "marble_rock_03/", 0.555, 0.85, 0.3),
		"wood": wood, "iron": iron, "dark": dark,
		"core_stone": GeneratedDungeonKit.material("wall_panel"),
	}
	(architecture.materials["trim"] as ShaderMaterial).set_shader_parameter("tint", Vector3(0.62, 0.57, 0.47))
	(architecture.materials["red_plaster"] as ShaderMaterial).set_shader_parameter("tint", Vector3(0.55, 0.055, 0.025))
	for family: String in ["plaster", "red_plaster"]:
		var plaster: ShaderMaterial = architecture.materials[family] as ShaderMaterial
		plaster.set_shader_parameter("plaster", 1.0)
		plaster.set_shader_parameter("substrate_albedo", load(PBR + "Bricks089/albedo.png"))
		plaster.set_shader_parameter("substrate_normal", load(PBR + "Bricks089/normal_gl.png"))
		plaster.set_shader_parameter("substrate_roughness", load(PBR + "Bricks089/roughness.png"))
		plaster.set_shader_parameter("substrate_ao", load(PBR + "Bricks089/ao.png"))
	for family: String in ["wall", "plaster", "floor"]:
		(architecture.materials[family] as ShaderMaterial).set_shader_parameter("algae", 0.6)
	add_child(architecture)
	architecture.build()
	# Practical lights remain sparse along the route; the side halls supply landmarks.
	for at: Vector3 in architecture.torch_posts:
		torch(at)
	build_landmarks()
	architecture.flush()
	# Static local reflections give wet timber and iron the surrounding architecture's light.
	for position_size: Array in [
		[Vector3(0, -17, 0), Vector3(62, 60, 70)],
		[Vector3(0, -10, 38), Vector3(36, 23, 35)],
	]:
		var probe: ReflectionProbe = ReflectionProbe.new()
		probe.position = position_size[0]
		probe.size = position_size[1]
		probe.max_distance = 65.0
		probe.interior = true
		probe.box_projection = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.intensity = 0.6
		add_child(probe)
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

func surface(folder: String, density: float, relief: float, damp: float = 0.0) -> ShaderMaterial:
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
	# Faint reflected light in the depths lets crossings read against the dark walls.
	for at: Vector3 in [Vector3(0, -34, -8), Vector3(14, -43, 9), Vector3(0, -20, 0), Vector3(14, -31, 4)]:
		var glow: OmniLight3D = OmniLight3D.new()
		glow.position = at
		glow.light_color = Color(0.13, 0.3, 0.26) if at.y < -40.0 else Color(0.55, 0.13, 0.065)
		glow.light_energy = 1.6
		glow.omni_range = 26
		glow.omni_attenuation = 1.3
		add_child(glow)
	var water_mesh: PlaneMesh = PlaneMesh.new()
	water_mesh.size = Vector2(92, 100)
	water_mesh.subdivide_width = 48
	water_mesh.subdivide_depth = 48
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "DeepWater"
	water.mesh = water_mesh
	water.material_override = load(BRIDGE + "water/material.tres") as Material
	water.position.y = -47.5
	add_child(water)

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
