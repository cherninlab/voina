extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(30):
		await process_frame
	var directory: String = OS.get_user_data_dir().path_join("ui-screenshots")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	await shot(directory, "01-lobby")
	var network: Node = root.get_node("NetworkManager")
	network.call("join_game", "127.0.0.1", int(network.get("port")))
	await shot(directory, "02-connecting")
	network.call("stop", "Connection failed")
	await shot(directory, "03-connection-failed")
	network.call("host_game", int(network.get("port")))
	for frame: int in range(30):
		await process_frame
	var ui: CanvasLayer = world.get_node("GameUI") as CanvasLayer
	ui.call("resume")
	await shot(directory, "04-gameplay")
	ui.call("open_pause")
	await shot(directory, "05-pause")
	ui.call("show_controls")
	await shot(directory, "06-controls")
	network.call("stop", "Left game")
	await process_frame
	quit()

func shot(directory: String, name: String) -> void:
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	assert(result == OK, "UI screenshot save failed")
	print("UI_CAPTURE: ", name)
