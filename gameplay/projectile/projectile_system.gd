extends Node3D
## Host-authoritative swept bolts (Q). Registered as the Projectiles autoload, so its RPC path is
## identical on every peer and no player or world scene needs a hook. Only peer 1 sweeps and decides
## hits. Every peer draws the same closed-form flight from reliable spawn/reflect/end events, aged by
## its measured one-way latency, so nothing is replicated per tick. See docs/projectiles.md.

signal confirmed(seq: int)
signal refused(seq: int)

const SPEED: float = 24.0
const GRAVITY: Vector3 = Vector3(0, -4.0, 0)
const RADIUS: float = 0.15
const DAMAGE: int = 20
const COST: float = 12.0
const COOLDOWN: float = 0.6
const LIFETIME: float = 2.0
const MAX_IN_FLIGHT: int = 3
# The host flies a client's bolt ahead by that client's one-way latency, so it matches the shooter's view.
const MAX_ADVANCE: float = 0.1
# The host's view of a client lags its owner; muzzle claims farther than this from the shooter are refused.
const ORIGIN_SLACK: float = 2.5
const AIM_RANGE: float = 60.0
const KILL_HEIGHT: float = -20.0

class Bolt:
	var id: int = 0
	var owner_peer: int = 0
	var origin: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var age: float = 0.0
	var passed: Array[RID] = []
	var visual: Node3D = null
	var stopped: bool = false

var bolts: Dictionary[int, Bolt] = {}
var predicted: Dictionary[int, Bolt] = {}
var next_id: int = 1
var next_seq: int = 0
var ready_at_msec: int = 0
var smoke_failed: bool = false
var sphere: SphereShape3D = SphereShape3D.new()
var bolt_mesh: BoxMesh = BoxMesh.new()
var bolt_material: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	sphere.radius = RADIUS
	bolt_mesh.size = Vector3(0.07, 0.07, 0.6)
	bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_material.albedo_color = Color("ffc861")
	multiplayer.peer_disconnected.connect(drop_owner)
	multiplayer.server_disconnected.connect(clear)
	multiplayer.connected_to_server.connect(clear)
	if "--projectile-smoke" in OS.get_cmdline_user_args():
		smoke_client()

static func flight_position(bolt: Bolt, time: float) -> Vector3:
	return bolt.origin + bolt.velocity * time + GRAVITY * (0.5 * time * time)

static func flight_velocity(bolt: Bolt, time: float) -> Vector3:
	return bolt.velocity + GRAVITY * time

func players_root() -> Node:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null(^"Players") if scene != null else null

func player(peer: int) -> CharacterBody3D:
	var root: Node = players_root()
	return root.get_node_or_null(str(peer)) as CharacterBody3D if root != null else null

func player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	var root: Node = players_root()
	if root != null:
		for child: Node in root.get_children():
			var body: CharacterBody3D = child as CharacterBody3D
			if body != null:
				rids.append(body.get_rid())
	return rids

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bolt") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var shooter: CharacterBody3D = player(multiplayer.get_unique_id())
		if shooter != null:
			fire(shooter)

# The owner checks the replicated combat state, then releases the bolt this frame.
func fire(shooter: CharacterBody3D) -> void:
	var combat: CombatController = shooter.get("combat") as CombatController
	if combat.blocking or Time.get_ticks_msec() < ready_at_msec or not bool(shooter.call(&"can_predict_action", COST)):
		return
	ready_at_msec = Time.get_ticks_msec() + int(COOLDOWN * 1000.0)
	var origin: Vector3 = (shooter.get("pivot") as Node3D).global_position
	launch(shooter, origin, aim_direction(shooter, origin))

# In third person the camera sits beside the body, so a bolt sent along the camera's facing from the
# chest would pass beside the reticle. Aim from the chest at whatever the reticle covers instead.
func aim_direction(shooter: CharacterBody3D, origin: Vector3) -> Vector3:
	var camera: Camera3D = shooter.get("camera") as Camera3D
	var forward: Vector3 = -camera.global_basis.z
	# Start the reticle ray level with the body, so nothing between camera and player is aimed at.
	var start: Vector3 = camera.global_position + forward * maxf(0.0, (origin - camera.global_position).dot(forward))
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, start + forward * AIM_RANGE)
	query.exclude = [shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] as Vector3 if not hit.is_empty() else start + forward * AIM_RANGE
	var direction: Vector3 = target - origin
	if direction.length_squared() < 1.0 or direction.dot(forward) <= 0.0:
		return forward
	return direction.normalized()

func launch(shooter: CharacterBody3D, origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server():
		handle_fire(multiplayer.get_unique_id(), 0, origin, direction)
		return
	next_seq += 1
	var bolt: Bolt = Bolt.new()
	bolt.owner_peer = multiplayer.get_unique_id()
	bolt.origin = origin
	bolt.velocity = direction * SPEED
	add_visual(bolt)
	predicted[next_seq] = bolt
	animate_shot(shooter)
	request_fire.rpc_id(1, next_seq, origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func request_fire(seq: int, origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server():
		handle_fire(multiplayer.get_remote_sender_id(), seq, origin, direction)

# Host validation of a fire request; returns whether a bolt was spawned. Direction is not checked
# against the replicated yaw/pitch: the owner already controls its aim, so that would only add lag misses.
func handle_fire(sender: int, seq: int, origin: Vector3, direction: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	var shooter: CharacterBody3D = player(sender)
	if shooter == null or shooter.get_multiplayer_authority() != sender:
		return false
	var chest: Vector3 = (shooter.get("sync_position") as Vector3) + Vector3.UP * HitResolver.CHEST_HEIGHT
	var combat: CombatController = shooter.get("combat") as CombatController
	var valid: bool = origin.is_finite() and direction.is_finite() and direction.length_squared() >= 0.25 and direction.length_squared() <= 2.25 and origin.distance_to(chest) <= ORIGIN_SLACK
	if not valid or in_flight(sender) >= MAX_IN_FLIGHT or not combat.begin_shot(COST, COOLDOWN):
		if sender in multiplayer.get_peers():
			fire_rejected.rpc_id(sender, seq)
		return false
	# A claimed muzzle on the far side of a wall from the shooter fires from the shooter's chest instead.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(chest, origin)
	query.exclude = player_rids()
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		origin = chest
	spawn(sender, seq, origin, direction.normalized() * SPEED)
	return true

func in_flight(peer: int) -> int:
	var count: int = 0
	for bolt: Bolt in bolts.values():
		if bolt.owner_peer == peer:
			count += 1
	return count

func spawn(owner_peer: int, seq: int, origin: Vector3, velocity: Vector3) -> void:
	var bolt: Bolt = Bolt.new()
	bolt.id = next_id
	next_id += 1
	bolt.owner_peer = owner_peer
	bolt.origin = origin
	bolt.velocity = velocity
	bolts[bolt.id] = bolt
	var advance: float = clampf(NetworkManager.one_way_seconds(owner_peer), 0.0, MAX_ADVANCE)
	spawned.rpc(bolt.id, owner_peer, seq, origin, velocity, advance)
	add_visual(bolt)
	animate_shot(player(owner_peer))
	# A bolt released inside a target's capsule hits it; cast_motion ignores shapes it starts inside.
	var touching: Dictionary = contact_at(bolt, origin)
	if not touching.is_empty():
		resolve(bolt, touching)
	elif advance > 0.0:
		fly(bolt, advance)

func _physics_process(delta: float) -> void:
	for id: int in bolts.keys():
		if not bolts.has(id):
			continue
		var bolt: Bolt = bolts[id]
		if multiplayer.is_server():
			fly(bolt, delta)
		else:
			coast(bolt, delta)
		place_visual(bolt)
	for seq: int in predicted.keys():
		var bolt: Bolt = predicted[seq]
		coast(bolt, delta)
		place_visual(bolt)

# Host: sweep the bolt's sphere along this tick's segment of its flight.
func fly(bolt: Bolt, delta: float) -> void:
	var from: Vector3 = flight_position(bolt, bolt.age)
	bolt.age += delta
	var to: Vector3 = flight_position(bolt, bolt.age)
	var query: PhysicsShapeQueryParameters3D = shape_query(bolt, from)
	query.motion = to - from
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var contact: Dictionary = contact_at(bolt, from + query.motion * fractions[1]) if fractions[1] < 1.0 else {}
	if not contact.is_empty():
		resolve(bolt, contact)
	elif bolt.age >= LIFETIME or to.y < KILL_HEIGHT:
		finish(bolt, to)

# Clients only draw: the visual stops at walls, and the host's end event removes it.
func coast(bolt: Bolt, delta: float) -> void:
	if bolt.stopped:
		return
	var from: Vector3 = flight_position(bolt, bolt.age)
	bolt.age += delta
	if bolt.age > LIFETIME + 1.0:
		drop_visual(bolt)
		bolts.erase(bolt.id)
		predicted.erase(predicted.find_key(bolt))
		return
	if bolt.visual == null:
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, flight_position(bolt, bolt.age))
	query.exclude = player_rids()
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		bolt.stopped = true
		bolt.visual.hide()

func shape_query(bolt: Bolt, at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	var exclude: Array[RID] = bolt.passed.duplicate()
	var shooter: CharacterBody3D = player(bolt.owner_peer)
	if shooter != null:
		exclude.append(shooter.get_rid())
	query.exclude = exclude
	return query

func contact_at(bolt: Bolt, at: Vector3) -> Dictionary:
	var contact: Dictionary = get_world_3d().direct_space_state.get_rest_info(shape_query(bolt, at))
	if not contact.is_empty():
		contact["at"] = at
	return contact

func resolve(bolt: Bolt, contact: Dictionary) -> void:
	var target: CharacterBody3D = instance_from_id(int(contact["collider_id"])) as CharacterBody3D
	if target == null or not target.has_method(&"receive_hit"):
		finish(bolt, contact["point"] as Vector3)
		return
	var combat: CombatController = target.get("combat") as CombatController
	var direction: Vector3 = flight_velocity(bolt, bolt.age).normalized()
	if combat.evades_ranged():
		bolt.passed.append(target.get_rid())
		return
	var facing: bool = CombatController.guards(float(target.get("yaw")), direction)
	if combat.parries(facing, NetworkManager.one_way_seconds(target.get_multiplayer_authority())):
		reflect(bolt, target)
		return
	# The existing hit path applies block, guard break, poise, knockback and feedback.
	target.call(&"receive_hit", DAMAGE, direction, true, player(bolt.owner_peer))
	finish(bolt, contact["at"] as Vector3)

# A parried bolt flies back along the defender's aim and now belongs to the defender.
func reflect(bolt: Bolt, defender: CharacterBody3D) -> void:
	var shooter: CharacterBody3D = player(bolt.owner_peer)
	defender.rpc(&"hit_feedback", CombatController.HitResult.PARRY, false)
	if shooter != null:
		shooter.rpc(&"hit_feedback", CombatController.HitResult.PARRY, true)
	var aim: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, float(defender.get("pitch"))).rotated(Vector3.UP, float(defender.get("yaw")))
	bolt.owner_peer = defender.get_multiplayer_authority()
	bolt.origin = defender.global_position + Vector3.UP * HitResolver.CHEST_HEIGHT + aim * 0.6
	bolt.velocity = aim * SPEED
	bolt.age = 0.0
	bolt.passed.clear()
	reflected.rpc(bolt.id, bolt.owner_peer, bolt.origin, bolt.velocity)

func finish(bolt: Bolt, point: Vector3) -> void:
	bolts.erase(bolt.id)
	drop_visual(bolt)
	flash(point)
	ended.rpc(bolt.id, point)

@rpc("authority", "call_remote", "reliable")
func spawned(id: int, owner_peer: int, seq: int, origin: Vector3, velocity: Vector3, advance: float) -> void:
	var bolt: Bolt = null
	if owner_peer == multiplayer.get_unique_id() and predicted.has(seq):
		bolt = predicted[seq]
		predicted.erase(seq)
		confirmed.emit(seq)
	else:
		bolt = Bolt.new()
		add_visual(bolt)
		animate_shot(player(owner_peer))
	bolt.id = id
	bolt.owner_peer = owner_peer
	bolt.origin = origin
	bolt.velocity = velocity
	bolt.age = advance + NetworkManager.one_way_seconds(1)
	bolts[id] = bolt

@rpc("authority", "call_remote", "reliable")
func reflected(id: int, owner_peer: int, origin: Vector3, velocity: Vector3) -> void:
	if not bolts.has(id):
		return
	var bolt: Bolt = bolts[id]
	bolt.owner_peer = owner_peer
	bolt.origin = origin
	bolt.velocity = velocity
	bolt.age = NetworkManager.one_way_seconds(1)
	bolt.stopped = false
	if bolt.visual != null:
		bolt.visual.show()

@rpc("authority", "call_remote", "reliable")
func ended(id: int, point: Vector3) -> void:
	if bolts.has(id):
		drop_visual(bolts[id])
		bolts.erase(id)
	flash(point)

@rpc("authority", "call_remote", "reliable")
func fire_rejected(seq: int) -> void:
	if predicted.has(seq):
		drop_visual(predicted[seq])
		predicted.erase(seq)
	refused.emit(seq)

func drop_owner(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: int in bolts.keys():
		var bolt: Bolt = bolts[id]
		if bolt.owner_peer == peer:
			finish(bolt, flight_position(bolt, bolt.age))

func clear() -> void:
	for bolt: Bolt in bolts.values():
		drop_visual(bolt)
	for bolt: Bolt in predicted.values():
		drop_visual(bolt)
	bolts.clear()
	predicted.clear()

func animate_shot(shooter: CharacterBody3D) -> void:
	var visual: Node = shooter.get("body") as Node if shooter != null else null
	if visual != null and visual.has_method(&"play_attack"):
		visual.call(&"play_attack", true)

func add_visual(bolt: Bolt) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = bolt_mesh
	mesh.material_override = bolt_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	bolt.visual = mesh
	place_visual(bolt)

func place_visual(bolt: Bolt) -> void:
	if bolt.visual == null:
		return
	var heading: Vector3 = flight_velocity(bolt, bolt.age).normalized()
	var up: Vector3 = Vector3.UP if absf(heading.y) < 0.99 else Vector3.BACK
	bolt.visual.global_transform = Transform3D(Basis.looking_at(heading, up), flight_position(bolt, bolt.age))

func drop_visual(bolt: Bolt) -> void:
	if bolt.visual != null:
		bolt.visual.queue_free()
		bolt.visual = null

func flash(point: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var spark: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	spark.mesh = mesh
	spark.material_override = bolt_material
	add_child(spark)
	spark.global_position = point
	get_tree().create_timer(0.1).timeout.connect(spark.queue_free)

# Two-process check over real ENet: refusals, prediction confirmation, cooldown and a host-decided hit.
func smoke_client() -> void:
	var refusals: Array[int] = []
	var confirmations: Array[int] = []
	refused.connect(func(seq: int) -> void: refusals.append(seq))
	confirmed.connect(func(seq: int) -> void: confirmations.append(seq))
	await get_tree().create_timer(2.0).timeout
	var local: CharacterBody3D = player(multiplayer.get_unique_id())
	var host: CharacterBody3D = player(1)
	if not smoke_check(local != null and host != null and local != host, "Both players must replicate"):
		return
	var host_combat: CombatController = host.get("combat") as CombatController
	# The client owns its movement: stand 4 m in front of the host with a clear line.
	local.position = host.position + Vector3(0, 0, -4)
	local.velocity = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout
	var origin: Vector3 = local.position + Vector3.UP * HitResolver.CHEST_HEIGHT
	var toward: Vector3 = (host.position - local.position).normalized()
	request_fire.rpc_id(1, 900, Vector3(NAN, 0, 0), toward)
	request_fire.rpc_id(1, 901, origin, Vector3.ZERO)
	request_fire.rpc_id(1, 902, origin + Vector3(0, 0, -30), toward)
	await get_tree().create_timer(0.4).timeout
	smoke_check(refusals.has(900) and refusals.has(901) and refusals.has(902), "Invalid bolts must be refused")
	smoke_check(host_combat.health == CombatController.MAX_HEALTH, "Refused bolts must not damage")
	launch(local, origin, toward)
	request_fire.rpc_id(1, 903, origin, toward)
	await get_tree().create_timer(1.0).timeout
	smoke_check(confirmations.has(1), "The owner's predicted bolt must be confirmed")
	smoke_check(refusals.has(903), "The shared cooldown must refuse a second bolt")
	smoke_check(host_combat.health == CombatController.MAX_HEALTH - DAMAGE, "Exactly one host-confirmed bolt must hit (is cover parked between the spawns?)")
	if smoke_check(bolts.is_empty() and predicted.is_empty(), "Finished bolts must be removed on the client") and not smoke_failed:
		print("PROJECTILE_SMOKE_OK: refusal, prediction confirm, cooldown, host-decided hit, cleanup")
		get_tree().quit()

func smoke_check(condition: bool, message: String) -> bool:
	if not condition:
		smoke_failed = true
		printerr("PROJECTILE_SMOKE_FAIL: " + message)
		get_tree().quit(1)
	return condition
