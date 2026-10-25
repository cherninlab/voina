class_name RedDescentDungeon
extends Node3D
## First playable Red Descent. The village remains the default map.

const NAVE: String = "res://content/environments/red_nave_v1/"
const BRIDGE: String = "res://content/environments/bridge_well_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
var architecture: RedDescentGeometry
var dressing: RedDescentDressing
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
	var wood: ShaderMaterial = surface(PBR + "Wood035/", 0.65, 0.65, 1.3, Vector3(0.85, 0.9, 0.95))
	wood.set_shader_parameter("timber", true)
	wood.set_shader_parameter("relief_m", 0.009)
	wood.set_shader_parameter("dry_roughness_min", 0.75)
	wood.set_shader_parameter("wet_roughness", 0.32)
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.027, 0.027)
	dark.roughness = 1.0
	var cloth: StandardMaterial3D = StandardMaterial3D.new()
	cloth.albedo_color = Color(0.12, 0.085, 0.052)
	cloth.roughness = 1.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	architecture.materials = {
		"stone": surface(PBR + "Bricks089/", 0.16, 0.7, 0.8, Vector3(0.84, 0.9, 1.0)),
		"wall": surface(PBR + "Bricks089/", 0.16, 0.7, 1.0, Vector3(0.84, 0.9, 1.0)),
		"plaster": surface(PBR + "Concrete012/", 0.4, 0.6, 0.6, Vector3(0.86, 0.9, 0.95)),
		"red_plaster": surface(PBR + "Concrete012/", 0.4, 0.6, 0.5, Vector3(0.55, 0.055, 0.025)),
		"trim": surface(PBR + "Bricks083/", 0.33, 0.6, 0.5, Vector3(0.58, 0.56, 0.52)),
		"floor": surface(PBR + "Rocks025/", 0.526, 0.8, 1.4, Vector3(0.85, 0.9, 0.98)),
		"rock": surface(PBR + "marble_rock_03/", 0.555, 0.85, 1.4, Vector3(0.78, 0.9, 1.0)),
		"wood": wood, "iron": iron, "dark": dark, "cloth": cloth,
		"core_stone": GeneratedDungeonKit.material("wall_panel"),
	}
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
	for spot: Dictionary in architecture.sconces:
		sconce(spot["at"] as Vector3, spot["facing"] as Vector3)
	build_landmarks()
	dressing = RedDescentDressing.new()
	add_child(dressing)
	dressing.build(self)
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

## damp scales the shader's wet-patch mask, which it already scales by 0.65 above y -24, so 1.4
## makes upper floors fully wet where the mask says; tint pulls each scan toward cold grey
## stone (docs/red-descent-grade.md).
func surface(folder: String, density: float, relief: float, damp: float = 0.0, tint: Vector3 = Vector3.ONE) -> ShaderMaterial:
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
	material.set_shader_parameter("tint", tint)
	return material

func atmosphere() -> void:
	# Grade toward Theo's paintovers (docs/red-descent-grade.md): torches are the light, a dim
	# neutral fill keeps unlit stone grey, and depth fades into green-grey haze.
	var environment: Environment = Environment.new()
	var haze: Color = Color(0.11, 0.145, 0.13)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = haze
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.52, 0.53, 0.5)
	environment.ambient_light_energy = 0.16
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	# Mobile has no volumetric fog: thin distance fog leaves near stone unveiled, and height
	# fog that thickens below the lowest crossing (y -26) fills the abyss under the bridges.
	environment.fog_enabled = true
	environment.fog_light_color = haze
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.006
	environment.fog_height = -26.0
	environment.fog_height_density = 0.13
	# Flames, flame-lit niches and the brightest wet glints bloom into soft warm halos.
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_hdr_threshold = 0.7
	environment.set_glow_level(5, 0.8) # level 6: a wider, softer halo
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.92
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	# Red light from the shaft depths: short, strong lights well below the crossings show
	# through the height fog as a dull glow; one more fills the deep choir behind its doorway.
	for at: Vector3 in [Vector3(-12, -38, -14), Vector3(16, -38, 14), Vector3(-10, -39, 16), Vector3(14, -39, -16), Vector3(36, -25, -2)]:
		var glow: OmniLight3D = OmniLight3D.new()
		glow.position = at
		glow.light_color = Color(0.85, 0.16, 0.06)
		glow.light_energy = 8.0 if at.y < -30.0 else 3.0
		glow.omni_range = 15.0 if at.y < -30.0 else 16.0
		glow.omni_attenuation = 1.2 if at.y < -30.0 else 1.5
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

const CUP_LAYER: int = 1 << 19 # render layer 20: torch cups, unlit by their own flames

func torch(at: Vector3) -> void:
	architecture.piece(Vector3(0.16, 1.45, 0.16), at + Vector3.UP * 0.72, "wood")
	# The cup casts no shadow, or its own flame prints a black square under every torch where
	# the pool of light should be. It sits on a render layer the torch lights skip, so the
	# flame half a metre above does not burn its top white either.
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.36, 0.25, 0.36)
	var cup: MeshInstance3D = MeshInstance3D.new()
	cup.mesh = box
	cup.material_override = architecture.materials["iron"]
	cup.position = at + Vector3.UP * 1.48
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cup.layers = CUP_LAYER
	add_child(cup)
	fire(at + Vector3.UP * 1.95, at + Vector3.UP * 2.1)

## A wall sconce in a stone room: an iron plate set into the masonry, an arm
## with a brace under it, and a cup at its end. at is the wall face at sconce
## height; facing points into the room.
func sconce(at: Vector3, facing: Vector3) -> void:
	var along: Vector3 = Vector3.UP.cross(facing).normalized()
	# The plate sits a little into the face: the walls bow up to 4 cm proud of it.
	architecture.piece(Vector3(0.16, 0.38, 0.06), at + facing * 0.01 - Vector3.UP * 0.1, "iron", Basis(along, Vector3.UP, facing))
	var end: Vector3 = at + facing * 0.52
	architecture.beam(at + facing * 0.03, end, 0.05, "iron")
	architecture.beam(at + facing * 0.03 - Vector3.UP * 0.26, at + facing * 0.34, 0.03, "iron")
	var bowl: CylinderMesh = CylinderMesh.new()
	bowl.top_radius = 0.13
	bowl.bottom_radius = 0.05
	bowl.height = 0.14
	var cup: MeshInstance3D = MeshInstance3D.new()
	cup.mesh = bowl
	cup.material_override = architecture.materials["iron"]
	cup.position = end + Vector3.UP * 0.07
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cup.layers = CUP_LAYER
	add_child(cup)
	fire(end + Vector3.UP * 0.45, end + Vector3.UP * 0.6)

## A flame quad and its light, for torches and sconces.
func fire(flame_at: Vector3, light_at: Vector3) -> void:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://content/environments/church_road/torch_flame.gdshader")
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.38, 0.65)
	var flame: MeshInstance3D = MeshInstance3D.new()
	flame.mesh = quad
	flame.material_override = material
	flame.position = flame_at
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_instance_shader_parameter("seed", float(fires.size()) * 0.137)
	add_child(flame)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = light_at
	# Steeper than inverse-square falloff gives each torch its own amber pool with dark gaps
	# between, so vaults and corners drop toward black; full specular lets wet patches glint.
	# Red minus blue stays above 0.5 so ui/shading_lighting.gd still treats it as a fire.
	light.light_color = Color(1.0, 0.62, 0.34)
	light.light_energy = 8.0
	light.omni_range = 12.0
	light.omni_attenuation = 2.5
	light.light_specular = 1.0
	light.light_cull_mask = ~CUP_LAYER & 0xFFFFF
	add_child(light)
	fires.append(light)

func build_landmarks() -> void:
	# Cold light at the entrance keeps the forest world perceptible behind the descent.
	var entrance: OmniLight3D = OmniLight3D.new()
	entrance.position = RedDescentLayout.at(Vector3(6, 3, 24))
	entrance.light_color = Color(0.32, 0.47, 0.62)
	# A breath of daylight at the threshold, not a lamp in the entry room's vault.
	entrance.light_energy = 1.6
	entrance.omni_range = 11
	add_child(entrance)
	# A simple physical restraint frame in the upper hall, set clear of the walking line.
	# Clear of the upper cells loop, which now comes back into the restraint through its east wall.
	var frame: Vector3 = RedDescentLayout.at(Vector3(90, -4, 40))
	for side: float in [-1.0, 1.0]:
		var foot: Vector3 = frame + Vector3(side * 1.1, 0, 0)
		architecture.piece(Vector3(0.34, 3.7, 0.34), foot + Vector3.UP * 1.85, "collision", Basis.IDENTITY, true)
		architecture.structure.timber(foot, foot + Vector3.UP * 3.7, 0.34, 0.34, "restraint post")
	architecture.structure.timber(frame + Vector3(-1.4, 3.1, 0), frame + Vector3(1.4, 3.1, 0), 0.4, 0.36, "restraint beam")
	# In the choir's open floor, clear of the return stair that climbs its walls.
	var altar: Vector3 = RedDescentLayout.at(Vector3(84, -28, 64))
	architecture.piece(Vector3(3.4, 1.1, 1.6), altar + Vector3.UP * 0.55, "stone", Basis.IDENTITY, true)
	architecture.piece(Vector3(3.8, 0.25, 2), altar + Vector3.UP * 1.2, "trim", Basis.IDENTITY, true)
	# Distinct side-hall silhouettes: rough coffins, nave rafters and an iron bell.
	for design: Vector3 in [Vector3(17, -10, 13), Vector3(21, -10, 13), Vector3(12, -10, 31), Vector3(23, -10, 31), Vector3(46, -18, 94), Vector3(54, -18, 94)]:
		var at: Vector3 = RedDescentLayout.at(design)
		# Stone-built rooms carry the T-171 mortuary and ossuary sets with real coffins.
		if architecture.stone_room_near(at + Vector3.UP * 0.3, 0.0):
			continue
		architecture.piece(Vector3(1.0, 0.65, 2.4), at + Vector3.UP * 0.35, "wood", Basis.IDENTITY, true)
		architecture.piece(Vector3(1.14, 0.12, 2.55), at + Vector3.UP * 0.72, "wood")
		for offset: float in [-0.75, 0.75]:
			architecture.piece(Vector3(1.15, 0.05, 0.08), at + Vector3(0, 0.8, offset), "iron")
	var bell_at: Vector3 = RedDescentLayout.at(Vector3(82, -12, 88))
	for side: float in [-1.0, 1.0]:
		var foot: Vector3 = bell_at + Vector3(side * 5.0, -6, 0)
		architecture.structure.timber(foot, foot + Vector3.UP * 8.0, 0.48, 0.48, "bell post")
		architecture.structure.timber(foot + Vector3.UP * 6.0, bell_at + Vector3(side * 3.0, 2, 0), 0.28, 0.28, "bell knee")
		architecture.piece(Vector3(0.9, 0.4, 0.9), foot + Vector3.UP * 0.2, "trim")
	architecture.structure.timber(bell_at + Vector3(-5, 2, 0), bell_at + Vector3(5, 2, 0), 0.4, 0.4, "bell beam")
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
