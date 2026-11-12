extends Node3D

var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("SPAWN_SLOT_FAIL: " + message)

func stop_motion(player: Node) -> void:
	player.set_physics_process(false)
	(player.get("combat") as CombatController).set_physics_process(false)

func check_static_clearance(world: Node3D, player: CharacterBody3D) -> void:
	var capsule: CapsuleShape3D = (player.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = player.global_transform
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query)
	check(hits.is_empty(), "Village slot %d capsule must clear actual static collision at %s: %s" % [int(player.get_meta("spawn_slot")), player.position, hits])

func run() -> void:
	var world: Node3D = preload("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	# The main smoke invocation selects white_room. Still test the actual village collision.
	world.call("load_map", GameMaps.VILLAGE)
	var players: Node3D = world.get("players") as Node3D
	var flow: MatchFlow = world.get("match_flow") as MatchFlow
	flow.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var starts: Array[Vector3] = []
	for peer: int in [1, 2, 3, 4]:
		check(int(world.call("next_spawn_slot")) == peer - 1, "Opening players receive consecutive vacant slots")
		world.call("peer_connected", peer) # Exercise the actual MultiplayerSpawner.
		var player: CharacterBody3D = players.get_node(str(peer)) as CharacterBody3D
		stop_motion(player)
		check_static_clearance(world, player)
		for previous: Vector3 in starts:
			check(player.position.distance_to(previous) >= 6.0, "Four village spawn slots stay distinct and separated")
		starts.append(player.position)
	check(starts[0].distance_to(starts[1]) == 6.0, "The smoke client's initial hop stays 6 m")
	check(int(world.call("next_spawn_slot")) == -1, "A full session has no spare slot")
	# A rejected fifth callback must not leave a spawn queued indefinitely.
	world.call("peer_connected", 9)
	check((world.get("pending_spawns") as Array[int]).is_empty() and not players.has_node("9"), "Full capacity rejects an extra arrival")

	world.call("peer_disconnected", 2)
	world.call("peer_connected", 5) # Same frame, before queued deletion releases native capacity.
	check(int(world.call("next_spawn_slot")) == -1 and not players.has_node("5"), "Queued deletion retains native spawner capacity until tree exit")
	flow.enter(MatchFlow.State.COUNTDOWN, 3.0, "Queued late join")
	await get_tree().process_frame
	await get_tree().process_frame
	var replacement: CharacterBody3D = players.get_node_or_null("5") as CharacterBody3D
	check(replacement != null and players.get_child_count() == 4, "Same-frame replacement eventually gets an avatar at full capacity")
	if replacement == null:
		get_tree().quit(1)
		return
	stop_motion(replacement)
	check(int(replacement.get_meta("spawn_slot")) == 1, "Replacement uses the departed peer's slot")
	check((replacement.get("combat") as CombatController).frozen and (replacement.get("combat") as CombatController).locked, "Queued late join inherits rules at the time it actually spawns")

	world.call("peer_disconnected", 5)
	world.call("peer_connected", 6)
	world.call("peer_disconnected", 6) # Leave while waiting for native capacity.
	await get_tree().process_frame
	await get_tree().process_frame
	check(not players.has_node("6") and (world.get("pending_spawns") as Array[int]).is_empty(), "A pending leaver never gets a delayed avatar")
	world.call("peer_connected", 7)
	stop_motion(players.get_node("7"))
	world.call("peer_disconnected", 7)
	world.call("peer_connected", 8)
	world.call("clear_players") # Stop while a replacement is waiting.
	await get_tree().process_frame
	await get_tree().process_frame
	check(players.get_child_count() == 0 and (world.get("pending_spawns") as Array[int]).is_empty(), "Stopping clears pending arrivals before deferred retries")
	world.call("peer_connected", 1)
	world.call("clear_players")
	world.call("peer_connected", 1) # Rehost before the old avatar's queued exit.
	check(players.get_node("1").is_queued_for_deletion(), "Immediate rehost waits for the old host avatar to exit")
	await get_tree().process_frame
	await get_tree().process_frame
	var rehost: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
	check(rehost != null and not rehost.is_queued_for_deletion() and players.get_child_count() == 1 and int(rehost.get_meta("spawn_slot")) == 0, "Immediate rehost creates one fresh host avatar in slot zero")
	if rehost == null:
		get_tree().quit(1)
		return
	rehost.free()
	# Exercise the native null return without polluting the smoke suite with its expected error.
	var spawner: MultiplayerSpawner = world.get("spawner") as MultiplayerSpawner
	var spawn_function: Callable = spawner.spawn_function
	spawner.spawn_function = func(_data: Variant) -> Node: return null
	var printed_errors: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	world.call("peer_connected", 10)
	Engine.print_error_messages = printed_errors
	spawner.spawn_function = spawn_function
	check(not players.has_node("10") and (world.get("pending_spawns") as Array[int]).is_empty(), "A null native spawn rejects the arrival without recording success or retrying forever")

	for phase: int in [MatchFlow.State.COUNTDOWN, MatchFlow.State.ROUND_OVER, MatchFlow.State.MATCH_OVER, MatchFlow.State.ROUND]:
		flow.enter(phase, 3.0, "Spawn regression")
		var joining: CharacterBody3D = world.call("create_player", [6, 0]) as CharacterBody3D
		var combat: CombatController = joining.get("combat") as CombatController
		check(combat.frozen == (phase != MatchFlow.State.ROUND), "Spawn inherits combat freeze before entering the tree")
		check(combat.locked == (phase == MatchFlow.State.COUNTDOWN), "Spawn inherits countdown lock before entering the tree")
		players.add_child(joining)
		joining.free()
	# Live movement and respawn must not silently settle out of intersecting cover.
	flow.enter(MatchFlow.State.OFF, 0.0, "")
	for slot: int in range(4):
		var player: CharacterBody3D = world.call("create_player", [1, slot]) as CharacterBody3D
		players.add_child(player) # Local authority so the actual movement/physics runs.
		for frame: int in range(30):
			await get_tree().physics_frame
		check(Vector2(player.position.x - starts[slot].x, player.position.z - starts[slot].z).length() < 0.05, "Village slot %d must not settle sideways after spawning" % slot)
		player.position += Vector3(0, 2, 0)
		(player.get("combat") as CombatController).respawn()
		check_static_clearance(world, player)
		for frame: int in range(30):
			await get_tree().physics_frame
		check(Vector2(player.position.x - starts[slot].x, player.position.z - starts[slot].z).length() < 0.05, "Village slot %d respawn must not settle sideways" % slot)
		player.free()
	world.queue_free()
	await get_tree().process_frame
	if not failed:
		print("SPAWN_SLOT_OK: static capsule clearance, settled spawns/respawns, actual spawner same-frame replacement, pending leave/stop, latejoin rules")
	get_tree().quit(1 if failed else 0)
