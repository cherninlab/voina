extends SceneTree
## Render the hillside church and graveyard in the real running world and probe its collision.
## "$GODOT" --path . --script scripts/capture_church.gd -- --host --capture-dir=/absolute/folder [--fog]
## Run without --headless so frames come from the Metal renderer. --fog approximates the coming
## haunted-forest grade (denser blue-grey fog) inside this script only.

var world: Node3D
var church: Node3D
var directory: String = OS.get_user_data_dir().path_join("church-screenshots")

func _initialize() -> void:
	capture.call_deferred()

func ground(x: float, z: float) -> float:
	return float(world.get_node("WoodlandVillage").call("landscape_surface_height", x, z))

func fail(message: String) -> void:
	printerr("CHURCH_CAPTURE_FAIL: ", message)
	quit(1)

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	# Collision must exist almost immediately: the villager grid samples it at host start.
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	church = world.get_node_or_null("ChurchGrounds") as Node3D
	if church == null:
		fail("ChurchGrounds node missing")
		return
	var floor_y: float = float(church.get("floor_y"))
	var door: Vector3 = Vector3(ChurchSite.DOOR.x, floor_y, ChurchSite.DOOR.y)
	var early: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(door + Vector3(0.0, 3.0, 0.8), door + Vector3(0.0, -3.0, 0.8)))
	if early.is_empty() or absf((early["position"] as Vector3).y - floor_y) > 0.05:
		fail("terrace floor missing two physics frames after start")
		return
	print("CHURCH_EARLY_COLLISION_OK: terrace floor at ", snappedf(floor_y, 0.01), " within two physics frames")
	for frame: int in range(120):
		await process_frame
	# Walls block: horizontal rays from outside hit the nave sides, back and tower.
	var probes: Array[Array] = [[door + Vector3(-9.0, 2.0, -8.0), door + Vector3(0.0, 2.0, -8.0), "west nave wall"], [door + Vector3(9.0, 2.0, -10.0), door + Vector3(0.0, 2.0, -10.0), "east nave wall"], [door + Vector3(0.0, 1.5, 4.0), door + Vector3(0.0, 1.5, -3.0), "closed door"], [Vector3(-14.0, ground(-14.0, -95.0) + 1.0, -95.0), Vector3(-26.0, ground(-14.0, -95.0) + 1.0, -95.0), "west yard wall"], [Vector3(6.0, ground(6.0, -84.0) + 1.0, -84.0), Vector3(6.0, ground(6.0, -84.0) + 1.0, -92.0), "front yard wall"]]
	for probe: Array in probes:
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(probe[0] as Vector3, probe[1] as Vector3))
		if hit.is_empty():
			fail("no collision on the " + String(probe[2]))
			return
	print("CHURCH_WALLS_OK: nave sides, closed door, yard walls block rays")
	if world.get("players").get_child_count() == 0:
		fail("capture requires --host")
		return
	var player: CharacterBody3D = world.get("players").get_child(0) as CharacterBody3D
	var capsule: Shape3D
	for child: Node in player.get_children():
		if child is CollisionShape3D:
			capsule = (child as CollisionShape3D).shape
			break
	var gate_x: float = ChurchSite.road_x(-87.5)
	var gate_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	gate_query.shape = capsule
	gate_query.exclude = [player.get_rid()]
	gate_query.transform = Transform3D(Basis.IDENTITY, Vector3(gate_x, ground(gate_x, -84.0) + 1.3, -84.0))
	gate_query.motion = Vector3(0.0, 0.0, -6.0)
	var clearance: PackedFloat32Array = space.cast_motion(gate_query)
	if clearance[0] < 0.99:
		fail("player capsule does not clear the open gate (%.2f)" % clearance[0])
		return
	print("CHURCH_GATE_OK: player capsule passes the open graveyard gate")
	# The real player lands on the path, the steps and the terrace in front of the door.
	var drops: Array[Vector3] = [Vector3(ChurchSite.road_x(-92.0), 0.0, -92.0), Vector3(ChurchSite.road_x(-102.0), 0.0, -102.0), Vector3(door.x, 0.0, door.z + 2.4), Vector3(door.x + 1.5, 0.0, door.z + 0.8)]
	for sample: Vector3 in drops:
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(sample.x, 60.0, sample.z), Vector3(sample.x, -20.0, sample.z)))
		if hit.is_empty():
			fail("no ground at %s" % sample)
			return
		var surface: Vector3 = hit["position"] as Vector3
		player.position = surface + Vector3.UP * 2.0
		player.velocity = Vector3.ZERO
		for frame: int in range(100):
			await physics_frame
		if not player.is_on_floor() or player.position.y < surface.y - 0.2:
			fail("player did not land at %s (now %s)" % [surface, player.position])
			return
	print("CHURCH_PLAYER_OK: real player lands on the yard path, steps and door terrace")
	# Villager spawn graves stay free of collision within a metre.
	for spot: Vector2 in MobSystem.SPAWN_SPOTS:
		var point: Vector2 = ChurchSite.YARD_CENTER + spot
		var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 1.0
		probe.shape = sphere
		probe.exclude = [player.get_rid()]
		probe.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, ground(point.x, point.y) + 1.4, point.y))
		var hits: Array[Dictionary] = space.intersect_shape(probe, 4)
		for hit: Dictionary in hits:
			var collider: Object = hit["collider"]
			if collider is StaticBody3D and (collider as Node).name == "ChurchCollision":
				fail("church collision within 1 m of spawn grave %s" % point)
				return
	print("CHURCH_SPAWN_GRAVES_OK: ", MobSystem.SPAWN_SPOTS.size(), " spawn graves clear of church collision")
	var lights: int = 0
	for node: Node in church.find_children("*", "OmniLight3D", true, false):
		lights += 1
		assert(not (node as OmniLight3D).shadow_enabled, "Church lights must not cast shadows")
	print("CHURCH_LIGHTS: ", lights, " non-shadowing OmniLights (Mobile applies at most 8 omni + 8 spot per mesh)")
	if "--fog" in OS.get_cmdline_user_args():
		for node: Node in world.find_children("*", "WorldEnvironment", true, false):
			var environment: Environment = (node as WorldEnvironment).environment
			environment.fog_light_color = Color("6f7f8c")
			environment.fog_density = 0.03
			environment.fog_sky_affect = 0.6
			environment.fog_aerial_perspective = 0.2
		print("CHURCH_FOG: capture-only blue-grey fog density 0.03")
	player.position = Vector3(0.0, 0.95, 3.0)
	player.velocity = Vector3.ZERO
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = (player.get("camera") as Camera3D).fov
	camera.far = 600.0
	var presentation: CanvasLayer = world.get_node("GameUI") as CanvasLayer
	presentation.visible = false
	var views: Array[Array] = [
		["trail", Vector3(ChurchSite.road_x(-30.0), ground(ChurchSite.road_x(-30.0), -30.0) + 1.7, -30.0), Vector3(door.x, floor_y + 16.0, door.z)],
		["gate", Vector3(ChurchSite.road_x(-79.0) + 0.6, ground(ChurchSite.road_x(-79.0), -79.0) + 1.7, -79.0), Vector3(gate_x - 1.0, floor_y + 4.0, -100.0)],
		["path", Vector3(ChurchSite.road_x(-97.0) + 0.4, ground(ChurchSite.road_x(-97.0), -97.0) + 1.7, -97.0), Vector3(door.x, floor_y + 5.0, door.z)],
		["facade", Vector3(5.5, ground(5.5, -101.0) + 2.0, -101.0), Vector3(door.x, floor_y + 5.5, door.z - 2.0)],
		["slope", Vector3(-19.0, ground(-19.0, -124.0) + 2.5, -124.0), Vector3(door.x, floor_y + 3.0, door.z - 6.0)],
		["door", Vector3(door.x + 3.2, floor_y + 0.9, door.z + 5.2), Vector3(door.x - 0.2, floor_y + 1.6, door.z)],
		["crow", Vector3(ChurchSite.road_x(-90.5), ground(ChurchSite.road_x(-90.5), -90.5) + 1.6, -90.5), Vector3(-3.4, ground(-3.4, -91.4) + 0.9, -91.4)],
		["grave", Vector3(7.6, ground(7.6, -96.6) + 1.7, -96.6), Vector3(6.0, ground(6.0, -99.0) - 0.5, -99.4)],
		["overview", Vector3(ChurchSite.road_x(-70.0), 32.0, -70.0), Vector3(-4.0, 2.0, -103.0)],
	]
	for view: Array in views:
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(20):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = directory.path_join("church-%s%s.png" % [String(view[0]), "-fog" if "--fog" in OS.get_cmdline_user_args() else ""])
		if image.save_png(path) != OK:
			fail("could not save " + path)
			return
		print("CHURCH_CAPTURE: ", path)
	quit()
