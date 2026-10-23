extends SceneTree
## Real Mobile/Metal frames of the playable map; launch through godot_bg.sh with --dungeon.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/red-descent"
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
	var dungeon: RedDescentDungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	var stone: ShaderMaterial = dungeon.architecture.materials["stone"] as ShaderMaterial
	print("CAPTURE_STONE: ", (stone.get_shader_parameter("albedo_map") as Texture2D).resource_path, " scale ", stone.get_shader_parameter("scale"))
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 78
	var views: Array[Array] = [
		["01-high-crossing", RedDescentLayout.at(Vector3(36.8, 1.05, 35.5)), RedDescentLayout.at(Vector3(55, -6, 47))],
		["02-central-wall", RedDescentLayout.at(Vector3(48.5, -11.35, 41)), RedDescentLayout.at(Vector3(32, -9, 42))],
		["03-low-crossing", RedDescentLayout.at(Vector3(47, -23.35, 54)), RedDescentLayout.at(Vector3(59, -18, 61))],
		["04-broken-nave", RedDescentLayout.at(Vector3(57, -16.35, 79)), RedDescentLayout.at(Vector3(52, -12, 94))],
		["05-deep-choir", RedDescentLayout.at(Vector3(86, -26.35, 54)), RedDescentLayout.at(Vector3(88, -23, 41))],
		["06-descent-overlook", RedDescentLayout.at(Vector3(64, -1.3, 35)), RedDescentLayout.at(Vector3(46, -16, 54))],
	]
	for view: Array in views:
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(36):
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
