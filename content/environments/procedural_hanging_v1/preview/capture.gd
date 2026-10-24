extends SceneTree
## Real Mobile/Metal frames of preview/hanging_preview.tscn. Windowed, so run through the wrapper:
## scripts/godot_bg.sh --path . --script res://content/environments/procedural_hanging_v1/preview/capture.gd -- --capture-dir=/abs/dir

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/hanging-preview"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1440, 900)
	var stage: Node3D = (load("res://content/environments/procedural_hanging_v1/preview/hanging_preview.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(stage)
	current_scene = stage
	var camera: Camera3D = Camera3D.new()
	stage.add_child(camera)
	for frame: int in range(20):
		await process_frame
	var views: Array[Dictionary] = stage.get("views")
	var error: float = float(stage.get("socket_error"))
	if error > 0.0001:
		printerr("HANGING_CAPTURE_FAIL: socket nodes differ from bake.json by %f m" % error)
		quit(1)
		return
	for view: Dictionary in views:
		camera.fov = float(view["fov"])
		camera.position = view["from"] as Vector3
		camera.look_at(view["to"] as Vector3)
		camera.make_current()
		for frame: int in range(30):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var low: float = 1.0
		var high: float = 0.0
		for y: int in range(0, image.get_height(), 48):
			for x: int in range(0, image.get_width(), 48):
				var value: float = image.get_pixel(x, y).get_luminance()
				low = minf(low, value)
				high = maxf(high, value)
		var file: String = directory.path_join(String(view["name"]) + ".png")
		if high - low < 0.04 or image.save_png(file) != OK:
			printerr("HANGING_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("HANGING_CAPTURE: " + file)
	quit(0)
