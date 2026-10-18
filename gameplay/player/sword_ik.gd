class_name SwordIK
extends SkeletonModifier3D

# Analytic two-bone IK. Targets/poles are in world space; bone poses are skeleton-local.
# Hand bones on both rigs: +Y runs along the fingers, +Z from the pinky side to the thumb
# side, and the palm faces -X on the right hand and +X on the left.
const GRIP_ALONG: Array[float] = [0.02, 0.12] # right and left hilt points, sword-local z; about a hand's width apart
const PALM_DEPTH: float = 0.04 # wrist bone to the hilt axis, across the palm
const PALM_LENGTH: float = 0.06 # wrist bone to where the fingers wrap
var visual: CharacterVisual
var arms: Array[PackedInt32Array] = []
var legs: Array[PackedInt32Array] = []
var last_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var last_hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

func configure(owner_visual: CharacterVisual) -> void:
	visual = owner_visual
	var rig: Skeleton3D = get_skeleton()
	for side: String in ["r", "l"]:
		arms.append(PackedInt32Array([rig.find_bone("upperarm_" + side), rig.find_bone("lowerarm_" + side), rig.find_bone("hand_" + side)]))
	for side: String in ["l", "r"]:
		legs.append(PackedInt32Array([rig.find_bone("thigh_" + side), rig.find_bone("calf_" + side), rig.find_bone("foot_" + side)]))

func grip_frame(side: int) -> Transform3D:
	# Wrist transform for a hammer grip: thumb side toward the blade, palm against the hilt.
	var sword_basis: Basis = visual.sword.global_basis.orthonormalized()
	var thumb: Vector3 = -sword_basis.z
	var palm: Vector3 = -sword_basis.x if side == 0 else sword_basis.x
	var fingers: Vector3 = palm.cross(thumb) if side == 0 else thumb.cross(palm)
	var hand_basis: Basis = Basis(-palm, fingers, thumb) if side == 0 else Basis(palm, fingers, thumb)
	var hilt_point: Vector3 = visual.sword.to_global(Vector3(0.0, 0.0, GRIP_ALONG[side]))
	return Transform3D(hand_basis, hilt_point - fingers * PALM_LENGTH - palm * PALM_DEPTH)

func _process_modification_with_delta(_delta: float) -> void:
	if visual == null:
		return
	var rig: Skeleton3D = get_skeleton()
	# Build a fresh procedural pose each pass; modifiers restore the source pose afterwards.
	rig.reset_bone_poses()
	pose_body(rig)
	pose_legs(rig)
	constrain_grip(rig)
	var weights: Array[float] = [visual.grip_right, visual.grip_left]
	for side: int in range(2):
		var sign: float = 1.0 if side == 0 else -1.0
		var frame: Transform3D = grip_frame(side)
		var rest: Vector3 = visual.to_global(Vector3(0.3 * sign, 0.12, 0.02))
		solve(rig, arms[side], rest.lerp(frame.origin, weights[side]), visual.to_global(Vector3(0.85 * sign, 0.05, 0.2)))
		orient_hand(rig, arms[side][2], frame.basis, weights[side])
		curl_fingers(rig, "r" if side == 0 else "l", weights[side])
		last_hands[side] = rig.global_transform * rig.get_bone_global_pose(arms[side][2]).origin

func pose_body(rig: Skeleton3D) -> void:
	# The whole visual faces the blade; the spine and head turn toward where the camera looks.
	var look: float = clampf(angle_difference(visual.motion.body_yaw, visual.camera_yaw), -1.0, 1.0)
	var lean: Vector2 = visual.motion.lean
	rotate_visual(rig, "pelvis", Basis.from_euler(Vector3(lean.x * 0.4, 0.0, lean.y * 0.4)), Vector3(-lean.y * 0.08, -0.05 - visual.gait_bob - visual.gait_crouch, lean.x * 0.08))
	rotate_visual(rig, "spine_01", Basis.from_euler(Vector3(lean.x * 0.6, look * 0.35, lean.y * 0.6)))
	rotate_visual(rig, "Head", Basis.from_euler(Vector3(visual.camera_pitch * 0.35, look * 0.65, 0.0)))

func rotate_visual(rig: Skeleton3D, bone_name: String, rotation: Basis, shift: Vector3 = Vector3.ZERO) -> void:
	var bone: int = rig.find_bone(bone_name)
	if bone < 0:
		return
	var space: Basis = rig.global_basis.inverse() * visual.global_basis
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	pose.basis = space * rotation * space.inverse() * pose.basis
	pose.origin += space * shift
	rig.set_bone_global_pose(bone, pose)

func pose_legs(rig: Skeleton3D) -> void:
	for index: int in range(legs.size()):
		var target: Vector3 = visual.feet[index] if visual.feet.size() == 2 else visual.foot_home(index)
		var pole: Vector3 = visual.global_position + Vector3(-0.2 if index == 0 else 0.2, -0.2, -1.0).rotated(Vector3.UP, visual.motion.body_yaw)
		solve(rig, legs[index], target, pole)
		var ankle: int = legs[index][2]
		var pose: Transform3D = rig.get_bone_global_pose(ankle)
		var normal: Vector3 = visual.foot_normals[index]
		var rest_world: Basis = rig.global_basis * rig.get_bone_global_rest(ankle).basis
		pose.basis = rig.global_basis.inverse() * Basis(Quaternion(Vector3.UP, normal)) * rest_world
		rig.set_bone_global_pose(ankle, pose)
		last_feet[index] = rig.global_transform * pose.origin

func constrain_grip(rig: Skeleton3D) -> void:
	# Translate the hilt into the gripping arms' reachable region instead of stretching bones.
	var weights: Array[float] = [visual.grip_right, visual.grip_left]
	for iteration: int in range(3):
		for side: int in range(2):
			if weights[side] < 0.95:
				continue
			var bones: PackedInt32Array = arms[side]
			var shoulder: Vector3 = rig.global_transform * rig.get_bone_global_pose(bones[0]).origin
			var elbow: Vector3 = rig.global_transform * rig.get_bone_global_pose(bones[1]).origin
			var hand: Vector3 = rig.global_transform * rig.get_bone_global_pose(bones[2]).origin
			var reach: float = shoulder.distance_to(elbow) + elbow.distance_to(hand) - 0.005
			var offset: Vector3 = grip_frame(side).origin - shoulder
			if offset.length() > reach:
				# Pull the hilt in but keep the blade aimed at its tip, so an anchored tip stays put.
				var tip: Vector3 = visual.sword.to_global(CharacterVisual.BLADE_TIP)
				visual.sword.global_position -= offset.normalized() * (offset.length() - reach)
				var toward_tip: Vector3 = tip - visual.sword.global_position
				if toward_tip.length_squared() > 0.0001 and absf(toward_tip.normalized().y) < 0.99:
					visual.sword.global_basis = Basis.looking_at(toward_tip, Vector3.UP)

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

func orient_hand(rig: Skeleton3D, bone: int, world_basis: Basis, weight: float) -> void:
	var pose: Transform3D = rig.get_bone_global_pose(bone)
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
