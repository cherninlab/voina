extends Node3D
## Original procedural village; cosmetic scenery never owns gameplay state.

var wood: StandardMaterial3D
var straw: StandardMaterial3D
var stone: StandardMaterial3D
var earth: StandardMaterial3D
var beam: StandardMaterial3D
var red: StandardMaterial3D
var teal: StandardMaterial3D
var cream: StandardMaterial3D
var gold: StandardMaterial3D

func _ready() -> void:
	name = "WoodlandVillage"
	wood = surface("b0a08a", "oak", 0.5)
	straw = surface("d5c491", "thatch", 0.5)
	stone = surface("88918f")
	earth = surface("c1b9a6", "ground", 0.3)
	beam = surface("493d32")
	red = surface("8f413b")
	teal = surface("3c7273")
	cream = surface("d5ccb2")
	gold = surface("b59a51")
	lighting()
	block(Vector3(56, 1, 56), Vector3(0, -0.5, 0), earth, true)
	# Visual terrain extends beyond the fenced playfield; collisions stay inside 56 m.
	block(Vector3(240, 0.2, 240), Vector3(0, -0.75, 0), surface("54684b"))
	for side: int in [-1, 1]:
		block(Vector3(0.4, 2.5, 56), Vector3(side * 28, 1.25, 0), wood, true)
		block(Vector3(56, 2.5, 0.4), Vector3(0, 1.25, side * 28), wood, true)
		for index: int in range(19):
			block(Vector3(0.22, 3.0, 0.22), Vector3(side * 27.7, 1.5, -27 + index * 3), beam)
			block(Vector3(0.22, 3.0, 0.22), Vector3(-27 + index * 3, 1.5, side * 27.7), beam)
	# Keep the spawn and combat-test axis x=0 unobstructed.
	for location: Vector3 in [Vector3(-5, 0.6, -4), Vector3(5, 0.6, 4), Vector3(-5, 0.6, 4), Vector3(5, 0.6, -4)]:
		block(Vector3(3, 1.2, 2), location, wood, true)
		for offset: float in [-1.25, 1.25]:
			block(Vector3(0.12, 1.25, 2.04), location + Vector3(offset, 0, 0), beam)
	for index: int in range(4):
		var x: float = -20.0 + index * 13.0
		house(Vector3(x, 0, -22), 0.0, red if index % 2 == 0 else teal)
		house(Vector3(x, 0, 22), PI, teal if index % 2 == 0 else wood)
	for side: int in [-1, 1]:
		stall(Vector3(side * 15, 0, -8), red if side < 0 else teal)
		stall(Vector3(side * 15, 0, 9), gold if side < 0 else cream)
		for index: int in range(3):
			barrel(Vector3(side * 20, 0, -5 + index * 4))
	well(Vector3(11, 0, 0))
	watchtower(Vector3(-23, 0, 2))
	var trees: Node3D = preload("res://gameplay/environment/tree_pack.tscn").instantiate() as Node3D
	add_child(trees)
	for index: int in range(14):
		var angle: float = TAU * index / 14.0
		var hill: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 16.0 + float(index % 4) * 5.0
		mesh.height = mesh.radius * 1.3
		mesh.radial_segments = 12
		mesh.rings = 6
		hill.mesh = mesh
		hill.position = Vector3(cos(angle) * 100, -7, sin(angle) * 100)
		hill.material_override = surface("5d7068" if index % 2 == 0 else "70808b")
		add_child(hill)

func surface(color: String, texture: String = "", tiling: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.95
	if not texture.is_empty():
		material.albedo_texture = load("res://content/environments/village_generated/%s.png" % texture) as Texture2D
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE * tiling
	return material

func block(size: Vector3, location: Vector3, material: Material, collision: bool = false, parent: Node3D = self) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = location
	parent.add_child(visual)
	if collision:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		visual.add_child(body)
	return visual

func roof(location: Vector3, width: float, depth: float, parent: Node3D) -> void:
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = Vector3(width, 2.8, depth)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = location
	visual.material_override = straw
	parent.add_child(visual)

func house(location: Vector3, yaw: float, paint: StandardMaterial3D) -> void:
	var root: Node3D = Node3D.new()
	root.position = location
	root.rotation.y = yaw
	add_child(root)
	block(Vector3(7, 3.8, 6), Vector3(0, 1.9, 0), paint, true, root)
	roof(Vector3(0, 5.2, 0), 8.0, 7.0, root)
	# Exposed frame, planks and shutters carry color without an overall brown grade.
	for x: float in [-3.4, 0.0, 3.4]:
		block(Vector3(0.25, 3.9, 0.25), Vector3(x, 1.95, 3.08), beam, false, root)
	for y: float in [0.3, 1.4, 3.65]:
		block(Vector3(7.2, 0.15, 0.18), Vector3(0, y, 3.12), wood, false, root)
	block(Vector3(1.3, 2.4, 0.15), Vector3(-1.5, 1.2, 3.15), wood, false, root)
	block(Vector3(1.5, 1.2, 0.16), Vector3(1.8, 2.1, 3.15), beam, false, root)
	block(Vector3(0.09, 1.2, 0.2), Vector3(1.8, 2.1, 3.25), cream, false, root)
	block(Vector3(1.5, 0.09, 0.2), Vector3(1.8, 2.1, 3.25), cream, false, root)
	block(Vector3(1.0, 2.6, 0.9), Vector3(2.3, 4.8, -1.8), stone, false, root)
	for side: int in [-1, 1]:
		var rafter: MeshInstance3D = block(Vector3(0.22, 5.4, 0.25), Vector3(side * 1.8, 4.8, 3.5), beam, false, root)
		rafter.rotation.z = side * -0.95

func stall(location: Vector3, cloth: StandardMaterial3D) -> void:
	block(Vector3(4, 1.1, 2.4), location + Vector3(0, 0.55, 0), wood, true)
	for x: float in [-1.9, 1.9]:
		for z: float in [-1.1, 1.1]:
			block(Vector3(0.14, 3.2, 0.14), location + Vector3(x, 1.6, z), beam)
	var canopy: MeshInstance3D = block(Vector3(4.5, 0.12, 3.0), location + Vector3(0, 3.15, 0), cloth)
	canopy.rotation.x = 0.12
	block(Vector3(4.5, 0.5, 0.08), location + Vector3(0, 2.95, 1.45), cloth)
	for x: float in [-1.2, 0.0, 1.2]:
		block(Vector3(0.7, 0.5, 0.7), location + Vector3(x, 1.35, 0), cream if x == 0 else gold)

func barrel(location: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = location + Vector3(0, 0.65, 0)
	add_child(body)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.3
	mesh.radial_segments = 12
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = wood
	body.add_child(visual)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 0.5
	cylinder.height = 1.3
	shape.shape = cylinder
	body.add_child(shape)

func well(location: Vector3) -> void:
	for index: int in range(12):
		var angle: float = TAU * index / 12.0
		var piece: MeshInstance3D = block(Vector3(0.7, 1.0, 0.45), location + Vector3(sin(angle) * 1.2, 0.5, cos(angle) * 1.2), stone, true)
		piece.rotation.y = angle
	for side: int in [-1, 1]:
		block(Vector3(0.18, 3.2, 0.18), location + Vector3(side * 1.25, 1.6, 0), beam)
	roof(location + Vector3(0, 3.5, 0), 3.4, 2.6, self)

func watchtower(location: Vector3) -> void:
	for x: float in [-1.5, 1.5]:
		for z: float in [-1.5, 1.5]:
			block(Vector3(0.3, 6, 0.3), location + Vector3(x, 3, z), beam, true)
	block(Vector3(3.5, 0.3, 3.5), location + Vector3(0, 4.2, 0), wood, true)
	roof(location + Vector3(0, 7.1, 0), 4.2, 4.2, self)
	for side: int in [-1, 1]:
		block(Vector3(0.2, 1.0, 3.4), location + Vector3(side * 1.6, 4.8, 0), teal)
		block(Vector3(3.4, 1.0, 0.2), location + Vector3(0, 4.8, side * 1.6), teal)

func lighting() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_color = Color("fff1d8")
	light.light_energy = 1.2
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 100.0
	add_child(light)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("3673a5")
	sky_material.sky_horizon_color = Color("cad9db")
	sky_material.ground_horizon_color = Color("b9c8c2")
	sky_material.ground_bottom_color = Color("53604b")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b2c6cc")
	environment.fog_density = 0.0015
	world.environment = environment
	add_child(world)
