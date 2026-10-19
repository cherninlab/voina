extends SceneTree
## Real-renderer views of the haunted forest along the north trail (T-092). Run WITHOUT --headless:
##   "$GODOT" --path . --script scripts/capture_haunted_forest.gd -- --host --port=7797 --capture-dir=/abs/dir
## Saves PNGs and prints the fog grade the forest zone applied at each camera.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(120):
		await process_frame
	var directory: String = OS.get_user_data_dir().path_join("haunted-forest-screenshots")
	var only: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(directory)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var forest: Node = world.get_node_or_null("HauntedForest")
	if forest == null:
		printerr("FOREST_CAPTURE_FAIL: HauntedForest node missing from build_arena")
		quit(1)
		return
	# The walking strip must stay clear of anything solid: sweep a player-sized capsule up the road.
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var blocked: int = 0
	for step: int in range(31):
		var z: float = ChurchSite.ROAD_START_Z - float(step) * 2.0
		var x: float = ChurchSite.road_x(z)
		var ground: float = ground_y(space, x, z)
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, Vector3(x, ground + 1.35, z))
		if not space.intersect_shape(query, 1).is_empty():
			blocked += 1
			printerr("FOREST_ROAD_BLOCKED at ", query.transform.origin)
	if blocked > 0:
		quit(1)
		return
	print("FOREST_ROAD_CLEAR: 31 capsule probes along the walking strip")
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var players: Node = world.get("players") as Node
	if players != null and players.get_child_count() > 0:
		var player_camera: Camera3D = players.get_child(0).get("camera") as Camera3D
		camera.fov = player_camera.fov
	camera.far = 600.0
	var presentation: CanvasLayer = world.get_node("GameUI") as CanvasLayer
	presentation.visible = false
	var views: Array[Dictionary] = []
	views.append({"name": "village-gate", "from": eye(space, -0.5, -11.0), "to": eye(space, -0.5, -32.0)})
	views.append({"name": "past-gate", "from": eye(space, ChurchSite.road_x(-32.0), -32.0), "to": eye(space, ChurchSite.road_x(-52.0), -52.0)})
	views.append({"name": "mid-trail-north", "from": eye(space, ChurchSite.road_x(-58.0), -58.0), "to": eye(space, ChurchSite.road_x(-78.0), -78.0)})
	views.append({"name": "mid-trail-west", "from": eye(space, ChurchSite.road_x(-62.0), -62.0), "to": eye(space, ChurchSite.road_x(-62.0) - 20.0, -66.0)})
	views.append({"name": "mid-trail-east", "from": eye(space, ChurchSite.road_x(-48.0), -48.0), "to": eye(space, ChurchSite.road_x(-48.0) + 20.0, -54.0)})
	views.append({"name": "tunnel", "from": eye(space, ChurchSite.road_x(-68.0), -68.0), "to": eye(space, ChurchSite.road_x(-84.0), -84.0) + Vector3.UP * 1.5})
	views.append({"name": "church-approach", "from": eye(space, ChurchSite.road_x(-86.0), -86.0), "to": eye(space, ChurchSite.DOOR.x, ChurchSite.DOOR.y - 8.0) + Vector3.UP * 4.0})
	views.append({"name": "looking-back", "from": eye(space, ChurchSite.road_x(-80.0), -80.0), "to": eye(space, ChurchSite.road_x(-50.0), -50.0)})
	var pools: Array = forest.get("pools") as Array
	if not pools.is_empty():
		var pool: Vector2 = pools[0] as Vector2
		var toward: Vector2 = (Vector2(ChurchSite.road_x(pool.y), pool.y) - pool).normalized()
		var stand: Vector2 = pool + toward * 6.5 + Vector2(0.0, 2.0)
		views.append({"name": "bog", "from": eye(space, stand.x, stand.y) + Vector3.UP * 0.6, "to": Vector3(pool.x, ground_y(space, pool.x, pool.y), pool.y)})
	views.append({"name": "lobby", "from": Vector3(34, 26, 38), "to": Vector3.ZERO})
	for view: Dictionary in views:
		if only != "" and not String(view["name"]) in only.split(","):
			continue
		camera.position = view["from"] as Vector3
		camera.look_at(view["to"] as Vector3)
		camera.make_current()
		# The fog zone eases toward its target; give it time to settle like a walking player.
		for frame: int in range(150):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = directory.path_join("forest-%s.png" % String(view["name"]))
		var result: Error = image.save_png(path)
		assert(result == OK, "Screenshot save failed: " + path)
		var environment: Environment = forest.get("environment") as Environment
		var weight: float = float(forest.get("weight"))
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if environment != null:
			print("FOREST_CAPTURE: %s weight %.2f fog %.4f colour %s sky %.2f aerial %.2f ambient %.2f %s | %d draws %d primitives" % [path, weight, environment.fog_density, environment.fog_light_color.to_html(false), environment.fog_sky_affect, environment.fog_aerial_perspective, environment.ambient_light_energy, environment.ambient_light_color.to_html(false), draws, primitives])
		else:
			print("FOREST_CAPTURE: ", path)
	quit()

func ground_y(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -50.0, z))
	var hit: Dictionary = space.intersect_ray(query)
	return 0.0 if hit.is_empty() else (hit["position"] as Vector3).y

func eye(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Vector3:
	return Vector3(x, ground_y(space, x, z) + 1.75, z)
