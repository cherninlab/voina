class_name HostileMob
extends CharacterBody3D
## A possessed villager of the church yard (ChurchSite). The host runs its brain: it lingers and
## wanders near its grave with long pauses, stares at a player who comes into the yard, creeps
## closer on all fours or in an upright shamble while circling, and pounces at close range for
## light damage. It never leaves the yard to hunt; a player who walks away is only stared after.

# Shared with MobVisual: append only, the ints are replicated.
# IDLE lingers, MOVE shambles upright, ACT coils for a pounce (attack_age from 0 to WINDUP),
# DEAD, STARE freezes facing a player, CRAWL moves on all fours, LEAP is the airborne pounce
# (attack_age from launch).
enum State { IDLE, MOVE, ACT, DEAD, STARE, CRAWL, LEAP }
const WINDUP: float = 0.5 # the pounce coil: the telegraph
const RECOVERY: float = 0.7 # crouched after landing
const DAMAGE: int = 8 # at most once per leap
const NOTICE: float = 14.0 # stare at visible players this close
const APPROACH: float = 8.0 # creep toward them inside this
const POUNCE: float = 4.5 # coil from this close, with a clear line
const LEAP_SPEED: Vector2 = Vector2(6.0, 8.0) # horizontal, toward where the target stood at launch
const LEAP_UP: float = 4.8
const LEAP_REACH: float = 1.1 # contact distance in front, centre to centre
const LEAP_MAX: float = 1.5 # a leap off a ledge still ends
const COOLDOWN: Vector2 = Vector2(2.5, 4.0)
const STARE_HOLD: Vector2 = Vector2(1.0, 3.0)
const PATIENCE: Vector2 = Vector2(6.0, 10.0) # staring this long at someone inside the ring, it creeps anyway
const CRAWL_SPEED: float = 2.5
const SHAMBLE_SPEED: float = 1.2
const WANDER_SPEED: float = 0.8
const WANDER: float = 3.5 # wandering radius around its grave
const MARGIN: float = 3.0 # players this far outside the yard ring are still watched
const POUNCE_MARGIN: float = 1.5 # but only pounced on this far outside it
const PROVOKED: float = 8.0 # seconds a hit makes it bolder
const MEMORY: float = 3.0
const GRAVITY: float = 20.0
const CHEST: Vector3 = Vector3.UP * HitResolver.CHEST_HEIGHT

var mob_id: int = 0
var system: MobSystem
var combat: CombatController = preload("res://gameplay/mobs/mob_combat.gd").new()
var history: HitResolver.PositionHistory = HitResolver.PositionHistory.new()
var sync_position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var state: int = State.IDLE
var attack_age: float = 0.0
var target: CharacterBody3D
var last_seen: Vector3 = Vector3.ZERO
var memory_left: float = 0.0
var sense_left: float = 0.0
var path_left: float = 0.0
var route: PackedVector3Array = PackedVector3Array()
var route_goal: Vector3 = Vector3.INF
var did_strike: bool = false
var corpse_left: float = 1.3
var visual: Node3D = preload("res://gameplay/mobs/mob_visual.gd").new()
var kick_velocity: Vector3 = Vector3.ZERO # host-side shove from a blade contact, decays
var hop: float = 0.0
var push_react_left: float = 0.0 # throttles the visible reaction while a player keeps shoving
var collision: CollisionShape3D = CollisionShape3D.new()
# Host-only brain state.
var home: Vector3 = Vector3.ZERO # its grave: where it spawned
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var wander_goal: Vector3 = Vector3.ZERO
var wandering: bool = false
var pause_left: float = 0.0
var stare_left: float = 0.0 # the first hold on noticing a player
var patience_left: float = 0.0
var freeze_left: float = 0.0 # short uncanny stops while creeping
var gait: int = State.CRAWL
var gait_left: float = 0.0
var circle_side: float = 1.0
var cooldown_left: float = 0.0
var recover_left: float = 0.0
var provoked_left: float = 0.0
var leap_velocity: Vector3 = Vector3.ZERO
var look_point: Vector3 = Vector3.ZERO # where a lost player left the yard
var look_left: float = 0.0

func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("hostile_mobs")
	rng.seed = hash(mob_id * 7919 + 17)
	pause_left = rng.randf_range(0.5, 4.0)
	circle_side = 1.0 if rng.randf() < 0.5 else -1.0
	combat.name = "Combat"
	combat.health = 60
	add_child(combat)
	combat.respawn_requested.connect(die)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	visual.set("female", is_female(mob_id))
	add_child(visual)
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "MobSync"
	sync.replication_interval = 1.0 / 30.0
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property: String in ["sync_position", "yaw", "state", "attack_age", "Combat:health", "Combat:phase"]:
		var path: NodePath = NodePath(".:" + property) if not property.begins_with("Combat:") else NodePath(property)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)

# Male or female body from the id the spawner replicates, so every peer, late joiners included,
# shows the same one. The top bit of a Knuth multiplicative hash mixes consecutive ids.
static func is_female(id: int) -> bool:
	return (posmod(id * 2654435761, 4294967296) >> 31) == 1

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		global_position = global_position.lerp(sync_position, minf(1.0, delta * 18.0))
		return
	if state == State.DEAD:
		corpse_left -= delta
		if corpse_left <= 0:
			queue_free()
		return
	velocity.x = 0.0
	velocity.z = 0.0
	if not (state == State.LEAP and attack_age == 0.0): # a launch keeps its take-off speed
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if hop > 0.0:
		velocity.y = hop
		hop = 0.0
	if combat.phase == CombatController.Phase.STAGGERED:
		# A parry or a heavy hit knocks it out of a coil or a leap; it falls where it is.
		if state == State.ACT or state == State.LEAP:
			cooldown_left = COOLDOWN.y
		state = State.IDLE
		leap_velocity = Vector3.ZERO
	elif system != null and system.started:
		sense_left -= delta
		memory_left = maxf(0.0, memory_left - delta)
		cooldown_left = maxf(0.0, cooldown_left - delta)
		provoked_left = maxf(0.0, provoked_left - delta)
		if sense_left <= 0:
			sense()
			sense_left = 0.2
		choose_action(delta)
	body_pushes(delta)
	kick_velocity = kick_velocity.lerp(Vector3.ZERO, 1.0 - exp(-3.5 * delta))
	velocity.x += kick_velocity.x
	velocity.z += kick_velocity.z
	move_and_slide()
	sync_position = global_position
	history.record(HitResolver.now(), sync_position)

# Players inside the yard ring, or just outside it, are watched; anyone farther is ignored.
static func trespassing(point: Vector3, margin: float = MARGIN) -> bool:
	return Vector2(point.x, point.z).distance_to(ChurchSite.YARD_CENTER) <= ChurchSite.YARD_RADIUS + margin

func busy() -> bool:
	return state == State.ACT or state == State.LEAP

func has_target() -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion()

# Perception supplies a last-known position. Movement never reads a hidden target's position.
func sense() -> void:
	var nearest_distance: float = NOTICE
	var seen: CharacterBody3D
	for node: Node in system.players.get_children():
		var player: CharacterBody3D = node as CharacterBody3D
		if player == null or player.is_queued_for_deletion() or not trespassing(player.global_position):
			continue
		var distance: float = global_position.distance_to(player.global_position)
		if distance < nearest_distance and can_see(player):
			seen = player
			nearest_distance = distance
	if busy():
		# The coil and the leap keep their target.
		if seen == target:
			last_seen = seen.global_position
			memory_left = MEMORY
		return
	if seen != null:
		notice(seen)
	elif target != null and (not has_target() or memory_left <= 0.0 or not trespassing(target.global_position)):
		lose_target()

func notice(player: CharacterBody3D) -> void:
	if not has_target():
		# A fresh sighting: freeze and stare before anything else.
		stare_left = rng.randf_range(STARE_HOLD.x, STARE_HOLD.y) if provoked_left <= 0.0 else 0.0
		patience_left = rng.randf_range(PATIENCE.x, PATIENCE.y)
		gait_left = 0.0
		look_left = 0.0
		wandering = false
	target = player
	last_seen = player.global_position
	memory_left = MEMORY

# Stare after a player who left (or was lost), then drift back to the grave.
func lose_target() -> void:
	if has_target():
		look_point = last_seen
		look_left = rng.randf_range(1.5, 3.0)
	target = null
	memory_left = 0.0
	route.clear()
	route_goal = Vector3.INF

func can_see(player: CharacterBody3D) -> bool:
	return HitResolver.wall_distance(get_world_3d().direct_space_state, global_position + CHEST, player.global_position + CHEST, system.actor_rids()) >= global_position.distance_to(player.global_position)

# A pounce needs sight and nothing solid between the two bodies at hip height.
func clear_leap(player: CharacterBody3D) -> bool:
	return can_see(player) and HitResolver.wall_distance(get_world_3d().direct_space_state, global_position, player.global_position, system.actor_rids()) >= global_position.distance_to(player.global_position) - 0.05

func choose_action(delta: float) -> void:
	if state == State.ACT:
		coil(delta)
		return
	if state == State.LEAP:
		fly(delta)
		return
	if recover_left > 0.0:
		recover_left -= delta
		state = State.IDLE
		return
	if has_target() and memory_left > 0.0:
		engage(delta)
		return
	if target != null and not has_target():
		target = null
	roam(delta)

func engage(delta: float) -> void:
	var offset: Vector3 = last_seen - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var provoked: bool = provoked_left > 0.0
	if stare_left > 0.0:
		stare_left -= delta
		stare(last_seen)
		return
	if distance > APPROACH and ChurchSite.in_yard(last_seen):
		patience_left -= delta
	if distance > (NOTICE if provoked or patience_left <= 0.0 else APPROACH):
		stare(last_seen)
		return
	if distance <= POUNCE and cooldown_left <= 0.0 and trespassing(target.global_position, POUNCE_MARGIN) and clear_leap(target):
		state = State.ACT
		attack_age = 0.0
		did_strike = false
		yaw = facing(offset)
		route.clear()
		return
	gait_left -= delta
	if gait_left <= 0.0:
		pick_gait(provoked)
	if freeze_left > 0.0:
		freeze_left -= delta
		stare(last_seen)
		return
	# Spiral in rather than beeline: aim at a point beside the player, and keep circling there
	# while the pounce recovers. The point stays inside the yard.
	var away: Vector3 = -offset / distance if distance > 0.01 else Vector3.BACK
	var ring: float = POUNCE - 1.0
	var swing: float = circle_side * (0.5 if cooldown_left <= 0.0 else 1.1)
	var goal: Vector3 = keep_in_yard(last_seen + away.rotated(Vector3.UP, swing) * ring)
	if walk(goal, CRAWL_SPEED if gait == State.CRAWL else SHAMBLE_SPEED, gait, delta):
		stare(last_seen)

func pick_gait(provoked: bool) -> void:
	gait = State.CRAWL if provoked or rng.randf() < 0.7 else State.MOVE
	gait_left = rng.randf_range(1.5, 3.5)
	if not provoked and rng.randf() < 0.3:
		freeze_left = rng.randf_range(0.3, 0.9)
	if rng.randf() < 0.25:
		circle_side = -circle_side

func roam(delta: float) -> void:
	if look_left > 0.0:
		look_left -= delta
		stare(look_point)
		return
	var from_home: float = Vector2(home.x - global_position.x, home.z - global_position.z).length()
	if from_home > WANDER + 1.5 or not ChurchSite.in_yard(global_position):
		# Drawn away by a chase, a shove or a leap: shamble all the way back to the grave.
		wander_goal = home
		wandering = true
	if wandering:
		if walk(wander_goal, SHAMBLE_SPEED if wander_goal == home else WANDER_SPEED, State.MOVE, delta):
			wandering = false
			pause_left = rng.randf_range(3.0, 9.0)
		return
	state = State.IDLE
	pause_left -= delta
	if pause_left > 0.0:
		return
	if rng.randf() < 0.35:
		# A sudden turn of the head and shoulders, then another long stillness.
		yaw = wrapf(yaw + rng.randf_range(-2.4, 2.4), -PI, PI)
		pause_left = rng.randf_range(2.0, 5.0)
		return
	var heading: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, rng.randf_range(-PI, PI))
	wander_goal = keep_in_yard(home + heading * rng.randf_range(1.0, WANDER))
	wandering = system.navigation.walkable(wander_goal) or system.navigation.heights.is_empty()
	pause_left = 1.0

func stare(point: Vector3) -> void:
	state = State.STARE
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	if offset.length_squared() > 0.01:
		yaw = facing(offset)

static func keep_in_yard(point: Vector3) -> Vector3:
	var flat: Vector2 = Vector2(point.x, point.z) - ChurchSite.YARD_CENTER
	flat = ChurchSite.YARD_CENTER + flat.limit_length(ChurchSite.YARD_RADIUS - 0.5)
	return Vector3(flat.x, point.y, flat.y)

# Follows the yard grid toward a point; true once there (or when no route leads closer).
func walk(destination: Vector3, speed: float, gait_state: int, delta: float) -> bool:
	if Vector2(destination.x - global_position.x, destination.z - global_position.z).length() < 0.35:
		return true
	path_left -= delta
	if path_left <= 0.0 or route.is_empty() or route_goal.distance_to(destination) > 1.0:
		route = grid().path(global_position, destination)
		route_goal = destination
		path_left = 0.4
	while not route.is_empty() and Vector2(route[0].x - global_position.x, route[0].z - global_position.z).length() < 0.22:
		route.remove_at(0)
	if route.is_empty():
		return true
	var direction: Vector3 = route[0] - global_position
	direction.y = 0
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	yaw = facing(direction)
	state = gait_state
	return false

# The grid this mob walks on: the church yard's. RaiderMob walks the forest's.
func grid() -> MobNavigation:
	return system.navigation

func facing(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

func coil(delta: float) -> void:
	attack_age += delta
	if not has_target() or not trespassing(target.global_position, POUNCE_MARGIN):
		state = State.IDLE
		return
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() > 0.01:
		yaw = facing(offset)
	if attack_age >= WINDUP:
		launch()

# A real jump at the target's position at launch: flight time from the take-off speed, and the
# horizontal speed that lands the body just short of where the player stood.
func launch() -> void:
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var direction: Vector3 = offset / distance if distance > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var airtime: float = 2.0 * LEAP_UP / GRAVITY
	leap_velocity = direction * clampf((distance - 0.4) / airtime, LEAP_SPEED.x, LEAP_SPEED.y)
	velocity.y = LEAP_UP
	velocity.x = leap_velocity.x
	velocity.z = leap_velocity.z
	yaw = facing(direction)
	state = State.LEAP
	attack_age = 0.0
	did_strike = false
	GameAudio.broadcast(&"dash", global_position)

func fly(delta: float) -> void:
	attack_age += delta
	velocity.x = leap_velocity.x
	velocity.z = leap_velocity.z
	if not did_strike and has_target():
		strike()
	if (attack_age > 0.15 and is_on_floor()) or attack_age >= LEAP_MAX:
		land()

func land() -> void:
	state = State.IDLE
	leap_velocity = Vector3.ZERO
	recover_left = RECOVERY
	cooldown_left = rng.randf_range(COOLDOWN.x, COOLDOWN.y)
	circle_side = -circle_side
	GameAudio.broadcast(&"mob_shove", global_position)

# Contact during the leap: once, in front, through the shared combat rules (block reduces it,
# a parry staggers the villager out of the air).
func strike() -> void:
	if combat.phase == CombatController.Phase.STAGGERED or not has_target():
		return
	var offset: Vector3 = target.global_position - global_position
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	var forward: Vector3 = leap_velocity.normalized() if leap_velocity.length_squared() > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, yaw)
	if flat.length() > LEAP_REACH or absf(offset.y) > 1.5:
		return
	if flat.length() > 0.3 and forward.dot(flat.normalized()) < 0.2:
		return
	did_strike = true
	target.call("receive_hit", DAMAGE, forward, false, self)
	if combat.phase == CombatController.Phase.STAGGERED:
		kick_velocity = -forward * 4.0
	else:
		leap_velocity = forward * 0.5 # drop onto them rather than through them

func receive_hit(damage: int, direction: Vector3, ranged: bool = false, attacker: CharacterBody3D = null) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	var attacker_combat: CombatController = attacker.get("combat") as CombatController if attacker != null else null
	var result: int = combat.take_hit(damage, ranged, CombatController.guards(yaw, direction), attacker_combat)
	if attacker != null:
		attacker.rpc("hit_feedback", result, true)
		provoke(attacker)

# A player who hurts a villager from inside the yard makes it bolder for a while: no more staring,
# it creeps from farther away and always crawls. It still never follows them out of the yard.
func provoke(attacker: CharacterBody3D) -> void:
	if system == null or attacker.get_parent() != system.players or not trespassing(attacker.global_position):
		return
	provoked_left = PROVOKED
	if not busy():
		notice(attacker)
		stare_left = 0.0
		freeze_left = 0.0

# A player's simulated blade touched this raider on the host. Speed sets the shove; a fast
# damaging contact or a lethal blow bisects along the blade's plane. Damage reuses the shared
# combat rules through receive_hit.
func blade_hit(attacker: CharacterBody3D, point: Vector3, direction: Vector3, speed: float, cut: bool, damage: int, blade_direction: Vector3) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = global_position - attacker.global_position
		flat.y = 0.0
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	# The plane the blade sweeps through: spanned by the blade and its travel.
	var normal: Vector3 = blade_direction.cross(direction)
	normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	if cut or (damage > 0 and damage >= combat.health):
		bisected.rpc(point, normal, flat * minf(speed, 20.0) * 0.35 + Vector3.UP * 2.0, direction)
		receive_hit(999, direction, false, attacker)
		return
	var shove: float = clampf(speed * 0.8, 0.6, 7.0)
	kick_velocity += flat * shove
	hop = 2.0 if speed > 6.0 else (1.0 if speed > 3.0 else 0.0)
	if damage > 0:
		slashed.rpc(flat * shove, point, normal, direction, speed)
		receive_hit(damage, direction, false, attacker)
	else:
		kicked.rpc(flat * shove, point, direction, speed)

# A player walking into this raider shoves it along; the host sees every player's replicated motion.
func body_pushes(delta: float) -> void:
	push_react_left = maxf(0.0, push_react_left - delta)
	if system == null or state == State.DEAD:
		return
	for node: Node in system.players.get_children():
		var player: CharacterBody3D = node as CharacterBody3D
		if player == null or player.is_queued_for_deletion():
			continue
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		if away.length() > 0.85 or away.length_squared() < 0.0001:
			continue
		away = away.normalized()
		var player_velocity: Vector3 = player.get("sync_velocity") as Vector3
		var approach: float = maxf(0.0, Vector3(player_velocity.x, 0.0, player_velocity.z).dot(away))
		kick_velocity += away * (1.5 + approach) * 8.0 * delta
		if approach > 1.0 and push_react_left <= 0.0:
			push_react_left = 0.5
			kicked.rpc(away * approach, global_position + CHEST, away, 0.0)

@rpc("authority", "call_local", "reliable")
func kicked(impulse: Vector3, point: Vector3, direction: Vector3, speed: float) -> void:
	visual.call("react", impulse, point, direction, speed)
	if speed > 0.0:
		GameAudio.play(&"mob_shove", point)
		HitEffects.splash(get_tree().current_scene, point, direction, clampf(speed / 10.0, 0.2, 1.0))

# A damaging hit: a wound line on the body, blood thrown in the blade's plane and a slash arc.
@rpc("authority", "call_local", "reliable")
func slashed(impulse: Vector3, point: Vector3, normal: Vector3, direction: Vector3, speed: float) -> void:
	visual.call("react", impulse, point, direction, speed)
	visual.call("wound", point, normal, direction)
	GameAudio.play(&"mob_slash", point)
	HitEffects.slash(get_tree().current_scene, point, normal, direction, point - global_position, clampf(speed / 6.0, 0.8, 2.0))

@rpc("authority", "call_local", "reliable")
func bisected(point: Vector3, normal: Vector3, impulse: Vector3, direction: Vector3) -> void:
	HitEffects.slash(get_tree().current_scene, point, normal, direction, point - global_position, 3.2)
	HitEffects.sever(get_tree().current_scene, HitEffects.cut_center(point, normal, global_position), normal, direction)
	visual.call("bisect", point, normal, impulse)
	GameAudio.play(&"mob_bisect", point)

func die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", true)
	history.clear()

# Player.receive_hit sends attacker feedback through this common interface.
@rpc("any_peer", "call_local", "reliable")
func hit_feedback(_result: int, _attacking: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not (multiplayer.is_server() and multiplayer.get_remote_sender_id() == 0):
		return

func _process(_delta: float) -> void:
	visual.rotation.y = yaw
	visual.call("show_state", state, combat.health, combat.phase == CombatController.Phase.STAGGERED, state == State.ACT)
	if state == State.DEAD:
		collision.set_deferred("disabled", true)
