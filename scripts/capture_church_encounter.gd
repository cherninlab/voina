extends SceneTree
## Render the church encounter in the real running world: the torch road, the church and the
## possessed villagers reacting to the real player. Run with the Metal renderer (not --headless):
## "$GODOT" --path . -s scripts/capture_church_encounter.gd -- --host --capture-dir=/absolute/folder
## Add --night to dim the sun and sky inside this capture only, to judge the torches after dark.

var world: Node3D
var village: Node3D
var camera: Camera3D = Camera3D.new()
var directory: String = OS.get_user_data_dir().path_join("church-encounter")
var shot: int = 0

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(150):
		await process_frame
	village = world.get_node("WoodlandVillage") as Node3D
	var players: Node3D = world.get("players") as Node3D
	if players.get_child_count() == 0:
		printerr("CHURCH_CAPTURE_FAIL: run with --host")
		quit(1)
		return
	var player: CharacterBody3D = players.get_child(0) as CharacterBody3D
	var mobs: MobSystem = world.get("mobs") as MobSystem
	if not mobs.started:
		mobs.start()
		for frame: int in range(30):
			await process_frame
	for node: String in ["ChurchGrounds", "ChurchRoad"]:
		if world.get_node_or_null(node) == null:
			printerr("CHURCH_CAPTURE_FAIL: missing ", node)
			quit(1)
			return
	if "--night" in OS.get_cmdline_user_args():
		darken()
	(world.get_node("GameUI") as CanvasLayer).visible = false
	camera.fov = (player.get("camera") as Camera3D).fov
	camera.far = 600.0
	world.add_child(camera)
	camera.make_current()
	print("CHURCH_CAPTURE: ", mobs.bodies.get_child_count(), " villagers at ", villager_summary(mobs))
	# Keep the player out of the yard while the scenery is framed, so villagers stay at rest.
	park(player, Vector3(ChurchSite.road_x(-40.0), 0.0, -40.0))
	await frame_at(Vector3(ChurchSite.road_x(-29.0), 1.7, -29.0), Vector3(ChurchSite.road_x(-58.0), 1.0, -58.0), "gate-up-road")
	await frame_at(Vector3(ChurchSite.road_x(-62.0) + 0.6, 1.7, -62.0), Vector3(ChurchSite.DOOR.x, 9.0, ChurchSite.DOOR.y), "mid-road-spire")
	await frame_at(Vector3(ChurchSite.road_x(-86.0), 1.8, -86.0), Vector3(ChurchSite.DOOR.x, 2.5, ChurchSite.DOOR.y), "yard-entrance")
	await frame_at(Vector3(ChurchSite.YARD_CENTER.x + 22.0, 14.0, ChurchSite.YARD_CENTER.y + 18.0), Vector3(ChurchSite.YARD_CENTER.x, 2.0, ChurchSite.YARD_CENTER.y - 4.0), "yard-overview")
	await frame_at(Vector3(4.0, 30.0, -20.0), Vector3(ChurchSite.road_x(-80.0), 0.0, -80.0), "road-from-above")
	# Walk the player into the yard beside a villager and let the encounter react.
	var nearest: HostileMob = nearest_villager(mobs, Vector3(ChurchSite.YARD_CENTER.x, 0.0, ChurchSite.YARD_CENTER.y))
	if nearest == null:
		printerr("CHURCH_CAPTURE_FAIL: no villager near the church")
		quit(1)
		return
	var home: Vector3 = nearest.global_position
	var toward: Vector3 = Vector3(ChurchSite.YARD_CENTER.x - home.x, 0.0, ChurchSite.YARD_CENTER.y - home.z)
	toward = toward.normalized() if toward.length_squared() > 0.01 else Vector3.BACK
	park(player, home + toward * 7.0)
	for wait: int in range(4):
		for frame: int in range(30):
			await physics_frame
		var watcher: Vector3 = player.global_position + Vector3.UP * 1.7 + (player.global_position - nearest.global_position).normalized() * 2.5
		await frame_at(watcher, nearest.global_position + Vector3.UP * 0.6, "villager-react-%d" % wait, false)
		print("CHURCH_CAPTURE: villager ", nearest.mob_id, " state ", HostileMob.State.keys()[nearest.state], " at ", snapped(nearest.global_position.distance_to(player.global_position), 0.1), " m")
	# Lineup: every living villager, close up from the front.
	for mob: Node in mobs.bodies.get_children():
		var villager: HostileMob = mob as HostileMob
		if villager == null or villager.state == HostileMob.State.DEAD:
			continue
		var front: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, villager.yaw)
		await frame_at(villager.global_position + front * 3.2 + Vector3.UP * 0.9, villager.global_position + Vector3.UP * 0.3, "villager-%d" % villager.mob_id, false)
	print("CHURCH_CAPTURE_OK: ", shot, " frames in ", directory)
	quit()

func ground(x: float, z: float) -> float:
	return float(village.call("landscape_surface_height", x, z))

func park(player: CharacterBody3D, point: Vector3) -> void:
	player.position = Vector3(point.x, ground(point.x, point.z) + 1.0, point.z)
	player.velocity = Vector3.ZERO
	player.set("sync_position", player.position)

# Positions are given above the local ground unless absolute is false.
func frame_at(eye: Vector3, target: Vector3, label: String, above_ground: bool = true) -> void:
	if above_ground:
		eye.y += ground(eye.x, eye.z)
		target.y += ground(target.x, target.z)
	camera.global_position = eye
	camera.look_at(target)
	for frame: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	shot += 1
	var path: String = directory.path_join("%02d-%s.png" % [shot, label])
	if root.get_texture().get_image().save_png(path) != OK:
		printerr("CHURCH_CAPTURE_FAIL: could not save ", path)
	print("CHURCH_CAPTURE_FRAME: ", path)

func darken() -> void:
	for node: Node in world.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).light_energy *= 0.08
	for node: Node in world.find_children("*", "WorldEnvironment", true, false):
		var environment: Environment = (node as WorldEnvironment).environment
		environment.background_energy_multiplier = 0.08
		environment.ambient_light_energy *= 0.15
		environment.ambient_light_sky_contribution *= 0.2

func nearest_villager(mobs: MobSystem, point: Vector3) -> HostileMob:
	var best: HostileMob
	for node: Node in mobs.bodies.get_children():
		var villager: HostileMob = node as HostileMob
		if villager == null or villager.state == HostileMob.State.DEAD:
			continue
		if best == null or villager.global_position.distance_squared_to(point) < best.global_position.distance_squared_to(point):
			best = villager
	return best

func villager_summary(mobs: MobSystem) -> String:
	var parts: PackedStringArray = []
	for node: Node in mobs.bodies.get_children():
		var villager: HostileMob = node as HostileMob
		if villager != null:
			parts.append("%d(%.0f,%.1f,%.0f)" % [villager.mob_id, villager.global_position.x, villager.global_position.y, villager.global_position.z])
	return ", ".join(parts)
