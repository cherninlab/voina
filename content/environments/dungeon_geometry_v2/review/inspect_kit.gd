extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1200, 900)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.045, 0.05)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -40, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var source: Node3D = load("res://content/environments/dungeon_geometry_v2/modular_fort_01/modular_fort_01_2k.gltf").instantiate() as Node3D
	var node: Node3D = source.find_child("*thin_gate_01*", true, false) as Node3D
	var gate: Node3D = node.duplicate() as Node3D
	gate.position = Vector3.ZERO
	world.add_child(gate)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-12, 5.5, 3.7)
	camera.look_at(Vector3(1.2, 3.4, 3.7))
	camera.make_current()
	for frame: int in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://content/environments/dungeon_geometry_v2/review/fort-gate.png")
	print("FORT_GATE_REVIEW_OK: ", node.name)
	source.free()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()
