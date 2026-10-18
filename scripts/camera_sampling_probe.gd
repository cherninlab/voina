extends SceneTree
## Matched source-sampling trials; writes actual Metal frames outside the repository.

func _initialize() -> void:
	probe.call_deferred()

func probe() -> void:
	assert(DisplayServer.get_name() != "headless", "Sampling comparison needs a real renderer")
	root.size = Vector2i(1600,1000)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var directory: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	assert(not directory.is_empty(), "Pass an external --capture-dir")
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(120):
		await process_frame
	var players: Node = world.get("players") as Node
	assert(players.get_child_count() > 0, "Run with --host")
	var owner_camera: Camera3D = players.get_child(0).get("camera") as Camera3D
	var camera: Camera3D = Camera3D.new()
	camera.fov = owner_camera.fov
	camera.far = 600.0
	world.add_child(camera)
	camera.make_current()
	(world.get_node("GameUI") as CanvasLayer).visible = false
	var names: Array[String] = ["4x-native", "8x-native", "4x-125", "8x-125"]
	for trial: int in range(names.size()):
		root.msaa_3d = Viewport.MSAA_4X if trial % 2 == 0 else Viewport.MSAA_8X
		root.scaling_3d_scale = 1.0 if trial < 2 else 1.25
		var output: String = directory.path_join(names[trial])
		DirAccess.make_dir_recursive_absolute(output)
		camera.position = Vector3(-18,2.3,17)
		camera.look_at(Vector3(-18,2.6,-5))
		for frame: int in range(24):
			await process_frame
		var gpu_ms: float = 0.0
		var cpu_ms: float = 0.0
		for frame: int in range(60):
			await process_frame
			await RenderingServer.frame_post_draw
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		if gpu_ms > 0.0:
			print("CAMERA_RENDER_TIME: ",names[trial]," GPU ms=",gpu_ms/60.0," CPU setup ms=",cpu_ms/60.0," samples=60")
		else:
			print("CAMERA_RENDER_TIME: ",names[trial]," GPU unavailable; CPU setup ms=",cpu_ms/60.0," samples=60")
		for frame: int in range(16):
			# Fixed orientation avoids introducing a second moving-camera variable.
			camera.position.x = -18.0 + float(frame) * 0.004
			await process_frame
			await RenderingServer.frame_post_draw
			var pixels: Image = root.get_texture().get_image()
			assert(pixels.save_png(output.path_join("frame-%02d.png" % frame)) == OK)
		print("CAMERA_SAMPLING: ", names[trial], " scale=",root.scaling_3d_scale," msaa=",root.msaa_3d," FOV=",camera.fov," frames=16")
	quit()
