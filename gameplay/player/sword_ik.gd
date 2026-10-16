class_name SwordIK
extends SkeletonModifier3D

# Analytic two-bone IK. Targets/poles are in world space; bone poses are skeleton-local.
var visual: CharacterVisual
var right_arm: PackedInt32Array
var left_arm: PackedInt32Array
var last_right_hand: Vector3 = Vector3.ZERO
var last_left_hand: Vector3 = Vector3.ZERO

func configure(owner_visual: CharacterVisual) -> void:
	visual = owner_visual
	var rig: Skeleton3D = get_skeleton()
	right_arm = chain(rig, "r")
	left_arm = chain(rig, "l")

func chain(rig: Skeleton3D, side: String) -> PackedInt32Array:
	return PackedInt32Array([rig.find_bone("upperarm_" + side), rig.find_bone("lowerarm_" + side), rig.find_bone("hand_" + side)])

func _process_modification_with_delta(_delta: float) -> void:
	if visual == null:
		return
	var rig: Skeleton3D = get_skeleton()
	var sword_pose: Transform3D = visual.sword.global_transform
	var right_target: Vector3 = sword_pose * Vector3(0.065, 0, 0.06)
	var left_target: Vector3 = sword_pose * Vector3(-0.065, 0, 0.23)
	var left_rest: Vector3 = visual.to_global(Vector3(-0.3, 0.12, 0.02))
	left_target = left_rest.lerp(left_target, visual.support_hand)
	solve(rig, right_arm, right_target, visual.to_global(Vector3(0.85, 0.05, 0.2)))
	solve(rig, left_arm, left_target, visual.to_global(Vector3(-0.85, 0.05, 0.2)))
	orient_hand(rig, right_arm[2], sword_pose.basis, false, 1.0)
	orient_hand(rig, left_arm[2], sword_pose.basis, true, visual.support_hand)
	curl_fingers(rig, "r", 1.0)
	curl_fingers(rig, "l", visual.support_hand)
	last_right_hand = rig.global_transform * rig.get_bone_global_pose(right_arm[2]).origin
	last_left_hand = rig.global_transform * rig.get_bone_global_pose(left_arm[2]).origin

func solve(rig: Skeleton3D, bones: PackedInt32Array, target_world: Vector3, pole_world: Vector3) -> void:
	if bones.size() != 3 or bones[0] < 0 or bones[1] < 0 or bones[2] < 0:
		return
	var root_pose: Transform3D = rig.get_bone_global_pose(bones[0])
	var elbow: Vector3 = rig.get_bone_global_pose(bones[1]).origin
	var wrist: Vector3 = rig.get_bone_global_pose(bones[2]).origin
	var upper_length: float = root_pose.origin.distance_to(elbow)
	var lower_length: float = elbow.distance_to(wrist)
	var offset: Vector3 = rig.to_local(target_world) - root_pose.origin
	var distance: float = clampf(offset.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var axis: Vector3 = offset.normalized() if offset.length_squared() > 0.000001 else Vector3.DOWN
	var pole: Vector3 = rig.to_local(pole_world) - root_pose.origin
	var bend: Vector3 = pole - axis * pole.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP)
	bend = bend.normalized()
	var along: float = (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height: float = sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var desired_elbow: Vector3 = root_pose.origin + axis * along + bend * height
	align_bone(rig, bones[0], elbow - root_pose.origin, desired_elbow - root_pose.origin)
	elbow = rig.get_bone_global_pose(bones[1]).origin
	wrist = rig.get_bone_global_pose(bones[2]).origin
	align_bone(rig, bones[1], wrist - elbow, root_pose.origin + axis * distance - elbow)

func align_bone(rig: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	rig.set_bone_global_pose(bone, pose)

func orient_hand(rig: Skeleton3D, bone: int, sword_basis: Basis, left: bool, weight: float) -> void:
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	var x_axis: Vector3 = sword_basis.z * (-1.0 if left else 1.0)
	var y_axis: Vector3 = sword_basis.x * (1.0 if left else -1.0)
	var world_basis: Basis = Basis(x_axis, y_axis, x_axis.cross(y_axis))
	var desired: Basis = rig.global_basis.inverse() * world_basis
	pose.basis = pose.basis.orthonormalized().slerp(desired.orthonormalized(), weight)
	rig.set_bone_global_pose(bone, pose)

func curl_fingers(rig: Skeleton3D, side: String, weight: float) -> void:
	for finger: String in ["index", "middle", "ring", "pinky"]:
		for segment: int in range(1, 4):
			var bone: int = rig.find_bone("%s_%02d_%s" % [finger, segment, side])
			if bone >= 0:
				var rest: Quaternion = rig.get_bone_rest(bone).basis.get_rotation_quaternion()
				rig.set_bone_pose_rotation(bone, rest * Quaternion(Vector3.RIGHT, -1.15 * weight))
