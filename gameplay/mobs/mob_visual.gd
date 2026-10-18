extends Node3D

const MODEL: PackedScene = preload("res://content/characters/quaternius/Superhero_Male_FullBody.gltf")
const CLIPS: AnimationLibrary = preload("res://content/animations/quaternius/male.res")
var playback: AnimationPlayer = AnimationPlayer.new()
var label: Label3D = Label3D.new()
var overlay: ShaderMaterial = ShaderMaterial.new()
var meshes: Array[MeshInstance3D] = []
var clip: StringName = &""
var model: Node3D
var react_left: float = 0.0 # how long since a shove still counts as a fresh reaction
var flash_left: float = 0.0
var freeze_left: float = 0.0 # a short animation hitstop so the blow lands
var skeleton: Skeleton3D
var puppet: MobPuppet = MobPuppet.new() # bone springs: hits flex the struck chain
var feet: MobFeet # foot planting through TwoBoneIK3D
var ragdoll: PhysicalBoneSimulator3D # the death fall, once it starts
# The final pose after modifiers, skeleton space; between passes the skeleton holds only the animation.
var poses: Array[Transform3D] = []
var locals: Array[Transform3D] = []
var last_push: Vector3 = Vector3.ZERO # the latest shove, world space, for the direction of a fall
var push_age: float = 99.0
var fallen: bool = false
var velocity: Vector3 = Vector3.ZERO
var last_position: Vector3 = Vector3.ZERO
# Each wound rides on its nearest bone: {bone, center, normal, travel (bone space), age}.
var wounds: Array[Dictionary] = []
const CUT_SHADER: Shader = preload("res://gameplay/mobs/mob_cut.gdshader")
const OVERLAY_SHADER: Shader = preload("res://gameplay/mobs/mob_overlay.gdshader")
const MAX_WOUNDS: int = 6
const FLASH: float = 0.09
const FREEZE: float = 0.07
const CORPSE: float = 8.0 # a fallen or cut body stays this long after the raider node is gone
var rendered: bool = DisplayServer.get_name() != "headless" # the dummy renderer cannot take shader parameters

func _ready() -> void:
	model = MODEL.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# Plan the feet from the clip, flex the puppet springs over it, then solve the legs back down.
	feet = MobFeet.install(skeleton, self)
	puppet.name = "Puppet"
	skeleton.add_child(puppet)
	skeleton.move_child(puppet, feet.get_index() + 1)
	skeleton.skeleton_updated.connect(cache_pose)
	last_position = global_position
	overlay.shader = OVERLAY_SHADER
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = overlay
	add_child(playback)
	playback.add_animation_library(&"", CLIPS)
	label.position.y = 1.35
	label.font_size = 28
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _process(delta: float) -> void:
	react_left = maxf(0.0, react_left - delta)
	flash_left = maxf(0.0, flash_left - delta)
	freeze_left = maxf(0.0, freeze_left - delta)
	playback.speed_scale = 0.0 if freeze_left > 0.0 else 1.0
	push_age += delta
	if delta > 0.0 and not fallen:
		velocity = velocity.lerp((global_position - last_position) / delta, minf(1.0, delta * 10.0))
		last_position = global_position
	update_overlay(delta)

func cache_pose() -> void:
	poses.resize(skeleton.get_bone_count())
	locals.resize(poses.size())
	for bone: int in range(poses.size()):
		poses[bone] = skeleton.get_bone_global_pose(bone)
		locals[bone] = skeleton.get_bone_pose(bone)

# A shove or blade contact. The struck bones spin along the blade's travel and spring back.
# point and travel are world space; without them the blow lands on the chest along the impulse.
func react(impulse: Vector3, point: Vector3 = Vector3.INF, travel: Vector3 = Vector3.ZERO, speed: float = 0.0) -> void:
	last_push = impulse
	push_age = 0.0
	react_left = 0.45
	if fallen or skeleton == null:
		return
	if not point.is_finite():
		point = bone_world(skeleton.find_bone("spine_03")).origin
	var along: Vector3 = travel if travel.length_squared() > 0.0001 else impulse
	puppet.hit(point, along, speed if speed > 0.0 else impulse.length() * 1.5)

func bone_world(bone: int) -> Transform3D:
	var pose: Transform3D = poses[bone] if bone < poses.size() else skeleton.get_bone_global_pose(bone)
	return skeleton.global_transform * pose

# Write the last final pose into the skeleton itself, so physics and copies start from what was seen.
func hold_pose(target: Skeleton3D) -> void:
	for bone: int in range(mini(locals.size(), target.get_bone_count())):
		target.set_bone_pose(bone, locals[bone])

# Death: the raider's own body becomes a ragdoll that collapses onto the terrain. It moves into the
# scene so it outlives the raider node, and keeps its wounds tracking the falling bones.
func fall() -> void:
	if fallen or model == null or not visible or not is_inside_tree() or get_tree().current_scene == null:
		return
	fallen = true
	label.visible = false
	playback.pause()
	hold_pose(skeleton)
	puppet.active = false
	feet.set_enabled(false)
	reparent(get_tree().current_scene, true)
	# Recent blows carry the body on; otherwise it slumps back and to one side.
	var shove: Vector3 = last_push if push_age < 1.0 else global_basis * Vector3(randf_range(-0.4, 0.4), 0.0, 0.6)
	ragdoll = MobRagdoll.build(skeleton, Callable(), Vector3(velocity.x, minf(velocity.y, 0.0), velocity.z))
	MobRagdoll.push(ragdoll, shove.limit_length(5.0) * 0.4 + Vector3.UP * 0.3)
	get_tree().create_timer(CORPSE).timeout.connect(queue_free)

# A damaging hit leaves a gash along the blade's plane, flashes the body and freezes the pose.
func wound(point: Vector3, normal: Vector3, travel: Vector3) -> void:
	flash_left = FLASH
	freeze_left = FREEZE
	if skeleton == null:
		return
	# Travel within the plane, so the gash runs the way the blade went.
	var along: Vector3 = travel - normal * travel.dot(normal)
	if along.length_squared() < 0.0001:
		along = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT)
	var nearest: int = 0
	var best: float = INF
	for bone: int in range(skeleton.get_bone_count()):
		var distance: float = bone_world(bone).origin.distance_squared_to(point)
		if distance < best:
			best = distance
			nearest = bone
	var inverse: Transform3D = bone_world(nearest).affine_inverse()
	wounds.append({"bone": nearest, "center": inverse * point, "normal": inverse.basis * normal, "travel": inverse.basis * along.normalized(), "age": 0.0})
	if wounds.size() > MAX_WOUNDS:
		wounds.remove_at(0)

func update_overlay(delta: float) -> void:
	var centers: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var travels: PackedVector3Array = PackedVector3Array()
	var ages: PackedFloat32Array = PackedFloat32Array()
	for entry: Dictionary in wounds:
		entry["age"] = float(entry["age"]) + delta
		var frame: Transform3D = bone_world(int(entry["bone"]))
		centers.append(frame * (entry["center"] as Vector3))
		normals.append((frame.basis * (entry["normal"] as Vector3)).normalized())
		travels.append((frame.basis * (entry["travel"] as Vector3)).normalized())
		ages.append(float(entry["age"]))
	if not rendered:
		return
	for index: int in range(centers.size(), MAX_WOUNDS):
		centers.append(Vector3.ZERO)
		normals.append(Vector3.UP)
		travels.append(Vector3.RIGHT)
		ages.append(0.0)
	overlay.set_shader_parameter("wound_count", wounds.size())
	overlay.set_shader_parameter("wound_center", centers)
	overlay.set_shader_parameter("wound_normal", normals)
	overlay.set_shader_parameter("wound_travel", travels)
	overlay.set_shader_parameter("wound_age", ages)
	overlay.set_shader_parameter("flash", flash_left / FLASH)

# Blood thrown in the blade's plane: a fan of streaks along the travel, a thinner back-spray,
# a mist at the contact and a bright slash arc lying in the plane.
func slash_burst(point: Vector3, normal: Vector3, travel: Vector3, amount: float) -> void:
	if not rendered or get_tree().current_scene == null:
		return
	var along: Vector3 = travel - normal * travel.dot(normal)
	along = along.normalized() if along.length_squared() > 0.0001 else normal.cross(Vector3.UP).normalized()
	if along.length_squared() < 0.5:
		along = Vector3.RIGHT
	var root: Node3D = Node3D.new()
	root.position = point
	get_tree().current_scene.add_child(root)
	get_tree().create_timer(1.8).timeout.connect(root.queue_free)
	for step: int in range(-3, 4):
		# Fan spread lies in the plane; a little upward bias keeps arcs readable before gravity wins.
		var direction: Vector3 = along.rotated(normal, deg_to_rad(step * 15.0)) + Vector3.UP * 0.2
		root.add_child(streaks(direction.normalized(), int(7.0 * amount), 2.5 + amount, 4.5 + 2.2 * amount, 0.06))
	root.add_child(streaks((-along + Vector3.UP * 0.4).normalized(), int(5.0 * amount), 1.0, 2.0 + amount, 0.05, 25.0))
	root.add_child(streaks(Vector3.UP, int(14.0 * amount), 0.4, 1.2 + amount, 0.022, 90.0))
	root.add_child(slash_arc(normal, along, amount))

func streaks(direction: Vector3, count: int, speed_min: float, speed_max: float, size: float, spread: float = 6.0) -> GPUParticles3D:
	var burst: GPUParticles3D = GPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.amount = clampi(count, 3, 40)
	burst.lifetime = 0.9
	burst.emitting = true
	burst.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0, -12.0, 0)
	process.damping_min = 0.5
	process.damping_max = 1.5
	process.scale_min = size * 0.6
	process.scale_max = size * 1.4
	process.particle_flag_align_y = true # stretched drops point along their flight
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.35))
	var scale_curve: CurveTexture = CurveTexture.new()
	scale_curve.curve = shrink
	process.scale_curve = scale_curve
	burst.process_material = process
	var drop: CapsuleMesh = CapsuleMesh.new()
	drop.radius = 0.22
	drop.height = 3.2
	drop.radial_segments = 6
	drop.rings = 1
	var blood: StandardMaterial3D = StandardMaterial3D.new()
	blood.albedo_color = Color(0.62, 0.02, 0.02)
	blood.emission_enabled = true
	blood.emission = Color(0.35, 0.0, 0.0)
	blood.roughness = 0.25
	drop.material = blood
	burst.draw_pass_1 = drop
	return burst

func slash_arc(normal: Vector3, along: Vector3, amount: float) -> MeshInstance3D:
	# A crescent along the blade's travel through the contact: white-hot spine, red fading edges.
	# The blade's plane usually contains the attacker's view, so the crescent widens across the
	# view instead of across the plane; otherwise it would only ever be seen edge-on.
	var side: Vector3 = normal.cross(along).normalized()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var across: Vector3 = along.cross(-camera.global_basis.z)
		if across.length_squared() > 0.04:
			side = across.normalized()
	var length: float = 0.9 + 0.25 * amount
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var rows: int = 18
	for row: int in range(rows + 1):
		var s: float = float(row) / rows
		var spine: Vector3 = along * lerpf(-0.45, length, s) + side * (0.12 * sin(PI * s))
		var half: float = (0.07 + 0.025 * amount) * pow(sin(PI * s), 0.7) * (0.4 + 0.6 * s)
		vertices.append_array([spine - side * half, spine, spine + side * half])
		colors.append_array([Color(0.9, 0.02, 0.02, 0.55), Color(1.0, 0.85, 0.75, 1.0), Color(0.9, 0.02, 0.02, 0.55)])
		if row < rows:
			var base: int = row * 3
			indices.append_array(PackedInt32Array([base, base + 1, base + 3, base + 1, base + 4, base + 3, base + 1, base + 2, base + 4, base + 2, base + 5, base + 4]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	mesh.surface_set_material(0, material)
	var arc: MeshInstance3D = MeshInstance3D.new()
	arc.mesh = mesh
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Snap open along the travel, then fade.
	arc.scale = Vector3.ONE * 0.6
	var tween: Tween = arc.create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3.ONE * 1.15, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(material, "albedo_color", Color(1, 1, 1, 0), 0.28).set_delay(0.06)
	return arc

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
	var head: Vector3 = bone_world(skeleton.find_bone("Head")).origin
	var top_side: float = signf(normal.dot(head - point))
	top_side = top_side if top_side != 0.0 else 1.0
	hold_pose(skeleton)
	# Bake the cut once, in the pose it happened in; both halves share the meshes.
	var cut_meshes: Array[ArrayMesh] = []
	for mesh: MeshInstance3D in meshes:
		cut_meshes.append(MobRagdoll.bake_cut(mesh, skeleton, point, normal))
	var middles: Dictionary[String, Vector3] = MobRagdoll.midpoints(skeleton)
	for side: float in [1.0, -1.0]:
		var copy: Node3D = MODEL.instantiate() as Node3D
		copy.name = "RaiderHalf"
		get_tree().current_scene.add_child(copy, true)
		copy.global_transform = model.global_transform
		var target: Skeleton3D = copy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		hold_pose(target)
		var index: int = 0
		for node: Node in copy.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if index < cut_meshes.size():
				mesh.mesh = cut_meshes[index]
			index += 1
			# The dummy renderer in headless runs cannot take shader parameters; halves still exist for tests.
			if not rendered:
				continue
			for surface: int in range(mesh.mesh.get_surface_count()):
				var base: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
				var material: ShaderMaterial = ShaderMaterial.new()
				material.shader = CUT_SHADER
				material.set_shader_parameter("has_albedo", base != null and base.albedo_texture != null)
				if base != null and base.albedo_texture != null:
					material.set_shader_parameter("albedo_tex", base.albedo_texture)
				material.set_shader_parameter("side", side)
				mesh.set_surface_override_material(surface, material)
		# Each half is a ragdoll of the parts on its side of the plane.
		var keep: Callable = func(bone_name: String) -> bool: return signf(normal.dot(middles[bone_name] - point)) == side
		var body: PhysicalBoneSimulator3D = MobRagdoll.build(target, keep, velocity)
		var top: bool = side == top_side
		var push: Vector3 = impulse if top else impulse * 0.25
		# The top tumbles with its launch; the legs get a kick at the hip so they topple instead of standing.
		MobRagdoll.push(body, push, Vector3.UP.cross(push).normalized() * (2.5 if top else 4.0))
		get_tree().create_timer(CORPSE).timeout.connect(copy.queue_free)

func show_state(state: int, health: int, staggered: bool, windup: bool) -> void:
	label.text = "RAIDER · %d" % health if health > 0 else "DEFEATED"
	if rendered:
		overlay.set_shader_parameter("tint", Color(1.0, 0.75, 0.1, 0.65) if windup else Color(0.85, 0.12, 0.12, 0.25))
	label.modulate = Color("ffd052") if windup else Color("ff8888")
	var next: StringName = &"Idle"
	if health <= 0:
		if not fallen:
			fall.call_deferred()
		return
	elif staggered:
		next = &"Hit_Chest"
	elif state == HostileMob.State.ACT:
		next = &"Punch_Jab"
	elif state == HostileMob.State.MOVE:
		next = &"Jog_Fwd"
	if clip != next:
		clip = next
		playback.play(clip, 0.12)
