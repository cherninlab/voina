extends SceneTree
## Small material/scan test, not a playable dungeon. Windowed runs use godot_bg.sh.

const BASE: String = "res://content/environments/bridge_well_v1/"
var world: Node3D

func _initialize() -> void:
	capture.call_deferred()

func mesh_node(mesh: Mesh, material: Material, position: Vector3) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	world.add_child(instance)
	return instance

func box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return mesh_node(mesh, material, position)

func save_frame(name: String, frames: int = 40) -> void:
	for frame: int in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = BASE + "review/" + name + ".png"
	if root.get_texture().get_image().save_png(path) != OK:
		printerr("BRIDGE_PREVIEW_FAIL: " + path)
		quit(1)
	print("BRIDGE_PREVIEW_OK: " + path)

func capture() -> void:
	root.size = Vector2i(1440, 1000)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.038)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.74, 0.82)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, -25, 0)
	key.light_energy = 0.75
	world.add_child(key)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 0, 8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	camera.make_current()
	var fragments: Array[Node3D] = []
	for index: int in range(2):
		var path: String = BASE + "scan_fragments/scan_00" + str(index + 1) + "_wall_fragment.glb"
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			printerr("BRIDGE_PREVIEW_FAIL: " + path)
			quit(1)
			return
		var fragment: Node3D = scene.instantiate() as Node3D
		world.add_child(fragment)
		fragment.position = Vector3(-1.8 if index == 0 else 1.8, 0, 0)
		fragments.append(fragment)
	await save_frame("scan-fragments-mobile")
	if OS.get_cmdline_user_args().has("--scan-only"):
		quit()
		return
	for fragment: Node3D in fragments:
		fragment.queue_free()
	await process_frame
	var wood: Material = load(BASE + "bridge_oak/wet_material.tres") as Material
	var stone: Material = load(BASE + "damp_masonry/wet_material.tres") as Material
	var water: Material = load(BASE + "water/material.tres") as Material
	var iron: Material = load("res://content/environments/red_nave_v1/oxidized_iron/material.tres") as Material
	box(Vector3(7, 0.3, 6), Vector3(-0.5, -1.9, 0), stone)
	box(Vector3(7, 3, 0.4), Vector3(-0.5, -0.5, -3), stone)
	box(Vector3(0.4, 3, 6), Vector3(-3.8, -0.5, 0), stone)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(7, 6)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	mesh_node(plane, water, Vector3(-0.5, -0.3, 0))
	for index: int in range(16):
		var z: float = -2.7 + index * 0.36
		var board_material: ShaderMaterial = wood.duplicate() as ShaderMaterial
		board_material.set_shader_parameter("tile_scale", Vector2(0.22, 1.0))
		board_material.set_shader_parameter("tile_offset", Vector2(fposmod(index * 0.37, 1.0), index * 0.123))
		var board: MeshInstance3D = box(Vector3(0.34, 0.13, 2.4), Vector3(1.85, 0.03 * sin(index * 1.8), z), board_material)
		board.rotation_degrees.y = 90 + sin(index * 2.1) * 1.5
		board.rotation_degrees.z = sin(index * 0.5) * 0.6
	for z: float in [-2.6, 0.0, 2.6]:
		box(Vector3(0.18, 1.3, 0.18), Vector3(0.62, 0.56, z), wood)
	for index: int in range(42):
		var z: float = -2.6 + index * 5.2 / 41.0
		var sag: float = -0.17 * abs(sin(z * PI / 2.6))
		var link: TorusMesh = TorusMesh.new()
		link.inner_radius = 0.045
		link.outer_radius = 0.067
		link.rings = 8
		link.ring_segments = 6
		var instance: MeshInstance3D = mesh_node(link, iron, Vector3(0.62, 1.02 + sag, z))
		instance.rotation_degrees.x = 90
		instance.rotation_degrees.y = 90 if index % 2 == 0 else 0
	var warm: OmniLight3D = OmniLight3D.new()
	warm.position = Vector3(-0.1, 2.5, 0.4)
	warm.light_color = Color(1, 0.63, 0.28)
	warm.light_energy = 2.5
	warm.omni_range = 9
	world.add_child(warm)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 65
	camera.position = Vector3(4.8, 3.8, 5.5)
	camera.look_at(Vector3(-0.15, -0.3, -0.5))
	await save_frame("water-wetness-0")
	await save_frame("water-wetness-1", 60)
	quit()
