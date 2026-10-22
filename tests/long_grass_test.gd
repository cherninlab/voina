extends Node3D
## Long Grass over real ENet: the host (--host --map=long_grass) checks generation, fences and the
## camp-by-camp encounters; a joiner (--join, any map) adopts the road and sees the live camp.

var world: Node3D
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func check(condition: bool, message: String) -> void:
	if not condition and not failed:
		failed = true
		printerr("LONG_GRASS_FAIL: " + message)
		get_tree().quit(1)

func wait_for(condition: Callable, limit: int = 600) -> bool:
	for frame: int in range(limit):
		if condition.call():
			return true
		await get_tree().physics_frame
	return false

func mobs() -> CampMobs:
	return world.get("mobs") as CampMobs

func players() -> Node3D:
	return world.get("players") as Node3D

func run() -> void:
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	await frames(10)
	if not BuildSync.user_arg("--join=").is_empty():
		check(await wait_for(func() -> bool: return players().get_child_count() == 2, 1800), "The joiner spawns")
		check(str(world.get("map_id")) == GameMaps.LONG_GRASS and world.has_node("LongGrass"), "The joiner adopts the long grass")
		check(await wait_for(func() -> bool: return mobs().active == 0 and mobs().alive > 0, 300), "The joiner sees the first camp awake")
		check(mobs().raiders.get_child_count() == mobs().alive, "The joiner receives the camp's cultists")
		if not failed:
			print("LONG_GRASS_CLIENT_OK: adopted road, live camp replicated")
			get_tree().quit()
		return
	var field: LongGrass = world.get_node("LongGrass") as LongGrass
	# Risograph is brightened on this map only (GameMaps.SHADING_ADJUST); other themes keep theirs.
	var shading: Node = null
	for child: Node in world.get_children():
		if child.get_script() == preload("res://ui/shading.gd"):
			shading = child
	var before: int = int(shading.get("theme_index"))
	shading.call("set_theme", (shading.call("theme_names") as PackedStringArray).find("Risograph"))
	check(is_equal_approx(float((shading.get("values") as Dictionary)["exposure"]), float(GameMaps.SHADING_ADJUST[GameMaps.LONG_GRASS]["Risograph"]["exposure"])), "Risograph is brightened on the long grass")
	shading.call("set_theme", (shading.call("theme_names") as PackedStringArray).find("Natural"))
	check(is_zero_approx(float((shading.get("values") as Dictionary)["exposure"])), "Other themes keep their own exposure")
	shading.call("set_theme", before)
	var settings: LongGrassSettings = field.settings
	# The same seed must give every peer the same road and camps.
	var again: LongGrass = LongGrass.new()
	again.generate()
	check(again.points == field.points and again.fires == field.fires and again.camp_cultists == field.camp_cultists, "Generation is deterministic")
	again.objective.free() # built with the node, but only added to the tree in _ready
	again.free()
	check(absf(field.road_length() - settings.length) <= settings.step, "The road is %d m long" % roundi(settings.length))
	check(field.camps.size() >= 3 and field.camps.size() == field.fires.size(), "Several camps along the road (%d)" % field.camps.size())
	for index: int in range(1, field.camps.size()):
		check(field.camp_stations[index] - field.camp_stations[index - 1] > settings.camp_radius * 2.0, "Camps %d and %d do not overlap" % [index - 1, index])
	var last: int = field.camps.size() - 1
	check(is_equal_approx(field.camp_stations[last], field.road_length()) and field.fires[last].distance_to(field.points[field.points.size() - 1]) < 0.01, "The road ends at the last fire")
	check(field.tree_count > 200, "Trees line the horizon (%d)" % field.tree_count)
	check(field.camp_cultists[field.camps.size() - 1] == settings.cultists_max, "The road's end holds the most cultists")
	# Sites alternate camp, ambush, camp ... with each ambush midway between its two fires.
	check(field.ambush_stations.size() == field.camps.size() - 1 and field.site_stations.size() == field.camps.size() * 2 - 1, "An ambush between every pair of camps")
	for index: int in range(field.site_stations.size()):
		check(field.site_camp[index] == (index % 2 == 0), "Site %d is a %s" % [index, "camp" if index % 2 == 0 else "ambush"])
		if index > 0:
			check(field.site_stations[index] > field.site_stations[index - 1], "Sites run in road order")
	check(is_equal_approx(field.ambush_stations[0], (field.camp_stations[0] + field.camp_stations[1]) * 0.5), "The first ambush is midway between the first two fires")
	check(field.grass_half_width() > settings.field_half_width + 5.0, "Grass reaches past the fence")
	var started_at: int = Time.get_ticks_msec()
	field.grass()
	print("LONG_GRASS_GRASS: %d clumps in %d ms" % [field.grass_clumps, Time.get_ticks_msec() - started_at])
	check(field.grass_clumps > 5000, "The field is planted")
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	for station: float in [50.0, 300.0, 600.0]:
		var normal: Vector3 = field.normal_at(station)
		for lateral: float in [0.0, 6.0, settings.field_half_width - 1.5]:
			query.transform = Transform3D(Basis.IDENTITY, field.point_at(station) + normal * lateral + Vector3.UP * 1.0)
			check(space.intersect_shape(query).is_empty(), "Open ground %.0f m along, %.1f m aside" % [station, lateral])
		var beyond: Vector3 = field.point_at(station) + normal * (settings.field_half_width + 0.1) + Vector3.UP * 1.0
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(beyond - normal * 3.0, beyond + normal * 3.0)).is_empty(), "The fence stops players %.0f m along" % station)
	# The final clearing is open all round; the fence closes the field just past it.
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		query.transform = Transform3D(Basis.IDENTITY, field.fires[last] + Vector3(cos(angle), 0.0, sin(angle)) * (settings.camp_radius - 1.5) + Vector3.UP * 1.0)
		check(space.intersect_shape(query).is_empty(), "The last clearing is open toward %.1f rad" % angle)
	var beyond_end: Vector3 = field.point_at(field.field_end()) + Vector3.UP * 1.0
	var tangent: Vector3 = field.tangent_at(field.road_length())
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(beyond_end - tangent * 3.0, beyond_end + tangent * 3.0)).is_empty(), "The field is fenced beyond the road's end")
	check(players().get_child_count() == 1, "The host spawns at the road's start")
	var player: CharacterBody3D = players().get_child(0) as CharacterBody3D
	check(player.position.distance_to(field.point_at(4.0)) < 2.0, "Spawn is on the road")
	await frames(30)
	check(mobs().active == -1 and mobs().raiders.get_child_count() == 0, "Camps sleep until approached")
	await visit(player, field, 0)
	check(mobs().active == 0 and mobs().raiders.get_child_count() == field.site_cultists[0], "The first camp wakes with %d cultists" % field.site_cultists[0])
	print("LONG_GRASS_HOST_READY: first camp awake")
	check(await wait_for(func() -> bool: return players().get_child_count() == 2, 1800), "A joiner arrives")
	check(await wait_for(func() -> bool: return players().get_child_count() == 1, 1800), "The joiner leaves")
	for node: Node in mobs().raiders.get_children():
		(node as HostileMob).receive_hit(999, Vector3.FORWARD)
	check(await wait_for(func() -> bool: return mobs().cleared == 1 and mobs().alive == 0, 120), "Felling the camp clears it")
	await visit(player, field, 1)
	check(mobs().active == 1 and mobs().alive == settings.ambush_cultists, "The ambush midway springs with %d cultists" % settings.ambush_cultists)
	for node: Node in mobs().raiders.get_children():
		var at: Vector3 = (node as Node3D).global_position
		check(field.distance_to_road(at, field.site_stations[1]) > settings.path_width * 0.5 and at.distance_to(field.site_anchors[1]) > settings.ambush_radius, "Ambushers rise from the grass, off the road and outside the space")
	# Walk on past the survivors: they give up, and the next camp wakes instead.
	await visit(player, field, 2)
	check(await wait_for(func() -> bool: return mobs().raiders.get_child_count() == field.site_cultists[2], 120), "Survivors of a site left behind vanish")
	check(mobs().active == 2 and mobs().cleared == 1, "Only felled sites count as cleared")
	NetworkManager.stop("Left game")
	await frames(3)
	NetworkManager.host_game(NetworkManager.port)
	await frames(10)
	check(mobs().active == -1 and mobs().cleared == 0 and mobs().raiders.get_child_count() == 0, "Rehosting resets every camp")
	if not failed:
		print("LONG_GRASS_OK: deterministic road, camps, fence, planted field, wake/clear/abandon, rehost")
		get_tree().quit()

# Put the player on the road short of a site and wait for it to wake.
func visit(player: CharacterBody3D, field: LongGrass, index: int) -> void:
	var reach: float = field.settings.wake_distance if field.site_camp[index] else field.settings.ambush_wake
	player.position = field.point_at(field.site_stations[index] - reach * 0.5) + Vector3.UP * 0.95
	player.set("sync_position", player.position)
	check(await wait_for(func() -> bool: return mobs().active == index, 120), "Site %d wakes when approached" % index)
	await frames(5)
