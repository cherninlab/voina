extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
var players: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var mobs: MobSystem = MobSystem.new()
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("MOB_FAIL: " + message)
		get_tree().quit(1)

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func wall(size: Vector3, location: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = location
	body.add_child(shape)
	add_child(body)

func create_player(data: Variant) -> Node:
	var info: Array = data as Array
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = str(int(info[0]))
	player.set_multiplayer_authority(int(info[0]))
	player.position = info[1] as Vector3
	player.set("sync_position", player.position)
	return player

func add_player(peer: int, location: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = create_player([peer, location]) as CharacterBody3D
	players.add_child(player)
	player.set_physics_process(false)
	return player

func add_mob(id: int, location: Vector3) -> HostileMob:
	var mob: HostileMob = mobs.create_mob([id, location]) as HostileMob
	mobs.bodies.add_child(mob)
	return mob

func place(player: CharacterBody3D, location: Vector3) -> void:
	player.position = location
	player.set("sync_position", location)
	if player is HostileMob:
		(player as HostileMob).history.clear()
	else:
		player.set("accepted_position", location)
		(player.get("history") as HitResolver.PositionHistory).clear()

func combat(player: CharacterBody3D) -> CombatController:
	return player.get("combat") as CombatController

func run() -> void:
	players.name = "Players"
	add_child(players)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = create_player
	add_child(spawner)
	mobs.name = "Mobs"
	mobs.players = players
	add_child(mobs)
	wall(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	wall(Vector3(1, 3, 4), Vector3(3, 1.5, 0))
	if "--mob-network" in OS.get_cmdline_user_args():
		add_to_group("match_world")
		multiplayer.peer_connected.connect(peer_connected)
		multiplayer.peer_disconnected.connect(peer_disconnected)
		NetworkManager.start_from_arguments()
		if multiplayer.is_server():
			network_host()
		else:
			network_client()
		return
	await local_checks()

func local_checks() -> void:
	var player: CharacterBody3D = add_player(1, Vector3(0, 0.95, -1.5))
	var mob: HostileMob = add_mob(1, Vector3(0, 0.95, 0))
	await frames(4)
	mobs.navigation.build(get_world_3d().direct_space_state, mobs.actor_rids())
	var route: PackedVector3Array = mobs.navigation.path(Vector3(0, 0.95, 0), Vector3(6, 0.95, 0))
	var detour: bool = false
	for point: Vector3 in route:
		if absf(point.z) > 2.5:
			detour = true
	check(route.size() > 10 and detour, "A capsule-clear path detours around cover")
	mob.sense()
	check(mob.target == player, "Visible players are sensed")
	place(player, Vector3(6, 0.95, 0))
	var remembered: Vector3 = mob.last_seen
	mob.sense()
	check(mob.last_seen == remembered, "Cover hides new player positions")
	mob.memory_left = 0.0
	mob.sense()
	check(mob.target == null, "Lost targets expire from memory")
	# Actually pursue the remembered position around the obstacle, with collision enabled.
	mob.target = player
	mob.last_seen = player.global_position
	mob.memory_left = HostileMob.MEMORY
	mob.sense_left = 100.0
	mobs.started = true
	await frames(110)
	check(mob.global_position.distance_to(Vector3(0, 0.95, 0)) > 2.0, "The brain moves along its route")
	mobs.started = false
	mob.set_physics_process(false)
	place(mob, Vector3(0, 0.95, 0))
	place(player, Vector3(0, 0.95, -1.5))
	player.set("yaw", PI)
	mob.state = HostileMob.State.IDLE
	mob.sense()
	mob.choose_action(0.01)
	check(mob.state == HostileMob.State.ACT, "A nearby visible target starts a telegraph")
	mob.choose_action(HostileMob.WINDUP - 0.1)
	check(combat(player).health == 100, "Windup gives time to react")
	mob.choose_action(0.11)
	check(combat(player).health == 88, "One committed melee hit deals damage")
	mob.choose_action(0.1)
	check(combat(player).health == 88, "Recovery cannot deal a second hit")
	# Raising guard just before impact parries and staggers the mob through existing combat.
	check(combat(player).set_block(true), "Player guard can be raised")
	mob.state = HostileMob.State.IDLE
	mob.sense()
	mob.choose_action(0.01)
	mob.choose_action(HostileMob.WINDUP)
	check(combat(player).health == 88 and mob.combat.phase == CombatController.Phase.STAGGERED, "Player parry staggers a raider")
	mob._physics_process(0.01)
	check(mob.state == HostileMob.State.IDLE, "Stagger cancels the pending action")
	combat(player).set_block(false)
	# A held front guard after the parry window takes only chip damage.
	combat(player).next_block = 0
	combat(player).set_block(true)
	combat(player).block_started = combat(player).clock - 1.0
	mob.combat.phase = CombatController.Phase.IDLE
	mob.target = player
	mob.yaw = 0
	mob.strike()
	check(combat(player).health == 85, "Held front guard reduces a mob hit to 3 health")
	combat(player).set_block(false)
	# A target can move out of the committed cone during windup.
	place(player, Vector3(0, 0.95, 1.5))
	mob.strike()
	check(combat(player).health == 85, "Turning away from a committed attack avoids it")
	# Real player attack resolution includes all mobs, with separate IDs under peer 1.
	place(player, Vector3(0, 0.95, 0))
	player.set("yaw", 0.0)
	place(mob, Vector3(-0.35, 0.95, -1.4))
	var second: HostileMob = add_mob(2, Vector3(0.35, 0.95, -1.4))
	second.set_physics_process(false)
	await frames(2)
	combat(player).struck.clear()
	player.call("resolve_attack", false)
	player.call("resolve_attack", false)
	check(mob.combat.health == 35 and second.combat.health == 35, "A melee swing hits each host-owned mob exactly once")
	place(second, Vector3(8, 0.95, 8))
	place(mob, Vector3(0, 0.95, -4))
	await frames(2)
	player.call("resolve_attack", true)
	check(mob.combat.health == 20, "The existing beam damages a mob")
	check(Projectiles.handle_fire(1, 0, player.global_position + HostileMob.CHEST, Vector3.FORWARD), "A bolt toward a mob is accepted")
	await frames(25)
	check(mob.combat.health == 0 and mob.state == HostileMob.State.DEAD, "The existing swept bolt kills a mob without respawn")
	mob.set_physics_process(true)
	await frames(90)
	check(not is_instance_valid(mob), "The host removes the corpse")
	if not failed:
		print("MOB_OK: navigation, perception, pursuit, telegraph, block, parry, miss, melee dedupe, beam, bolt, death")
		get_tree().quit()

func host_started() -> void:
	var player: Node = spawner.spawn([1, Vector3(0, 0.95, 3)])
	player.set_physics_process(false)
	mobs.start()

func peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		var player: Node = spawner.spawn([peer, Vector3(10, 0.95, 10)])
		player.set_physics_process(false)

func peer_disconnected(_peer: int) -> void:
	if multiplayer.is_server():
		print("MOB_NETWORK_HOST_OK: authoritative combat, late join, death/despawn")
		get_tree().quit()

func network_host() -> void:
	for frame: int in range(600):
		await get_tree().physics_frame
		var player: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
		if player != null and combat(player).health < 100:
			mobs.started = false
			var mob: HostileMob = mobs.bodies.get_node("Mob1") as HostileMob
			mob.receive_hit(15, Vector3.FORWARD, true)
			place(mob, Vector3(1.25, 0.95, 0))
			print("MOB_NETWORK_READY")
			return
	check(false, "Mobs must chase and damage the host player")

func network_client() -> void:
	for frame: int in range(600):
		await get_tree().physics_frame
		if mobs.bodies.get_child_count() == 3 and players.get_child_count() == 2:
			break
	await frames(30)
	check(mobs.bodies.get_child_count() == 3, "Late join receives all three mobs")
	var mob: HostileMob = mobs.bodies.get_node_or_null("Mob1") as HostileMob
	if mob == null:
		return
	check(mob.combat.health == 45 and mob.sync_position.distance_to(Vector3(1.25, 0.95, 0)) < 0.1, "Late join receives current health and position")
	check(combat(players.get_node("1") as CharacterBody3D).health < 100, "Mob damage to a player replicates")
	mob.receive_hit(100, Vector3.FORWARD)
	mob.combat.take_hit(100, false, false)
	mobs.start()
	check(mob.combat.health == 45 and not mobs.started, "Client cannot damage mobs or start an encounter")
	finish_network_check.rpc_id(1)
	for frame: int in range(180):
		await get_tree().physics_frame
		if mobs.bodies.get_child_count() == 2:
			break
	check(mobs.bodies.get_child_count() == 2, "Host death and despawn replicate to a late joiner")
	if not failed:
		print("MOB_NETWORK_OK: late join, health, position, host damage, client authority refusal, despawn")
		get_tree().quit()

# Test-only phase advance. Production scenes do not expose a mob damage request RPC.
@rpc("any_peer", "call_remote", "reliable")
func finish_network_check() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() in multiplayer.get_peers():
		(mobs.bodies.get_node("Mob1") as HostileMob).receive_hit(100, Vector3.FORWARD)
