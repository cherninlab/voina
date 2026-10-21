extends Node3D
## Cinder Crypt: original geometry, existing licensed stone textures and flame shader.
## One floor fits the existing 44 m mob grid; collision never depends on visual dressing.

const TEXTURES: String = "res://content/environments/valhalla/textures/KB3D_VHL_"
var stone: ShaderMaterial
var trim: ShaderMaterial
var floor_material: ShaderMaterial
var iron: StandardMaterial3D
var flame: ShaderMaterial
var objective: Label = Label.new()
var fires: Array[OmniLight3D] = []

func _ready() -> void:
	name = "CinderCrypt"
	stone = masonry("StoneGeneric", Color(0.64, 0.68, 0.7))
	trim = masonry("StoneGeneric", Color(0.78, 0.75, 0.65))
	floor_material = masonry("StoneFloor", Color(0.56, 0.58, 0.59))
	iron = StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.10, 0.085)
	iron.metallic = 0.65
	iron.roughness = 0.8
	flame = ShaderMaterial.new()
	flame.shader = preload("res://content/environments/church_road/torch_flame.gdshader")
	atmosphere()
	# Entrance, burial hall, short throat and altar chamber. All floors meet at y=0.
	for room: Rect2 in [Rect2(-5, 8, 10, 13), Rect2(-13, -7, 26, 15), Rect2(-3, -12, 6, 5), Rect2(-9, -21, 18, 9)]:
		box(Vector3(room.size.x, 0.5, room.size.y), Vector3(room.get_center().x, -0.25, room.get_center().y), floor_material, true)
		box(Vector3(room.size.x + 1.0, 0.6, room.size.y + 1.0), Vector3(room.get_center().x, 7.2, room.get_center().y), stone, true)
	# Outer walls, then the shoulders between each room and its doorway.
	wall(Vector2(-5, 8), Vector2(-5, 21))
	wall(Vector2(5, 8), Vector2(5, 21))
	wall(Vector2(-5, 21), Vector2(5, 21))
	wall(Vector2(-13, -7), Vector2(-13, 8))
	wall(Vector2(13, -7), Vector2(13, 8))
	for z: float in [8.0, -7.0]:
		wall(Vector2(-13, z), Vector2(-2.5, z))
		wall(Vector2(2.5, z), Vector2(13, z))
	wall(Vector2(-3, -12), Vector2(-3, -7))
	wall(Vector2(3, -12), Vector2(3, -7))
	wall(Vector2(-9, -21), Vector2(-9, -12))
	wall(Vector2(9, -21), Vector2(9, -12))
	wall(Vector2(-9, -21), Vector2(9, -21))
	wall(Vector2(-9, -12), Vector2(-2.5, -12))
	wall(Vector2(2.5, -12), Vector2(9, -12))
	for z: float in [8.0, -7.0, -12.0]:
		arch(z, 2.5)
	# Central tomb breaks sight and creates two wide, reconnecting combat lanes.
	tomb(Vector3(0, 0, 1), 1.25)
	# A low inscription screen keeps the entrance sheltered, with room to pass on either side.
	box(Vector3(3.6, 2.5, 0.65), Vector3(0, 1.25, 11.5), stone, true)
	inscription("C I N D E R   C R Y P T", Vector3(0, 1.8, 11.88), 0.005)
	inscription("THE FIVE KEEP WATCH\nSilence them. Reach the altar.", Vector3(0, 1.05, 11.89), 0.003)
	# Colliding columns; the ribs are cosmetic, well above a jumping player's capsule.
	for x: float in [-7.5, 7.5]:
		for z: float in [-4.0, 4.5]:
			box(Vector3(1.35, 0.3, 1.35), Vector3(x, 0.15, z), trim, true)
			box(Vector3(0.95, 4.6, 0.95), Vector3(x, 2.6, z), stone, true)
			box(Vector3(1.5, 0.4, 1.5), Vector3(x, 5.1, z), trim)
	for z: float in [-4.0, 4.5]:
		rib(z, 12.8)
	for side: float in [-1.0, 1.0]:
		for z: float in [-3.5, 3.5]:
			tomb(Vector3(side * 11.2, 0, z), 0.8)
		for z: float in [16.0, 9.0]:
			brazier(Vector3(side * 3.7, 0, z))
		for z: float in [5.0, -5.0]:
			brazier(Vector3(side * 10.0, 0, z))
		brazier(Vector3(side * 6.8, 0, -17.5))
		# Recessed-looking burial tablets on the end wall of the final chamber.
		for x: float in [3.0, 5.3, 7.6]:
			box(Vector3(1.4, 2.7, 0.2), Vector3(side * x, 2.0, -20.62), iron)
			box(Vector3(0.11, 1.0, 0.13), Vector3(side * x, 2.2, -20.47), trim)
			box(Vector3(0.65, 0.11, 0.13), Vector3(side * x, 2.4, -20.45), trim)
	# The altar is a clear landmark; no loot or interaction is implied by the prototype.
	box(Vector3(4.2, 0.25, 2.0), Vector3(0, 0.125, -18.4), trim, true)
	box(Vector3(2.6, 1.05, 1.0), Vector3(0, 0.775, -18.4), stone, true)
	box(Vector3(3.1, 0.2, 1.5), Vector3(0, 1.4, -18.4), trim, true)
	inscription("LET THE CINDERS REST", Vector3(0, 3.6, -20.55), 0.005)
	var cold: OmniLight3D = OmniLight3D.new()
	cold.position = Vector3(0, 4.0, -18)
	cold.light_color = Color(0.35, 0.62, 0.9)
	cold.light_energy = 2.2
	cold.omni_range = 11.0
	add_child(cold)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_left = 300
	objective.offset_right = -24
	objective.offset_top = 24
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.9, 0.83, 0.66))
	objective.add_theme_color_override("font_outline_color", Color.BLACK)
	objective.add_theme_constant_override("outline_size", 5)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(objective)
	print("DUNGEON_GEOMETRY_READY: entrance, burial hall loop, altar")

func masonry(family: String, tint: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://content/environments/church/church_stone.gdshader")
	material.set_shader_parameter("albedo_map", load(TEXTURES + family + "_basecolor.png"))
	material.set_shader_parameter("normal_map", load(TEXTURES + family + "_normal.png"))
	material.set_shader_parameter("roughness_map", load(TEXTURES + family + "_roughness.png"))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("scale", 0.65)
	material.set_shader_parameter("moss", 0.08)
	material.set_shader_parameter("ash", 0.2)
	material.set_shader_parameter("grime", 0.35)
	return material

func atmosphere() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.018, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.38, 0.47, 0.6)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.045, 0.065, 0.09)
	environment.fog_density = 0.006
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func box(size: Vector3, at: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		visual.add_child(body)
	return visual

func wall(from: Vector2, to: Vector2) -> void:
	var delta: Vector2 = to - from
	var middle: Vector2 = (from + to) * 0.5
	var length: float = delta.length()
	var wall_mesh: MeshInstance3D = box(Vector3(length + 0.6, 7.0, 0.65), Vector3(middle.x, 3.5, middle.y), stone, true)
	wall_mesh.rotation.y = -atan2(delta.y, delta.x)
	# Individual weathered courses, batched per wall. Their shallow joints catch the fire light.
	var mesh: BoxMesh = BoxMesh.new()
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	var columns: int = ceili(length / 1.6)
	multi.instance_count = columns * 11
	for row: int in range(11):
		for column: int in range(columns):
			var slot: int = row * columns + column
			var x: float = (float(column) + 0.5) * length / float(columns) - length * 0.5
			var y: float = float(row) * 0.61 - 3.16
			multi.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3(length / float(columns) - 0.035, 0.57, 0.75)), Vector3(x, y, 0)))
			var value: float = 0.82 + float(posmod(row * 17 + column * 31, 19)) * 0.018
			multi.set_instance_color(slot, Color(value, value, value))
	var facing: MultiMeshInstance3D = MultiMeshInstance3D.new()
	facing.multimesh = multi
	facing.material_override = stone
	wall_mesh.add_child(facing)

func arch(z: float, half_width: float) -> void:
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.5, 3.5, 1.0), Vector3(side * half_width, 1.75, z), trim, true)
	for segment: int in range(11):
		var angle: float = float(segment) / 10.0 * PI
		var piece: MeshInstance3D = box(Vector3(0.8, 0.6, 1.0), Vector3(cos(angle) * half_width, 3.5 + sin(angle) * half_width, z), trim)
		piece.rotation.z = angle - PI * 0.5
	box(Vector3(5.0, 0.8, 0.75), Vector3(0, 6.8, z), stone, true)

func rib(z: float, half_width: float) -> void:
	for segment: int in range(13):
		var x: float = -half_width + (float(segment) + 0.5) * half_width * 2.0 / 13.0
		var y: float = 5.3 + 1.3 * (1.0 - pow(x / half_width, 2.0))
		var piece: MeshInstance3D = box(Vector3(half_width * 2.0 / 13.0 + 0.05, 0.45, 0.8), Vector3(x, y, z), trim)
		piece.rotation.z = atan(-2.6 * x / (half_width * half_width))

func tomb(at: Vector3, size: float) -> void:
	box(Vector3(2.0, 0.2, 3.5) * size, at + Vector3(0, 0.1 * size, 0), trim, true)
	box(Vector3(1.65, 1.15, 3.1) * size, at + Vector3(0, 0.775 * size, 0), stone, true)
	box(Vector3(1.9, 0.22, 3.35) * size, at + Vector3(0, 1.46 * size, 0), trim, true)
	box(Vector3(0.14, 0.05, 1.5) * size, at + Vector3(0, 1.59 * size, 0), iron)
	box(Vector3(0.8, 0.05, 0.14) * size, at + Vector3(0, 1.59 * size, -0.25 * size), iron)

func brazier(at: Vector3) -> void:
	box(Vector3(0.8, 0.25, 0.8), at + Vector3(0, 0.125, 0), trim, true)
	box(Vector3(0.22, 1.1, 0.22), at + Vector3(0, 0.8, 0), iron, true)
	box(Vector3(0.65, 0.18, 0.65), at + Vector3(0, 1.4, 0), iron)
	var fire: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.65, 1.0)
	fire.mesh = quad
	fire.material_override = flame
	fire.position = at + Vector3(0, 1.95, 0)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.set_instance_shader_parameter("seed", float(fires.size()) * 0.137)
	add_child(fire)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = at + Vector3(0, 2.2, 0)
	light.light_color = Color(1.0, 0.57, 0.22)
	light.light_energy = 3.2
	light.omni_range = 8.0
	light.omni_attenuation = 1.4
	# Interior shadows stop fire light passing through the crypt's separating walls.
	light.shadow_enabled = true
	add_child(light)
	fires.append(light)

func inscription(text: String, at: Vector3, pixel_size: float) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = Color(0.78, 0.69, 0.48)
	label.outline_size = 0
	add_child(label)

func _process(_delta: float) -> void:
	var world: Node3D = get_parent() as Node3D
	var players: Node3D = world.get("players") as Node3D
	var local: Node3D = players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	objective.visible = local != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if local == null:
		return
	var mobs: Node = world.get("mobs") as Node
	var remaining: int = int(mobs.get("remaining"))
	objective.text = "CINDER CRYPT  ·  %d / 5 cultists remain\nClear the crypt, then reach the blue altar." % remaining
	if remaining == 0:
		objective.text = "CINDER CRYPT  ·  Cultists defeated\nReach the blue altar at the far end."
		if local.position.distance_to(Vector3(0, 0.95, -16.5)) < 4.0:
			objective.text = "CINDER CRYPT  ·  CLEARED\nFirst dungeon complete. Esc → Leave game to restart."
