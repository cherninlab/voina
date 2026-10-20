class_name RobeCloth
extends SpringBoneSimulator3D

# The hooded cultist's robe (T-110). The gown below the hips hangs from COLUMNS chains of JOINTS bones
# under the pelvis, and each bell sleeve from a droop bone on the forearm
# (scripts/art/build_hooded_cultist.py).
# Standing, nothing is simulated: Gait (first of all the modifiers) shortens the stride, as a robe
# hobbles it, and Push (last) hands the garment shader this frame's hips, knees, ankles, elbows and
# hands. The shader (content/mobs/hooded_cultist/robe_shape.gdshaderinc) moves each skirt vertex out
# to the farthest point of the legs above it, so the robe tents over a forward knee and stretches
# between the legs, and no leg or hand shows through it.
# A death or a cut drapes the robe: this SpringBoneSimulator3D (engine code) and Stride (the chains
# following the thighs) start, the chains go slack and heavy and fall along the legs onto a ground
# plane, the cut edge hanging free, and the shader only pushes the cloth out of the legs. A cut half
# draws with gameplay/mobs/mob_cut.gdshader, which shapes its robe the same way. Everything is
# cosmetic and runs on every peer from the pose the host's state and RPCs already drive; nothing
# here is replicated.

const COLUMNS: int = 8
const JOINTS: int = 4 # bones per skirt chain, from the hips to the hem
const HEM: float = 0.166 # the last bone's extension down to the hem (m)
const SLEEVE: float = 0.25 # each sleeve's droop bone length (m)
# Dead or cut: barely holds its shape, so it sags onto the legs it hangs along (rather than sliding
# off them) and down to the ground, and loses its swing as it lands.
const DRAPE_STIFFNESS: float = 1.2
const DRAPE_DRAG: float = 0.75
const DRAPE_GRAVITY: float = 2.0
const SLEEVE_STIFFNESS: float = 1.6
# How much of each thigh's swing the skirt on its side takes: alive, and on a ragdoll, where it
# lays the robe along bent legs instead of straight out from the hips.
const STRIDE_FOLLOW: float = 0.6
const DRAPE_FOLLOW: float = 0.85
const PUSH_SHADER: Shader = preload("res://content/mobs/hooded_cultist/robe_push.gdshader")
var draped: bool = false
var ground: SpringBoneCollisionPlane3D
var stride: Stride
var gait: Gait
var push: Push

# Adds the robe to a cultist skeleton. Null for a body without skirt bones (the plain raider, or an
# older cultist asset). garments: the robe mesh to keep the legs inside; own_material: draw it with
# the push shader (false on a cut half, whose cut shader pushes the same way).
static func install(rig: Skeleton3D, garments: MeshInstance3D = null, own_material: bool = true) -> RobeCloth:
	if rig.find_bone(bone_name(0, 0)) < 0:
		return null
	var cloth: RobeCloth = RobeCloth.new()
	cloth.name = "RobeCloth"
	# First of all the modifiers, so foot planting and IK work from the shorter stride.
	cloth.gait = Gait.new()
	cloth.gait.name = "RobeGait"
	cloth.gait.setup(rig)
	var first: int = rig.get_child_count()
	for child: Node in rig.get_children():
		if child is SkeletonModifier3D:
			first = mini(first, child.get_index())
	rig.add_child(cloth.gait)
	rig.move_child(cloth.gait, first)
	cloth.stride = Stride.new()
	cloth.stride.name = "RobeStride"
	cloth.stride.setup(rig)
	rig.add_child(cloth.stride)
	# Settings and the ground first: the simulator gathers its child colliders as it enters the tree.
	cloth.configure(rig)
	cloth.active = false # standing, the shader shapes the robe; the springs only drape a corpse
	cloth.stride.active = false
	rig.add_child(cloth)
	if garments != null:
		cloth.push = Push.new()
		cloth.push.name = "RobePush"
		cloth.push.setup(rig, garments, own_material)
		rig.add_child(cloth.push)
	return cloth

static func bone_name(column: int, joint: int) -> String:
	return "robe_%02d_%d" % [column, joint]

func configure(rig: Skeleton3D) -> void:
	var sleeves: PackedStringArray = PackedStringArray()
	for side: String in ["l", "r"]:
		if rig.find_bone("sleeve_" + side) >= 0:
			sleeves.append("sleeve_" + side)
	setting_count = COLUMNS + sleeves.size()
	for setting: int in range(setting_count):
		set_center_from(setting, SpringBoneSimulator3D.CENTER_FROM_NODE)
		set_center_node(setting, NodePath(".."))
		set_extend_end_bone(setting, true)
		set_end_bone_direction(setting, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
	for column: int in range(COLUMNS):
		set_root_bone_name(column, bone_name(column, 0))
		set_end_bone_name(column, bone_name(column, JOINTS - 1))
		set_end_bone_length(column, HEM)
		set_radius(column, 0.02)
	for index: int in range(sleeves.size()):
		set_root_bone_name(COLUMNS + index, sleeves[index])
		set_end_bone_name(COLUMNS + index, sleeves[index])
		set_end_bone_length(COLUMNS + index, SLEEVE)
		set_radius(COLUMNS + index, 0.02)
	# The ground under the feet: the root bone stays at the feet while alive. Level in the
	# skeleton's frame (its Y is up), whatever axes the root bone carries.
	ground = SpringBoneCollisionPlane3D.new()
	ground.name = "Ground"
	ground.bone_name = "root"
	var level: Basis = rig.get_bone_global_rest(rig.find_bone("root")).basis.inverse()
	ground.rotation_offset = level.get_rotation_quaternion()
	ground.position_offset = level * Vector3(0.0, 0.01, 0.0)
	add_child(ground)
	for setting: int in range(setting_count):
		set_enable_all_child_collisions(setting, setting < COLUMNS) # sleeves only hang
	tune(DRAPE_STIFFNESS, DRAPE_DRAG, DRAPE_GRAVITY)

func tune(stiffness: float, drag: float, gravity: float) -> void:
	for setting: int in range(setting_count):
		var sleeve: bool = setting >= COLUMNS
		set_stiffness(setting, maxf(stiffness, SLEEVE_STIFFNESS * (0.25 if draped else 1.0)) if sleeve else stiffness)
		set_drag(setting, drag)
		set_gravity(setting, gravity)
		set_gravity_direction(setting, Vector3.DOWN)

# The body died or was cut: the cloth simulates, loses its shape and falls onto the legs and the
# ground. Moves the robe's modifiers after the ragdoll's simulator, so they hang from the pose the physics gives
# this frame. floor_point and floor_normal (world space, optional) place the ground under the body,
# held still from then on: a ragdoll moves bones, never the skeleton node (a cut half even carries
# its root bone along on the pelvis).
func drape(floor_point: Vector3 = Vector3.INF, floor_normal: Vector3 = Vector3.UP) -> void:
	draped = true
	active = true
	reset() # from the pose the robe hangs in now
	stride.active = true
	if push != null:
		push.tent = 0.0 # lying down, the legs only push the cloth out
	gait.active = false # the ragdoll moves the legs now
	stride.follow = DRAPE_FOLLOW
	var rig: Skeleton3D = get_skeleton()
	if rig != null:
		for modifier: SkeletonModifier3D in [stride, self, push]:
			if modifier != null:
				rig.move_child(modifier, rig.get_child_count() - 1)
		if floor_point.is_finite():
			var up: Vector3 = floor_normal.normalized()
			var plane: Transform3D = Transform3D(Basis(Quaternion(Vector3.UP, up)), floor_point + up * 0.01)
			remove_child(ground)
			ground.free()
			ground = SpringBoneCollisionPlane3D.new() # follows no bone
			ground.name = "Ground"
			add_child(ground)
			ground.global_transform = plane
	tune(DRAPE_STIFFNESS, DRAPE_DRAG, DRAPE_GRAVITY)

# The ground point and normal under a world position, or INF where nothing is below.
static func floor_under(world: World3D, from: Vector3) -> Array[Vector3]:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, from + Vector3.DOWN * 3.0, 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return [Vector3.INF, Vector3.UP]
	return [hit["position"] as Vector3, hit["normal"] as Vector3]

# A robe hobbles the stride: the legs swing GAIT of the clip's swing away from their rest pose, so
# the trailing leg does not kick out through the back of the robe and the knee does not lift through
# the front. Runs first, so the feet still plant from the shorter stride.
const GAIT: float = 0.72
const GAIT_BONES: PackedStringArray = ["thigh_l", "calf_l", "thigh_r", "calf_r"]

class Gait extends SkeletonModifier3D:
	var bones: PackedInt32Array = PackedInt32Array()
	var rests: Array[Quaternion] = []

	func setup(rig: Skeleton3D) -> void:
		for bone_name: String in GAIT_BONES:
			bones.append(rig.find_bone(bone_name))
			rests.append(rig.get_bone_rest(bones[-1]).basis.get_rotation_quaternion())

	func _process_modification_with_delta(_delta: float) -> void:
		var rig: Skeleton3D = get_skeleton()
		for index: int in range(bones.size()):
			rig.set_bone_pose_rotation(bones[index], rests[index].slerp(rig.get_bone_pose_rotation(bones[index]), GAIT))

# Turns each skirt chain's hip bone by part of the swing of the thigh on its side (both thighs
# blend across the front and back), as the pose the springs then pull toward.
class Stride extends SkeletonModifier3D:
	var roots: PackedInt32Array = PackedInt32Array()
	var left: PackedFloat32Array = PackedFloat32Array() # each chain's share of the left thigh
	var thighs: PackedInt32Array = PackedInt32Array()
	var rests: Array[Quaternion] = []
	var follow: float = STRIDE_FOLLOW

	func setup(rig: Skeleton3D) -> void:
		for column: int in range(COLUMNS):
			roots.append(rig.find_bone(RobeCloth.bone_name(column, 0)))
			# Columns run round from the front; the left thigh is on +X, a quarter turn on. The share
			# changes smoothly round the robe, so the panels over the front and back, between the legs,
			# take both swings evenly and neighbouring columns never pull apart.
			left.append(0.5 + 0.5 * sin(TAU * float(column) / float(COLUMNS)))
		for side: String in ["thigh_l", "thigh_r"]:
			thighs.append(rig.find_bone(side))
			rests.append(rig.get_bone_rest(thighs[-1]).basis.get_rotation_quaternion())

	func _process_modification_with_delta(_delta: float) -> void:
		var rig: Skeleton3D = get_skeleton()
		var swing_l: Quaternion = rig.get_bone_pose_rotation(thighs[0]) * rests[0].inverse()
		var swing_r: Quaternion = rig.get_bone_pose_rotation(thighs[1]) * rests[1].inverse()
		for index: int in range(roots.size()):
			var turn: Quaternion = Quaternion.IDENTITY.slerp(swing_l, left[index] * follow) * Quaternion.IDENTITY.slerp(swing_r, (1.0 - left[index]) * follow)
			rig.set_bone_pose_rotation(roots[index], turn * rig.get_bone_pose_rotation(roots[index]))

# Hands the garment shader this frame's leg capsules (in the garment mesh's space, which the
# shader's skinned VERTEX is in), after every other modifier, so they match the legs as drawn.
class Push extends SkeletonModifier3D:
	# The joints the shader shapes the robe round, in its order: hips, knees and ankles left then
	# right, then each elbow and the hand, which runs on past the wrist (robe_shape.gdshaderinc).
	const LEGS: PackedStringArray = ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "lowerarm_l", "hand_l", "lowerarm_r", "hand_r"]
	const NAMES: Array[StringName] = [&"thigh_l", &"knee_l", &"ankle_l", &"thigh_r", &"knee_r", &"ankle_r", &"elbow_l", &"hand_l", &"elbow_r", &"hand_r"]
	const HAND: float = 0.12 # how far past the wrist the hand's capsule reaches (m)
	var tent: float = 1.0 # standing: shape the robe round the legs; 0 once draped
	static var converted: Dictionary[Material, ShaderMaterial] = {}
	var garments: MeshInstance3D
	var bones: PackedInt32Array = PackedInt32Array()
	var ends: PackedVector3Array = PackedVector3Array() # last capsule ends sent, a then b per leg
	var rendered: bool = DisplayServer.get_name() != "headless" # the dummy renderer takes no shader parameters

	func setup(rig: Skeleton3D, mesh: MeshInstance3D, own_material: bool = true) -> void:
		garments = mesh
		for bone_name: String in LEGS:
			bones.append(rig.find_bone(bone_name))
		ends.resize(bones.size())
		for surface: int in range(mesh.mesh.get_surface_count() if own_material else 0):
			mesh.set_surface_override_material(surface, pushed(mesh.get_active_material(surface)))

	# The imported material's look on the push shader, shared by every cultist.
	static func pushed(source: Material) -> ShaderMaterial:
		if converted.has(source):
			return converted[source]
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PUSH_SHADER
		var standard: BaseMaterial3D = source as BaseMaterial3D
		if standard != null:
			material.set_shader_parameter("albedo", standard.albedo_color)
			material.set_shader_parameter("use_texture", standard.albedo_texture != null)
			material.set_shader_parameter("albedo_texture", standard.albedo_texture)
			material.set_shader_parameter("use_normal", standard.normal_enabled and standard.normal_texture != null)
			material.set_shader_parameter("normal_texture", standard.normal_texture)
			material.set_shader_parameter("normal_scale", standard.normal_scale)
			material.set_shader_parameter("roughness", standard.roughness)
		converted[source] = material
		return material

	# The imported materials back, so a cut bakes and copies their textures (MobVisual.bisect).
	func restore() -> void:
		if is_instance_valid(garments):
			for surface: int in range(garments.mesh.get_surface_count()):
				garments.set_surface_override_material(surface, null)

	func _process_modification_with_delta(_delta: float) -> void:
		if not is_instance_valid(garments):
			return
		var rig: Skeleton3D = get_skeleton()
		var to_mesh: Transform3D = garments.transform.affine_inverse() # the garments sit under the skeleton
		for index: int in range(bones.size()):
			ends[index] = to_mesh * rig.get_bone_global_pose(bones[index]).origin
		for index: int in [7, 9]: # the forearms run on over the hands
			ends[index] += (ends[index] - ends[index - 1]).normalized() * HAND
		if not rendered:
			return
		for index: int in range(NAMES.size()):
			garments.set_instance_shader_parameter(NAMES[index], ends[index])
		garments.set_instance_shader_parameter(&"tent", tent)
