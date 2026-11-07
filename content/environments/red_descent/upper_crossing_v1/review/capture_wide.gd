extends SceneTree

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	root.size = Vector2i(960, 540)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(3840, 2160)
	viewport.world_3d = root.world_3d
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(16.7889, 1.0086, -13.3896)
	camera.fov = 106.0
	camera.near = 0.05
	viewport.add_child(camera)
	if "--stair-coping" in OS.get_cmdline_user_args():
		camera.position = Vector3(39, -4.8, -33)
		camera.fov = 95.0
		camera.look_at(Vector3(37.6, -6, -36))
	else:
		camera.look_at(camera.position + Vector3(0.67, -0.54, 0.51))
	camera.make_current()
	for frame: int in range(26):
		await process_frame
	RenderingServer.force_draw()
	var result: Image = viewport.get_texture().get_image()
	var output: String = OS.get_cmdline_user_args()[-1]
	if result.get_size() != Vector2i(3840, 2160) or result.save_png(output) != OK:
		push_error("4K capture failed")
		quit(1)
		return
	print("WIDE_CAPTURE: ", result.get_size(), " ", output)
	viewport.queue_free()
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()
