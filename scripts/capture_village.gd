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
	var gate_shape: Shape3D
	for child: Node in player.get_children():
		if child is CollisionShape3D:
			gate_shape = (child as CollisionShape3D).shape
			break
	assert(gate_shape != null, "Use the actual player collision shape for gate clearance")
	var gate_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	gate_query.shape = gate_shape
	gate_query.transform = Transform3D(Basis.IDENTITY,Vector3(1.2,1.6,-24.5))
	gate_query.motion = Vector3(0,0,-10)
	gate_query.exclude = [player.get_rid()]
	var gate_clearance: PackedFloat32Array = space.cast_motion(gate_query)
	assert(gate_clearance[0] > 0.99, "Northern village approach must pass a player capsule")
	print("VILLAGE_GATE_OK: player capsule clears northern approach")
	var previous_height: float = 0.0
	for step: int in range(21):
		var z: float = -27.0-float(step)*0.5
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(1.2,3.0,z),Vector3(1.2,-4.0,z))
		var hit: Dictionary = space.intersect_ray(query)
		assert(not hit.is_empty(), "Northern approach needs continuous ground")
		var height: float = (hit["position"] as Vector3).y
		assert(step == 0 or absf(height-previous_height) < 0.25, "Northern approach must avoid an abrupt floor step")
		previous_height = height
	print("VILLAGE_APPROACH_GROUND_OK: 21 continuous ramp samples")
	for sample: Vector3 in [Vector3(0, 0, 0), Vector3(10, 0, 10), Vector3(-10, 0, -10), Vector3(24, 0, 14)]:
		player.position = sample + Vector3.UP * 3.0
		player.velocity = Vector3.ZERO
		for frame: int in range(100):
			await physics_frame
		if not player.is_on_floor() or player.position.y < -0.5:
			printerr("VILLAGE_PLAYER_FAIL: player did not land at ", sample, " position ", player.position)
			quit(1)
			return
	for sample: Vector3 in [Vector3(0,0,-40),Vector3(50,0,0),Vector3(-60,0,0),Vector3(0,0,60),Vector3(3.4,0,-70),Vector3(-1.8,0,-100)]:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(sample + Vector3.UP*150.0,sample - Vector3.UP*50.0)
		var hit: Dictionary = space.intersect_ray(query)
		assert(not hit.is_empty(), "Outer rendered terrain must have matching collision")
		var surface: Vector3 = hit["position"] as Vector3
		player.position = surface + Vector3.UP*3.0
		player.velocity = Vector3.ZERO
		for frame: int in range(120):
			await physics_frame
		assert(player.is_on_floor() and player.position.y >= surface.y-0.2, "Real player must land on outer terrain")
	print("VILLAGE_OUTER_GROUND_OK: real player lands beyond all four old square edges and at two woodland trail sites")
	var village: Node3D = world.get_node("WoodlandVillage") as Node3D
	for step: int in range(13):
		var z: float = -38.0-float(step)*6.0
		var x: float = float(village.call("north_trail_center",z))
		var expected: float = float(village.call("landscape_surface_height",x,z))
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x,expected+2.0,z),Vector3(x,expected-2.0,z))
		var hit: Dictionary = space.intersect_ray(query)
		assert(not hit.is_empty() and absf((hit["position"] as Vector3).y-expected)<0.05,"Trail collision must match rendered terrain")
		assert((hit["normal"] as Vector3).y>0.71,"Sampled trail slopes must be walkable")
	print("VILLAGE_TRAIL_GROUND_OK: 13 matched terrain samples with walkable normals")
	player.position = Vector3(0, 0.95, 3)
	player.velocity = Vector3.ZERO
	print("VILLAGE_PLAYER_OK: real player lands at ten inner/outer terrain locations")
	var directory: String = OS.get_user_data_dir().path_join("village-screenshots")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var player_camera: Camera3D = player.get("camera") as Camera3D
	camera.fov = player_camera.fov
	var checked_lens: bool = false
	for layer: Node in world.get_children():
		var effect_script: Script = layer.get_script() as Script
		if effect_script != null and effect_script.resource_path == "res://ui/fisheye.gd":
			var lens_material: ShaderMaterial = layer.get("material") as ShaderMaterial
			var source_half_fov: float = float(lens_material.get_shader_parameter("source_half_fov"))
			assert(is_equal_approx(source_half_fov, deg_to_rad(camera.fov) * 0.5), "Capture and wide-angle source projection must match")
			checked_lens = true
	assert(checked_lens, "Capture must retain the game's wide-angle pass")
	print("VILLAGE_PROJECTION_OK: owner/capture FOV ", camera.fov, "; wide-angle source verified")
	camera.far = 600.0
	var positions: Array[Vector3] = [Vector3(33, 28, 37), Vector3(-18, 2.3, 17), Vector3(-13, 5, -10), Vector3(4,2.3,-20), Vector3(-6,2.2,-44)]
	var targets: Array[Vector3] = [Vector3(0, 0, -2), Vector3(-18, 2.6, -5), Vector3(-23, 3, 4), Vector3(0,1,-40), Vector3(3,0.5,-68)]
	for index: int in range(positions.size()):
		camera.position = positions[index]
		camera.look_at(targets[index])
		camera.make_current()
		var presentation: CanvasLayer = world.get_node("GameUI") as CanvasLayer
		presentation.visible = false
		for frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = directory.path_join("village-%02d.png" % (index + 1))
		var result: Error = image.save_png(path)
		assert(result == OK, "Screenshot save failed: " + path)
		print("VILLAGE_CAPTURE: ", path)
	if "--capture-motion" in OS.get_cmdline_user_args():
		# A slow 4-second dolly uses the real renderer and untouched fisheye canvas.
		var start: Vector3 = positions[1]
		for frame: int in range(240):
			camera.position = start + Vector3(float(frame) / 60.0, 0, 0)
			camera.look_at(targets[1])
			await process_frame
			await RenderingServer.frame_post_draw
		print("VILLAGE_MOTION_OK: 240 rendered frames, native scale ", root.scaling_3d_scale, " MSAA ", root.msaa_3d, " screen AA ", root.screen_space_aa)
	quit()
