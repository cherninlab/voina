class_name MobRagdoll
extends RefCounted

const CAP_SHADER: Shader = preload("res://gameplay/mobs/mob_cap.gdshader")

# Jointed physical bodies for a raider's skeleton, built at runtime under an engine
# PhysicalBoneSimulator3D: a whole-body ragdoll for a death, or the bodies with skin on one side
# of a cut for a bisected half. Bodies sit on layer 0 with mask 1, so they land on the terrain and are
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

# Each vertex's signed distance (metres) to a plane in the current pose, baked into UV2.x of a copy
# of the mesh, and the plane's normal baked into its tangent so it turns with the vertex's bones.
# The cut shader discards by the distance and caps the opening from the two, so a cut stays on the
# body however the bones later move.
static func bake_cut(mesh: MeshInstance3D, rig: Skeleton3D, point: Vector3, normal: Vector3) -> ArrayMesh:
	var to_rig: Transform3D = rig.global_transform.affine_inverse()
	var local_point: Vector3 = to_rig * point
	var local_normal: Vector3 = (to_rig.basis.inverse().transposed() * normal).normalized()
	var metres: float = (rig.global_basis * local_normal).length()
	# Per bind: distance = a . vertex + c for a vertex skinned only by that bind.
	var slopes: PackedVector3Array = PackedVector3Array()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var bases: Array[Basis] = []
	var skinnings: Array[Transform3D] = []
	for bind: int in range(mesh.skin.get_bind_count()):
		var skinning: Transform3D = rig.get_bone_global_pose(bind_bone(mesh.skin, rig, bind)) * mesh.skin.get_bind_pose(bind)
		slopes.append(skinning.basis.transposed() * local_normal)
		offsets.append(local_normal.dot(skinning.origin) - local_normal.dot(local_point))
		bases.append(skinning.basis)
		skinnings.append(skinning)
	var result: ArrayMesh = ArrayMesh.new()
	var caps: Array[Array] = []
	for surface: int in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / maxi(vertices.size(), 1)
		var cut: PackedVector2Array = PackedVector2Array()
		cut.resize(vertices.size())
		var tangents: PackedFloat32Array = PackedFloat32Array()
		tangents.resize(vertices.size() * 4)
		var posed: PackedVector3Array = PackedVector3Array()
		posed.resize(vertices.size())
		for index: int in range(vertices.size()):
			var vertex: Vector3 = vertices[index]
			var distance: float = 0.0
			var blend: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
			for slot: int in range(per):
				var weight: float = weights[index * per + slot]
				if weight > 0.0:
					var bind: int = bones[index * per + slot]
					distance += weight * (slopes[bind].dot(vertex) + offsets[bind])
					blend = Basis(blend.x + bases[bind].x * weight, blend.y + bases[bind].y * weight, blend.z + bases[bind].z * weight)
					posed[index] += skinnings[bind] * vertex * weight
			cut[index] = Vector2(distance * metres, 0.0)
			# The bind-space vector that skinning in this pose turns back onto the plane normal.
			var tangent: Vector3 = (blend.inverse() * local_normal).normalized() if absf(blend.determinant()) > 0.000001 else local_normal
			tangents[index * 4] = tangent.x
			tangents[index * 4 + 1] = tangent.y
			tangents[index * 4 + 2] = tangent.z
			tangents[index * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TEX_UV2] = cut
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var flags: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		for channel: int in range(4):
			var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + channel * Mesh.ARRAY_FORMAT_CUSTOM_BITS
			flags |= mesh.mesh.surface_get_format(surface) & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
		result.add_surface_from_arrays(mesh.mesh.surface_get_primitive_type(surface), arrays, [], {}, flags)
		result.surface_set_material(surface, mesh.get_active_material(surface))
		if mesh.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES and arrays[Mesh.ARRAY_INDEX] != null:
			var cap: Array = cap_arrays(arrays, posed, local_normal)
			if not cap.is_empty():
				caps.append([cap, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0])
	# The faces of the cut, after the mesh's own surfaces so their indices stay put.
	for cap: Array in caps:
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cap[0] as Array, [], {}, int(cap[1]))
		result.surface_set_name(result.get_surface_count() - 1, CAP)
		result.surface_set_material(result.get_surface_count() - 1, cap_material())
	return result

const CAP: String = "cut_cap"
static var cap_shared: ShaderMaterial

static func cap_material() -> ShaderMaterial:
	if cap_shared == null:
		cap_shared = ShaderMaterial.new()
		cap_shared.shader = CAP_SHADER
	return cap_shared

# The solid face where the plane crosses a closed part of the skin. Each triangle the plane crosses
# gives a segment between two edge crossings; the segments chain into loops (edges are matched by
# welded vertex position, so UV seams do not break them), and each closed loop is triangulated in
# the plane. A crossing is skinned like the two vertices of its edge, blended, so the face rides
# the bones with the skin around it.
static func cap_arrays(arrays: Array, posed: PackedVector3Array, normal: Vector3) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var distances: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per: int = bones.size() / maxi(vertices.size(), 1)
	var welded: PackedInt32Array = PackedInt32Array()
	var ids: Dictionary[Vector3i, int] = {}
	for vertex: Vector3 in vertices:
		var key: Vector3i = Vector3i((vertex * 10000.0).round())
		if not ids.has(key):
			ids[key] = ids.size()
		welded.append(ids[key])
	# One crossing per welded edge: where it is, and which vertices and blend it comes from.
	var crossings: Dictionary[Vector2i, int] = {}
	var ends: Array[Vector3i] = [] # vertex a, vertex b, t * 1e6
	var links: Array[PackedInt32Array] = []
	for corner: int in range(0, indices.size() - 2, 3):
		var found: PackedInt32Array = PackedInt32Array()
		for edge: int in range(3):
			var a: int = indices[corner + edge]
			var b: int = indices[corner + (edge + 1) % 3]
			if (distances[a].x > 0.0) == (distances[b].x > 0.0):
				continue
			var key: Vector2i = Vector2i(mini(welded[a], welded[b]), maxi(welded[a], welded[b]))
			if not crossings.has(key):
				crossings[key] = ends.size()
				ends.append(Vector3i(a, b, int(distances[a].x / (distances[a].x - distances[b].x) * 1000000.0)))
				links.append(PackedInt32Array())
			found.append(crossings[key])
		if found.size() == 2 and found[0] != found[1]:
			links[found[0]].append(found[1])
			links[found[1]].append(found[0])
	var side: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = normal.cross(side)
	var cap_vertices: PackedVector3Array = PackedVector3Array()
	var cap_normals: PackedVector3Array = PackedVector3Array()
	var cap_uvs: PackedVector2Array = PackedVector2Array()
	var cap_bones: PackedInt32Array = PackedInt32Array()
	var cap_weights: PackedFloat32Array = PackedFloat32Array()
	var cap_indices: PackedInt32Array = PackedInt32Array()
	var visited: Array[bool] = []
	visited.resize(ends.size())
	for start: int in range(ends.size()):
		if visited[start]:
			continue
		var loop: PackedInt32Array = PackedInt32Array([start])
		visited[start] = true
		var current: int = start
		while true:
			var next: int = -1
			for other: int in links[current]:
				if not visited[other]:
					next = other
					break
			if next < 0:
				break
			visited[next] = true
			loop.append(next)
			current = next
		# Open chains come from open skin (eyebrows, a hole in the mesh); they have no inside to cap.
		if loop.size() < 3 or not links[current].has(start):
			continue
		var flat: PackedVector2Array = PackedVector2Array()
		var base: int = cap_vertices.size()
		for crossing: int in loop:
			var a: int = ends[crossing].x
			var b: int = ends[crossing].y
			var t: float = ends[crossing].z / 1000000.0
			var where: Vector3 = posed[a].lerp(posed[b], t)
			flat.append(Vector2(where.dot(side), where.dot(up)))
			cap_vertices.append(vertices[a].lerp(vertices[b], t))
			var tangent: Vector3 = Vector3(tangents[a * 4], tangents[a * 4 + 1], tangents[a * 4 + 2]).lerp(Vector3(tangents[b * 4], tangents[b * 4 + 1], tangents[b * 4 + 2]), t)
			cap_normals.append(tangent.normalized())
			cap_uvs.append(flat[-1])
			# Blend the two vertices' bone weights and keep the strongest `per`.
			var blend: Dictionary[int, float] = {}
			for pair: Vector2 in [Vector2(a, 1.0 - t), Vector2(b, t)]:
				for slot: int in range(per):
					var weight: float = weights[int(pair.x) * per + slot] * pair.y
					if weight > 0.0:
						var bind: int = bones[int(pair.x) * per + slot]
						blend[bind] = blend.get(bind, 0.0) + weight
			var order: Array = blend.keys()
			order.sort_custom(func(x: int, y: int) -> bool: return blend[x] > blend[y])
			var total: float = 0.0
			for slot: int in range(mini(per, order.size())):
				total += blend[order[slot]]
			for slot: int in range(per):
				cap_bones.append(int(order[slot]) if slot < order.size() else 0)
				cap_weights.append(blend[order[slot]] / total if slot < order.size() else 0.0)
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(flat)
		for corner: int in triangles:
			cap_indices.append(base + corner)
	if cap_indices.is_empty():
		return []
	var cap: Array = []
	cap.resize(Mesh.ARRAY_MAX)
	cap[Mesh.ARRAY_VERTEX] = cap_vertices
	cap[Mesh.ARRAY_NORMAL] = cap_normals
	cap[Mesh.ARRAY_TEX_UV] = cap_uvs
	cap[Mesh.ARRAY_BONES] = cap_bones
	cap[Mesh.ARRAY_WEIGHTS] = cap_weights
	cap[Mesh.ARRAY_INDEX] = cap_indices
	return cap

static func bind_bone(skin: Skin, rig: Skeleton3D, bind: int) -> int:
	var bone: int = skin.get_bind_bone(bind)
	return bone if bone >= 0 else rig.find_bone(skin.get_bind_name(bind))

# Which parts each side of a baked cut simulates: [side +1, side -1]. A side keeps every part with
# skin showing on it, so a lengthwise cut still has a whole spine under its half of the torso.
# Groups of parts still joined by skin on that side are linked through the parts between them;
# groups with no skin between them (a forearm cut off below the elbow) fall as separate pieces.
static func split(cut_meshes: Array[ArrayMesh], originals: Array[MeshInstance3D], rig: Skeleton3D) -> Array[PackedStringArray]:
	var names: PackedStringArray = PackedStringArray()
	for part: Dictionary in PARTS:
		names.append(String(part["bone"]))
	# Every bone counts toward its nearest part at or above it; the root toward the pelvis.
	var owner: PackedInt32Array = PackedInt32Array()
	for bone: int in range(rig.get_bone_count()):
		var up: int = bone
		while up >= 0 and not names.has(rig.get_bone_name(up)):
			up = rig.get_bone_parent(up)
		owner.append(names.find(rig.get_bone_name(up)) if up >= 0 else 0)
	var parents: PackedInt32Array = PackedInt32Array()
	for name: String in names:
		parents.append(names.find(jointed_parent(rig, rig.find_bone(name))))
	var totals: PackedInt32Array = PackedInt32Array()
	totals.resize(names.size())
	var shown: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	for counts: PackedInt32Array in shown:
		counts.resize(names.size())
	var triangles: Array[Dictionary] = [] # per surface: part of each vertex, distances, indices
	for mesh_index: int in range(cut_meshes.size()):
		var skin: Skin = originals[mesh_index].skin
		for surface: int in range(cut_meshes[mesh_index].get_surface_count()):
			if cut_meshes[mesh_index].surface_get_name(surface) == CAP:
				continue
			var arrays: Array = cut_meshes[mesh_index].surface_get_arrays(surface)
			var distances: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per: int = bones.size() / maxi(distances.size(), 1)
			var parts: PackedInt32Array = PackedInt32Array()
			parts.resize(distances.size())
			for index: int in range(distances.size()):
				var best: int = 0
				for slot: int in range(1, per):
					if weights[index * per + slot] > weights[index * per + best]:
						best = slot
				parts[index] = owner[bind_bone(skin, rig, bones[index * per + best])]
				totals[parts[index]] += 1
				shown[0 if distances[index].x > 0.0 else 1][parts[index]] += 1
			triangles.append({"parts": parts, "distances": distances, "indices": arrays[Mesh.ARRAY_INDEX]})
	var result: Array[PackedStringArray] = []
	for side_index: int in range(2):
		var side: float = 1.0 if side_index == 0 else -1.0
		var kept: Array[bool] = []
		var group: PackedInt32Array = PackedInt32Array() # union-find over parts
		for part: int in range(names.size()):
			kept.append(shown[side_index][part] >= maxi(6, int(totals[part] * 0.02)))
			group.append(part)
		for part: int in range(names.size()):
			if kept[part] and parents[part] >= 0 and kept[parents[part]]:
				group[find(group, part)] = find(group, parents[part])
		var roots: PackedInt32Array = PackedInt32Array()
		for part: int in range(names.size()):
			if kept[part] and not roots.has(find(group, part)):
				roots.append(find(group, part))
		for entry: Dictionary in triangles if roots.size() > 1 else []:
			var parts: PackedInt32Array = entry["parts"]
			var distances: PackedVector2Array = entry["distances"]
			var indices: PackedInt32Array = entry["indices"]
			for corner: int in range(0, indices.size() - 2, 3):
				var a: int = indices[corner]
				var b: int = indices[corner + 1]
				var c: int = indices[corner + 2]
				if distances[a].x * side <= 0.0 or distances[b].x * side <= 0.0 or distances[c].x * side <= 0.0:
					continue
				for pair: Vector2i in [Vector2i(parts[a], parts[b]), Vector2i(parts[b], parts[c])]:
					if kept[pair.x] and kept[pair.y] and find(group, pair.x) != find(group, pair.y):
						link(pair.x, pair.y, parents, kept, group)
		var chosen: PackedStringArray = PackedStringArray()
		for part: int in range(names.size()):
			if kept[part]:
				chosen.append(names[part])
		result.append(chosen)
	return result

static func find(group: PackedInt32Array, part: int) -> int:
	while group[part] != part:
		part = group[part]
	return part

# Keeps every part on the tree path between two parts and joins them all into one group.
static func link(a: int, b: int, parents: PackedInt32Array, kept: Array[bool], group: PackedInt32Array) -> void:
	var above: PackedInt32Array = PackedInt32Array()
	var up: int = a
	while up >= 0:
		above.append(up)
		up = parents[up]
	var path: PackedInt32Array = PackedInt32Array()
	up = b
	while up >= 0 and not above.has(up):
		path.append(up)
		up = parents[up]
	for part: int in above.slice(0, above.find(up) + 1 if up >= 0 else above.size()):
		path.append(part)
	for part: int in path:
		kept[part] = true
		group[find(group, part)] = find(group, a)

# The simulated parts grouped into pieces that hang together through joints.
static func pieces(simulator: PhysicalBoneSimulator3D) -> Array[Array]:
	var bodies: Dictionary[String, PhysicalBone3D] = {}
	for node: Node in simulator.get_children():
		bodies[(node as PhysicalBone3D).bone_name] = node as PhysicalBone3D
	var rig: Skeleton3D = simulator.get_parent() as Skeleton3D
	var groups: Dictionary[PhysicalBone3D, Array] = {}
	for body: PhysicalBone3D in bodies.values():
		var top: PhysicalBone3D = body
		while top.joint_type != PhysicalBone3D.JOINT_TYPE_NONE:
			top = bodies[jointed_parent(rig, rig.find_bone(top.bone_name))]
		if not groups.has(top):
			groups[top] = []
		groups[top].append(body)
	var result: Array[Array] = []
	result.assign(groups.values())
	return result
