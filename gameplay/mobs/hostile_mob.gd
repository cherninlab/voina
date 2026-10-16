class_name HostileMob
extends CharacterBody3D

enum State { IDLE, MOVE, ACT, DEAD }
const WINDUP: float = 0.5
const RECOVERY: float = 0.8
const REACH: float = 1.9
const DAMAGE: int = 12
const MEMORY: float = 3.0
const SIGHT: float = 14.0
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
var did_strike: bool = false
var corpse_left: float = 1.3
var visual: Node3D = preload("res://gameplay/mobs/mob_visual.gd").new()
var collision: CollisionShape3D = CollisionShape3D.new()

func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("hostile_mobs")
	combat.name = "Combat"
	combat.health = 60
	add_child(combat)
	combat.respawn_requested.connect(die)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
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
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	if combat.phase == CombatController.Phase.STAGGERED:
		state = State.IDLE
	elif system != null and system.started:
		sense_left -= delta
		memory_left = maxf(0.0, memory_left - delta)
		if sense_left <= 0:
			sense()
			sense_left = 0.2
		choose_action(delta)
	move_and_slide()
	sync_position = global_position
	history.record(HitResolver.now(), sync_position)

# Perception supplies a last-known position. Movement never reads a hidden target's position.
func sense() -> void:
	var nearest_distance: float = SIGHT
	var seen: CharacterBody3D
	for node: Node in system.players.get_children():
		var player: CharacterBody3D = node as CharacterBody3D
		if player == null or player.is_queued_for_deletion():
			continue
		var distance: float = global_position.distance_to(player.global_position)
		if distance < nearest_distance and can_see(player):
			seen = player
			nearest_distance = distance
	if seen != null:
		# Keep the committed attack target until recovery ends.
		if state != State.ACT:
			target = seen
		last_seen = seen.global_position
		memory_left = MEMORY
	elif memory_left <= 0 and state != State.ACT:
		target = null

func can_see(player: CharacterBody3D) -> bool:
	return HitResolver.wall_distance(get_world_3d().direct_space_state, global_position + CHEST, player.global_position + CHEST, system.actor_rids()) >= global_position.distance_to(player.global_position)

func choose_action(delta: float) -> void:
	if state == State.ACT:
		attack_age += delta
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			state = State.IDLE
			return
		if attack_age >= WINDUP and not did_strike:
			did_strike = true
			strike()
		if attack_age >= WINDUP + RECOVERY:
			state = State.IDLE
		return
	if not is_instance_valid(target) or memory_left <= 0:
		state = State.IDLE
		return
	if global_position.distance_to(last_seen) < 1.65 and can_see(target):
		yaw = facing(target.global_position - global_position)
		state = State.ACT
		attack_age = 0.0
		did_strike = false
		return
	path_left -= delta
	if path_left <= 0:
		route = system.navigation.path(global_position, last_seen)
		path_left = 0.4
	while not route.is_empty() and Vector2(route[0].x - global_position.x, route[0].z - global_position.z).length() < 0.22:
		route.remove_at(0)
	if route.is_empty():
		state = State.IDLE
		return
	var direction: Vector3 = route[0] - global_position
	direction.y = 0
	direction = direction.normalized()
	velocity.x = direction.x * 2.7
	velocity.z = direction.z * 2.7
	yaw = facing(direction)
	state = State.MOVE

func facing(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

func strike() -> void:
	if combat.phase == CombatController.Phase.STAGGERED or not is_instance_valid(target):
		return
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	if HitResolver.in_cone(global_position, forward, target.global_position, REACH, deg_to_rad(45)) and can_see(target):
		target.call("receive_hit", DAMAGE, forward, false, self)

func receive_hit(damage: int, direction: Vector3, ranged: bool = false, attacker: CharacterBody3D = null) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	var attacker_combat: CombatController = attacker.get("combat") as CombatController if attacker != null else null
	var result: int = combat.take_hit(damage, ranged, CombatController.guards(yaw, direction), attacker_combat)
	if attacker != null:
		attacker.rpc("hit_feedback", result, true)

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
	visual.call("show_state", state, combat.health, combat.phase == CombatController.Phase.STAGGERED, state == State.ACT and attack_age < WINDUP)
	if state == State.DEAD:
		collision.set_deferred("disabled", true)
