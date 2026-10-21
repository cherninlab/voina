extends SceneTree
## Real Mobile/Metal frames of the playable map; launch through godot_bg.sh with --dungeon.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/cinder-crypt"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1440, 900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	for frame: int in range(90):
		await process_frame
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 78
	var views: Array[Array] = [
		["entrance", Vector3(-3, 2.6, 18), Vector3(0, 2.3, 4)],
		["burial-hall", Vector3(-4, 2.4, 7), Vector3(0, 2.1, -5)],
		["altar", Vector3(1.2, 2.4, -11.5), Vector3(0, 2.1, -19)],
	]
	for view: Array in views:
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var file: String = directory.path_join(String(view[0]) + ".png")
		if root.get_texture().get_image().save_png(file) != OK:
			printerr("DUNGEON_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("DUNGEON_CAPTURE: " + file)
	# Let the audio thread retire active Ogg playbacks before this scripted capture exits.
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	for frame: int in range(10):
		await process_frame
	quit()
