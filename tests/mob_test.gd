extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
# The test yard rises northward like the real hillside: 6 degrees, ground 3 m at the yard centre.
const SLOPE: float = 0.105
const BASE: float = 3.0
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

func ground_y(z: float) -> float:
	return BASE - SLOPE * (z - ChurchSite.YARD_CENTER.y)

# A point in the yard, offset from its centre, standing (capsule centre) on the slope.
func yard(offset: Vector2, above: float = MobNavigation.STAND) -> Vector3:
	var flat: Vector2 = ChurchSite.YARD_CENTER + offset
	return Vector3(flat.x, ground_y(flat.y) + above, flat.y)

func box(size: Vector3, location: Vector3, tilt: float = 0.0) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cube: BoxShape3D = BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.position = location
	body.rotation.x = tilt
	body.add_child(shape)
	add_child(body)

func build_yard() -> void:
	var tilt: float = atan(SLOPE)
	var top: Vector3 = Vector3(ChurchSite.YARD_CENTER.x, BASE, ChurchSite.YARD_CENTER.y)
	box(Vector3(70, 1, 70), top - Vector3(0, cos(tilt), sin(tilt)) * 0.5, tilt)
	box(Vector3(1, 3, 4), yard(Vector2(3, 0), 1.3)) # cover
	box(Vector3(3, 0.2, 3), yard(Vector2(-6, 6), 2.7)) # a roof with open ground under it

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
		player.velocity = Vector3.ZERO
	else:
		player.set("accepted_position", location)
		(player.get("history") as HitResolver.PositionHistory).clear()

func combat(player: CharacterBody3D) -> CombatController:
	return player.get("combat") as CombatController

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# A calm villager with its pounce ready, standing still.
func reset(mob: HostileMob, location: Vector3) -> void:
	place(mob, location)
	mob.state = HostileMob.State.IDLE
	mob.cooldown_left = 0.0
	mob.recover_left = 0.0
	mob.stare_left = 0.0
	mob.freeze_left = 0.0
	mob.provoked_left = 0.0
	mob.look_left = 0.0
	mob.kick_velocity = Vector3.ZERO
	mob.leap_velocity = Vector3.ZERO
	mob.target = null
	mob.combat.phase = CombatController.Phase.IDLE

func fresh(player: CharacterBody3D) -> void:
	var guard: CombatController = combat(player)
	guard.set_block(false)
	guard.health = 100
	guard.stamina = 100.0
	guard.poise = 100.0
	guard.phase = CombatController.Phase.IDLE
	guard.next_block = 0.0

# Sense the player without the first stare, as if it had been watching for a while.
func aim(mob: HostileMob) -> void:
	mob.sense()
	mob.stare_left = 0.0

# Coil and launch by hand, then let physics fly the leap; on_frame runs every airborne tick.
func pounce(mob: HostileMob, player: CharacterBody3D, on_frame: Callable = Callable()) -> float:
	aim(mob)
	mob.choose_action(0.01)
	check(mob.state == HostileMob.State.ACT, "A close visible player starts the pounce coil (state %d)" % mob.state)
	mob.choose_action(HostileMob.WINDUP)
	check(mob.state == HostileMob.State.LEAP, "The coil ends in a leap")
	var start: float = mob.global_position.y
	var peak: float = start
	mobs.started = true
	for frame: int in range(120):
		await get_tree().physics_frame
		peak = maxf(peak, mob.global_position.y)
		if on_frame.is_valid():
			on_frame.call()
		if mob.state != HostileMob.State.LEAP:
			break
	mobs.started = false
	return peak - start

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
	build_yard()
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
	var player: CharacterBody3D = add_player(1, yard(Vector2(0, 12)))
	await frames(4)
	# The yard grid follows the slope, detours around cover and sees ground under a roof.
	var navigation: MobNavigation = mobs.navigation
	navigation.build(get_world_3d().direct_space_state, mobs.actor_rids())
	var route: PackedVector3Array = navigation.path(yard(Vector2(0, 0)), yard(Vector2(6, 0)))
	var detour: bool = false
	var grounded: bool = true
	for point: Vector3 in route:
		detour = detour or absf(point.z - ChurchSite.YARD_CENTER.y) > 2.5
		grounded = grounded and absf(point.y - (ground_y(point.z) + MobNavigation.STAND)) < 0.08
	check(route.size() > 10 and detour, "A capsule-clear path detours around cover")
	check(grounded, "Path points follow the sloped ground")
	check(navigation.walkable(yard(Vector2(-6, 6))) and absf(navigation.stand_point(yard(Vector2(-6, 6))).y - yard(Vector2(-6, 6)).y) < 0.08, "Ground under a roof keeps its own height")
	check(not navigation.walkable(yard(Vector2(3, 0))) and navigation.walkable(navigation.stand_point(yard(Vector2(3, 0)))), "Cover is solid and nearest() finds free ground beside it")
	check(navigation.covers(yard(Vector2(ChurchSite.YARD_RADIUS + 4.0, 0))) and navigation.covers(yard(Vector2(0, -ChurchSite.YARD_RADIUS - 4.0))), "The grid covers the whole yard")
	# A player outside the yard is ignored even when close to a villager at its edge.
	var mob: HostileMob = add_mob(1, yard(Vector2(12, 8)))
	place(player, yard(Vector2(12, 21)))
	await frames(2)
	mob.sense()
	check(mob.target == null, "A player outside the yard is ignored")
	mobs.started = true
	var strayed: float = 0.0
	var engaged: bool = false
	for frame: int in range(300):
		await get_tree().physics_frame
		strayed = maxf(strayed, flat_distance(mob.global_position, mob.home))
		engaged = engaged or mob.state in [HostileMob.State.STARE, HostileMob.State.CRAWL, HostileMob.State.ACT, HostileMob.State.LEAP]
	mobs.started = false
	check(not engaged and strayed <= HostileMob.WANDER + 0.5 and ChurchSite.in_yard(mob.global_position) and combat(player).health == 100, "Villagers stay home while players pass outside (strayed %.1f m)" % strayed)
	# A visible player inside the yard is stared at first, and only watched beyond 8 m.
	reset(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(0, 10)))
	player.set("yaw", 0.0)
	await frames(2)
	mob.sense()
	check(mob.target == player and mob.stare_left >= HostileMob.STARE_HOLD.x, "A visible player in the yard is noticed with a stare hold")
	mob.choose_action(0.01)
	var toward: Vector3 = player.global_position - mob.global_position
	check(mob.state == HostileMob.State.STARE and absf(angle_difference(mob.yaw, mob.facing(Vector3(toward.x, 0, toward.z)))) < 0.05, "Staring freezes facing the player")
	mob.choose_action(HostileMob.STARE_HOLD.y)
	mob.choose_action(0.01)
	check(mob.state == HostileMob.State.STARE, "A player beyond 8 m is only watched")
	place(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(4, 0))) # behind the cover
	var remembered: Vector3 = mob.last_seen
	mob.sense()
	check(mob.last_seen == remembered, "Cover hides new player positions")
	mob.memory_left = 0.0
	mob.sense()
	check(mob.target == null and mob.look_left > 0.0, "A lost player is stared after, then forgotten")
	# Closer than 8 m it creeps in, coils and leaps on its own, for 8 damage once.
	reset(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(0, 6.5)))
	await frames(2)
	var seen: Array[int] = []
	var coil_started: float = -1.0
	var coil_time: float = 0.0
	var coil_distance: float = 0.0
	var clock: float = 0.0
	mobs.started = true
	for frame: int in range(600):
		await get_tree().physics_frame
		clock += 1.0 / 60.0
		if seen.is_empty() or seen.back() != mob.state:
			seen.append(mob.state)
			if mob.state == HostileMob.State.ACT:
				coil_started = clock
				coil_distance = flat_distance(mob.global_position, player.global_position)
			elif mob.state == HostileMob.State.LEAP:
				coil_time = clock - coil_started
		if HostileMob.State.LEAP in seen and mob.state == HostileMob.State.IDLE:
			break
	mobs.started = false
	var crept: bool = seen.find(HostileMob.State.CRAWL) != -1 or seen.find(HostileMob.State.MOVE) != -1
	check(crept and seen.find(HostileMob.State.ACT) > maxi(seen.find(HostileMob.State.CRAWL), seen.find(HostileMob.State.MOVE)), "It stares, creeps closer, then coils (states %s)" % str(seen))
	check(coil_distance <= HostileMob.POUNCE + 0.1 and absf(coil_time - HostileMob.WINDUP) < 0.05, "The coil starts within pounce range and lasts the telegraph (%.2f m, %.2f s)" % [coil_distance, coil_time])
	check(combat(player).health == 100 - HostileMob.DAMAGE, "One leap lands one light hit (health %d)" % combat(player).health)
	# By hand: the coil gives time to react, the jump is real and hits once.
	fresh(player)
	reset(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(0, 3.5)))
	await frames(3)
	aim(mob)
	mob.choose_action(0.01)
	check(mob.state == HostileMob.State.ACT, "A close visible player starts the coil")
	mob.choose_action(HostileMob.WINDUP - 0.05)
	check(mob.state == HostileMob.State.ACT and combat(player).health == 100, "The coil gives time to react")
	mob.choose_action(0.06)
	var heading: Vector3 = (player.global_position - mob.global_position) * Vector3(1, 0, 1)
	check(mob.state == HostileMob.State.LEAP and mob.leap_velocity.length() >= HostileMob.LEAP_SPEED.x - 0.01 and mob.leap_velocity.length() <= HostileMob.LEAP_SPEED.y + 0.01 and mob.leap_velocity.normalized().dot(heading.normalized()) > 0.99 and is_equal_approx(mob.velocity.y, HostileMob.LEAP_UP), "The leap launches toward the player's position")
	var peak: float = 0.0
	mobs.started = true
	for frame: int in range(120):
		await get_tree().physics_frame
		peak = maxf(peak, mob.global_position.y - yard(Vector2(0, 0)).y)
		if mob.state != HostileMob.State.LEAP:
			break
	check(peak > 0.3 and combat(player).health == 92, "A real jump deals one hit (rise %.2f m, health %d)" % [peak, combat(player).health])
	check(mob.state == HostileMob.State.IDLE and mob.cooldown_left >= HostileMob.COOLDOWN.x - 0.1, "It lands, recovers and waits out a cooldown")
	var again: bool = false
	for frame: int in range(60):
		await get_tree().physics_frame
		again = again or mob.state == HostileMob.State.ACT or mob.state == HostileMob.State.LEAP
	mobs.started = false
	check(not again and combat(player).health == 92, "No second pounce during the cooldown")
	# A held front guard reduces a leap to chip damage.
	fresh(player)
	reset(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(0, 3.5)))
	await frames(3)
	check(combat(player).set_block(true), "Player guard can be raised")
	combat(player).block_started = combat(player).clock - 1.0
	await pounce(mob, player)
	check(combat(player).health == 98, "A held front guard reduces a leap to 2 damage (health %d)" % combat(player).health)
	combat(player).set_block(false)
	# Raising guard just before contact parries and staggers the villager out of the air.
	fresh(player)
	reset(mob, yard(Vector2(0, 0)))
	place(player, yard(Vector2(0, 3.5)))
	await frames(3)
	var guard: Callable = func() -> void:
		if not combat(player).blocking and flat_distance(mob.global_position, player.global_position) < 1.9:
			combat(player).set_block(true)
	await pounce(mob, player, guard)
	await frames(1)
	check(combat(player).health == 100 and mob.combat.phase == CombatController.Phase.STAGGERED and mob.state == HostileMob.State.IDLE, "A parry staggers the villager out of its leap")
	check(mob.cooldown_left >= HostileMob.COOLDOWN.y - 0.1, "A parried pounce waits out the longest cooldown")
	combat(player).set_block(false)
	# Player melee still hits each villager once and provokes it; beam and bolts still kill.
	mob.combat.phase = CombatController.Phase.IDLE
	reset(mob, yard(Vector2(-0.35, 6.6)))
	place(player, yard(Vector2(0, 8)))
	player.set("yaw", 0.0)
	var second: HostileMob = add_mob(2, yard(Vector2(0.35, 6.6)))
	second.set_physics_process(false)
	await frames(2)
	combat(player).struck.clear()
	player.call("resolve_attack", false)
	player.call("resolve_attack", false)
	check(mob.combat.health == 35 and second.combat.health == 35, "A melee swing hits each villager exactly once")
	check(mob.provoked_left > 0.0 and mob.target == player and mob.stare_left == 0.0, "A hit from inside the yard provokes the villager")
	reset(second, yard(Vector2(0.35, 6.6)))
	place(player, yard(Vector2(0, 26)))
	second.receive_hit(1, Vector3.FORWARD, true, player)
	check(second.provoked_left == 0.0 and second.target == null, "A hit from outside the yard does not draw it out")
	place(player, yard(Vector2(0, 8)))
	place(second, yard(Vector2(8, 14)))
	place(mob, yard(Vector2(0, 4)))
	await frames(2)
	player.call("resolve_attack", true)
	check(mob.combat.health == 20, "The existing beam damages a villager")
	check(Projectiles.handle_fire(1, 0, player.global_position + HostileMob.CHEST, Vector3.FORWARD), "A bolt toward a villager is accepted")
	await frames(25)
	check(mob.combat.health == 0 and mob.state == HostileMob.State.DEAD, "The existing swept bolt kills a villager without respawn")
	await frames(90)
	check(not is_instance_valid(mob), "The host removes the corpse")
	# Lost players are stared after, then the villager drifts back to its grave.
	second.set_physics_process(true)
	reset(second, yard(Vector2(8, 4)))
	second.home = yard(Vector2(8, -4))
	place(player, yard(Vector2(8, 9)))
	await frames(2)
	second.sense()
	place(player, yard(Vector2(8, 26)))
	second.sense()
	second.choose_action(0.01)
	check(second.target == null and second.state == HostileMob.State.STARE, "A player who leaves the yard is stared after")
	mobs.started = true
	await frames(720)
	mobs.started = false
	check(flat_distance(second.global_position, second.home) <= HostileMob.WANDER + 1.5, "It drifts back home (%.1f m away)" % flat_distance(second.global_position, second.home))
	second.queue_free()
	await frames(2)
	# The encounter spawns on the yard's ground and replaces the dead at the farthest grave.
	place(player, yard(Vector2(-11, -6)))
	mobs.start()
	await frames(4)
	check(mobs.bodies.get_child_count() == MobSystem.COUNT and mobs.spawn_points.size() == MobSystem.SPAWN_SPOTS.size(), "The encounter spawns its villagers")
	var on_ground: bool = true
	for point: Vector3 in mobs.spawn_points:
		on_ground = on_ground and ChurchSite.in_yard(point) and absf(point.y - (ground_y(point.z) + MobNavigation.STAND + 0.05)) < 0.08
	check(on_ground, "Spawn points sit on the sloped yard ground")
	var expected: Vector3 = MobSystem.farthest_spawn(mobs.spawn_points, [player.global_position])
	(mobs.bodies.get_node("Mob1") as HostileMob).receive_hit(999, Vector3.FORWARD)
	var replacement: HostileMob
	for frame: int in range(500):
		await get_tree().physics_frame
		replacement = mobs.bodies.get_node_or_null("Mob%d" % (MobSystem.COUNT + 1)) as HostileMob
		if replacement != null:
			break
	check(replacement != null and flat_distance(replacement.global_position, expected) < 0.1 and mobs.bodies.get_child_count() == MobSystem.COUNT, "A replacement rises at the grave farthest from the players")
	mobs.clear()
	if not failed:
		print("MOB_OK: sloped yard grid, territory, stare, creep, coil, leap, one hit per leap, block, parry, provoke, melee dedupe, beam, bolt, death, return home, spawn and respawn")
		get_tree().quit()

func host_started() -> void:
	# Close to the first grave, so a villager pounces on the host before anyone joins.
	var player: Node = spawner.spawn([1, yard(MobSystem.SPAWN_SPOTS[0] + Vector2(0, 5))])
	player.set_physics_process(false)
	mobs.start()

func peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		# Outside the yard: the villagers leave this one alone.
		var player: Node = spawner.spawn([peer, yard(Vector2(0, 26))])
		player.set_physics_process(false)

func peer_disconnected(_peer: int) -> void:
	if multiplayer.is_server():
		print("MOB_NETWORK_HOST_OK: authoritative pounce, late join, death/despawn")
		get_tree().quit()

func network_host() -> void:
	for frame: int in range(900):
		await get_tree().physics_frame
		var player: CharacterBody3D = players.get_node_or_null("1") as CharacterBody3D
		if player != null and combat(player).health < 100:
			mobs.started = false
			var mob: HostileMob = mobs.bodies.get_node("Mob1") as HostileMob
			mob.receive_hit(15, Vector3.FORWARD, true)
			place(mob, yard(Vector2(1.25, 0)))
			var crawler: HostileMob = mobs.bodies.get_node("Mob2") as HostileMob
			crawler.state = HostileMob.State.CRAWL
			print("MOB_NETWORK_READY")
			return
	check(false, "A villager must pounce on and damage the host player")

func network_client() -> void:
	for frame: int in range(600):
		await get_tree().physics_frame
		if mobs.bodies.get_child_count() == MobSystem.COUNT and players.get_child_count() == 2:
			break
	await frames(30)
	check(mobs.bodies.get_child_count() == MobSystem.COUNT, "Late join receives every villager")
	var mob: HostileMob = mobs.bodies.get_node_or_null("Mob1") as HostileMob
	var crawler: HostileMob = mobs.bodies.get_node_or_null("Mob2") as HostileMob
	if mob == null or crawler == null:
		return
	check(mob.combat.health == 45 and mob.sync_position.distance_to(yard(Vector2(1.25, 0))) < 0.1, "Late join receives current health and position")
	check(mob.global_position.distance_to(mob.sync_position) < 0.3, "The client body follows the host's position on the slope")
	check(crawler.state == HostileMob.State.CRAWL, "Late join receives the villager's state")
	check(combat(players.get_node("1") as CharacterBody3D).health < 100, "Pounce damage to a player replicates")
	mob.receive_hit(100, Vector3.FORWARD)
	mob.combat.take_hit(100, false, false)
	mobs.start()
	check(mob.combat.health == 45 and not mobs.started, "Client cannot damage villagers or start an encounter")
	finish_network_check.rpc_id(1)
	for frame: int in range(180):
		await get_tree().physics_frame
		if mobs.bodies.get_child_count() == MobSystem.COUNT - 1:
			break
	check(mobs.bodies.get_child_count() == MobSystem.COUNT - 1, "Host death and despawn replicate to a late joiner")
	if not failed:
		print("MOB_NETWORK_OK: late join, health, position, state, host damage, client authority refusal, despawn")
		get_tree().quit()

# Test-only phase advance. Production scenes do not expose a mob damage request RPC.
@rpc("any_peer", "call_remote", "reliable")
func finish_network_check() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() in multiplayer.get_peers():
		(mobs.bodies.get_node("Mob1") as HostileMob).receive_hit(100, Vector3.FORWARD)
