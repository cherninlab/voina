class_name CharacterVisual
extends Node3D

@export var model_scene: PackedScene
@export var animation_library: AnimationLibrary

var meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var ik: SwordIK
var sword: Node3D = Node3D.new()
var sword_meshes: Array[MeshInstance3D] = []
var highlight: StandardMaterial3D = StandardMaterial3D.new()
var playback: AnimationPlayer = AnimationPlayer.new()
var clip: StringName = &""

var grip_right: float = 1.0
var grip_left: float = 0.0
var swing_elapsed: float = -1.0
var swing_direction: Vector2 = Vector2.RIGHT
var motion: HeavySwordMotion = HeavySwordMotion.new()
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var feet: Array[Vector3] = []
var foot_normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
var ground_level: float = -0.9 # world height of the floor under the planted feet
var step_from: Vector3 = Vector3.ZERO
var step_to: Vector3 = Vector3.ZERO
var stepping: int = -1
var step_time: float = 0.0
var step_duration: float = 0.2
var next_foot: int = 0
var gait_bob: float = 0.0
var gait_crouch: float = 0.12 # hips stay dropped for a half-bent stance and lower further at speed
var grounded_pose: bool = true
const BLADE_TIP: Vector3 = Vector3(0, 0, -1.65)

func _ready() -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
	model.name = "Model"
	# Pack faces +Z; gameplay faces -Z, with the capsule origin 0.9 m above ground.
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "", true, false):
		if node is MeshInstance3D:
			meshes.append(node as MeshInstance3D)
		elif node is Skeleton3D:
			skeleton = node as Skeleton3D
	# Keep imported clips available for inspection; runtime posing is procedural IK.
	if animation_library != null:
		playback.name = "Playback"
		add_child(playback)
		playback.add_animation_library(&"", animation_library)
		select_clip(&"Idle")
		playback.advance(0.0)
		playback.pause()
	build_sword()
	ground_level = global_position.y - 0.9
	motion.reset(global_rotation.y, global_position, ground_level)
	update_pose(0.0, Vector3.ZERO, false, false)
	if skeleton != null:
		ik = SwordIK.new()
		skeleton.add_child(ik)
		ik.configure(self)
	highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func build_sword() -> void:
	sword.name = "Longsword"
	add_child(sword)
	var steel: StandardMaterial3D = material(Color("c1d2df"), 0.8, 0.25)
	var gold: StandardMaterial3D = material(Color("a88b51"), 0.75, 0.32)
	var leather: StandardMaterial3D = material(Color("302329"), 0.0, 0.85)
	# A tapered, diamond-section blade, generated locally with no external assets.
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base: Array[Vector3] = [Vector3(-0.055, 0, -0.12), Vector3(0, 0.018, -0.12), Vector3(0.055, 0, -0.12), Vector3(0, -0.018, -0.12)]
	var near_tip: Array[Vector3] = [Vector3(-0.035, 0, -1.4), Vector3(0, 0.012, -1.4), Vector3(0.035, 0, -1.4), Vector3(0, -0.012, -1.4)]
	for i: int in range(4):
		var next: int = (i + 1) % 4
		for vertex: Vector3 in [base[i], near_tip[i], base[next], base[next], near_tip[i], near_tip[next], near_tip[i], BLADE_TIP, near_tip[next]]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	add_sword_mesh(surface.commit(), Vector3.ZERO, steel)
	var guard: BoxMesh = BoxMesh.new()
	guard.size = Vector3(0.36, 0.055, 0.065)
	add_sword_mesh(guard, Vector3(0, 0, -0.10), gold)
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.025
	handle.bottom_radius = 0.028
	handle.height = 0.37
	var grip: MeshInstance3D = add_sword_mesh(handle, Vector3(0, 0, 0.11), leather)
	grip.rotation.x = PI / 2.0
	var pommel: SphereMesh = SphereMesh.new()
	pommel.radius = 0.045
	pommel.height = 0.09
	add_sword_mesh(pommel, Vector3(0, 0, 0.31), gold)

func material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result

func add_sword_mesh(mesh: Mesh, location: Vector3, surface_material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = location
	instance.material_override = surface_material
	sword.add_child(instance)
	sword_meshes.append(instance)
	return instance

func start_swing(direction: Vector2) -> void:
	swing_direction = direction.normalized()
	swing_elapsed = 0.0
	motion.strike(swing_direction)

func cancel_swing() -> void:
	swing_elapsed = -1.0

func reset_motion(view_yaw: float) -> void:
	motion.reset(view_yaw, global_position, ground_level)
	feet.clear()
	stepping = -1
	grip_right = 1.0
	grip_left = 0.0

func drive_sword(delta: float, view_yaw: float, view_pitch: float, held: bool, attacking: bool, blocking: bool, interrupted: bool, velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_finite(view_yaw) or not is_finite(view_pitch):
		return
	camera_yaw = view_yaw
	camera_pitch = view_pitch
	if interrupted:
		cancel_swing()
	# A staggered or dashing body lets go of the drag; the blade keeps falling under its own weight.
	var free: bool = not interrupted
	motion.step(delta, view_yaw, view_pitch, held and free, attacking and free, blocking and free, global_position, ground_level, velocity)
	# Both hands hold the hilt while dragging or whenever the blade stands ahead; a blade left off
	# to one side is held by the hand on that side.
	var side: float = motion.bearing()
	var both: bool = motion.raised > 0.5 or absf(side) < 1.0
	grip_right = move_toward(grip_right, 1.0 if both or side <= 0.0 else 0.0, delta * 6.0)
	grip_left = move_toward(grip_left, 1.0 if both or side > 0.0 else 0.0, delta * 6.0)

func update_pose(delta: float, _world_velocity: Vector3, _blocking: bool, staggered: bool) -> void:
	if staggered:
		cancel_swing()
	if swing_elapsed >= 0.0:
		swing_elapsed += delta
		if swing_elapsed >= CombatController.MELEE_WINDUP + CombatController.MELEE_ACTIVE + CombatController.MELEE_RECOVERY:
			cancel_swing()
	# The body turns to face the blade; the parent carries the camera yaw, so counter-rotate here.
	rotation.y = angle_difference(camera_yaw, motion.body_yaw)
	var direction: Vector3 = motion.blade_direction()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD.rotated(Vector3.UP, motion.body_yaw)
	sword.global_transform = Transform3D(Basis.looking_at(direction, up), motion.hilt)

func foot_home(index: int, travel: Vector3 = Vector3.ZERO) -> Vector3:
	var stance: Vector3 = Vector3(-0.16 if index == 0 else 0.16, -0.81, 0.04)
	return global_position + stance.rotated(Vector3.UP, motion.body_yaw) + travel

func ground_foot(location: Vector3, index: int) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(location + Vector3.UP * 0.6, location + Vector3.DOWN * 1.1)
	if get_parent() is CollisionObject3D:
		query.exclude = [(get_parent() as CollisionObject3D).get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		foot_normals[index] = hit["normal"] as Vector3
		return (hit["position"] as Vector3) + Vector3.UP * 0.085
	foot_normals[index] = Vector3.UP
	return location

func update_feet(delta: float, velocity: Vector3, grounded: bool) -> void:
	var landed: bool = grounded and not grounded_pose
	grounded_pose = grounded
	if feet.is_empty() or landed:
		feet = [ground_foot(foot_home(0), 0), ground_foot(foot_home(1), 1)]
		stepping = -1
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z)
	var speed: float = horizontal.length()
	var pace: float = clampf(speed / 6.5, 0.0, 1.0)
	# Always on half-bent knees, a little lower at speed.
	gait_crouch = move_toward(gait_crouch, 0.12 + 0.06 * pace, delta * 0.6)
	if not grounded:
		stepping = -1
		for index: int in range(2):
			feet[index] = foot_home(index) + Vector3.UP * 0.18
		return
	var travel: Vector3 = horizontal / speed if speed > 0.2 else Vector3.ZERO
	if stepping < 0:
		# A planted foot steps once it trails the hips by half a stride, or drifts sideways under a turn.
		var duration: float = lerpf(0.26, 0.12, pace)
		var ahead: float = clampf(speed * duration * 0.5 + 0.05, 0.05, 0.4)
		for candidate: int in [next_foot, 1 - next_foot]:
			var offset: Vector3 = feet[candidate] - foot_home(candidate)
			offset.y = 0.0
			var behind: float = -offset.dot(travel)
			var drift: float = (offset - travel * offset.dot(travel)).length()
			if behind >= ahead or drift > 0.24:
				stepping = candidate
				step_from = feet[candidate]
				# Land where the hips will be when the step finishes, plus half a stride ahead.
				step_to = ground_foot(foot_home(candidate, travel * (speed * duration + ahead)), candidate)
				step_duration = duration
				step_time = 0.0
				next_foot = 1 - candidate
				break
	if stepping >= 0:
		step_time = minf(1.0, step_time + delta / step_duration)
		feet[stepping] = step_from.lerp(step_to, smoothstep(0.0, 1.0, step_time)) + Vector3.UP * sin(step_time * PI) * 0.15
		ground_level = feet[1 - stepping].y - 0.085
		if step_time >= 1.0:
			stepping = -1
	else:
		ground_level = minf(feet[0].y, feet[1].y) - 0.085
	gait_bob = sin(step_time * PI) * 0.025 if stepping >= 0 else 0.0

func set_first_person(enabled: bool) -> void:
	for mesh: MeshInstance3D in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The sword remains visible in first person, including its forward attack arc.

func set_highlight(enabled: bool, color: Color) -> void:
	highlight.albedo_color = Color(color, 0.35)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = highlight if enabled else null

func select_clip(next: StringName, speed: float = 1.0) -> void:
	if clip == next:
		return
	clip = next
	playback.play(clip, 0.08, speed)

func play_attack(_ranged: bool) -> void:
	# IK owns the full body during gameplay; no canned melee/locomotion clip is started.
	pass

func animate(delta: float, velocity: Vector3, _grounded: bool, phase: int, blocking: bool, frozen: bool) -> void:
	update_pose(0.0 if frozen else delta, velocity, blocking, phase == CombatController.Phase.STAGGERED)
