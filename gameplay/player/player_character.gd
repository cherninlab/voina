extends CharacterBody3D

var sync_position: Vector3 = Vector3.ZERO
var sync_velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var health: int = 100
var spawn_position: Vector3 = Vector3.ZERO
var camera: Camera3D = Camera3D.new()
var pivot: Node3D = Node3D.new()
var arm: SpringArm3D = SpringArm3D.new()
var body: MeshInstance3D = MeshInstance3D.new()
var nose: MeshInstance3D = MeshInstance3D.new()
var third_person: bool = true
var last_attack: float = -1.0
var visual_attack_until: float = 0.0
var accepted_position: Vector3 = Vector3.ZERO
var last_motion_check: float = 0.0

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
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	body.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("53d7ef") if get_multiplayer_authority() == 1 else Color("ff816c")
	body.material_override = material
	add_child(body)
	var nose_mesh: BoxMesh = BoxMesh.new()
	nose_mesh.size = Vector3(0.18, 0.18, 0.4)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.5, -0.5)
	body.add_child(nose)
	pivot.position.y = 0.65
	add_child(pivot)
	arm.spring_length = 2.6
	arm.margin = 0.2
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.2
	arm.shape = sphere
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	arm.add_child(camera)
	camera.position.x = 0.55
	camera.current = is_multiplayer_authority() and not NetworkManager.dedicated
	add_sync("MovementSync", get_multiplayer_authority(), [^":sync_position", ^":sync_velocity", ^":yaw", ^":pitch"])
	add_sync("HealthSync", 1, [^":health"])
	if is_multiplayer_authority() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func add_sync(sync_name: String, authority: int, properties: Array[NodePath]) -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = sync_name
	synchronizer.set_multiplayer_authority(authority)
	synchronizer.replication_interval = 1.0 / 30.0
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property: NodePath in properties:
		config.add_property(property)
		config.property_set_replication_mode(property, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = config
	add_child(synchronizer)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		match key.physical_keycode:
			KEY_V: set_camera_mode(not third_person)
			KEY_R: yaw += PI
			KEY_F: attack(false)
			KEY_E: attack(true)
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				attack(false)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		yaw -= motion.screen_relative.x * 0.0024
		pitch = clampf(pitch - motion.screen_relative.y * 0.0024, -1.39, 1.39)
	if event is InputEventMagnifyGesture:
		var gesture: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if gesture.factor < 0.85:
			set_camera_mode(true)
		elif gesture.factor > 1.15:
			set_camera_mode(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_camera_mode(use_third_person: bool) -> void:
	third_person = use_third_person
	arm.spring_length = 2.6 if third_person else 0.0
	camera.position.x = 0.55 if third_person else 0.0
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if third_person else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	nose.cast_shadow = body.cast_shadow

func _physics_process(delta: float) -> void:
	rotation.y = yaw
	pivot.rotation.x = pitch
	if is_multiplayer_authority():
		var direction: Vector3 = Vector3.ZERO
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			direction = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		direction = direction.normalized().rotated(Vector3.UP, yaw)
		velocity.x = move_toward(velocity.x, direction.x * 6.5, delta * 32)
		velocity.z = move_toward(velocity.z, direction.z * 6.5, delta * 32)
		if not is_on_floor():
			velocity.y -= 20 * delta
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_C):
			velocity.y = 5.5
		move_and_slide()
		sync_position = position
		sync_velocity = velocity
		if position.y < -10:
			position = spawn_position
	else:
		if multiplayer.is_server():
			validate_motion()
		position = position.lerp(sync_position, 1.0 - exp(-20.0 * delta))
		velocity = sync_velocity
	body.rotation.z = 0.18 if Time.get_ticks_msec() / 1000.0 < visual_attack_until else 0.0

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
		correct_position.rpc(accepted_position, Vector3.ZERO)
	accepted_position = sync_position
	last_motion_check = now

func attack(ranged: bool) -> void:
	visual_attack_until = Time.get_ticks_msec() / 1000.0 + 0.2
	if multiplayer.is_server():
		request_attack(ranged)
	else:
		request_attack.rpc_id(1, ranged)

@rpc("any_peer", "call_remote", "reliable")
func request_attack(ranged: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_attack < 0.5 or health <= 0:
		return
	last_attack = now
	attack_effect.rpc(ranged)
	if not ranged:
		await get_tree().create_timer(0.15).timeout
		if not is_inside_tree():
			return
	var origin: Vector3 = global_position + Vector3.UP * 0.65
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	if ranged:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + forward * 40.0)
		query.exclude = [get_rid()]
		var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		var target: CharacterBody3D = result.get("collider") as CharacterBody3D
		if target != null and target.has_method("receive_hit"):
			target.call("receive_hit", 15, forward)
	else:
		for target: Node in get_parent().get_children():
			if target == self:
				continue
			var other: CharacterBody3D = target as CharacterBody3D
			var offset: Vector3 = other.global_position - global_position
			if offset.length() <= 2.2 and forward.dot(offset.normalized()) >= cos(deg_to_rad(35)):
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, other.global_position + Vector3.UP * 0.65)
				query.exclude = [get_rid()]
				var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
				if result.get("collider") == other:
					other.call("receive_hit", 25, forward)

func receive_hit(damage: int, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	health = maxi(0, health - damage)
	if health == 0:
		health = 100
		accepted_position = spawn_position
		sync_position = spawn_position
		position = spawn_position
		correct_position.rpc(spawn_position, Vector3.ZERO)
	else:
		correct_position.rpc(sync_position, direction * 5.0 + Vector3.UP * 2)

@rpc("any_peer", "call_local", "reliable")
func correct_position(location: Vector3, impulse: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and not (sender == 0 and multiplayer.is_server()):
		return
	position = location
	sync_position = location
	if is_multiplayer_authority():
		velocity = impulse

@rpc("any_peer", "call_local", "reliable")
func attack_effect(ranged: bool) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and not (sender == 0 and multiplayer.is_server()):
		return
	visual_attack_until = Time.get_ticks_msec() / 1000.0 + 0.3
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
