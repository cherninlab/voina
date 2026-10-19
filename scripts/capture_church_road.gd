extends SceneTree
## Real Metal captures of the torch-lit church road (ChurchRoad), plus overlay/torch placement checks.
## Run WITHOUT --headless; frames are saved outside the repository:
## "$GODOT" --path . --script scripts/capture_church_road.gd -- --host --port=7796 --shading-ephemeral --capture-dir=/absolute/folder
## --shading-ephemeral keeps this machine's saved shading theme out of the run (the default Natural look).
## The night and dusk variants dim the sun and thicken a blue-grey fog inside this script only.

func _initialize() -> void:
	capture.call_deferred()

func fail(message: String) -> void:
	printerr("CHURCH_ROAD_FAIL: ", message)
	quit(1)

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(150):
		await process_frame
	var road: Node3D = world.get_node_or_null("ChurchRoad") as Node3D
	if road == null or (road.get("torches") as Array).is_empty():
		fail("ChurchRoad did not build")
		return
	# Cosmetic only: nothing under the road may collide or block navigation.
	if not road.find_children("*", "CollisionObject3D", true, false).is_empty() or not road.find_children("*", "CollisionShape3D", true, false).is_empty():
		fail("torches or overlay carry collision")
		return
	var lights: Array[Node] = road.find_children("*", "OmniLight3D", true, false)
	var torches: Array = road.get("torches") as Array
	if lights.size() > 10:
		fail("light budget exceeded: %d" % lights.size())
		return
	print("CHURCH_ROAD_BUDGET_OK: ", torches.size(), " stakes, ", lights.size(), " omni lights (budget 10), no collision")
	# Each overlay chunk must pair with at most eight omni lights, the Mobile per-instance limit.
	var all_lights: Array[Node] = world.find_children("*", "OmniLight3D", true, false)
	var most: int = 0
	var reached: int = 0
	for chunk: MeshInstance3D in road.get("chunks") as Array[MeshInstance3D]:
		var bounds: AABB = chunk.global_transform * chunk.mesh.get_aabb()
		var paired: int = 0
		var own: int = 0
		for node: Node in all_lights:
			var light: OmniLight3D = node as OmniLight3D
			if not light.is_visible_in_tree():
				continue
			var reach: AABB = AABB(light.global_position - Vector3.ONE * light.omni_range, Vector3.ONE * light.omni_range * 2.0)
			if reach.intersects(bounds):
				paired += 1
				if road.is_ancestor_of(light):
					own += 1
		most = maxi(most, paired)
		if own > 0:
			reached += 1
	if most > 8:
		fail("an overlay chunk overlaps %d omni lights; Mobile applies only 8" % most)
		return
	print("CHURCH_ROAD_CHUNKS_OK: ", (road.get("chunks") as Array).size(), " chunks, at most ", most, " omni lights each, ", reached, " lit by torches")
	# The overlay must hug the visible ground: compare vertices and triangle edge midpoints with the
	# collision built from the same meshes.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var lowest: float = INF
	var highest: float = -INF
	var samples: int = 0
	for chunk: MeshInstance3D in road.get("chunks") as Array[MeshInstance3D]:
		var arrays: Array = chunk.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		for triangle: int in range(indices.size() / 3):
			var a: Vector3 = chunk.global_transform * vertices[indices[triangle * 3]]
			var b: Vector3 = chunk.global_transform * vertices[indices[triangle * 3 + 1]]
			var c: Vector3 = chunk.global_transform * vertices[indices[triangle * 3 + 2]]
			for point: Vector3 in [a, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0]:
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point - Vector3.UP * 1.5)
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					fail("no ground under overlay at %s" % point)
					return
				var gap: float = point.y - (hit["position"] as Vector3).y
				lowest = minf(lowest, gap)
				highest = maxf(highest, gap)
				samples += 1
	print("CHURCH_ROAD_OVERLAY_GAP: ", samples, " samples, clearance min %.3f m max %.3f m" % [lowest, highest])
	if lowest < 0.0 or highest > 0.08:
		fail("overlay sinks below or floats above the ground")
		return
	var worst_foot: float = 0.0
	for torch: Node3D in torches:
		var foot: Vector3 = torch.global_position
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 2.0, foot - Vector3.UP * 2.0)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			fail("no ground under torch at %s" % foot)
			return
		worst_foot = maxf(worst_foot, absf(foot.y - (hit["position"] as Vector3).y))
		var across: float = absf(foot.x - ChurchSite.road_x(foot.z))
		print("CHURCH_ROAD_TORCH: ", torch.name, " at (%.1f, %.2f, %.1f), %.2f m from the centre line" % [foot.x, foot.y, foot.z, across])
	if worst_foot > 0.03:
		fail("a stake foot is %.3f m off the ground" % worst_foot)
		return
	print("CHURCH_ROAD_FEET_OK: stake feet within %.3f m of the ground" % worst_foot)

	var directory: String = OS.get_user_data_dir().path_join("church-road-screenshots")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var presentation: CanvasLayer = world.get_node_or_null("GameUI") as CanvasLayer
	if presentation != null:
		presentation.visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.far = 600.0
	var players: Node = world.get("players") as Node
	if players != null and players.get_child_count() > 0:
		var player_camera: Camera3D = players.get_child(0).get("camera") as Camera3D
		if player_camera != null:
			camera.fov = player_camera.fov
	var close_torch: Node3D = torches[2] as Node3D
	var close_across: Vector3 = Vector3(ChurchSite.road_x(close_torch.position.z) - close_torch.position.x, 0.0, 0.0).normalized()
	var views: Dictionary[String, Array] = {
		"gate": [eye(road, -27.6, 1.75), eye(road, -50.0, 1.0)],
		"midroad": [eye(road, -50.0, 1.7), eye(road, -76.0, 1.2)],
		"torch": [close_torch.position + close_across * 1.25 + Vector3(0.0, 1.45, 0.55), close_torch.position + Vector3(0.0, 1.3, 0.0)],
		"overview": [Vector3(15.0, 30.0, -16.0), Vector3(0.0, 0.0, -62.0)],
	}
	await shoot(world, camera, views, directory, "day")
	set_mood(world, 0.18, 0.35, Color("4a5762"), 0.03)
	await shoot(world, camera, {"gate": views["gate"], "midroad": views["midroad"]}, directory, "dusk")
	set_mood(world, 0.02, 0.1, Color("1f2830"), 0.045)
	views["high"] = [eye(road, -40.0, 10.0) + Vector3(1.5, 0.0, 0.0), eye(road, -64.0, 0.0)]
	# Looking back at the village puts its lanterns in view, competing for the landscape's eight slots.
	views["south"] = [eye(road, -45.0, 1.7), eye(road, -27.0, 1.2)]
	await shoot(world, camera, views, directory, "night")
	# Evidence for the overlay: the same night view with the mud chunks hidden.
	for chunk: MeshInstance3D in road.get("chunks") as Array[MeshInstance3D]:
		chunk.visible = false
	await shoot(world, camera, {"midroad": views["midroad"], "south": views["south"]}, directory, "night-no-overlay")
	# Mobile gives each mesh the eight omni lights with the lowest distance / (range * energy) from
	# its centre. Eight tiny decoys at the landscape's centre, 39 m up where they light nothing,
	# stand in for church, forest or village lights that win its slots: the bare landscape loses
	# every torch pool, the overlay chunks keep theirs.
	var landscape_center: Vector3 = Vector3(0.0, 39.0, 0.0)
	for index: int in range(8):
		var decoy: OmniLight3D = OmniLight3D.new()
		decoy.omni_range = 1.0
		decoy.light_energy = 16.0
		world.add_child(decoy)
		decoy.global_position = landscape_center + Vector3(float(index) * 0.1, 0.0, 0.0)
	await shoot(world, camera, {"midroad": views["midroad"]}, directory, "night-crowded-no-overlay")
	for chunk: MeshInstance3D in road.get("chunks") as Array[MeshInstance3D]:
		chunk.visible = true
	await shoot(world, camera, {"midroad": views["midroad"]}, directory, "night-crowded")
	quit()

func eye(road: Node3D, z: float, height: float) -> Vector3:
	var x: float = ChurchSite.road_x(z)
	return Vector3(x, float(road.call("surface_height", x, z)) + height, z)

# Capture-only grade: a dim sun, a dark sky and a cold blue-grey fog that swallows the distance.
func set_mood(world: Node3D, sun: float, sky: float, fog: Color, density: float) -> void:
	# The baked village bounce light is daylight; drop it, as the realtime shading themes do.
	for node: Node in world.find_children("*", "LightmapGI", true, false):
		(node as LightmapGI).light_data = null
	# Hold the village's periodic storm flash off so every variant is graded the same way.
	var storm: Node = world.find_child("AshenVillage", true, false)
	if storm != null:
		storm.set_process(false)
		var storm_sky: ShaderMaterial = storm.get("storm") as ShaderMaterial
		if storm_sky != null:
			storm_sky.set_shader_parameter("lightning", 0.0)
	for node: Node in world.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).light_energy = sun * (1.0 if node.name != "DistantRedSheetLightning" else 0.0)
	for node: Node in world.find_children("*", "WorldEnvironment", true, false):
		var environment: Environment = (node as WorldEnvironment).environment
		environment.background_energy_multiplier = sky
		environment.ambient_light_energy = sky * 0.6
		environment.fog_enabled = true
		environment.fog_light_color = fog
		environment.fog_density = density
		environment.fog_sky_affect = 0.85
		environment.fog_sun_scatter = 0.0
		environment.fog_aerial_perspective = 0.0

func shoot(world: Node3D, camera: Camera3D, views: Dictionary[String, Array], directory: String, mood: String) -> void:
	for label: String in views:
		camera.position = views[label][0] as Vector3
		camera.look_at(views[label][1] as Vector3)
		camera.make_current()
		for frame: int in range(20):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = directory.path_join("road-%s-%s.png" % [mood, label])
		if image.save_png(path) != OK:
			fail("screenshot save failed: " + path)
			return
		print("CHURCH_ROAD_CAPTURE: ", path)
