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

# A damaging hit leaves a gash along the blade's plane and briefly freezes the pose.
func wound(point: Vector3, normal: Vector3, travel: Vector3) -> void:
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
	var kept: Array[PackedStringArray] = MobRagdoll.split(cut_meshes, meshes, skeleton)
	for side: float in [1.0, -1.0]:
		var copy: Node3D = MODEL.instantiate() as Node3D
		copy.name = "RaiderHalf"
		copy.set_meta("side", side)
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
				if mesh.mesh.surface_get_name(surface) == MobRagdoll.CAP:
					continue
				var base: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
				var material: ShaderMaterial = ShaderMaterial.new()
				material.shader = CUT_SHADER
				material.set_shader_parameter("has_albedo", base != null and base.albedo_texture != null)
				if base != null and base.albedo_texture != null:
					material.set_shader_parameter("albedo_tex", base.albedo_texture)
				material.set_shader_parameter("side", side)
				mesh.set_surface_override_material(surface, material)
		# Each half is a ragdoll of the parts with skin on its side of the plane.
		var parts: PackedStringArray = kept[0 if side > 0.0 else 1]
		var body: PhysicalBoneSimulator3D = MobRagdoll.build(target, parts.has, velocity)
		var top: bool = side == top_side
		var push: Vector3 = impulse if top else impulse * 0.25
		# The top tumbles with its launch; the legs get a kick at the hip so they topple instead of standing.
		MobRagdoll.push(body, push, Vector3.UP.cross(push).normalized() * (2.5 if top else 4.0))
		# Blood pours from the cut face, which points along -side * normal, on each piece's part
		# nearest the cut: a big spill from the half itself, a shorter gush from severed limbs.
		var heaviest: float = 0.0
		var spills: Array[Dictionary] = []
		for piece: Array in MobRagdoll.pieces(body):
			var mass: float = 0.0
			var nearest: PhysicalBone3D
			for part: PhysicalBone3D in piece:
				mass += part.mass
				if nearest == null or part.global_position.distance_squared_to(point) < nearest.global_position.distance_squared_to(point):
					nearest = part
			heaviest = maxf(heaviest, mass)
			spills.append({"part": nearest, "mass": mass})
		for spill: Dictionary in spills:
			var part: PhysicalBone3D = spill["part"] as PhysicalBone3D
			var local_point: Vector3 = part.to_local(point)
			var local_direction: Vector3 = part.global_basis.inverse() * (normal * -side)
			if float(spill["mass"]) >= heaviest:
				HitEffects.spill(part, local_point, local_direction)
			else:
				HitEffects.gush(part, local_point, local_direction, 1.6)
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
