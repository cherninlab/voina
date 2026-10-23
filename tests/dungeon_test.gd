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
	# Guards must navigate their own vertically separated halls, not the lowest floor.
	for index: int in range(5):
		var guard: HostileMob = mobs.raiders.get_child(index) as HostileMob
		var floor_y: float = -4.0 if index < 2 else -28.0
		check(absf(guard.position.y - floor_y - 0.95) < 0.25, "Guard %d stands on its own hall floor" % index)
	var grid: MobNavigation = mobs.raider_grids[MobSystem.Zone.VILLAGE]
	var hall_target: Vector3 = RedDescentLayout.at(Vector3(83, -3.05, 36))
	check(grid.walkable(hall_target), "Upper hall grid includes the pursuit target")
	var hunter: HostileMob = mobs.raiders.get_child(0) as HostileMob
	check(grid.path(hunter.position, hall_target).size() > 1, "Upper guard has a path to the player")
	player.position = hall_target
	player.set("sync_position", player.position)
	hunter.set_physics_process(true)
	await frames(240)
	check((player.get("combat") as CombatController).health < 100, "Upper guard sees, pursues and strikes a real player")
	hunter.set_physics_process(false)
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
		print("DUNGEON_OK: four safe spawns, two hall elevations, pursuit/combat, finite encounter, leave/rehost")
		get_tree().quit()
