extends Node3D
## Actual player capsule follows the connected level, without teleporting between spans.

var world: Node3D
var player: CharacterBody3D
var failed: bool = false
var distance_walked: float = 0.0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("DUNGEON_TRAVERSAL_FAIL: " + message)
		get_tree().quit(1)

func walk(points: PackedVector3Array, label: String) -> void:
	for index: int in range(points.size()):
		var target: Vector3 = points[index] + Vector3.UP * 0.91
		var ticks: int = 0
		var limit: int = ceili(player.position.distance_to(target) / 6.0 * 60.0) + 180
		while Vector2(player.position.x - target.x, player.position.z - target.z).length() > 0.16:
			await get_tree().physics_frame
			var offset: Vector3 = target - player.position
			offset.y = 0.0
			var horizontal: Vector3 = offset.normalized() * minf(6.5, offset.length() * 60.0)
			player.velocity = Vector3(horizontal.x, -0.6 if player.is_on_floor() else player.velocity.y - 18.0 / 60.0, horizontal.z)
			var before: Vector3 = player.position
			player.move_and_slide()
			player.apply_floor_snap()
			distance_walked += player.position.distance_to(before)
			ticks += 1
			if ticks > limit or player.position.y < minf(target.y, points[maxi(0, index - 1)].y) - 3.0:
				for collision_index: int in range(player.get_slide_collision_count()):
					var contact: KinematicCollision3D = player.get_slide_collision(collision_index)
					print("TRAVERSAL_CONTACT: %s normal %s" % [contact.get_position(), contact.get_normal()])
				check(false, "%s node %d blocked/fell: %s -> %s, floor=%s" % [label, index, player.position, target, player.is_on_floor()])
				return
		# Downhill seams can leave the capsule briefly airborne; let gravity settle it.
		for settling: int in range(90):
			if player.is_on_floor():
				break
			await get_tree().physics_frame
			player.velocity = Vector3(0, player.velocity.y - 18.0 / 60.0, 0)
			player.move_and_slide()
		check(absf(player.position.y - target.y) < 0.65, "%s node %d wrong elevation: %s expected %s" % [label, index, player.position, target])
		if failed:
			return
	print("DUNGEON_ROUTE_OK: %s (%d nodes)" % [label, points.size()])

func run() -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	for frame: int in range(20):
		await get_tree().physics_frame
	var players: Node3D = world.get("players") as Node3D
	check(players.get_child_count() == 1, "Host player exists")
	player = players.get_child(0) as CharacterBody3D
	player.set_physics_process(false)
	player.floor_snap_length = 0.35
	var mobs: MobSystem = world.get("mobs") as MobSystem
	for mob: Node in mobs.raiders.get_children():
		mob.set_physics_process(false)
	player.position = RedDescentLayout.main_route()[0] + Vector3.UP * 0.95
	player.velocity = Vector3.ZERO
	await walk(RedDescentLayout.main_route(), "descent")
	if failed:
		return
	# The real player update must preserve a valid deep floor below the old -10 m limit.
	player.set("sync_position", player.position)
	player.set_physics_process(true)
	for frame: int in range(8):
		await get_tree().physics_frame
	player.set_physics_process(false)
	check(player.position.y < -26.0, "Deep choir does not trigger the outdoor fall recovery")
	await walk(RedDescentLayout.return_route(), "return stair")
	if failed:
		return
	var paths: Array[Dictionary] = RedDescentLayout.routes()
	for index: int in [3, 2, 1, 0]:
		var reverse: PackedVector3Array = (paths[index]["points"] as PackedVector3Array).duplicate()
		reverse.reverse()
		await walk(reverse, "egress " + String(paths[index]["id"]))
		if failed:
			return
	# Probe optional loops from their actual connections, keeping each loop continuous.
	for index: int in [13, 14, 15, 16]:
		var route: PackedVector3Array = paths[index]["points"] as PackedVector3Array
		player.position = route[0] + Vector3.UP * 0.95
		player.velocity = Vector3.ZERO
		await walk(route, String(paths[index]["id"]))
		if failed:
			return
	# The narrow sloping crossings must work away from the route's centre too.
	for path_index: int in [1, 9]:
		var path: Dictionary = paths[path_index]
		var centerline: PackedVector3Array = path["points"] as PackedVector3Array
		for lateral: float in [-0.75, 0.75]:
			var lane: PackedVector3Array = PackedVector3Array()
			for index: int in range(centerline.size()):
				var tangent: Vector3 = centerline[mini(index + 1, centerline.size() - 1)] - centerline[maxi(index - 1, 0)]
				tangent.y = 0.0
				var side: Vector3 = Vector3(-tangent.z, 0, tangent.x).normalized()
				lane.append(centerline[index] + side * lateral)
			player.position = lane[0] + Vector3.UP * 0.95
			player.velocity = Vector3.ZERO
			await walk(lane, "%s lane %.2f" % [String(path["id"]), lateral])
			if failed:
				return
	print("DUNGEON_TRAVERSAL_OK: %.0f m actual capsule walking; descent, slopes, return, egress, four optional loops, both bridge lanes, deep-floor recovery" % distance_walked)
	get_tree().quit()
