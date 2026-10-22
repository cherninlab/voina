extends Node3D
## A plain, evenly lit test room: 20 x 28 m, walls on every side, players at the south end and
## raiders arriving from the far corners for as long as the session lasts (WaveMobs).

const HALF: Vector2 = Vector2(10, 14)
const HEIGHT: float = 6.0
var objective: Label = Label.new()

func _ready() -> void:
	name = "WhiteRoom"
	var white: StandardMaterial3D = StandardMaterial3D.new()
	white.albedo_color = Color(0.93, 0.93, 0.92)
	white.roughness = 0.9
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.8, 0.8, 0.79)
	floor_material.roughness = 0.95
	var lines: StandardMaterial3D = StandardMaterial3D.new()
	lines.albedo_color = Color(0.62, 0.62, 0.62)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.95, 0.95, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, 30, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	add_child(light)
	box(Vector3(HALF.x * 2.0, 0.5, HALF.y * 2.0), Vector3(0, -0.25, 0), floor_material)
	box(Vector3(HALF.x * 2.0 + 1.0, 0.5, HALF.y * 2.0 + 1.0), Vector3(0, HEIGHT + 0.25, 0), white)
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.5, HEIGHT, HALF.y * 2.0 + 1.0), Vector3(side * (HALF.x + 0.25), HEIGHT * 0.5, 0), white)
		box(Vector3(HALF.x * 2.0, HEIGHT, 0.5), Vector3(0, HEIGHT * 0.5, side * (HALF.y + 0.25)), white)
	# A faint 2 m floor grid, so distance and speed still read on a blank floor. Cosmetic only.
	for x: int in range(-4, 5):
		box(Vector3(0.04, 0.01, HALF.y * 2.0), Vector3(x * 2.0, 0.005, 0), lines, false)
	for z: int in range(-6, 7):
		box(Vector3(HALF.x * 2.0, 0.01, 0.04), Vector3(0, 0.005, z * 2.0), lines, false)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_left = 300
	objective.offset_right = -24
	objective.offset_top = 24
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	objective.add_theme_color_override("font_outline_color", Color.WHITE)
	objective.add_theme_constant_override("outline_size", 5)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(objective)
	print("WHITE_ROOM_READY: 20 x 28 m")

func box(size: Vector3, at: Vector3, material: Material, solid: bool = true) -> void:
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

func _process(_delta: float) -> void:
	var world: Node3D = get_parent() as Node3D
	var players: Node3D = world.get("players") as Node3D
	var local: Node3D = players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	objective.visible = local != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if local == null:
		return
	var mobs: Node = world.get("mobs") as Node
	objective.text = "WHITE ROOM  ·  %d raiders  ·  %d felled\nThey keep coming. Esc → Leave game to stop." % [int(mobs.get("alive")), int(mobs.get("felled"))]
