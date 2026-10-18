class_name MobPuppet
extends SkeletonModifier3D

# Bone springs layered over the animation, so a blow flexes the body like a puppet instead of
# tilting it as one block. A hit spins every spring bone between the pelvis and the struck point
# by the torque the blade's travel exerts about that joint; the bones hanging off that chain
# (head, the other arm) lag the other way. Each bone then swings back on an underdamped spring.
# Rotations live in skeleton space so they turn with the raider.

# name: [frequency (Hz), damping ratio, gain, lag when a parent jerks]
const SPRINGS: Dictionary[String, Array] = {
	"pelvis": [1.3, 0.45, 0.3, 0.0],
	"spine_01": [1.7, 0.35, 0.4, 0.0],
	"spine_02": [1.7, 0.35, 0.4, 0.0],
	"spine_03": [1.8, 0.32, 0.5, 0.0],
	"neck_01": [2.0, 0.3, 0.4, 0.35],
	"Head": [2.0, 0.28, 0.5, 0.5],
	"upperarm_l": [1.2, 0.25, 1.0, 0.6],
	"lowerarm_l": [1.5, 0.25, 1.0, 0.45],
	"upperarm_r": [1.2, 0.25, 1.0, 0.6],
	"lowerarm_r": [1.5, 0.25, 1.0, 0.45],
}
const MAX_ANGLE: float = 1.1
var bones: PackedInt32Array = PackedInt32Array()
var parents: PackedInt32Array = PackedInt32Array() # index into bones of the nearest spring ancestor, or -1
var ends: PackedInt32Array = PackedInt32Array() # a child bone, for the segment a hit can land on
var angles: Array[Vector3] = [] # rotation vectors, skeleton space
var spins: Array[Vector3] = []

func _ready() -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null:
		return
	for bone_name: String in SPRINGS:
		var bone: int = rig.find_bone(bone_name)
		if bone < 0:
			continue
		bones.append(bone)
		angles.append(Vector3.ZERO)
		spins.append(Vector3.ZERO)
	for index: int in range(bones.size()):
		var up: int = rig.get_bone_parent(bones[index])
		var found: int = -1
		while up >= 0 and found < 0:
			found = bones.find(up)
			up = rig.get_bone_parent(up)
		parents.append(found)
		var children: PackedInt32Array = rig.get_bone_children(bones[index])
		ends.append(children[0] if not children.is_empty() else -1)

func settled() -> bool:
	for index: int in range(bones.size()):
		if angles[index].length() > 0.02 or spins[index].length() > 0.2:
			return false
	return true

# point and travel are world space; speed is the blade's speed at contact (m/s).
func hit(point: Vector3, travel: Vector3, speed: float) -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or bones.is_empty() or travel.length_squared() < 0.0001:
		return
	var local_point: Vector3 = rig.to_local(point)
	var force: Vector3 = (rig.global_basis.inverse() * travel).normalized() * clampf(speed, 1.0, 14.0)
	# The struck bone is the spring segment nearest the contact; hands and fingers count as forearm.
	var struck: int = 0
	var best: float = INF
	for index: int in range(bones.size()):
		var start: Vector3 = rig.get_bone_global_pose(bones[index]).origin
		var finish: Vector3 = rig.get_bone_global_pose(ends[index]).origin if ends[index] >= 0 else start + Vector3.UP * 0.2
		if rig.get_bone_name(bones[index]).begins_with("lowerarm"):
			finish = start + (finish - start) * 1.7
		var distance: float = Geometry3D.get_closest_point_to_segment(local_point, start, finish).distance_to(local_point)
		if distance < best:
			best = distance
			struck = index
	var chain: PackedInt32Array = PackedInt32Array()
	var walk: int = struck
	while walk >= 0:
		chain.append(walk)
		walk = parents[walk]
	var kicks: Array[Vector3] = []
	kicks.resize(bones.size())
	kicks.fill(Vector3.ZERO)
	for index: int in chain:
		var lever: Vector3 = local_point - rig.get_bone_global_pose(bones[index]).origin
		if index == struck and ends[index] >= 0:
			# The blade carries the struck part as a whole, even when it lands next to the joint.
			var middle: Vector3 = (rig.get_bone_global_pose(ends[index]).origin - rig.get_bone_global_pose(bones[index]).origin) * 0.5
			if lever.length() < middle.length():
				lever = middle
		kicks[index] = lever.cross(force) / (lever.length_squared() + 0.05) * float(SPRINGS[rig.get_bone_name(bones[index])][2])
	# Bones hanging off the chain keep their inertia: they lag behind the jerk of their parent.
	for index: int in range(bones.size()):
		if chain.has(index) or parents[index] < 0:
			continue
		var lag: float = float(SPRINGS[rig.get_bone_name(bones[index])][3])
		kicks[index] = -kicks[parents[index]] * lag
	for index: int in range(bones.size()):
		spins[index] += kicks[index]

func _process_modification_with_delta(delta: float) -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or bones.is_empty():
		return
	var steps: int = clampi(ceili(delta / (1.0 / 120.0)), 1, 8)
	var step: float = delta / steps
	for index: int in range(bones.size()):
		var spring: Array = SPRINGS[rig.get_bone_name(bones[index])]
		var omega: float = TAU * float(spring[0])
		for repeat: int in range(steps):
			spins[index] += (-angles[index] * omega * omega - spins[index] * 2.0 * float(spring[1]) * omega) * step
			angles[index] += spins[index] * step
		if angles[index].length() > MAX_ANGLE:
			angles[index] = angles[index].normalized() * MAX_ANGLE
			spins[index] *= 0.5
	# Parents come first in SPRINGS, so each bone turns on top of its already bent parent.
	for index: int in range(bones.size()):
		var angle: float = angles[index].length()
		if angle < 0.0005:
			continue
		var pose: Transform3D = rig.get_bone_global_pose(bones[index])
		pose.basis = Basis(angles[index] / angle, angle) * pose.basis
		rig.set_bone_global_pose(bones[index], pose)
