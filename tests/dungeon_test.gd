extends Node3D

var world: Node3D
var mobs: MobSystem
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("DUNGEON_FAIL: " + message)
		get_tree().quit(1)

func run() -> void:
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	mobs = world.get("mobs") as MobSystem
	await frames(15)
	check(world.has_node("CinderCrypt") and not world.has_node("WoodlandVillage") and not Wildlife.active, "Only the dungeon is built; outdoor wildlife stays inactive")
	var players: Node3D = world.get("players") as Node3D
	if not multiplayer.is_server():
		await frames(90)
		check(players.get_child_count() == 2, "Late join receives both players")
		check(mobs.raiders.get_child_count() == 3 and int(mobs.get("remaining")) == 3, "Late join receives three surviving cultists and objective count")
		var first: HostileMob = mobs.raiders.get_child(0) as HostileMob
		var before: int = first.combat.health
		first.receive_hit(999, Vector3.FORWARD)
		await frames(4)
		check(first.combat.health == before, "Client damage cannot bypass host authority")
		if not failed:
			print("DUNGEON_CLIENT_OK: late join, surviving enemies, objective, authority")
			get_tree().quit()
		return
	check(players.get_child_count() == 1 and mobs.raiders.get_child_count() == 5, "Host spawns at the entrance with five cultists")
	var player: CharacterBody3D = players.get_child(0) as CharacterBody3D
	player.set_physics_process(false)
	for mob: Node in mobs.raiders.get_children():
		mob.set_physics_process(false)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = mobs.actor_rids()
	var positions: Array[Vector3] = []
	for slot: int in range(4):
		var spawn: Vector3 = world.call("player_spawn", slot) as Vector3
		positions.append(spawn)
		query.transform = Transform3D(Basis.IDENTITY, spawn)
		check(space.intersect_shape(query).is_empty(), "Spawn %d clears walls and furniture" % slot)
	for a: int in range(positions.size()):
		for b: int in range(a + 1, positions.size()):
			check(positions[a].distance_to(positions[b]) >= 1.9, "Four player spawns are separated")
	var grid: MobNavigation = mobs.raider_grids[MobSystem.Zone.VILLAGE]
	# Test both routes, every doorway, and the last chamber against actual capsule clearance.
	var route: Array[Vector3] = [Vector3(-3, 0.95, 17), Vector3(-3, 0.95, 10), Vector3(0, 0.95, 8), Vector3(-4, 0.95, 3), Vector3(4, 0.95, 3), Vector3(-4, 0.95, -3), Vector3(4, 0.95, -3), Vector3(0, 0.95, -8), Vector3(0, 0.95, -12), Vector3(0, 0.95, -16)]
	for point: Vector3 in route:
		query.transform = Transform3D(Basis.IDENTITY, point)
		check(space.intersect_shape(query).is_empty(), "Player capsule clears route at %s" % point)
		check(grid.walkable(point), "Enemy grid reaches %s" % point)
		var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 2, 1, query.exclude))
		check(not floor_hit.is_empty() and absf((floor_hit["position"] as Vector3).y) < 0.02, "Floor supports %s" % point)
		check(grid.path(player.position, point).size() > 1, "Connected route from entrance to %s" % point)
	for wall: Vector3 in [Vector3(13, 1, 0), Vector3(-13, 1, 0), Vector3(0, 1, 21), Vector3(0, 1, -21), Vector3(0, 7.2, 0)]:
		query.transform = Transform3D(Basis.IDENTITY, wall)
		check(not space.intersect_shape(query).is_empty(), "Dungeon boundary blocks %s" % wall)
	# Move the real player capsule: the headless display cannot capture a mouse for WASD input.
	player.position = Vector3(-3, 0.95, 18)
	player.set("sync_position", player.position)
	for frame: int in range(120):
		await get_tree().physics_frame
		player.velocity = Vector3(0, -0.2, -6.5)
		player.move_and_slide()
	check(player.position.z < 10.0 and player.is_on_floor(), "Real player walks from entry to burial hall approach (%s)" % player.position)
	player.position = positions[0]
	player.set("sync_position", player.position)
	var hunter: HostileMob = mobs.raiders.get_child(0) as HostileMob
	player.position = Vector3(-5, 0.95, 2)
	player.set("sync_position", player.position)
	hunter.set_physics_process(true)
	await frames(180)
	check((player.get("combat") as CombatController).health < 100, "A dungeon cultist sees, pursues and strikes a player in the burial hall")
	player.position = positions[0]
	player.set("sync_position", player.position)
	# Two deaths before a real late join; remaining enemies are held at their posts for the probe.
	for index: int in range(2):
		var mob: HostileMob = mobs.raiders.get_child(index) as HostileMob
		mob.receive_hit(999, Vector3.FORWARD)
		mob.set_physics_process(true)
	await frames(210)
	check(int(mobs.get("remaining")) == 3, "Host objective counts deaths")
	print("DUNGEON_HOST_READY: three survivors for late join")
	while players.get_child_count() < 2:
		await get_tree().physics_frame
	await frames(140)
	while players.get_child_count() > 1:
		await get_tree().physics_frame
	for node: Node in mobs.raiders.get_children():
		var mob: HostileMob = node as HostileMob
		mob.receive_hit(999, Vector3.FORWARD)
		mob.set_physics_process(true)
	await frames(600)
	check(int(mobs.get("remaining")) == 0 and mobs.raiders.get_child_count() == 0, "Cleared dungeon has no replacement enemies after ten seconds")
	NetworkManager.stop("test restart")
	await frames(3)
	NetworkManager.host_game(NetworkManager.port)
	await frames(10)
	check(mobs.raiders.get_child_count() == 5 and int(mobs.get("remaining")) == 5, "Leave and rehost resets the encounter")
	if not failed:
		print("DUNGEON_OK: four safe spawns, solid boundaries, both paths, navigation, real walking, finite encounter, leave/rehost")
		get_tree().quit()
