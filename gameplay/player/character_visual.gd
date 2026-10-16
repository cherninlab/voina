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
var action_left: float = 0.0

var support_hand: float = 0.0
var swing_elapsed: float = -1.0
var swing_direction: Vector2 = Vector2.RIGHT
var trail_direction: Vector3 = Vector3.BACK
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
	# The Standard pack has no clips. Lower the T-pose arms into a static neutral pose.
	if animation_library != null:
		playback.name = "Playback"
		add_child(playback)
		playback.add_animation_library(&"", animation_library)
		select_clip(&"Idle")
		playback.advance(0.0)
	build_sword()
	trail_direction = global_basis * Vector3.BACK
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

func cancel_swing() -> void:
	swing_elapsed = -1.0

func update_pose(delta: float, world_velocity: Vector3, blocking: bool, staggered: bool) -> void:
	if staggered:
		cancel_swing()
	if swing_elapsed >= 0.0:
		swing_elapsed += delta
		if swing_elapsed >= CombatController.MELEE_WINDUP + CombatController.MELEE_ACTIVE + CombatController.MELEE_RECOVERY:
			cancel_swing()
	# World-space lag lets the blade follow turns and trail opposite travel.
	var horizontal: Vector3 = Vector3(world_velocity.x, 0, world_velocity.z)
	var wanted_trail: Vector3 = (global_basis * Vector3.BACK - horizontal * 0.12).normalized()
	trail_direction = trail_direction.lerp(wanted_trail, 1.0 - exp(-7.0 * delta)).normalized()
	var local_trail: Vector3 = global_basis.inverse() * trail_direction
	var idle_position: Vector3 = Vector3(0.32, 0.17, 0.05)
	var idle_direction: Vector3 = Vector3(local_trail.x * 0.75 + 0.12, -1.02, maxf(0.5, local_trail.z) * 1.28).normalized()
	# Keep the tip at floor height in the flat arena without scaling the weapon.
	idle_direction.y = -1.02 / 1.65
	var flat: Vector2 = Vector2(idle_direction.x, idle_direction.z).normalized() * sqrt(1.0 - idle_direction.y * idle_direction.y)
	idle_direction.x = flat.x
	idle_direction.z = flat.y
	var pose_position: Vector3 = idle_position
	var pose_direction: Vector3 = idle_direction
	var support: float = 0.0
	if swing_elapsed >= 0.0:
		var active_start: float = CombatController.MELEE_WINDUP
		var active_end: float = active_start + CombatController.MELEE_ACTIVE
		var progress: float = clampf((swing_elapsed - active_start) / CombatController.MELEE_ACTIVE, 0.0, 1.0)
		var angle: float = lerpf(-1.25, 1.25, progress)
		var cut: Vector3 = Vector3(swing_direction.x * sin(angle), -swing_direction.y * sin(angle), -cos(angle))
		var grip: Vector3 = Vector3(0.06 + swing_direction.x * sin(angle) * 0.16, 0.43 - swing_direction.y * sin(angle) * 0.1, -0.27)
		var weight: float = smoothstep(0.0, active_start, swing_elapsed)
		if swing_elapsed > active_end:
			weight = 1.0 - smoothstep(active_end, active_end + CombatController.MELEE_RECOVERY, swing_elapsed)
		pose_position = idle_position.lerp(grip, weight)
		pose_direction = idle_direction.slerp(cut.normalized(), weight)
		support = weight
	elif blocking:
		pose_position = Vector3(0.08, 0.35, -0.30)
		pose_direction = Vector3(0.35, 0.8, -0.3).normalized()
		support = 1.0
	support_hand = support
	sword.position = pose_position
	sword.basis = Basis.looking_at(pose_direction, Vector3.UP)

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

func play_attack(ranged: bool) -> void:
	if animation_library == null:
		return
	action_left = 0.4 if ranged else 0.52
	clip = &""
	var action: StringName = &"Pistol_Shoot" if ranged else &"Sword_Idle"
	select_clip(action, animation_library.get_animation(action).length / action_left)

func animate(delta: float, motion: Vector3, grounded: bool, phase: int, blocking: bool, frozen: bool) -> void:
	update_pose(0.0 if frozen else delta, motion, blocking, phase == CombatController.Phase.STAGGERED)
	if animation_library == null:
		return
	playback.speed_scale = 0.0 if frozen else 1.0
	if not frozen:
		action_left = maxf(0.0, action_left - delta)
	if phase == CombatController.Phase.STAGGERED:
		action_left = 0.0
		select_clip(&"Hit_Chest")
	elif phase == CombatController.Phase.DASHING:
		action_left = 0.0
		select_clip(&"Sprint", 1.5)
	elif blocking:
		select_clip(&"Sword_Idle")
	elif action_left > 0:
		return
	elif not grounded:
		select_clip(&"Jump")
	elif Vector2(motion.x, motion.z).length() > 0.3:
		select_clip(&"Jog_Fwd")
	else:
		select_clip(&"Idle")
