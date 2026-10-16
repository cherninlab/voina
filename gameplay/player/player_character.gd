extends CharacterBody3D

var sync_position: Vector3 = Vector3.ZERO
var sync_velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var combat: CombatController = CombatController.new()
var spawn_position: Vector3 = Vector3.ZERO
var camera: Camera3D = Camera3D.new()
var pivot: Node3D = Node3D.new()
var arm: SpringArm3D = SpringArm3D.new()
const MALE_VISUAL: PackedScene = preload("res://content/characters/quaternius/male.tscn")
const FEMALE_VISUAL: PackedScene = preload("res://content/characters/quaternius/female.tscn")
var body: CharacterVisual
var third_person: bool = true
var drag_gesture: DragGesture = DragGesture.new()
var approved_swing_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector3 = Vector3.ZERO
var dash_left: float = 0.0
var dash_pending: bool = false
var swing_time: float = -1.0
var swing_pending: bool = false
var sword_held: bool = false # Owner-synchronized cosmetic intent; never grants damage.
var feedback: String = ""
var feedback_left: float = 0.0
var shake_left: float = 0.0
var hitstop_left: float = 0.0
var aim_friction: float = 1.0
var aim_cast: ShapeCast3D = ShapeCast3D.new()
var flash_left: float = 0.0
var flash_color: Color = Color.WHITE
var accepted_position: Vector3 = Vector3.ZERO
var stagger_anchor: Vector3 = Vector3.ZERO
var stagger_anchored: bool = false
var last_motion_check: float = 0.0
var history: HitResolver.PositionHistory = HitResolver.PositionHistory.new()
var remote_motion: RemoteMotion = RemoteMotion.new()
var corrections_sent: int = 0

# Knockback slide plus slack; walking during the owner's latency is added per peer.
const STAGGER_DRIFT: float = 2.0

func _ready() -> void:
	spawn_position = position
	accepted_position = position
	last_motion_check = Time.get_ticks_msec() / 1000.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	add_child(collision)
	var visual_scene: PackedScene = MALE_VISUAL if get_multiplayer_authority() == 1 else FEMALE_VISUAL
	body = visual_scene.instantiate() as CharacterVisual
	add_child(body)
	body.reset_motion(yaw)
	pivot.position.y = 0.65
	add_child(pivot)
	arm.spring_length = 2.6
	arm.position.x = 0.55
	arm.margin = 0.2
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.2
	arm.shape = sphere
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	arm.add_child(camera)
	camera.current = is_multiplayer_authority() and not NetworkManager.dedicated
	# Every network frame (60/s at the game's 60 fps cap), so remote bodies trail by network transit,
	# not by half a slow snapshot interval. An interval equal to the frame time would skip frames.
	var movement: MultiplayerSynchronizer = add_sync("MovementSync", get_multiplayer_authority(), [^":sync_position", ^":sync_velocity", ^":yaw", ^":pitch", ^":sword_held"], 0.0)
	movement.synchronized.connect(func() -> void: remote_motion.receive(sync_position, sync_velocity, HitResolver.now(), position))
	remote_motion.reset(position, HitResolver.now())
	combat.name = "Combat"
	combat.set_multiplayer_authority(1)
	combat.attack_started.connect(func(ranged: bool) -> void: attack_effect.rpc(ranged, approved_swing_direction))
	combat.attack_active.connect(resolve_attack)
	combat.respawn_requested.connect(respawn)
	add_child(combat)
	add_sync("CombatSync", 1, [^"Combat:health", ^"Combat:stamina", ^"Combat:poise", ^"Combat:blocking", ^"Combat:phase"])
	var aim_shape: SphereShape3D = SphereShape3D.new()
	aim_shape.radius = 0.35
	aim_cast.shape = aim_shape
	aim_cast.target_position = Vector3(0, 0, -40)
	aim_cast.add_exception(self)
	camera.add_child(aim_cast)
	if is_multiplayer_authority() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func add_sync(sync_name: String, authority: int, properties: Array[NodePath], interval: float = 1.0 / 30.0) -> MultiplayerSynchronizer:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = sync_name
	synchronizer.set_multiplayer_authority(authority)
	synchronizer.replication_interval = interval
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property: NodePath in properties:
		config.add_property(property)
		config.property_set_replication_mode(property, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = config
	add_child(synchronizer)
	return synchronizer

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		release_input()
		return
	if event.is_action_released(&"melee"):
		drag_gesture.cancel()
	if event.is_action_released(&"block"):
		send_block(false)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(&"camera_toggle"):
		set_camera_mode(not third_person)
	elif event.is_action_pressed(&"quick_turn"):
		drag_gesture.cancel()
		yaw += PI
	elif event.is_action_pressed(&"melee"):
		if not combat.blocking and can_predict_action(18.0):
			drag_gesture.begin()
	elif event.is_action_pressed(&"block"):
		send_block(true)
	elif event.is_action_pressed(&"dash"):
		dash()
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if not motion.screen_relative.is_finite():
			return
		var sensitivity: float = InputSettings.sensitivity * aim_friction
		yaw -= motion.screen_relative.x * sensitivity
		pitch = clampf(pitch - motion.screen_relative.y * sensitivity, -1.39, 1.39)
		# Camera and sword share the same look input, including after the initial attack.
		if drag_gesture.held:
			var cut: Vector2 = drag_gesture.move(motion.screen_relative)
			if not cut.is_zero_approx():
				attack(false, cut)
	if event is InputEventMagnifyGesture:
		var gesture: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if gesture.factor < 0.85:
			set_camera_mode(true)
		elif gesture.factor > 1.15:
			set_camera_mode(false)

func release_input() -> void:
	drag_gesture.cancel()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	send_block(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_multiplayer_authority() and is_node_ready():
		release_input()

func movement_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	return Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)

# The owner predicts dash and swing from the replicated combat state so movement reacts this frame.
# The host repeats the checks; action_rejected cancels a prediction it refused.
func can_predict_action(cost: float) -> bool:
	return combat.phase == CombatController.Phase.IDLE and combat.stamina >= cost and dash_left <= 0.0 and swing_time < 0.0

func dash() -> void:
	drag_gesture.cancel()
	if not can_predict_action(CombatController.DASH_COST):
		return
	var direction: Vector3 = movement_direction()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	direction = direction.normalized()
	if multiplayer.is_server():
		request_dash(direction)
		return
	dash_direction = direction
	dash_left = CombatController.DASH_DURATION
	dash_pending = true
	request_dash.rpc_id(1, direction)

func cancel_prediction() -> void:
	if dash_pending:
		dash_left = 0.0
	if swing_pending:
		swing_time = -1.0
		body.cancel_swing()
	dash_pending = false
	swing_pending = false

func send_block(wants_block: bool) -> void:
	if wants_block:
		drag_gesture.cancel()
	if multiplayer.is_server():
		request_block(wants_block)
	else:
		request_block.rpc_id(1, wants_block)

func owns_request() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return multiplayer.is_server() and (sender == 0 or sender == get_multiplayer_authority())

@rpc("any_peer", "call_remote", "reliable")
func request_block(wants_block: bool) -> void:
	if owns_request():
		combat.set_block(wants_block)

@rpc("any_peer", "call_remote", "reliable")
func request_dash(direction: Vector3) -> void:
	if not owns_request() or not direction.is_finite() or absf(direction.y) > 0.01 or direction.length_squared() < 0.01:
		return
	if combat.begin_dash():
		dash_effect.rpc(direction.normalized())
	else:
		reject_request()

func reject_request() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		action_rejected.rpc_id(sender)

@rpc("any_peer", "call_remote", "reliable")
func action_rejected() -> void:
	if from_server():
		cancel_prediction()

@rpc("any_peer", "call_local", "reliable")
func dash_effect(direction: Vector3) -> void:
	if not from_server():
		return
	if dash_pending:
		dash_pending = false
		return
	dash_direction = direction
	dash_left = CombatController.DASH_DURATION

func from_server() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == 1 or (sender == 0 and multiplayer.is_server())

func set_camera_mode(use_third_person: bool) -> void:
	drag_gesture.cancel()
	third_person = use_third_person
	arm.spring_length = 2.6 if third_person else 0.0
	arm.position.x = 0.55 if third_person else 0.0
	body.set_first_person(not third_person)

func _physics_process(delta: float) -> void:
	rotation.y = yaw
	pivot.rotation.x = pitch
	if is_multiplayer_authority():
		var direction: Vector3 = Vector3.ZERO
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			direction = movement_direction()
		var staggered: bool = combat.phase == CombatController.Phase.STAGGERED
		if staggered:
			drag_gesture.cancel()
			direction = Vector3.ZERO
			dash_left = 0.0
			swing_time = -1.0
		if swing_time >= 0.0:
			swing_time += delta
			if swing_time >= CombatController.MELEE_WINDUP + CombatController.MELEE_ACTIVE + CombatController.MELEE_RECOVERY:
				swing_time = -1.0
				swing_pending = false
		sword_held = drag_gesture.held and not staggered and not combat.blocking
		body.drive_sword(delta, yaw, pitch, sword_held, swing_time >= 0.0, combat.blocking, staggered or dash_left > 0.0, velocity)
		if dash_left > 0 and not staggered:
			velocity.x = dash_direction.x * 16.0
			velocity.z = dash_direction.z * 16.0
		else:
			var speed: float = 3.0 if combat.blocking or swing_time >= 0.0 else 6.5
			var pull: Vector3 = body.motion.pull_velocity if not staggered else Vector3.ZERO
			velocity.x = move_toward(velocity.x, direction.x * speed + pull.x, delta * 24.0)
			velocity.z = move_toward(velocity.z, direction.z * speed + pull.z, delta * 24.0)
		dash_left = maxf(0, dash_left - delta)
		if not is_on_floor():
			velocity.y -= 20 * delta
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed(&"jump") and combat.phase != CombatController.Phase.STAGGERED:
			velocity.y = 5.5
		move_and_slide()
		if position.y < -10:
			position = spawn_position
			body.reset_motion(yaw)
		sync_position = position
		sync_velocity = velocity
		if DisplayServer.get_name() != "headless":
			update_aim_friction()
	else:
		if multiplayer.is_server():
			validate_motion()
			enforce_stagger()
		# Host-side corrections write sync_position directly, without a snapshot signal.
		if sync_position != remote_motion.snapshot_position:
			remote_motion.receive(sync_position, sync_velocity, HitResolver.now(), position)
		position = remote_motion.shown(HitResolver.now(), delta)
		velocity = sync_velocity
		var swinging: bool = combat.phase in [CombatController.Phase.WINDUP, CombatController.Phase.ACTIVE, CombatController.Phase.RECOVERY] and body.swing_elapsed >= 0.0
		body.drive_sword(delta, yaw, pitch, sword_held, swinging, combat.blocking, combat.phase in [CombatController.Phase.STAGGERED, CombatController.Phase.DASHING], sync_velocity)
	body.update_feet(delta, velocity, is_on_floor() if is_multiplayer_authority() else absf(sync_velocity.y) < 0.5)
	if multiplayer.is_server():
		history.record(HitResolver.now(), sync_position)

func update_aim_friction() -> void:
	aim_cast.force_shapecast_update()
	aim_friction = 1.0
	if aim_cast.is_colliding():
		var target: Node3D = aim_cast.get_collider(0) as Node3D
		if target != null and target.has_method("receive_hit"):
			aim_friction = 0.55

func _process(delta: float) -> void:
	feedback_left = maxf(0, feedback_left - delta)
	shake_left = maxf(0, shake_left - delta)
	flash_left = maxf(0, flash_left - delta)
	if hitstop_left > 0:
		hitstop_left -= delta
	var grounded: bool = is_on_floor() if is_multiplayer_authority() else absf(sync_velocity.y) < 0.5
	body.animate(delta, velocity, grounded, combat.phase, combat.blocking, hitstop_left > 0)
	body.set_highlight(flash_left > 0 or combat.blocking, flash_color if flash_left > 0 else Color("fff1a2"))
	if is_multiplayer_authority():
		camera.h_offset = sin(Time.get_ticks_msec() * 0.07) * shake_left * 0.12
		camera.v_offset = cos(Time.get_ticks_msec() * 0.09) * shake_left * 0.1

# A staggered owner should only slide from knockback. The host clamps horizontal drift
# around where it saw the stagger begin, allowing walking until the stagger reaches the owner.
func enforce_stagger() -> void:
	var staggered: bool = combat.phase == CombatController.Phase.STAGGERED
	if staggered and not stagger_anchored:
		stagger_anchor = sync_position
	stagger_anchored = staggered
	if not staggered:
		return
	var offset: Vector3 = sync_position - stagger_anchor
	offset.y = 0.0
	var allowed: float = STAGGER_DRIFT + 6.5 * (NetworkManager.one_way_seconds(get_multiplayer_authority()) * 2.0 + 0.05)
	if offset.length() <= allowed:
		return
	var clamped: Vector3 = stagger_anchor + offset.normalized() * allowed
	clamped.y = sync_position.y
	accepted_position = clamped
	corrections_sent += 1
	correct_position.rpc(clamped, Vector3.ZERO)

func validate_motion() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - last_motion_check
	if elapsed < 0.25:
		return
	# ponytail: generous casual movement envelope; competitive play needs server prediction.
	if not sync_position.is_finite() or not sync_velocity.is_finite() or not is_finite(yaw) or not is_finite(pitch) or sync_position.distance_to(accepted_position) > 20.0 * elapsed + 2.0:
		sync_position = accepted_position
		sync_velocity = Vector3.ZERO
		yaw = 0
		pitch = 0
		corrections_sent += 1
		correct_position.rpc(accepted_position, Vector3.ZERO)
	accepted_position = sync_position
	last_motion_check = now

func attack(ranged: bool, direction: Vector2 = Vector2.RIGHT) -> void:
	if not ranged:
		if combat.blocking or not can_predict_action(18.0):
			return
		swing_time = 0.0
		if not multiplayer.is_server():
			body.start_swing(direction)
	if multiplayer.is_server():
		request_attack(ranged, direction)
	else:
		swing_pending = not ranged
		request_attack.rpc_id(1, ranged, direction)

@rpc("any_peer", "call_remote", "reliable")
func request_attack(ranged: bool, direction: Vector2 = Vector2.RIGHT) -> void:
	if not owns_request():
		return
	if not direction.is_finite() or direction.length_squared() < 0.01 or direction.length_squared() > 4.0:
		reject_request()
		return
	# Direction is presentation only; host combat still decides timing, cost and damage.
	if combat.phase == CombatController.Phase.IDLE:
		approved_swing_direction = direction.normalized()
	var round_trip: float = NetworkManager.round_trip_seconds(get_multiplayer_authority())
	if not combat.begin_attack(ranged, HitResolver.head_start_seconds(round_trip)):
		if multiplayer.get_remote_sender_id() == 0:
			swing_time = -1.0
			body.cancel_swing()
		reject_request()

# Targets are judged where the attacker's screen showed them (HitResolver), and the attacker
# from its latest replicated position rather than the host's smoothed copy.
func resolve_attack(ranged: bool) -> void:
	if not multiplayer.is_server():
		return
	var view_time: float = HitResolver.now() - HitResolver.rewind_seconds(NetworkManager.round_trip_seconds(get_multiplayer_authority()))
	var targets: Array[CharacterBody3D] = []
	var centers: PackedVector3Array = PackedVector3Array()
	var exclude: Array[RID] = []
	var candidates: Array[Node] = get_parent().get_children()
	candidates.append_array(get_tree().get_nodes_in_group("hostile_mobs"))
	for target: Node in candidates:
		var other: CharacterBody3D = target as CharacterBody3D
		if other == null:
			continue
		exclude.append(other.get_rid())
		if other is HostileMob and (other as HostileMob).combat.health <= 0:
			continue
		if other != self and not other.is_queued_for_deletion():
			targets.append(other)
			var other_history: HitResolver.PositionHistory = other.get("history") as HitResolver.PositionHistory
			centers.append(other_history.sample(view_time, other.global_position))
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = sync_position + Vector3.UP * HitResolver.CHEST_HEIGHT
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	if ranged:
		var index: int = HitResolver.first_ray_target(space, origin, origin + forward * 40.0, centers, exclude)
		if index >= 0:
			targets[index].call("receive_hit", 15, forward, true, self)
		return
	for index: int in range(targets.size()):
		var center: Vector3 = centers[index]
		var chest: Vector3 = center + Vector3.UP * HitResolver.CHEST_HEIGHT
		if not HitResolver.in_cone(sync_position, forward, center, 2.2, deg_to_rad(35)):
			continue
		if HitResolver.wall_distance(space, origin, chest, exclude) < origin.distance_to(chest):
			continue
		# All mobs belong to peer 1, so use their own negative IDs for swing deduplication.
		var hit_id: int = -(targets[index] as HostileMob).mob_id if targets[index] is HostileMob else targets[index].get_multiplayer_authority()
		if combat.strike(hit_id):
			targets[index].call("receive_hit", 25, forward, false, self)
			if combat.phase == CombatController.Phase.STAGGERED:
				break

func receive_hit(damage: int, direction: Vector3, ranged: bool = false, attacker: CharacterBody3D = null) -> void:
	if not multiplayer.is_server():
		return
	var defender_forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var attacker_combat: CombatController = attacker.get("combat") as CombatController if attacker != null else null
	var incoming: Vector3 = -direction
	incoming.y = 0
	var old_health: int = combat.health
	var parry_grace: float = NetworkManager.one_way_seconds(get_multiplayer_authority())
	var result: int = combat.take_hit(damage, ranged, defender_forward.dot(incoming.normalized()) >= 0.34, attacker_combat, parry_grace)
	if result == CombatController.HitResult.EVADE:
		return
	hit_feedback.rpc(result, false)
	if attacker != null:
		attacker.rpc("hit_feedback", result, true)
	if result == CombatController.HitResult.HIT and combat.health < old_health:
		push.rpc(direction * 5.0 + Vector3.UP * 2)

func respawn() -> void:
	history.clear()
	accepted_position = spawn_position
	sync_position = spawn_position
	position = spawn_position
	correct_position.rpc(spawn_position, Vector3.ZERO)

@rpc("any_peer", "call_local", "reliable")
func hit_feedback(result: int, dealt: bool) -> void:
	if not from_server():
		return
	feedback = "HIT" if result == CombatController.HitResult.HIT else ("PARRY" if result == CombatController.HitResult.PARRY else "BLOCK")
	feedback_left = 0.6
	hitstop_left = 0.06
	if not dealt:
		flash_left = 0.12
		flash_color = Color("ff5656") if result == CombatController.HitResult.HIT else Color("fff1a2")
	if is_multiplayer_authority():
		shake_left = 0.14 if dealt else 0.3

func interrupt() -> void:
	drag_gesture.cancel()
	body.cancel_swing()
	sword_held = false
	dash_left = 0.0
	swing_time = -1.0
	dash_pending = false
	swing_pending = false

@rpc("any_peer", "call_local", "reliable")
func correct_position(location: Vector3, impulse: Vector3) -> void:
	if not from_server():
		return
	interrupt()
	body.reset_motion(yaw)
	if location.distance_to(sync_position) > 1.0:
		history.clear()  # a teleport must not be interpolated by rewound hits
	position = location
	sync_position = location
	remote_motion.reset(location, HitResolver.now())
	if is_multiplayer_authority():
		velocity = impulse

# Knockback reaches the owner as velocity only. Teleporting the owner to the host's last snapshot
# would undo up to a round trip of its own movement on every hit.
@rpc("any_peer", "call_local", "reliable")
func push(impulse: Vector3) -> void:
	if not from_server():
		return
	interrupt()
	if is_multiplayer_authority():
		velocity = impulse

@rpc("any_peer", "call_local", "reliable")
func attack_effect(ranged: bool, direction: Vector2 = Vector2.RIGHT) -> void:
	if not from_server():
		return
	if not ranged:
		if not swing_pending:
			body.start_swing(direction)
			if is_multiplayer_authority():
				swing_time = 0.0
		swing_pending = false
	body.play_attack(ranged)
	if not ranged or DisplayServer.get_name() == "headless":
		return
	var beam: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 40)
	beam.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("77f9ec")
	beam.material_override = material
	get_tree().current_scene.add_child(beam)
	beam.global_transform = pivot.global_transform
	beam.translate_object_local(Vector3(0, 0, -20))
	get_tree().create_timer(0.07).timeout.connect(beam.queue_free)
