class_name MobRagdoll
extends RefCounted

# Jointed physical bodies for a raider's skeleton, built at runtime under an engine
# PhysicalBoneSimulator3D: a whole-body ragdoll for a death, or the bodies on one side of a cut
# for a bisected half. Bodies sit on layer 0 with mask 1, so they land on the terrain and are
# shoved by actors without blocking anyone or colliding with each other. Shapes are sized
# through their resources; no node is scaled.

# bone, child for the segment (empty: straight along the bone for `length`), shape, radius or box
# half-width, mass (kg), joint, swing (cone) or bend limit (hinge, degrees), twist.
const PARTS: Array[Dictionary] = [
	{"bone": "pelvis", "to": "spine_01", "box": Vector3(0.34, 0.24, 0.22), "mass": 10.0, "joint": PhysicalBone3D.JOINT_TYPE_NONE},
	{"bone": "spine_01", "to": "spine_02", "box": Vector3(0.32, 0.2, 0.13), "mass": 6.0, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 18.0, "twist": 12.0},
	{"bone": "spine_02", "to": "spine_03", "box": Vector3(0.34, 0.21, 0.11), "mass": 6.0, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 18.0, "twist": 12.0},
	{"bone": "spine_03", "to": "neck_01", "box": Vector3(0.4, 0.23, 0.22), "mass": 9.0, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 20.0, "twist": 15.0},
	{"bone": "Head", "length": 0.24, "radius": 0.11, "mass": 4.5, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 40.0, "twist": 35.0},
	{"bone": "upperarm_l", "to": "lowerarm_l", "radius": 0.055, "mass": 2.5, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 75.0, "twist": 35.0},
	{"bone": "lowerarm_l", "to": "hand_l", "extra": 0.12, "radius": 0.045, "mass": 2.0, "joint": PhysicalBone3D.JOINT_TYPE_HINGE, "bend": 125.0},
	{"bone": "upperarm_r", "to": "lowerarm_r", "radius": 0.055, "mass": 2.5, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 75.0, "twist": 35.0},
	{"bone": "lowerarm_r", "to": "hand_r", "extra": 0.12, "radius": 0.045, "mass": 2.0, "joint": PhysicalBone3D.JOINT_TYPE_HINGE, "bend": 125.0},
	{"bone": "thigh_l", "to": "calf_l", "radius": 0.08, "mass": 8.0, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 50.0, "twist": 20.0},
	{"bone": "calf_l", "to": "foot_l", "radius": 0.06, "mass": 4.0, "joint": PhysicalBone3D.JOINT_TYPE_HINGE, "bend": 130.0},
	{"bone": "foot_l", "to": "ball_l", "extra": 0.06, "radius": 0.045, "mass": 1.2, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 25.0, "twist": 10.0},
	{"bone": "thigh_r", "to": "calf_r", "radius": 0.08, "mass": 8.0, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 50.0, "twist": 20.0},
	{"bone": "calf_r", "to": "foot_r", "radius": 0.06, "mass": 4.0, "joint": PhysicalBone3D.JOINT_TYPE_HINGE, "bend": 130.0},
	{"bone": "foot_r", "to": "ball_r", "extra": 0.06, "radius": 0.045, "mass": 1.2, "joint": PhysicalBone3D.JOINT_TYPE_CONE, "swing": 25.0, "twist": 10.0},
]

# The world-space midpoint of each part's segment, for choosing which side of a cut it is on.
static func midpoints(rig: Skeleton3D) -> Dictionary[String, Vector3]:
	var result: Dictionary[String, Vector3] = {}
	for part: Dictionary in PARTS:
		var segment: Array[Vector3] = segment_of(rig, part)
		result[String(part["bone"])] = rig.global_transform * ((segment[0] + segment[1]) * 0.5)
	return result

# Segment start and end in skeleton space, from the current pose.
static func segment_of(rig: Skeleton3D, part: Dictionary) -> Array[Vector3]:
	var bone: int = rig.find_bone(String(part["bone"]))
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	var along: Vector3 = local_along(rig, part)
	return [pose.origin, pose * along]

static func local_along(rig: Skeleton3D, part: Dictionary) -> Vector3:
	if part.has("to"):
		var child: Vector3 = rig.get_bone_rest(rig.find_bone(String(part["to"]))).origin
		return child + child.normalized() * float(part.get("extra", 0.0))
	return Vector3.UP * float(part["length"])

# Builds the parts `keep` accepts (by bone name) and starts simulating them from the current pose.
# A part whose jointed parent is not kept falls free.
static func build(rig: Skeleton3D, keep: Callable = Callable(), velocity: Vector3 = Vector3.ZERO) -> PhysicalBoneSimulator3D:
	var simulator: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	rig.add_child(simulator)
	var kept: PackedStringArray = PackedStringArray()
	for part: Dictionary in PARTS:
		if not keep.is_valid() or bool(keep.call(String(part["bone"]))):
			kept.append(String(part["bone"]))
	for part: Dictionary in PARTS:
		var bone_name: String = String(part["bone"])
		if not kept.has(bone_name):
			continue
		var body: PhysicalBone3D = make_part(rig, part, kept)
		simulator.add_child(body)
		body.global_transform = rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone_name)) * body.body_offset
	simulator.physical_bones_start_simulation()
	for node: Node in simulator.get_children():
		(node as PhysicalBone3D).linear_velocity = velocity
	if kept.size() < PARTS.size():
		# Before the simulator, so the bodies it then poses are not dragged by a moved ancestor.
		var stitch: Stitch = Stitch.new()
		stitch.name = "Stitch"
		rig.add_child(stitch)
		rig.move_child(stitch, simulator.get_index())
		stitch.setup(rig, simulator)
	return simulator

# On a cut half, bones without a body that do not hang below one would stay where the cut happened
# and stretch the triangles joining them to the falling part. Each instead rides rigidly on the
# nearest simulated bone, keeping its offset from the moment of the cut.
class Stitch extends SkeletonModifier3D:
	var riders: PackedInt32Array = PackedInt32Array()
	var anchors: Array[PhysicalBone3D] = []
	var offsets: Array[Transform3D] = []

	func setup(rig: Skeleton3D, simulator: PhysicalBoneSimulator3D) -> void:
		var simulated: PackedInt32Array = PackedInt32Array()
		var bodies: Dictionary[int, PhysicalBone3D] = {}
		for node: Node in simulator.get_children():
			var body: PhysicalBone3D = node as PhysicalBone3D
			simulated.append(rig.find_bone(body.bone_name))
			bodies[simulated[-1]] = body
		# Parents come before children in this rig, so riders apply top-down.
		for bone: int in range(rig.get_bone_count()):
			if simulated.has(bone):
				continue
			var anchor: int = nearest(rig, bone, simulated)
			if anchor < 0 or is_ancestor(rig, anchor, bone, simulated):
				continue
			riders.append(bone)
			anchors.append(bodies[anchor])
			offsets.append(rig.get_bone_global_pose(anchor).affine_inverse() * rig.get_bone_global_pose(bone))

	# Breadth-first over the bone tree; ties go to the parent side.
	static func nearest(rig: Skeleton3D, start: int, simulated: PackedInt32Array) -> int:
		var frontier: PackedInt32Array = PackedInt32Array([start])
		var seen: PackedInt32Array = PackedInt32Array([start])
		while not frontier.is_empty():
			var next: PackedInt32Array = PackedInt32Array()
			for bone: int in frontier:
				var around: PackedInt32Array = PackedInt32Array([rig.get_bone_parent(bone)])
				around.append_array(rig.get_bone_children(bone))
				for other: int in around:
					if other < 0 or seen.has(other):
						continue
					if simulated.has(other):
						return other
					seen.append(other)
					next.append(other)
			frontier = next
		return -1

	# True when `bone` already follows `anchor` through unsimulated parents.
	static func is_ancestor(rig: Skeleton3D, anchor: int, bone: int, simulated: PackedInt32Array) -> bool:
		var up: int = rig.get_bone_parent(bone)
		while up >= 0:
			if up == anchor:
				return true
			if simulated.has(up):
				return false
			up = rig.get_bone_parent(up)
		return false

	func _process_modification_with_delta(_delta: float) -> void:
		# The anchor bone's pose this frame, read from its body as the simulator will apply it.
		var rig: Skeleton3D = get_skeleton()
		var to_rig: Transform3D = rig.global_transform.affine_inverse()
		for index: int in range(riders.size()):
			var anchor: Transform3D = to_rig * anchors[index].global_transform * anchors[index].body_offset.affine_inverse()
			rig.set_bone_global_pose(riders[index], anchor * offsets[index])

static func make_part(rig: Skeleton3D, part: Dictionary, kept: PackedStringArray) -> PhysicalBone3D:
	var bone_name: String = String(part["bone"])
	var bone: int = rig.find_bone(bone_name)
	var along: Vector3 = local_along(rig, part)
	var length: float = along.length()
	# Body frame in bone space: -Z runs down the segment, X is the limb's sideways hinge axis.
	var rest: Basis = rig.get_bone_global_rest(bone).basis
	var lateral: Vector3 = rest.inverse() * (Vector3.UP if bone_name.contains("arm") else Vector3.RIGHT)
	var back: Vector3 = -along.normalized()
	lateral = (lateral - back * lateral.dot(back)).normalized()
	var frame: Basis = Basis(lateral, back.cross(lateral), back)
	var body: PhysicalBone3D = PhysicalBone3D.new()
	body.name = "Body_" + bone_name
	body.bone_name = bone_name
	body.body_offset = Transform3D(frame, along * 0.5)
	body.mass = float(part["mass"])
	body.collision_layer = 0
	body.collision_mask = 1
	body.linear_damp = 0.15
	body.angular_damp = 2.5
	body.friction = 0.9
	var shape: CollisionShape3D = CollisionShape3D.new()
	if part.has("box"):
		var box: BoxShape3D = BoxShape3D.new()
		var size: Vector3 = part["box"] as Vector3
		box.size = Vector3(size.x, size.y, maxf(size.z, length))
		shape.shape = box
	elif bone_name == "Head":
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = float(part["radius"])
		shape.shape = sphere
	else:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = float(part["radius"])
		capsule.height = maxf(length + capsule.radius, capsule.radius * 2.0 + 0.01)
		shape.shape = capsule
		shape.rotation.x = PI / 2.0 # the capsule's Y axis onto the segment's Z
	body.add_child(shape)
	# The joint sits at the bone's head. Cone twist turns about the joint's X and hinges about its
	# Z, so a quarter turn about Y lays X down the segment and Z across it.
	var parent: String = jointed_parent(rig, bone)
	var joint: int = int(part["joint"]) if kept.has(parent) else PhysicalBone3D.JOINT_TYPE_NONE
	body.joint_type = joint
	body.joint_offset = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, length * 0.5))
	if joint == PhysicalBone3D.JOINT_TYPE_CONE:
		body.set("joint_constraints/swing_span", float(part["swing"]))
		body.set("joint_constraints/twist_span", float(part["twist"]))
	elif joint == PhysicalBone3D.JOINT_TYPE_HINGE:
		body.set("joint_constraints/angular_limit_enabled", true)
		body.set("joint_constraints/angular_limit_lower", -float(part["bend"]))
		body.set("joint_constraints/angular_limit_upper", 5.0)
	return body

# The nearest ancestor that has a part, or "" at the pelvis.
static func jointed_parent(rig: Skeleton3D, bone: int) -> String:
	var up: int = rig.get_bone_parent(bone)
	while up >= 0:
		var up_name: String = rig.get_bone_name(up)
		for part: Dictionary in PARTS:
			if String(part["bone"]) == up_name:
				return up_name
		up = rig.get_bone_parent(up)
	return ""

# Changes every simulated part's velocity: linear (m/s) and spin (rad/s), whatever its mass.
static func push(simulator: PhysicalBoneSimulator3D, linear: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	for node: Node in simulator.get_children():
		var body: PhysicalBone3D = node as PhysicalBone3D
		body.linear_velocity += linear
		body.angular_velocity += spin

# Each vertex's signed distance to a plane in the current pose, baked into UV2.x of a copy of the
# mesh. The cut shader discards by it, so a cut stays on the body however the bones later move.
static func bake_cut(mesh: MeshInstance3D, rig: Skeleton3D, point: Vector3, normal: Vector3) -> ArrayMesh:
	var to_rig: Transform3D = rig.global_transform.affine_inverse()
	var local_point: Vector3 = to_rig * point
	var local_normal: Vector3 = (to_rig.basis.inverse().transposed() * normal).normalized()
	# Per bind: distance = a . vertex + c for a vertex skinned only by that bind.
	var slopes: PackedVector3Array = PackedVector3Array()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	for bind: int in range(mesh.skin.get_bind_count()):
		var bone: int = mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = rig.find_bone(mesh.skin.get_bind_name(bind))
		var skinning: Transform3D = rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind)
		slopes.append(skinning.basis.transposed() * local_normal)
		offsets.append(local_normal.dot(skinning.origin) - local_normal.dot(local_point))
	var result: ArrayMesh = ArrayMesh.new()
	for surface: int in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / maxi(vertices.size(), 1)
		var cut: PackedVector2Array = PackedVector2Array()
		cut.resize(vertices.size())
		for index: int in range(vertices.size()):
			var vertex: Vector3 = vertices[index]
			var distance: float = 0.0
			for slot: int in range(per):
				var weight: float = weights[index * per + slot]
				if weight > 0.0:
					var bind: int = bones[index * per + slot]
					distance += weight * (slopes[bind].dot(vertex) + offsets[bind])
			cut[index] = Vector2(distance, 0.0)
		arrays[Mesh.ARRAY_TEX_UV2] = cut
		var flags: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		for channel: int in range(4):
			var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + channel * Mesh.ARRAY_FORMAT_CUSTOM_BITS
			flags |= mesh.mesh.surface_get_format(surface) & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
		result.add_surface_from_arrays(mesh.mesh.surface_get_primitive_type(surface), arrays, [], {}, flags)
		result.surface_set_material(surface, mesh.get_active_material(surface))
	return result
