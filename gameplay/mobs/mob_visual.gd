extends Node3D

# The two Quaternius bodies share one 65-bone skeleton, so every modifier, ragdoll part and clip
# name below works on either; each has its own clips retargeted to its proportions.
const MODELS: Array[PackedScene] = [preload("res://content/characters/quaternius/Superhero_Male_FullBody.gltf"), preload("res://content/characters/quaternius/Superhero_Female_FullBody.gltf")]
const CLIPS: Array[AnimationLibrary] = [preload("res://content/animations/quaternius/male.res"), preload("res://content/animations/quaternius/female.res")]
var female: bool = false # set by HostileMob from its replicated id before this enters the tree
# Which possessed villager this is; read from the parent's replicated mob_id when it enters the tree,
# or set directly where there is no HostileMob (captures, tests).
var mob_id: int = 1
var playback: AnimationPlayer = AnimationPlayer.new()
var overlay: ShaderMaterial = ShaderMaterial.new()
var possession: MobPossession = MobPossession.new() # the variant's distortion, stances and quirks
var hands: MobPossession.Hands # arm IK for the crawl, coil and leap
var look_at_node: Node3D # a fallback stare target where there are no players (captures)
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
# HostileMob.State, including the possessed villagers' states (the host enum may not have them yet).
const IDLE: int = 0
const MOVE: int = 1
const ACT: int = 2
const STARE: int = 4
const CRAWL: int = 5
const LEAP: int = 6
const WALK_SPEED: float = 0.86 # ground speed of the Walk clip at speed 1 (m/s)
const SIGHT: float = 14.0 # how far a villager's head follows a player
# Eye sockets in each body's skin texture (UV), darkened by the overlay: male then female, each
# the two centres and the radii.
const SOCKETS: Array[Vector2] = [Vector2(0.139, 0.177), Vector2(0.235, 0.177), Vector2(0.032, 0.022), Vector2(0.131, 0.176), Vector2(0.234, 0.176), Vector2(0.03, 0.02)]
var clip_speed: float = 1.0 # this state's base playback speed, before the stutter
var streak_bones: PackedInt32Array = PackedInt32Array()
const CORPSE: float = 8.0 # a fallen or cut body stays this long after the raider node is gone
var rendered: bool = DisplayServer.get_name() != "headless" # the dummy renderer cannot take shader parameters

func _ready() -> void:
	var parent_id: Variant = get_parent().get("mob_id") if get_parent() != null else null
	if parent_id is int:
		mob_id = int(parent_id)
	model = MODELS[int(female)].instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# Possess the clip (proportions, stance, head), plan the feet from it, flex the puppet springs
	# over it, solve the legs back down, then plant or reach with the hands.
	possession.name = "Possession"
	possession.configure(mob_id)
	possession.body = self
	skeleton.add_child(possession)
	feet = MobFeet.install(skeleton, self)
	possession.feet = feet
	puppet.name = "Puppet"
	skeleton.add_child(puppet)
	skeleton.move_child(puppet, feet.get_index() + 1)
	hands = MobPossession.Hands.install(skeleton, possession)
	skeleton.skeleton_updated.connect(cache_pose)
	last_position = global_position
	overlay.shader = OVERLAY_SHADER
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = overlay
	for bone_name: String in ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]:
		streak_bones.append(skeleton.find_bone(bone_name))
	if rendered:
		possess_skin(overlay)
		for mesh: MeshInstance3D in meshes:
			mesh.set_instance_shader_parameter("surface_role", role_of(mesh))
	add_child(playback)
	playback.add_animation_library(&"", CLIPS[int(female)])

# Each mesh's part in the overlay: 0 hair (only wounds), 1 skin, 2 eyes.
func role_of(mesh: MeshInstance3D) -> int:
	var material: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
	var texture: String = material.albedo_texture.resource_path if material != null and material.albedo_texture != null else ""
	return 2 if texture.contains("Eye") else (1 if texture.contains("Superhero") else 0)

# Pale, bruised skin and dull eyes for this villager, drawn by the overlay over the body's texture.
func possess_skin(material: ShaderMaterial) -> void:
	var body: StandardMaterial3D
	for mesh: MeshInstance3D in meshes:
		if role_of(mesh) == 1:
			body = mesh.get_active_material(0) as StandardMaterial3D
	if body != null:
		material.set_shader_parameter("skin_albedo", body.albedo_texture)
		material.set_shader_parameter("skin_normal", body.normal_texture)
		material.set_shader_parameter("use_normal", body.normal_texture != null)
	material.set_shader_parameter("possessed", 1.0)
	material.set_shader_parameter("skin_tint", possession.skin)
	material.set_shader_parameter("bruise_amount", possession.bruises)
	material.set_shader_parameter("bruise_seed", float(possession.mob_id % 97) * 1.37)
	material.set_shader_parameter("streak_amount", possession.streaks)
	material.set_shader_parameter("eye_glow", possession.glow)
	var first: int = 3 * int(female)
	material.set_shader_parameter("socket_a", SOCKETS[first])
	material.set_shader_parameter("socket_b", SOCKETS[first + 1])
	material.set_shader_parameter("socket_size", SOCKETS[first + 2])

func _process(delta: float) -> void:
	react_left = maxf(0.0, react_left - delta)
	freeze_left = maxf(0.0, freeze_left - delta)
	var stutter: float = possession.clip_speed(delta)
	playback.speed_scale = 0.0 if freeze_left > 0.0 else clip_speed * stutter
	push_age += delta
	if delta > 0.0 and not fallen:
		velocity = velocity.lerp((global_position - last_position) / delta, minf(1.0, delta * 10.0))
		last_position = global_position
	possession.velocity = velocity
	update_look()
	update_overlay(delta)

# The head follows the nearest player in sight range: hard while staring, crawling or coiled, idly
# otherwise. Players come from the encounter on every peer.
func update_look() -> void:
	var best: Vector3 = Vector3.INF
	var nearest: float = SIGHT
	var host: HostileMob = get_parent() as HostileMob
	var players: Node3D = host.system.players if host != null and host.system != null else null
	for node: Node in players.get_children() if players != null else []:
		var player: Node3D = node as Node3D
		if player == null or player.is_queued_for_deletion():
			continue
		var distance: float = player.global_position.distance_to(global_position)
		if distance < nearest:
			nearest = distance
			best = player.global_position + Vector3.UP * 0.75
	if not best.is_finite() and is_instance_valid(look_at_node):
		best = look_at_node.global_position
	possession.look_target = best
	var focus: float = 1.0 if possession.mode != MobPossession.Mode.UPRIGHT else 0.45
	possession.look_weight = focus if best.is_finite() else 0.0

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
	playback.pause()
	hold_pose(skeleton)
	puppet.active = false
	possession.active = false
	hands.set_enabled(false)
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
	# Dried blood runs down the forearms and shins: their frames, for the overlay.
	var origins: PackedVector3Array = PackedVector3Array()
	var axes: PackedVector3Array = PackedVector3Array()
	var sides: PackedVector3Array = PackedVector3Array()
	var lengths: PackedFloat32Array = PackedFloat32Array()
	for bone: int in streak_bones:
		var frame: Transform3D = bone_world(bone)
		var child: PackedInt32Array = skeleton.get_bone_children(bone)
		origins.append(frame.origin)
		axes.append(frame.basis.y.normalized())
		sides.append(frame.basis.x.normalized())
		lengths.append(skeleton.get_bone_pose_position(child[0]).length() * (possession.arm_length if bone == streak_bones[0] or bone == streak_bones[1] else possession.leg_length) if not child.is_empty() else 0.25)
	overlay.set_shader_parameter("streak_origin", origins)
	overlay.set_shader_parameter("streak_axis", axes)
	overlay.set_shader_parameter("streak_side", sides)
	overlay.set_shader_parameter("streak_length", lengths)
	overlay.set_shader_parameter("glow_strength", 0.3 + 3.0 * possession.flare())
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
	var center: Vector3 = HitEffects.cut_center(point, normal, global_position)
	var top_side: float = signf(normal.dot(head - point))
	top_side = top_side if top_side != 0.0 else 1.0
	hold_pose(skeleton)
	# Bake the cut once, in the pose it happened in; both halves share the meshes.
	var cut_meshes: Array[ArrayMesh] = []
	for mesh: MeshInstance3D in meshes:
		cut_meshes.append(MobRagdoll.bake_cut(mesh, skeleton, point, normal))
	var kept: Array[PackedStringArray] = MobRagdoll.split(cut_meshes, meshes, skeleton)
	# The halves keep the pale skin: the same overlay without wounds, cut away on the other side.
	var half_overlay: ShaderMaterial
	if rendered:
		half_overlay = ShaderMaterial.new()
		half_overlay.shader = OVERLAY_SHADER
		possess_skin(half_overlay)
		half_overlay.set_shader_parameter("use_normal", false) # the cut bake rewrote the tangents
		half_overlay.set_shader_parameter("streak_amount", 0.0)
	for side: float in [1.0, -1.0]:
		var copy: Node3D = MODELS[int(female)].instantiate() as Node3D
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
			mesh.material_overlay = half_overlay
			mesh.set_instance_shader_parameter("surface_role", role_of(meshes[mini(index - 1, meshes.size() - 1)]))
			mesh.set_instance_shader_parameter("cut_side", side)
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
		# The stream starts from the middle of each stump, not the skin the blade touched.
		var heaviest: float = 0.0
		var spills: Array[Dictionary] = []
		for piece: Array in MobRagdoll.pieces(body):
			var mass: float = 0.0
			var nearest: PhysicalBone3D
			for part: PhysicalBone3D in piece:
				mass += part.mass
				if nearest == null or part.global_position.distance_squared_to(center) < nearest.global_position.distance_squared_to(center):
					nearest = part
			heaviest = maxf(heaviest, mass)
			spills.append({"part": nearest, "mass": mass})
		for spill: Dictionary in spills:
			var part: PhysicalBone3D = spill["part"] as PhysicalBone3D
			var local_point: Vector3 = part.to_local(HitEffects.part_face(part, center, normal))
			var local_direction: Vector3 = part.global_basis.inverse() * (normal * -side)
			if float(spill["mass"]) >= heaviest:
				HitEffects.spill(part, local_point, local_direction)
			else:
				HitEffects.gush(part, local_point, local_direction, 1.6)
		get_tree().create_timer(CORPSE).timeout.connect(copy.queue_free)

# The host's state, shown as the possessed body: a lingering idle, a slow stuttering shamble, the
# staring squat, the all-fours crawl, the pounce coil (the attack's telegraph, read from the body,
# not a label) and the leap. Unknown states idle.
func show_state(state: int, health: int, staggered: bool, windup: bool) -> void:
	var next: StringName = &"Idle"
	var stance: int = MobPossession.Mode.UPRIGHT
	var speed: float = Vector2(velocity.x, velocity.z).length()
	clip_speed = 0.75
	if health <= 0:
		if not fallen:
			fall.call_deferred()
		return
	if windup or state == ACT:
		stance = MobPossession.Mode.COIL
		clip_speed = 0.3
	elif state == MOVE:
		# The shamble's clip follows the ground speed; anything faster jogs.
		next = &"Walk" if speed < 1.9 else &"Jog_Fwd"
		clip_speed = clampf(speed / WALK_SPEED, 0.5, 1.6) if next == &"Walk" else 1.0
	elif state == STARE:
		stance = MobPossession.Mode.SQUAT
		clip_speed = 0.05
	elif state == CRAWL:
		stance = MobPossession.Mode.CRAWL
		clip_speed = 0.5
	elif state == LEAP:
		stance = MobPossession.Mode.LEAP
		clip_speed = 0.5
	if staggered:
		next = &"Hit_Chest"
		clip_speed = 1.0
		stance = possession.mode if possession.mode != MobPossession.Mode.LEAP else MobPossession.Mode.UPRIGHT
	possession.mode = stance
	if clip != next:
		clip = next
		playback.play(clip, 0.12)
