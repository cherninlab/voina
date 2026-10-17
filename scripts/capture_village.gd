extends SceneTree
## Render the real running world; save frames outside the repository by passing --capture-dir=.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(120):
		await process_frame
	# Check traversable geometry in the real physics world, including the new ramp.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for sample: Vector3 in [Vector3(0, 0, 0), Vector3(-23, 2.2, 8), Vector3(-23, 4.3, 2)]:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 1.0, sample - Vector3.UP * 1.0)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			printerr("VILLAGE_GEOMETRY_FAIL: missing floor or ramp at ", sample)
			quit(1)
			return
	print("VILLAGE_GEOMETRY_OK: spawn floor, ramp midpoint, lookout landing")
	if world.get("players").get_child_count() == 0:
		printerr("VILLAGE_PLAYER_FAIL: capture test requires --host")
		quit(1)
		return
	var player: CharacterBody3D = world.get("players").get_child(0) as CharacterBody3D
	for sample: Vector3 in [Vector3(0, 0, 0), Vector3(10, 0, 10), Vector3(-10, 0, -10), Vector3(24, 0, 14)]:
		player.position = sample + Vector3.UP * 3.0
		player.velocity = Vector3.ZERO
		for frame: int in range(100):
			await physics_frame
		if not player.is_on_floor() or player.position.y < -0.5:
			printerr("VILLAGE_PLAYER_FAIL: player did not land at ", sample, " position ", player.position)
			quit(1)
			return
	player.position = Vector3(0, 0.95, 3)
	player.velocity = Vector3.ZERO
	print("VILLAGE_PLAYER_OK: real player lands at four terrain locations")
	var directory: String = OS.get_user_data_dir().path_join("village-screenshots")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 68.0
	camera.far = 300.0
	var positions: Array[Vector3] = [Vector3(33, 28, 37), Vector3(-18, 2.3, 17), Vector3(-13, 5, -10)]
	var targets: Array[Vector3] = [Vector3(0, 0, -2), Vector3(-18, 2.6, -5), Vector3(-23, 3, 4)]
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
