extends SceneTree
## Import/bounds/LOD checks, plus optional real Godot material previews.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var directory: String = ""
	var selected: PackedStringArray = PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--only="):
			selected = argument.trim_prefix("--only=").split(",")
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.11)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.environment.ambient_light_energy = 0.55
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -30, 0)
	light.light_energy = 2.0
	light.shadow_enabled = true
	stage.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	root.size = Vector2i(800, 800)
	var visual: MeshInstance3D = MeshInstance3D.new()
	stage.add_child(visual)
	var report: Array[Dictionary] = []
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	for id: String in GeneratedDungeonKit.IDS:
		if not selected.is_empty() and not id in selected:
			continue
		var counts: Array[int] = []
		var bounds: AABB = GeneratedDungeonKit.mesh(id).get_aabb()
		assert(bounds.size.is_finite() and bounds.size.y > 0.1, id + " invalid bounds")
		assert(absf(bounds.position.y) < 0.03, id + " is not grounded")
		for level: int in range(3):
			var mesh: Mesh = GeneratedDungeonKit.mesh(id, level)
			var triangles: int = 0
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
				assert(not colors.is_empty(), id + " missing reference colours")
				var low: float = 1.0
				var high: float = 0.0
				for color: Color in colors:
					low = minf(low, color.get_luminance())
					high = maxf(high, color.get_luminance())
				assert(high - low > 0.02, id + " has uniform placeholder colours")
				assert((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), id + " missing normals")
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			assert(triangles > 0 and triangles <= (36000 if level == 0 else (12000 if level == 1 else 2600)), id + " triangle budget")
			counts.append(triangles)
		report.append({"id": id, "size_m": [bounds.size.x, bounds.size.y, bounds.size.z], "triangles": counts})
		if directory.is_empty():
			continue
		visual.mesh = GeneratedDungeonKit.mesh(id)
		visual.material_override = GeneratedDungeonKit.material(id)
		var center: Vector3 = bounds.get_center()
		var radius: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		camera.size = radius * 1.35
		camera.position = center + Vector3(0.3, 0.2, 1.0).normalized() * radius * 2.5
		camera.look_at(center)
		for frame: int in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(directory.path_join(id + ".png")) == OK)
	if not directory.is_empty():
		var file: FileAccess = FileAccess.open(directory.path_join("mesh-check.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("GENERATED_KIT_OK: ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	quit()
