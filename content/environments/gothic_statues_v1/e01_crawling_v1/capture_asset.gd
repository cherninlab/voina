extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 900))
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var packed: PackedScene = load("res://e01_crawling_lod0.glb") as PackedScene
	stage.add_child(packed.instantiate())
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.065, 0.07, 0.08)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.82, 0.85, 0.9)
	world.environment.ambient_light_energy = 0.65
	stage.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.94, 0.84)
	light.light_energy = 1.8
	light.rotation_degrees = Vector3(-42, -32, 0)
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(5, 5)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.1, 0.11, 0.13)
	floor_material.roughness = 0.9
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.003
	stage.add_child(floor_mesh)
	var camera: Camera3D = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(-2.4, 1.8, 2.7)
	camera.look_at(Vector3(0, 0.58, 0))
	camera.fov = 40
	camera.current = true
	for frame: int in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var target: String = OS.get_cmdline_user_args()[0]
	assert(root.get_texture().get_image().save_png(target) == OK)
	print("STATUE_CAPTURE_OK ", target)
	quit()
