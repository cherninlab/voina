class_name MobFeet
extends SkeletonModifier3D

# Foot planting over the raider's clips, the way the player's legs find the ground: each animated
# foot keeps its height above the terrain under it, the hips drop so the lower foot can reach, and
# an engine TwoBoneIK3D bends the legs to the targets. A second MobFeet after the solver tilts each
# foot onto the ground's slope. Rays only see layer 1 statics; actors' capsules are skipped.
# A possessed villager's own stances (MobPossession) can steer each foot to a goal instead of the
# clip's foot, raise it onto its toes and send the knee another way, backward for reversed knees.

const LEGS: Array[Array] = [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]
const REACH: float = 0.4 # the most a foot rises or the hips drop
const MAX_TILT: float = 0.6
var body: Node3D # the visual; its origin sits 0.9 m above the capsule's bottom
var planner: MobFeet # set on the aligning stage
var ik: TwoBoneIK3D
var legs: Array[PackedInt32Array] = []
var pelvis: int = -1
var targets: Array[Node3D] = []
var poles: Array[Node3D] = []
var lifts: Array[float] = [0.0, 0.0]
var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
var foot_bases: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY] # animated foot rotations, skeleton space
var drop: float = 0.0
var primed: bool = false
# World positions the feet reach for instead of the animated feet, by goal_weight; their heights
# count from the ground under the capsule, so the terrain under each still lifts or lowers it.
var goals: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var goal_weight: float = 0.0
var raise: Array[float] = [0.0, 0.0] # extra target height, such as an ankle lifted by a raised heel
var pole_dirs: Array[Vector3] = [Vector3.BACK, Vector3.BACK] # where each knee points, skeleton space (+Z forward)

# Adds planner, solver and aligner under the skeleton, after any modifiers already there.
static func install(rig: Skeleton3D, visual: Node3D) -> MobFeet:
	var plan: MobFeet = MobFeet.new()
	plan.name = "FootPlanner"
	plan.body = visual
	rig.add_child(plan)
	plan.ik = TwoBoneIK3D.new()
	plan.ik.name = "LegIK"
	rig.add_child(plan.ik)
	plan.ik.setting_count = 2
	for index: int in range(2):
		var target: Node3D = Node3D.new()
		target.name = "FootTarget%d" % index
		target.top_level = true
		plan.add_child(target)
		plan.targets.append(target)
		var pole: Node3D = Node3D.new()
		pole.name = "KneePole%d" % index
		pole.top_level = true
		plan.add_child(pole)
		plan.poles.append(pole)
		plan.ik.set_root_bone_name(index, LEGS[index][0])
		plan.ik.set_middle_bone_name(index, LEGS[index][1])
		plan.ik.set_end_bone_name(index, LEGS[index][2])
		plan.ik.set_target_node(index, plan.ik.get_path_to(target))
		plan.ik.set_pole_node(index, plan.ik.get_path_to(pole))
		plan.legs.append(PackedInt32Array([rig.find_bone(LEGS[index][0]), rig.find_bone(LEGS[index][1]), rig.find_bone(LEGS[index][2])]))
	plan.pelvis = rig.find_bone("pelvis")
	var align: MobFeet = MobFeet.new()
	align.name = "FootAligner"
	align.planner = plan
	rig.add_child(align)
	return plan

func set_enabled(enabled: bool) -> void:
	active = enabled
	ik.active = enabled
	for node: Node in get_skeleton().get_children():
		if node is MobFeet:
			(node as MobFeet).active = enabled

func _process_modification_with_delta(delta: float) -> void:
	var rig: Skeleton3D = get_skeleton()
	if planner != null:
		align(rig)
	elif body != null and legs.size() == 2 and pelvis >= 0:
		plan(rig, delta)

func plan(rig: Skeleton3D, delta: float) -> void:
	var base: float = body.global_position.y - 0.9
	var follow: float = 1.0 if not primed else 1.0 - exp(-18.0 * delta)
	primed = true
	var feet: Array[Vector3] = []
	for index: int in range(2):
		var foot: Transform3D = rig.get_bone_global_pose(legs[index][2])
		foot_bases[index] = foot.basis
		var animated: Vector3 = rig.global_transform * foot.origin
		feet.append(animated.lerp(goals[index], goal_weight) if goal_weight > 0.0 else animated)
		var ground: Dictionary = probe(feet[index], base)
		var want: float = clampf(float(ground.get("height", base)) - base, -REACH, REACH)
		lifts[index] = lerpf(lifts[index], want, follow)
		# Normalized lerp, not slerp: Vector3.slerp builds its axis from the cross product, and for
		# the nearly parallel normals of a settled foot that axis is off unit length (engine error).
		normals[index] = normals[index].lerp(ground.get("normal", Vector3.UP) as Vector3, follow).normalized()
	# Stances with goals already set their hips for the ground they stand on.
	drop = lerpf(drop, minf(0.0, minf(lifts[0], lifts[1])) * (1.0 - goal_weight), follow)
	var hips: Transform3D = rig.get_bone_global_pose(pelvis)
	hips.origin += rig.global_basis.inverse() * Vector3.UP * drop
	rig.set_bone_global_pose(pelvis, hips)
	for index: int in range(2):
		targets[index].global_position = feet[index] + Vector3.UP * (lifts[index] + raise[index])
		# The knee is pushed toward its pole from the animated knee or, for a goal the clip knows
		# nothing about, from the middle of the leg.
		var knee: Vector3 = rig.global_transform * rig.get_bone_global_pose(legs[index][1]).origin
		var hip: Vector3 = rig.global_transform * rig.get_bone_global_pose(legs[index][0]).origin
		var middle: Vector3 = knee.lerp((hip + targets[index].global_position) * 0.5, goal_weight)
		poles[index].global_position = middle + rig.global_basis * pole_dirs[index].normalized() * 0.6

func align(rig: Skeleton3D) -> void:
	for index: int in range(2):
		var bone: int = planner.legs[index][2]
		var pose: Transform3D = rig.get_bone_global_pose(bone)
		var up: Vector3 = rig.global_basis.inverse() * Vector3.UP
		var normal: Vector3 = rig.global_basis.inverse() * planner.normals[index]
		var tilt: Quaternion = Quaternion(up.normalized(), normal.normalized())
		if tilt.get_angle() > MAX_TILT:
			tilt = Quaternion(tilt.get_axis(), MAX_TILT)
		pose.basis = Basis(tilt) * planner.foot_bases[index]
		rig.set_bone_global_pose(bone, pose)

func probe(foot: Vector3, base: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(foot.x, base + REACH + 0.15, foot.z), Vector3(foot.x, base - REACH - 0.15, foot.z), 1)
	var skipped: Array[RID] = []
	if body.get_parent() is CollisionObject3D:
		skipped.append((body.get_parent() as CollisionObject3D).get_rid())
	for attempt: int in range(4):
		query.exclude = skipped
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if hit["collider"] is CharacterBody3D or hit["collider"] is RigidBody3D:
			skipped.append(hit["rid"] as RID)
			continue
		var normal: Vector3 = hit["normal"] as Vector3
		return {"height": (hit["position"] as Vector3).y, "normal": normal if normal.y > 0.5 else Vector3.UP}
	return {}
