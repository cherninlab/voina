extends SceneTree
## Close bridge frames for T-159 review: bends, landings, undersides, rails.
## scripts/godot_bg.sh --path . --script scripts/capture_bridges.gd -- --dungeon --shading-ephemeral --capture-dir=/abs/dir [--no-baked-bridges]

const VIEWS: Array[Array] = [
	# name, eye, target (level coordinates before RedDescentLayout.at), fov
	["b1-high-bend", Vector3(43.0, 0.3, 37.4), Vector3(50.0, -1.8, 36.6), 70.0],
	["b2-high-underside", Vector3(49.5, -5.2, 32.6), Vector3(53.0, -2.7, 35.0), 70.0],
	["b3-high-entry", Vector3(26.5, 1.6, 33.2), Vector3(34.0, -0.4, 35.2), 70.0],
	["b4-low-bend", Vector3(31.5, -22.4, 34.3), Vector3(38.5, -24.3, 38.5), 70.0],
	["b5-low-side", Vector3(44.0, -23.0, 61.5), Vector3(51.0, -26.0, 56.0), 70.0],
	["b6-rail-detail", Vector3(39.6, 0.4, 37.0), Vector3(41.8, -0.4, 38.9), 50.0],
]

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/red-descent-bridges"
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
	world.get_node("GameUI").set_process(false)
	root.disable_3d = false
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		var script: Script = node.get_script() as Script
		(node as CanvasLayer).visible = script != null and script.resource_path == "res://ui/shading.gd"
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	for view: Array in VIEWS:
		camera.fov = float(view[3])
		camera.position = RedDescentLayout.at(view[1] as Vector3)
		camera.look_at(RedDescentLayout.at(view[2] as Vector3))
		camera.make_current()
		for frame: int in range(36):
			await process_frame
		await RenderingServer.frame_post_draw
		var file: String = directory.path_join(String(view[0]) + ".png")
		if root.get_texture().get_image().save_png(file) != OK:
			printerr("BRIDGE_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("BRIDGE_CAPTURE: " + file)
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()
