extends SceneTree
## Render the real running world; save frames outside the repository by passing --capture-dir=.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(120):
		await process_frame
	var directory: String = OS.get_user_data_dir().path_join("village-screenshots")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 68.0
	camera.far = 300.0
	var positions: Array[Vector3] = [Vector3(33, 28, 37), Vector3(9, 4.5, 13), Vector3(-18, 5, 11)]
	var targets: Array[Vector3] = [Vector3(0, 0, -2), Vector3(-4, 2, -18), Vector3(7, 2, -12)]
	for index: int in range(positions.size()):
		camera.position = positions[index]
		camera.look_at(targets[index])
		camera.make_current()
		for frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = directory.path_join("village-%02d.png" % (index + 1))
		var result: Error = image.save_png(path)
		assert(result == OK, "Screenshot save failed: " + path)
		print("VILLAGE_CAPTURE: ", path)
	quit()
