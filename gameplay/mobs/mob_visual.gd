extends Node3D

const MODEL: PackedScene = preload("res://content/characters/quaternius/Superhero_Male_FullBody.gltf")
const CLIPS: AnimationLibrary = preload("res://content/animations/quaternius/male.res")
var playback: AnimationPlayer = AnimationPlayer.new()
var label: Label3D = Label3D.new()
var tint: StandardMaterial3D = StandardMaterial3D.new()
var meshes: Array[MeshInstance3D] = []
var clip: StringName = &""
var model: Node3D
var lean: Vector3 = Vector3.ZERO # tilt (radians about x and z) away from the last blade shove
var lean_speed: Vector3 = Vector3.ZERO
var react_left: float = 0.0
const CUT_SHADER: Shader = preload("res://gameplay/mobs/mob_cut.gdshader")

func _ready() -> void:
	model = MODEL.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = tint
	add_child(playback)
	playback.add_animation_library(&"", CLIPS)
	label.position.y = 1.35
	label.font_size = 28
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _process(delta: float) -> void:
	react_left = maxf(0.0, react_left - delta)
	# A spring tilts the body away from the shove and settles back.
	lean_speed += (-lean * 60.0 - lean_speed * 9.0) * delta
	lean += lean_speed * delta
	if model != null:
		model.rotation = Vector3(lean.x, PI, lean.z)

func react(impulse: Vector3) -> void:
	# Impulse is world space; tilt about the horizontal axis perpendicular to it, in this node's frame.
	var local: Vector3 = impulse.rotated(Vector3.UP, -global_rotation.y)
	lean_speed += Vector3(-local.z, 0.0, local.x) * 1.4
	react_left = 0.45

func splash(point: Vector3, direction: Vector3, amount: float) -> void:
	# A one-shot burst of droplets from the contact, thrown along the blade's travel.
	if DisplayServer.get_name() == "headless" or get_tree().current_scene == null:
		return
	var burst: GPUParticles3D = GPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = int(clampf(18.0 * amount, 10.0, 60.0))
	burst.lifetime = 0.8
	burst.emitting = true
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = (direction + Vector3.UP * 0.6).normalized()
	process.spread = 40.0
	process.initial_velocity_min = 1.5 * amount + 1.0
	process.initial_velocity_max = 4.0 * amount + 2.0
	process.gravity = Vector3(0, -9.8, 0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.03
	process.scale_max = 0.07
	process.color = Color(0.45, 0.02, 0.02)
	burst.process_material = process
	var droplet: SphereMesh = SphereMesh.new()
	droplet.radius = 0.5
	droplet.height = 1.0
	droplet.radial_segments = 6
	droplet.rings = 3
	var blood: StandardMaterial3D = StandardMaterial3D.new()
	blood.albedo_color = Color(0.5, 0.03, 0.03)
	blood.roughness = 0.3
	droplet.material = blood
	burst.draw_pass_1 = droplet
	burst.position = point
	get_tree().current_scene.add_child(burst)
	get_tree().create_timer(1.6).timeout.connect(burst.queue_free)

func bisect(point: Vector3, normal: Vector3, impulse: Vector3) -> void:
	if model == null or not visible:
		return
	visible = false
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	var top_side: float = signf(normal.dot(head - point))
	for side: float in [1.0, -1.0]:
		var half: RigidBody3D = RigidBody3D.new()
		half.global_transform = global_transform
		half.mass = 1.0
		half.collision_layer = 0
		half.collision_mask = 1
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(0.45, 0.8, 0.35)
		shape.shape = box
		shape.position.y = 0.3 if side == top_side else -0.3
		half.add_child(shape)
		var copy: Node3D = MODEL.instantiate() as Node3D
		copy.rotation.y = PI
		copy.position.y = -0.9
		half.add_child(copy)
		var target: Skeleton3D = copy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for bone: int in range(skeleton.get_bone_count()):
			target.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone))
			target.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone))
			target.set_bone_pose_scale(bone, skeleton.get_bone_pose_scale(bone))
		# The cut plane in the copy's model space, which matches ours: discard the far side.
		var plane_point: Vector3 = model.to_local(point)
		var plane_normal: Vector3 = (model.global_basis.inverse() * normal).normalized() * -side
		# The dummy renderer in headless runs cannot take shader parameters; halves still exist for tests.
		for node: Node in copy.find_children("*", "MeshInstance3D", true, false) if DisplayServer.get_name() != "headless" else []:
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in range(mesh.mesh.get_surface_count()):
				var base: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
				var material: ShaderMaterial = ShaderMaterial.new()
				material.shader = CUT_SHADER
				material.set_shader_parameter("has_albedo", base != null and base.albedo_texture != null)
				if base != null and base.albedo_texture != null:
					material.set_shader_parameter("albedo_tex", base.albedo_texture)
				material.set_shader_parameter("plane_point", plane_point)
				material.set_shader_parameter("plane_normal", plane_normal)
				mesh.set_surface_override_material(surface, material)
		get_tree().current_scene.add_child(half)
		var push: Vector3 = impulse if side == top_side else impulse * 0.25
		half.apply_impulse(push, Vector3.UP * (0.4 if side == top_side else -0.3))
		# The top tumbles with its launch; the legs get a kick at the hip so they topple instead of standing.
		half.apply_torque_impulse(Vector3.UP.cross(push).normalized() * (0.4 if side == top_side else 1.6))
		get_tree().create_timer(7.0).timeout.connect(half.queue_free)

func show_state(state: int, health: int, staggered: bool, windup: bool) -> void:
	label.text = "RAIDER · %d" % health if health > 0 else "DEFEATED"
	tint.albedo_color = Color(1.0, 0.75, 0.1, 0.65) if windup else Color(0.85, 0.12, 0.12, 0.25)
	label.modulate = Color("ffd052") if windup else Color("ff8888")
	var next: StringName = &"Idle"
	if health <= 0:
		rotation.z = lerp_angle(rotation.z, PI / 2.0, 0.15)
	elif staggered or react_left > 0.0:
		next = &"Hit_Chest"
	elif state == HostileMob.State.ACT:
		next = &"Punch_Jab"
	elif state == HostileMob.State.MOVE:
		next = &"Jog_Fwd"
	if clip != next:
		clip = next
		playback.play(clip, 0.12)
