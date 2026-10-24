extends Node3D
## Test grid of flagstone modules under a low warm torch, for seam and scale review (T-165).
## Open flagstone_preview.tscn in the editor, or let capture_flagstones.gd drive it.

@export var family: String = "laid"
## Empty: pick a variant of the family per cell, so variants meet at every seam.
@export var variant: String = ""
@export var grid: Vector2i = Vector2i(3, 3)
@export var seed: int = 1
## Thin red posts at interior module corners, to find the seams in a capture.
@export var markers: bool = false
@export var torch_position: Vector3 = Vector3(6.4, 0.45, 5.2)
## A second torch at post height over the grid centre, so a whole-grid view is readable.
@export var fill: bool = false
## A Red Descent room id: floor its real outline with FlagstoneFloor.cover() instead of a grid,
## at y = 0 with stand-in walls. Torch positions are then relative to the room centre.
@export var room: String = ""
var torch: OmniLight3D
var center: Vector3 = Vector3.ZERO

func _ready() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.009, 0.005, 0.005)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.43, 0.46)
	environment.ambient_light_energy = 0.36
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var depth: float = FlagstoneFloor.BORDER_WIDTH if family == "border" else FlagstoneFloor.SIZE
	if not room.is_empty():
		build_room()
	else:
		center = Vector3(grid.x * FlagstoneFloor.SIZE * 0.5, 0.0, grid.y * depth * 0.5)
		for x: int in range(grid.x):
			for z: int in range(grid.y):
				var id: String = variant if not variant.is_empty() else FlagstoneFloor.pick(family, Vector2i(x, z), seed)
				var module: Node3D = FlagstoneFloor.module(id)
				module.position = Vector3(x * FlagstoneFloor.SIZE, 0.0, z * depth)
				add_child(module)
	torch = OmniLight3D.new()
	torch.light_color = Color(1.0, 0.63, 0.3)
	torch.light_energy = 3.6
	torch.omni_range = 10.5
	torch.omni_attenuation = 1.25
	torch.shadow_enabled = true
	torch.position = torch_position + (center if not room.is_empty() else Vector3.ZERO)
	add_child(torch)
	if fill:
		var high: OmniLight3D = OmniLight3D.new()
		high.light_color = Color(1.0, 0.63, 0.3)
		high.light_energy = 4.0
		high.omni_range = 14.0
		high.omni_attenuation = 1.0
		high.shadow_enabled = true
		high.position = center + Vector3(-1.3, 2.1, 1.1)
		add_child(high)
	if markers:
		var post: CylinderMesh = CylinderMesh.new()
		post.top_radius = 0.008
		post.bottom_radius = 0.008
		post.height = 0.3
		var red: StandardMaterial3D = StandardMaterial3D.new()
		red.albedo_color = Color(0.9, 0.05, 0.03)
		red.emission_enabled = true
		red.emission = Color(0.8, 0.03, 0.02)
		for x: int in range(grid.x + 1):
			for z: int in range(grid.y + 1):
				var marker: MeshInstance3D = MeshInstance3D.new()
				marker.mesh = post
				marker.material_override = red
				marker.position = Vector3(x * FlagstoneFloor.SIZE, 0.15, z * depth)
				add_child(marker)

func outline() -> PackedVector2Array:
	for data: Dictionary in RedDescentLayout.rooms():
		if String(data["id"]) == room:
			return data["points"] as PackedVector2Array
	push_error("flagstone preview: unknown room " + room)
	return PackedVector2Array()

func build_room() -> void:
	var polygon: PackedVector2Array = outline()
	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in polygon:
		sum += point
	center = Vector3(sum.x, 0.0, sum.y) / float(polygon.size())
	FlagstoneFloor.cover(self, polygon, 0.0, family, seed)
	# Stand-in walls just outside the outline: the floor must stop cleanly at their faces.
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_color = Color(0.16, 0.135, 0.12)
	stone.roughness = 1.0
	polygon = FlagstoneFloor.counter_clockwise(polygon)
	for index: int in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var along: Vector2 = (b - a).normalized()
		var wall: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(a.distance_to(b) + 0.6, 1.4, 0.6)
		wall.mesh = box
		wall.material_override = stone
		var middle: Vector2 = (a + b) * 0.5 - Vector2(-along.y, along.x) * 0.3
		wall.transform = Transform3D(Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(-along.y, 0.0, along.x)), Vector3(middle.x, 0.7, middle.y))
		add_child(wall)
