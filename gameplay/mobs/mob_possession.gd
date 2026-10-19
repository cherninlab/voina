class_name MobPossession
extends SkeletonModifier3D

# A possessed villager's body, layered over the clip before the feet plan. From the mob id it picks
# one mild distortion and a few small extras, so every villager of a wave looks differently
# possessed but still human: knees that bend backward, short legs with long arms, a stretched
# crooked neck, a hunch with one arm hanging limp, or long arms. It also poses the stances the
# clips lack (the staring squat, the all-fours crawl, the pounce coil and the leap), tracks the
# nearest player with the head, snaps the head and twitches, and stutters the clip.
# Limbs change length by moving each child bone along its parent (pose translations only), never by
# scale, so every bone stays orthonormal and the death ragdoll and the bisect build unscaled bodies
# from the pose. Skeleton space: +Y up, +Z the body's forward, +X its left; the origin is the ground
# under the capsule.

enum Mode { UPRIGHT, SQUAT, CRAWL, COIL, LEAP }
enum Kind { BACKWARD_KNEES, SHORT_LEGS, CROOKED_NECK, HUNCHED, LONG_ARMS }
const KIND_NAMES: PackedStringArray = ["backward knees", "short legs, long arms", "crooked neck", "hunched, dangling arm", "long arms"]
# How fast each mode takes over once chosen (1/s): rising is slow and uncanny, the leap explosive.
const RATES: PackedFloat32Array = [2.4, 3.5, 6.0, 10.0, 14.0]
const SKINS: Array[Color] = [Color(0.71, 0.7, 0.67), Color(0.64, 0.68, 0.72), Color(0.69, 0.71, 0.61), Color(0.75, 0.71, 0.63)]
const GLOWS: Array[Color] = [Color(0.95, 0.86, 0.5), Color(0.66, 0.84, 1.0), Color(0.76, 1.0, 0.58)]
const DUTY: float = 0.6 # share of a crawl cycle each limb is planted
const CYCLE: float = 0.9 # metres travelled per crawl cycle
const WRIST: float = 0.055 # wrist height over the ground with the palm flat
const TWITCH_BONES: PackedStringArray = ["Head", "neck_01", "spine_03", "clavicle_l", "clavicle_r", "hand_l", "hand_r"]
const MAX_STEP: float = 0.2 # longest frame the stances integrate (s)
const TWITCH_MAX: float = 0.5 # largest twitch (rad)

# The variant, a pure function of the id (configure).
var mob_id: int = 0
var kind: int = Kind.BACKWARD_KNEES
var arm_length: float = 1.0 # upper arm and forearm length factor
var leg_length: float = 1.0 # thigh and shin length factor
var neck_stretch: float = 0.0 # metres added to the neck
var backward_knees: bool = false
var crouch: float = 0.03 # how far the hips sit below the clip's when standing (m)
var hunch: float = 0.1 # forward curl spread over the spine (rad)
var head_roll: float = 0.0 # permanent sideways tilt (rad), + toward the left shoulder
var head_thrust: float = 0.15 # the neck leaning forward, the face kept level (rad)
var shoulder_drop: Vector2 = Vector2.ZERO # left, right (rad)
var dangle: Vector2 = Vector2.ZERO # how limp each arm hangs: left, right
var claw: float = 0.5 # finger curl (rad per joint)
var heel: float = 0.0 # standing on the balls of the feet (rad)
var skin: Color = SKINS[0]
var glow: Color = GLOWS[0]
var bruises: float = 0.5
var streaks: float = 0.2 # share of forearm and shin with dried blood running down
var stutter_rate: float = 0.5 # clip holds per second
var twitch_rate: float = 0.3 # twitches per second
var gait_skew: float = 0.0 # the hind legs a little out of step
var trait_seed: int = 0
var trait_draw: int = 0

# Driven by the visual every frame.
var mode: int = Mode.UPRIGHT
var velocity: Vector3 = Vector3.ZERO # world, measured from the visual's motion
var look_target: Vector3 = Vector3.INF # world; INF looks ahead
var look_weight: float = 0.0
var body: Node3D # the visual
var feet: MobFeet

var weights: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var clock: float = 0.0
var phase: float = 0.0
var stride: float = 0.0
var travel: Vector3 = Vector3.BACK # crawl direction, skeleton space
var head_dir: Vector3 = Vector3(0.0, -0.15, 1.0).normalized()
var snap: Vector3 = Vector3.ZERO # yaw, pitch, roll on top of the head's aim
var snap_goal: Vector3 = Vector3.ZERO
var snap_rate: float = 2.0
var snap_left: float = 3.0
var snap_hold: float = 0.0
var hold_left: float = 0.0
var hold_time: float = 0.0
var catch_left: float = 0.0
var stutter_left: float = 1.0
var twitch_left: float = 2.0
var twitch_angles: Array[Vector3] = []
var twitch_spins: Array[Vector3] = []
var land_left: float = 0.0
var crouch_left: float = 0.0 # after a landing, standing up waits this long (the host's 0.7 s recovery)
var coil_time: float = 0.0
var ground_front: float = 0.0
var ground_back: float = 0.0
var clip_feet: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY] # the clip's foot rotations, before the hips move
var hips_lowered: float = 0.0 # how far the standing stance dropped the hips below the clip's (crouch, landing)
var toes: float = 0.0 # how far the feet are rolled onto their toes (rad)
# For the hand stages: goals in skeleton space, how much the arm IK applies, how much of that is
# planting on the ground, and where the elbows point.
var hand_goals: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var arm_weight: float = 0.0
var planting: float = 0.0
var elbow_dirs: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]

var pelvis: int = -1
var spine: PackedInt32Array = PackedInt32Array()
var neck: int = -1
var head: int = -1
var clavicles: PackedInt32Array = PackedInt32Array()
var upperarms: PackedInt32Array = PackedInt32Array()
var lowerarms: PackedInt32Array = PackedInt32Array()
var hands: PackedInt32Array = PackedInt32Array()
var calves: PackedInt32Array = PackedInt32Array()
var foot_bones: PackedInt32Array = PackedInt32Array()
var fingers: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var finger_hinges: Array[Array] = [[], []] # local curl axis per finger bone
var thumbs: PackedInt32Array = PackedInt32Array()
var twitch_bones: PackedInt32Array = PackedInt32Array()
var torso: float = 0.5 # pelvis to shoulders (m)
var reach: float = 0.5 # shoulder to wrist with this variant's arms (m)
var leg: float = 0.89 # hip to ankle with this variant's legs (m)
var ankle: float = 0.08 # ankle height over a flat foot's sole
var heel_lever: Vector3 = Vector3(0.0, 0.07, -0.14) # the ankle seen from the ball of the foot

# 32-bit integer mix (lowbias32): consecutive ids land far apart. Separate from
# HostileMob.is_female's multiplicative hash, so body and possession vary independently.
static func hash32(value: int) -> int:
	var x: int = value & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x846CA68B) & 0xFFFFFFFF
	return x ^ (x >> 16)

# The distortion every peer shows for this id. The main kind cycles with the id, so any five
# consecutive villagers (a wave and its replacements) show all five; the rest comes from the hash.
func configure(id: int) -> void:
	mob_id = id
	kind = posmod(id - 1, Kind.size())
	trait_seed = hash32(id * 7919 + 104729)
	trait_draw = 0
	var side: float = 1.0 if pick(0.0, 1.0) < 0.5 else -1.0
	head_roll = side * pick(0.05, 0.12)
	arm_length = 1.0 + pick(0.0, 0.05)
	hunch = pick(0.06, 0.14)
	head_thrust = pick(0.1, 0.22)
	crouch = pick(0.02, 0.05)
	shoulder_drop = Vector2(pick(0.0, 0.07), pick(0.0, 0.07))
	match kind:
		Kind.BACKWARD_KNEES:
			backward_knees = true
			crouch = pick(0.035, 0.05)
			heel = pick(0.26, 0.36)
			hunch += 0.05
		Kind.SHORT_LEGS:
			leg_length = pick(0.87, 0.9)
			arm_length = pick(1.12, 1.17)
			backward_knees = pick(0.0, 1.0) < 0.3
			crouch = 0.035 if backward_knees else crouch
		Kind.CROOKED_NECK:
			neck_stretch = pick(0.035, 0.045)
			head_roll = side * pick(0.26, 0.36)
			head_thrust += 0.08
			# The shoulder under the tilted head hikes; the other drops.
			shoulder_drop[0 if side < 0.0 else 1] = pick(0.12, 0.2)
		Kind.HUNCHED:
			hunch = pick(0.4, 0.48)
			head_thrust += 0.1
			var limp: int = 0 if pick(0.0, 1.0) < 0.5 else 1
			dangle[limp] = pick(0.8, 0.9)
			shoulder_drop[limp] = pick(0.15, 0.22)
			head_roll = (1.0 if limp == 0 else -1.0) * pick(0.1, 0.18)
		Kind.LONG_ARMS:
			arm_length = pick(1.16, 1.2)
			neck_stretch = pick(0.015, 0.025)
			hunch += 0.06
			backward_knees = pick(0.0, 1.0) < 0.25
			crouch = 0.035 if backward_knees else crouch
	# Long arms hang a little limp, so their length shows.
	dangle = dangle.max(Vector2.ONE * clampf((arm_length - 1.0) * 2.5, 0.0, 0.4))
	claw = pick(0.35, 0.65)
	skin = SKINS[mini(int(pick(0.0, SKINS.size())), SKINS.size() - 1)]
	glow = GLOWS[mini(int(pick(0.0, GLOWS.size())), GLOWS.size() - 1)]
	bruises = pick(0.3, 0.8)
	streaks = pick(0.0, 0.35)
	stutter_rate = pick(0.3, 0.8)
	twitch_rate = pick(0.2, 0.45)
	gait_skew = pick(-0.06, 0.06)
	rng.seed = hash32(id * 31 + 7)
	snap_left = rng.randf_range(1.5, 5.0)
	stutter_left = rng.randf_range(0.3, 1.5)
	twitch_left = rng.randf_range(0.5, 3.0)
	clock = rng.randf_range(0.0, 50.0)

# The next trait of this id, uniform in [low, high): each draw hashes the id's seed with its index.
# (RandomNumberGenerator's first draws come out nearly equal for some pairs of seeds.)
func pick(low: float, high: float) -> float:
	trait_draw += 1
	return lerpf(low, high, float(hash32(trait_seed ^ ((trait_draw * 0x9E3779B9) & 0xFFFFFFFF))) / 4294967296.0)

func describe() -> String:
	return "%d %s: arms %.2f legs %.2f neck +%.3f knees %s roll %.2f hunch %.2f" % [mob_id, KIND_NAMES[kind], arm_length, leg_length, neck_stretch, "backward" if backward_knees else "forward", head_roll, hunch]

func _ready() -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null:
		return
	pelvis = rig.find_bone("pelvis")
	for bone_name: String in ["spine_01", "spine_02", "spine_03"]:
		spine.append(rig.find_bone(bone_name))
	neck = rig.find_bone("neck_01")
	head = rig.find_bone("Head")
	for side: String in ["l", "r"]:
		clavicles.append(rig.find_bone("clavicle_" + side))
		upperarms.append(rig.find_bone("upperarm_" + side))
		lowerarms.append(rig.find_bone("lowerarm_" + side))
		hands.append(rig.find_bone("hand_" + side))
		calves.append(rig.find_bone("calf_" + side))
		foot_bones.append(rig.find_bone("foot_" + side))
	# Fingers curl toward the palm, which faces down in the T rest pose: about -Z on the left
	# hand (its fingers point +X), +Z on the right.
	for index: int in range(2):
		var hinge: Vector3 = Vector3(0.0, 0.0, -1.0 if index == 0 else 1.0)
		for finger: String in ["index", "middle", "ring", "pinky"]:
			for joint: int in range(1, 4):
				var bone: int = rig.find_bone("%s_0%d_%s" % [finger, joint, "l" if index == 0 else "r"])
				if bone < 0:
					continue
				fingers[index].append(bone)
				finger_hinges[index].append((rig.get_bone_global_rest(bone).basis.inverse() * hinge).normalized())
		for joint: int in range(1, 4):
			thumbs.append(rig.find_bone("thumb_0%d_%s" % [joint, "l" if index == 0 else "r"]))
	for bone_name: String in TWITCH_BONES:
		twitch_bones.append(rig.find_bone(bone_name))
		twitch_angles.append(Vector3.ZERO)
		twitch_spins.append(Vector3.ZERO)
	torso = rig.get_bone_global_rest(upperarms[0]).origin.y - rig.get_bone_global_rest(pelvis).origin.y
	reach = (rig.get_bone_rest(lowerarms[0]).origin.length() + rig.get_bone_rest(hands[0]).origin.length()) * arm_length
	leg = (rig.get_bone_rest(calves[0]).origin.length() + rig.get_bone_rest(foot_bones[0]).origin.length()) * leg_length
	var foot_rest: Transform3D = rig.get_bone_global_rest(foot_bones[0])
	var ball: Vector3 = rig.get_bone_global_rest(rig.find_bone("ball_l")).origin
	ankle = foot_rest.origin.y
	heel_lever = foot_rest.origin - ball

func cycle_length() -> float:
	return CYCLE * (0.5 + 0.25 * arm_length + 0.25 * leg_length)

# Animation speed factor: mostly a slight drift, sometimes a frame hold and a jerk to catch up.
func clip_speed(delta: float) -> float:
	if hold_left > 0.0:
		hold_left -= delta
		if hold_left <= 0.0:
			catch_left = hold_time * 0.7
		return 0.0
	if catch_left > 0.0:
		catch_left -= delta
		return 2.3
	stutter_left -= delta
	if stutter_left <= 0.0:
		hold_time = rng.randf_range(0.06, 0.17)
		hold_left = hold_time
		stutter_left = rng.randf_range(0.6, 2.4) / maxf(stutter_rate, 0.05)
	return 1.0 + 0.16 * sin(clock * 2.3 + mob_id) * sin(clock * 0.9 + 1.3 * mob_id)

# 0..1: how far the pounce coil has wound up, for the eye flare.
func flare() -> float:
	return clampf(coil_time / 0.45, 0.0, 1.0) * weights[Mode.COIL]

func _process_modification_with_delta(delta: float) -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or pelvis < 0:
		return
	delta = clampf(delta, 0.0, MAX_STEP) # a hitch must not throw the springs or the gait
	advance(rig, delta)
	stretch(rig)
	stance(rig)
	arms(rig)
	aim_head(rig, delta)
	legs(rig)
	twitch(rig, delta)

func advance(rig: Skeleton3D, delta: float) -> void:
	clock += delta
	# Out of a leap the body lands quickly, whatever comes next.
	# Leaving the leap lands it: the hips dip and the spine curls for a moment, and a villager
	# told to stand lands in a crouch first.
	if mode != Mode.LEAP and weights[Mode.LEAP] > 0.5 and land_left <= 0.0:
		land_left = 0.4
		crouch_left = 0.7
	land_left = maxf(0.0, land_left - delta)
	crouch_left = 0.0 if mode == Mode.LEAP else maxf(0.0, crouch_left - delta)
	var target: int = Mode.SQUAT if mode == Mode.UPRIGHT and crouch_left > 0.0 else mode
	var blend: float = 1.0 - exp(-(RATES[target] if weights[Mode.LEAP] < 0.3 or target == Mode.LEAP else 9.0) * delta)
	for index: int in range(weights.size()):
		weights[index] = lerpf(weights[index], 1.0 if index == target else 0.0, blend)
	coil_time = coil_time + delta if mode == Mode.COIL else 0.0
	var flat: Vector3 = rig.global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	flat.y = 0.0
	var speed: float = flat.length()
	if speed > 0.1:
		var turned: Vector3 = travel.lerp(flat / speed, 1.0 - exp(-8.0 * delta))
		if turned.length_squared() > 0.0001:
			travel = turned.normalized()
	stride = lerpf(stride, clampf(speed / 1.0, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	phase = fposmod(phase + speed * delta / cycle_length(), 1.0)
	# Head snaps while standing: a jerk far too fast, a hold, then a slow drift back.
	snap_left -= delta
	if snap_left <= 0.0:
		if snap_goal == Vector3.ZERO and weights[Mode.UPRIGHT] > 0.6:
			snap_goal = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.25, 0.2), rng.randf_range(-0.45, 0.45))
			snap_rate = 32.0
			snap_left = rng.randf_range(0.4, 1.4)
		else:
			snap_goal = Vector3.ZERO
			snap_rate = 1.6
			snap_left = rng.randf_range(2.5, 7.0)
	snap = snap.lerp(snap_goal, 1.0 - exp(-snap_rate * delta))
	# Twitches: a sharp kick into a stiff spring on one bone; rare while staring.
	twitch_left -= delta * (0.35 if mode == Mode.SQUAT else (1.3 if mode == Mode.CRAWL else 1.0))
	if twitch_left <= 0.0:
		twitch_left = rng.randf_range(0.4, 2.0) / maxf(twitch_rate, 0.05)
		var which: int = rng.randi() % twitch_bones.size()
		var axis: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		twitch_spins[which] += axis * rng.randf_range(6.0, 12.0) * (1.3 if which == 0 else 1.0)

# Longer or shorter limbs and a longer neck: each child bone slides along its parent.
func stretch(rig: Skeleton3D) -> void:
	for index: int in range(2):
		rig.set_bone_pose_position(lowerarms[index], rig.get_bone_pose_position(lowerarms[index]) * arm_length)
		rig.set_bone_pose_position(hands[index], rig.get_bone_pose_position(hands[index]) * arm_length)
		rig.set_bone_pose_position(calves[index], rig.get_bone_pose_position(calves[index]) * leg_length)
		rig.set_bone_pose_position(foot_bones[index], rig.get_bone_pose_position(foot_bones[index]) * leg_length)
	if neck_stretch > 0.0:
		var position: Vector3 = rig.get_bone_pose_position(head)
		rig.set_bone_pose_position(head, position + position.normalized() * neck_stretch)

static func turn(rig: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	pose.basis = Basis(rotation) * pose.basis
	rig.set_bone_global_pose(bone, pose)

# Turns a bone so its length (+Y) points along direction, by weight.
static func aim(rig: Skeleton3D, bone: int, direction: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	var current: Vector3 = pose.basis.y.normalized()
	var goal: Vector3 = direction.normalized()
	if current.dot(goal) > 0.99995:
		return
	pose.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(current, goal), minf(weight, 1.0))) * pose.basis
	rig.set_bone_global_pose(bone, pose)

func ground_offset(rig: Skeleton3D, point: Vector3) -> float:
	if feet == null or body == null or not body.is_inside_tree():
		return 0.0
	var base: float = body.global_position.y - 0.9
	var hit: Dictionary = feet.probe(rig.global_transform * point, base)
	return float(hit.get("height", base)) - base

# Hips and spine for the blended stance. Each stance sets the hips' height and how far back they
# sit, and a chest pitch split between the hips and a curled spine.
func stance(rig: Skeleton3D) -> void:
	for index: int in range(2):
		clip_feet[index] = rig.get_bone_global_pose(foot_bones[index]).basis
	var w: PackedFloat32Array = weights
	var low: float = w[Mode.SQUAT] + w[Mode.CRAWL] + w[Mode.COIL]
	if low > 0.01:
		ground_back = lerpf(ground_back, ground_offset(rig, Vector3(0.0, 0.0, -0.25)), 0.25)
		ground_front = lerpf(ground_front, ground_offset(rig, Vector3(0.0, 0.0, 0.35)), 0.25)
	var legs_scale: float = leg / 0.89
	# Crawl and coil pitch the chest down until the hands reach the ground with the arms almost straight.
	var crawl_hips: float = 0.68 * legs_scale + ground_back
	var crawl_chest: float = acos(clampf((WRIST + reach * 0.92 + ground_front - crawl_hips) / torso, -1.0, 1.0))
	var coil_hips: float = 0.5 * legs_scale + ground_back
	var coil_chest: float = acos(clampf((WRIST + reach * 0.88 + ground_front - coil_hips) / torso, -1.0, 1.0))
	var hips: Transform3D = rig.get_bone_global_pose(pelvis)
	var rest: Quaternion = rig.get_bone_global_rest(pelvis).basis.get_rotation_quaternion()
	var upright: Vector3 = hips.origin - Vector3.UP * (crouch + 0.89 * (1.0 - leg_length))
	var heights: PackedFloat32Array = PackedFloat32Array([upright.y, 0.6 * legs_scale + ground_back * 0.5, crawl_hips, coil_hips, hips.origin.y + 0.05])
	# The coil rocks back onto the haunches as it winds up, hands still planted ahead.
	var wind: float = clampf(coil_time / 0.4, 0.0, 1.0)
	var backs: PackedFloat32Array = PackedFloat32Array([upright.z, -0.16, -0.2, -0.22 - 0.16 * wind, 0.0])
	var chests: PackedFloat32Array = PackedFloat32Array([0.0, 0.9, crawl_chest, coil_chest, 1.0])
	var curls: PackedFloat32Array = PackedFloat32Array([hunch, hunch + 0.22, 0.28, 0.36, 0.15])
	var height: float = 0.0
	var back: float = 0.0
	var chest: float = 0.0
	var curl: float = 0.0
	for index: int in range(w.size()):
		height += w[index] * heights[index]
		back += w[index] * backs[index]
		chest += w[index] * chests[index]
		curl += w[index] * curls[index]
	# A landing dips the hips and curls the back.
	var dip: float = sin(PI * land_left / 0.4) if land_left > 0.0 else 0.0
	height -= dip * 0.14
	curl += dip * 0.25
	hips_lowered = crouch + dip * 0.14
	# Breathing sway while standing, a tremble that grows through the coil, stillness in the stare.
	var sway: float = (w[Mode.UPRIGHT] + w[Mode.CRAWL] * 0.4) * 0.03
	var tremble: float = w[Mode.COIL] * clampf(coil_time / 0.4, 0.0, 1.0)
	var shake: Vector3 = Vector3(sin(clock * 47.0), sin(clock * 53.0 + 1.0), sin(clock * 41.0 + 2.0)) * tremble
	hips.origin = Vector3(upright.x * w[Mode.UPRIGHT] + shake.x * 0.004, height + shake.y * 0.004, back)
	var pitch: float = chest - curl * (1.0 - w[Mode.UPRIGHT])
	var lean: Quaternion = Quaternion(Vector3.RIGHT, pitch + shake.z * 0.02 + sway * sin(clock * 1.3)) * Quaternion(Vector3.BACK, sway * 0.6 * sin(clock * 0.83 + 1.0))
	hips.basis = Basis(lean * hips.basis.get_rotation_quaternion().slerp(rest, 1.0 - w[Mode.UPRIGHT]))
	rig.set_bone_global_pose(pelvis, hips)
	var shares: PackedFloat32Array = PackedFloat32Array([0.3, 0.35, 0.35])
	for index: int in range(spine.size()):
		turn(rig, spine[index], Quaternion(Vector3.RIGHT, curl * shares[index] + shake.z * 0.01))

func arms(rig: Skeleton3D) -> void:
	var w: PackedFloat32Array = weights
	var stand: float = w[Mode.UPRIGHT]
	# Shoulders: the variant's drop, pushed forward when on all fours or reaching.
	var forward_reach: float = (w[Mode.CRAWL] + w[Mode.COIL]) * 0.35 + w[Mode.LEAP] * 0.5
	var shrug: float = w[Mode.COIL] * 0.3 # shoulder blades up, like a cat about to spring
	for index: int in range(2):
		var sign: float = 1.0 if index == 0 else -1.0
		turn(rig, clavicles[index], Quaternion(Vector3.BACK, sign * (shrug - shoulder_drop[index])) * Quaternion(Vector3.UP, -sign * forward_reach))
	# Arms hang under their own weight: a limp arm always, both in the staring squat. A gentle
	# pendulum keeps a hanging arm alive.
	for index: int in range(2):
		var sign: float = 1.0 if index == 0 else -1.0
		var hang: float = clampf(dangle[index] * (stand + w[Mode.SQUAT]) + 0.9 * w[Mode.SQUAT], 0.0, 1.0)
		var swing: float = 0.12 * sin(clock * 2.2 + index * 1.7) * dangle[index]
		aim(rig, upperarms[index], Vector3(sign * 0.12, -1.0, 0.18 + swing), hang)
		aim(rig, lowerarms[index], Vector3(sign * 0.05, -1.0, 0.42 + swing * 1.5), hang)
		aim(rig, hands[index], Vector3(sign * 0.02, -1.0, 0.25 + swing), hang * 0.7)
	# Claws instead of the clips' fists: fingers straight from the knuckle, hooked at the tips, the
	# thumb left open.
	var curl: float = claw * (stand * 0.8 + w[Mode.SQUAT] * 1.0 + w[Mode.COIL] * 0.5 + w[Mode.CRAWL] * 0.3 + w[Mode.LEAP] * 0.7)
	var joints: PackedFloat32Array = PackedFloat32Array([0.25, 1.0, 0.85])
	for index: int in range(2):
		for finger: int in range(fingers[index].size()):
			var bone: int = fingers[index][finger]
			var hooked: Basis = rig.get_bone_rest(bone).basis * Basis(finger_hinges[index][finger] as Vector3, curl * joints[finger % 3])
			rig.set_bone_pose_rotation(bone, hooked.get_rotation_quaternion())
	for bone: int in thumbs:
		if bone >= 0:
			rig.set_bone_pose_rotation(bone, rig.get_bone_rest(bone).basis.get_rotation_quaternion())
	# Hand goals for the arm IK: planted ahead of the shoulders on all fours, stretched out ahead in a leap.
	arm_weight = clampf(w[Mode.CRAWL] + w[Mode.COIL] + w[Mode.LEAP], 0.0, 1.0)
	planting = (w[Mode.CRAWL] + w[Mode.COIL]) / maxf(arm_weight, 0.001)
	for index: int in range(2):
		var sign: float = 1.0 if index == 0 else -1.0
		var shoulder: Vector3 = rig.get_bone_global_pose(upperarms[index]).origin
		var crawl: Vector3 = Vector3(sign * 0.2, WRIST, shoulder.z + 0.08) + gait(0.5 * index, 0.09)
		var coil: Vector3 = Vector3(sign * 0.21, WRIST, 0.22)
		var leap: Vector3 = shoulder + Vector3(sign * 0.08, 0.12, reach * 0.95)
		var goal: Vector3 = Vector3.ZERO
		if arm_weight > 0.001:
			goal = (crawl * w[Mode.CRAWL] + coil * w[Mode.COIL] + leap * w[Mode.LEAP]) / (w[Mode.CRAWL] + w[Mode.COIL] + w[Mode.LEAP])
		hand_goals[index] = goal
		elbow_dirs[index] = Vector3(sign * 0.6, 0.15, -1.0).lerp(Vector3(sign * 0.8, -0.6, 0.0), w[Mode.LEAP] / maxf(arm_weight, 0.001))

# One limb's offset in a diagonal crawl gait: planted and sliding back while the body moves over it,
# then lifted and swung forward. Phase offsets pair each hand with the opposite foot.
func gait(offset: float, lift: float) -> Vector3:
	var p: float = fposmod(phase + offset, 1.0)
	var stroke: float = DUTY * cycle_length()
	if p < DUTY:
		return travel * stroke * (0.5 - p / DUTY) * stride
	var s: float = (p - DUTY) / (1.0 - DUTY)
	return travel * stroke * (s * s * (3.0 - 2.0 * s) - 0.5) * stride + Vector3.UP * sin(PI * s) * lift * minf(stride * 2.0, 1.0)

# The head stares: it turns slowly toward the nearest player, or keeps the face level ahead when
# the body pitches, tilted by the variant's crooked roll and thrown by snaps.
func aim_head(rig: Skeleton3D, delta: float) -> void:
	var w: PackedFloat32Array = weights
	var thrust: float = head_thrust + w[Mode.SQUAT] * 0.35 + w[Mode.COIL] * 0.25
	turn(rig, neck, Quaternion(Vector3.RIGHT, thrust))
	var lock: float = clampf(w[Mode.UPRIGHT] * 0.55 + w[Mode.SQUAT] + w[Mode.CRAWL] + w[Mode.COIL] + w[Mode.LEAP] * 0.85, 0.0, 1.0)
	var head_pose: Transform3D = rig.get_bone_global_pose(head)
	var want: Vector3 = Vector3(0.0, -0.18 - w[Mode.SQUAT] * 0.1, 1.0).normalized()
	if look_target.is_finite() and look_weight > 0.0:
		var to: Vector3 = rig.global_transform.affine_inverse() * look_target - head_pose.origin
		if to.length_squared() > 0.01:
			var yaw: float = clampf(atan2(to.x, to.z), -1.3, 1.3)
			var tilt: float = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.8, 0.6)
			var target: Vector3 = Vector3(sin(yaw) * cos(tilt), sin(tilt), cos(yaw) * cos(tilt))
			want = want.lerp(target, look_weight).normalized()
	# Slow, steady tracking: the stare never darts. (want always faces forward, so the blend never
	# passes through zero; the guard only catches a bad target.)
	var angle: float = head_dir.angle_to(want)
	if angle > 0.0001:
		var turned: Vector3 = head_dir.lerp(want, minf(1.0, 1.1 * delta / angle))
		head_dir = turned.normalized() if turned.is_finite() and turned.length_squared() > 0.0001 else want
	var facing: Vector3 = (Quaternion(Vector3.UP, snap.x) * Quaternion(Vector3.RIGHT, -snap.y)) * head_dir
	var roll: float = head_roll * (1.0 + w[Mode.SQUAT] * 0.6) + snap.z
	var goal: Basis = Basis(Quaternion(facing, roll)) * looking(facing)
	var current: Quaternion = head_pose.basis.get_rotation_quaternion()
	var wanted: Quaternion = goal.get_rotation_quaternion()
	# The neck takes part of the turn so the skin does not twist at the head joint.
	var turn_by: Quaternion = wanted * current.inverse()
	turn(rig, neck, Quaternion.IDENTITY.slerp(turn_by, 0.35 * lock))
	head_pose = rig.get_bone_global_pose(head)
	head_pose.basis = Basis(head_pose.basis.get_rotation_quaternion().slerp(wanted, lock))
	rig.set_bone_global_pose(head, head_pose)

static func looking(forward: Vector3) -> Basis:
	var z: Vector3 = forward.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	return Basis(x, z.cross(x), z)

# How far a heel raised by `angle` about the ball of the foot lifts the ankle.
func heel_rise(angle: float) -> float:
	return heel_lever.y * cos(angle) - heel_lever.z * sin(angle) - heel_lever.y

func legs(rig: Skeleton3D) -> void:
	if feet == null:
		return
	var w: PackedFloat32Array = weights
	var stand: float = w[Mode.UPRIGHT]
	toes = stand * heel + w[Mode.SQUAT] * maxf(heel, 0.3) + w[Mode.CRAWL] * 0.75 + w[Mode.COIL] * 0.6 + w[Mode.LEAP] * 0.9
	var hips: Vector3 = rig.get_bone_global_pose(pelvis).origin
	var legs_scale: float = leg / 0.89
	feet.goal_weight = clampf(1.0 - stand, 0.0, 1.0)
	for index: int in range(2):
		var sign: float = 1.0 if index == 0 else -1.0
		# The clip's foot, not the one the pitched hips carried along, rolled onto its toes.
		var foot: Transform3D = rig.get_bone_global_pose(foot_bones[index])
		foot.basis = Basis(Quaternion(Vector3.RIGHT, toes)) * clip_feet[index]
		rig.set_bone_global_pose(foot_bones[index], foot)
		# The standing feet come from the clip, which the lowered hips carried down with them.
		feet.raise[index] = heel_rise(toes) * (1.0 if w[Mode.LEAP] < 0.5 else 0.0) + hips_lowered * stand
		var squat: Vector3 = Vector3(sign * 0.17, ankle, 0.03)
		var coil: Vector3 = Vector3(sign * 0.18, ankle, -0.06)
		var crawl: Vector3 = Vector3(sign * 0.17, ankle, hips.z - 0.4 * legs_scale) + gait(0.5 * (1 - index) + gait_skew, 0.11)
		var leap: Vector3 = hips + Vector3(sign * 0.15, -0.5, -0.42) * legs_scale
		if feet.goal_weight > 0.001:
			var goal: Vector3 = (squat * w[Mode.SQUAT] + crawl * w[Mode.CRAWL] + coil * w[Mode.COIL] + leap * w[Mode.LEAP]) / (1.0 - stand)
			feet.goals[index] = rig.global_transform * goal
		# Knees forward (or backward), out in the squat, down under a crawl or a leap.
		var knee: Vector3 = Vector3(0.0, 0.0, 1.0) * stand + Vector3(sign * 0.4, 0.0, 1.0) * w[Mode.SQUAT] + Vector3(sign * 0.25, -0.5, 1.0) * w[Mode.CRAWL] + Vector3(sign * 0.45, -0.2, 1.0) * w[Mode.COIL] + Vector3(sign * 0.2, -0.6, 1.0) * w[Mode.LEAP]
		if backward_knees:
			knee = Vector3(knee.x, -knee.y, -knee.z)
		feet.pole_dirs[index] = knee if knee.length_squared() > 0.0001 else Vector3.BACK

func twitch(rig: Skeleton3D, delta: float) -> void:
	step_twitches(delta)
	for index: int in range(twitch_bones.size()):
		var angle: float = twitch_angles[index].length()
		if angle > 0.0005 and twitch_bones[index] >= 0:
			turn(rig, twitch_bones[index], Quaternion(twitch_angles[index] / angle, angle))

# The stiff twitch springs, in steps of at most 1/120 s: one long step (a hitch) would make the
# integration unstable and blow the angles up.
func step_twitches(delta: float) -> void:
	var omega: float = TAU * 6.5
	var steps: int = clampi(ceili(delta / (1.0 / 120.0)), 1, 32)
	var step: float = delta / steps
	for index: int in range(twitch_bones.size()):
		for repeat: int in range(steps):
			twitch_spins[index] += (-twitch_angles[index] * omega * omega - twitch_spins[index] * 2.0 * 0.38 * omega) * step
			twitch_angles[index] += twitch_spins[index] * step
		if not twitch_angles[index].is_finite() or not twitch_spins[index].is_finite():
			twitch_angles[index] = Vector3.ZERO
			twitch_spins[index] = Vector3.ZERO
		elif twitch_angles[index].length() > TWITCH_MAX:
			twitch_angles[index] = twitch_angles[index].normalized() * TWITCH_MAX
			twitch_spins[index] *= 0.5

# The arm IK's two stages, after the feet: the planner sets each hand's target (on the ground under
# a crawl or coil) and elbow pole; the aligner, after the solver, lays the palm on the ground.
class Hands extends SkeletonModifier3D:
	var pose: MobPossession
	var planner: Hands # set on the aligning stage
	var ik: TwoBoneIK3D
	var targets: Array[Node3D] = []
	var poles: Array[Node3D] = []
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var heights: Array[float] = [0.0, 0.0]
	var palms: Array[Vector3] = [Vector3.LEFT, Vector3.LEFT] # each hand's palm axis, bone space

	static func install(rig: Skeleton3D, possession: MobPossession) -> Hands:
		var plan: Hands = Hands.new()
		plan.name = "HandPlanner"
		plan.pose = possession
		rig.add_child(plan)
		plan.ik = TwoBoneIK3D.new()
		plan.ik.name = "ArmIK"
		rig.add_child(plan.ik)
		plan.ik.setting_count = 2
		for index: int in range(2):
			var side: String = "l" if index == 0 else "r"
			var target: Node3D = Node3D.new()
			target.name = "HandTarget%d" % index
			target.top_level = true
			plan.add_child(target)
			plan.targets.append(target)
			var pole: Node3D = Node3D.new()
			pole.name = "ElbowPole%d" % index
			pole.top_level = true
			plan.add_child(pole)
			plan.poles.append(pole)
			plan.ik.set_root_bone_name(index, "upperarm_" + side)
			plan.ik.set_middle_bone_name(index, "lowerarm_" + side)
			plan.ik.set_end_bone_name(index, "hand_" + side)
			plan.ik.set_target_node(index, plan.ik.get_path_to(target))
			plan.ik.set_pole_node(index, plan.ik.get_path_to(pole))
			# The palm faces down in the T rest pose.
			plan.palms[index] = (rig.get_bone_global_rest(rig.find_bone("hand_" + side)).basis.inverse() * Vector3.DOWN).normalized()
		plan.ik.active = false
		var align: Hands = Hands.new()
		align.name = "HandAligner"
		align.pose = possession
		align.planner = plan
		rig.add_child(align)
		return plan

	func set_enabled(enabled: bool) -> void:
		for node: Node in get_skeleton().get_children():
			if node is Hands:
				(node as Hands).active = enabled
		ik.active = enabled and pose.arm_weight > 0.001

	func _process_modification_with_delta(delta: float) -> void:
		var rig: Skeleton3D = get_skeleton()
		if pose == null or rig == null:
			return
		if planner != null:
			align(rig)
		else:
			plan(rig, delta)

	func plan(rig: Skeleton3D, delta: float) -> void:
		ik.active = pose.arm_weight > 0.001
		ik.influence = pose.arm_weight
		if not ik.active:
			return
		var follow: float = 1.0 - exp(-18.0 * delta)
		var base: float = pose.body.global_position.y - 0.9 if pose.body != null else rig.global_position.y
		for index: int in range(2):
			var goal: Vector3 = rig.global_transform * pose.hand_goals[index]
			# A planted hand finds the ground under it, like the feet.
			if pose.planting > 0.01 and pose.feet != null and pose.body != null and pose.body.is_inside_tree():
				var hit: Dictionary = pose.feet.probe(goal, base)
				heights[index] = lerpf(heights[index], clampf(float(hit.get("height", base)) - base, -0.4, 0.4), follow)
				normals[index] = normals[index].lerp(hit.get("normal", Vector3.UP) as Vector3, follow).normalized()
				goal.y += heights[index] * pose.planting
			targets[index].global_position = goal
			var shoulder: Vector3 = rig.global_transform * rig.get_bone_global_pose(pose.upperarms[index]).origin
			poles[index].global_position = (shoulder + goal) * 0.5 + rig.global_basis * pose.elbow_dirs[index].normalized() * 0.5

	# Palms flat on the ground, fingers ahead and a little out.
	func align(rig: Skeleton3D) -> void:
		var weight: float = pose.arm_weight * pose.planting
		if weight <= 0.001:
			return
		for index: int in range(2):
			var bone: int = pose.hands[index]
			var hand: Transform3D = rig.get_bone_global_pose(bone)
			var normal: Vector3 = (rig.global_basis.inverse() * planner.normals[index]).normalized()
			var ahead: Vector3 = Vector3(0.3 if index == 0 else -0.3, 0.0, 1.0)
			ahead = (ahead - normal * ahead.dot(normal)).normalized()
			var local_palm: Vector3 = planner.palms[index]
			var local_finger: Vector3 = Vector3.UP
			local_palm = (local_palm - local_finger * local_palm.dot(local_finger)).normalized()
			var from: Basis = Basis(local_palm, local_finger, local_palm.cross(local_finger))
			var to: Basis = Basis(-normal, ahead, (-normal).cross(ahead))
			var flat: Quaternion = (to * from.inverse()).get_rotation_quaternion()
			hand.basis = Basis(hand.basis.get_rotation_quaternion().slerp(flat, weight))
			rig.set_bone_global_pose(bone, hand)
