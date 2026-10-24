extends SceneTree
## Real Mobile/Metal frames; use godot_bg.sh with --dungeon --shading-ephemeral.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/red-descent"
	var dressing_views: bool = "--dressing" in OS.get_cmdline_user_args()
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
	# Hide presentation UI while preserving the map's full-screen shading pass.
	world.get_node("GameUI").set_process(false)
	root.disable_3d = false # The offline title normally suspends 3D rendering.
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		var script: Script = node.get_script() as Script
		(node as CanvasLayer).visible = script != null and script.resource_path == "res://ui/shading.gd"
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
		["07-timber-detail", RedDescentLayout.at(Vector3(38.6, 0.9, 36.8)), RedDescentLayout.at(Vector3(41, -0.6, 39)), 58.0],
		["08-nave-materials", RedDescentLayout.at(Vector3(46, -16.35, 87)), RedDescentLayout.at(Vector3(39, -15.7, 90)), 65.0],
	]
	var metrics: Array[Dictionary] = []
	if dressing_views:
		views.append_array([
			["09-entry-floor", Vector3(-41, 1.65, -24), Vector3(-43, 0.3, -29), 65.0],
			["10-restraint-frame", Vector3(40, -2.35, -8), Vector3(40, -1.8, -13), 65.0],
			["11-nave-framing", Vector3(0, -3.5, 31), Vector3(0, -1.4, 38.5), 78.0],
			["12-bell-hangings", Vector3(32, -16.35, 34), Vector3(32, -11.3, 38), 78.0],
			["13-chapel-spill", Vector3(3, -8.35, -37), Vector3(3, -9.6, -41.4), 65.0],
			["14-choir-debris", Vector3(33, -26.35, -4), Vector3(30, -27.7, -8), 65.0],
		])
	for view: Array in views:
		camera.fov = float(view[3]) if view.size() > 3 else 78.0
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(36):
			await process_frame
		var intervals: Array[float] = []
		for frame: int in range(20):
			var started: int = Time.get_ticks_usec()
			await process_frame
			intervals.append(float(Time.get_ticks_usec() - started) / 1000.0)
		intervals.sort()
		metrics.append({"view": String(view[0]), "capture_frame_median_ms": intervals[10], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		# Explicit draw also completes captures while macOS throttles an unfocused window.
		RenderingServer.force_draw()
		var file: String = directory.path_join(String(view[0]) + ".png")
		var frame_image: Image = root.get_texture().get_image()
		var low: float = 1.0
		var high: float = 0.0
		for y: int in range(0, frame_image.get_height(), 48):
			for x: int in range(0, frame_image.get_width(), 48):
				var value: float = frame_image.get_pixel(x, y).get_luminance()
				low = minf(low, value)
				high = maxf(high, value)
		if high - low < 0.04:
			printerr("DUNGEON_CAPTURE_FAIL: blank frame " + file)
			quit(1)
			return
		if frame_image.save_png(file) != OK:
			printerr("DUNGEON_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("DUNGEON_CAPTURE: " + file)
	var metrics_file: FileAccess = FileAccess.open(directory.path_join("render-metrics.json"), FileAccess.WRITE)
	metrics_file.store_string(JSON.stringify(metrics, "\t"))
	# Let the audio thread retire active Ogg playbacks before this scripted capture exits.
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()
