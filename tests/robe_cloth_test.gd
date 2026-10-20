extends Node3D

# The hooded cultist's robe (RobeCloth, T-110): alive it sways with the jog and stays outside the
# legs, finite, without stretching apart; it settles when the cultist stops; a death and a bisect
# make it fall onto the ground and settle within two seconds, with the ragdolls, caps and halves
# intact. Run at a fixed frame rate: --fixed-fps 60.
# With `-- --perf` (no --fixed-fps): the frame time with five cultists jogging round a circle and two
# cut ones, with the robe's modifiers on, off and on again. Headless, frames run uncapped, so the
# difference is the robe's CPU cost; rendered, it includes drawing (often capped by the display).
const VISUAL: GDScript = preload("res://gameplay/mobs/mob_visual.gd")
const JOG: float = 2.7 # RaiderMob.RUN_SPEED
# The leg mesh's own reach from its bones (m): the thigh's, the calf's (the knee is narrower).
const THIGH: float = 0.085
const CALF: float = 0.06
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("ROBE_FAIL: " + message)

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func cultist(location: Vector3) -> Node3D:
	var body: Node3D = VISUAL.new()
	body.set("raider", true)
	body.set("cultist", true)
	body.position = location
	add_child(body)
	return body

# The final pose (after every modifier) of a skeleton, world space; held only during its update.
func posed(rig: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var capture: Callable = func() -> void:
		for bone: int in range(rig.get_bone_count()):
			poses.append(rig.global_transform * rig.get_bone_global_pose(bone))
	rig.skeleton_updated.connect(capture, CONNECT_ONE_SHOT)
	await rig.skeleton_updated
	return poses

# Every skirt joint and hem tip, world space: column by column, hips to hem.
func skirt(rig: Skeleton3D, poses: Array[Transform3D]) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for column: int in range(RobeCloth.COLUMNS):
		for joint: int in range(RobeCloth.JOINTS):
			points.append(poses[rig.find_bone(RobeCloth.bone_name(column, joint))].origin)
		var last: Transform3D = poses[rig.find_bone(RobeCloth.bone_name(column, RobeCloth.JOINTS - 1))]
		points.append(last.origin + last.basis.y.normalized() * RobeCloth.HEM)
	return points

func finite(points: PackedVector3Array) -> bool:
	for point: Vector3 in points:
		if not point.is_finite() or point.length() > 1000.0:
			return false
	return true

# The widest gap between neighbouring columns at the hem, relative to the rest gap.
func hem_spread(points: PackedVector3Array, rest: float) -> float:
	var widest: float = 0.0
	var per: int = RobeCloth.JOINTS + 1
	for column: int in range(RobeCloth.COLUMNS):
		var a: Vector3 = points[column * per + per - 1]
		var b: Vector3 = points[((column + 1) % RobeCloth.COLUMNS) * per + per - 1]
		widest = maxf(widest, a.distance_to(b) / rest)
	return widest

# How far points stay outside the leg mesh (negative: inside).
func outside(rig: Skeleton3D, poses: Array[Transform3D], points: PackedVector3Array) -> float:
	var nearest: float = INF
	for limb: Array in [["thigh_l", "calf_l", THIGH], ["calf_l", "foot_l", CALF], ["thigh_r", "calf_r", THIGH], ["calf_r", "foot_r", CALF]]:
		var a: Vector3 = poses[rig.find_bone(String(limb[0]))].origin
		var b: Vector3 = poses[rig.find_bone(String(limb[1]))].origin
		for point: Vector3 in points:
			nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)) - float(limb[2]))
	return nearest

# How far the skirt's joints and the points between them stay outside the leg mesh (negative:
# inside), measured to the bone axes less each limb's own thickness.
func clearance(rig: Skeleton3D, poses: Array[Transform3D], points: PackedVector3Array) -> float:
	var nearest: float = INF
	var per: int = RobeCloth.JOINTS + 1
	for limb: Array in [["thigh_l", "calf_l", THIGH], ["calf_l", "foot_l", CALF], ["thigh_r", "calf_r", THIGH], ["calf_r", "foot_r", CALF]]:
		var a: Vector3 = poses[rig.find_bone(String(limb[0]))].origin
		var b: Vector3 = poses[rig.find_bone(String(limb[1]))].origin
		for column: int in range(RobeCloth.COLUMNS):
			# The hip joint is pinned; from the first bend down the cloth must keep clear.
			for joint: int in range(1, per):
				for t: float in [0.0, 0.5]:
					var point: Vector3 = points[column * per + joint].lerp(points[column * per + mini(joint + 1, per - 1)], t)
					nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)) - float(limb[2]))
	return nearest

func run() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	add_child(floor_body)
	if OS.get_cmdline_user_args().has("--perf"):
		await perf()
		get_tree().quit()
		return
	await alive()
	await death()
	await cut()
	if not failed:
		print("ROBE_OK: standing robe tented round the legs by its shader down to the feet, nothing simulated; drapes on the ground within two seconds after a death and a bisect, legs kept inside on corpses and halves")
	get_tree().quit(1 if failed else 0)

func alive() -> void:
	var body: Node3D = cultist(Vector3(0, 0.9, 10))
	await frames(2)
	var cloth: RobeCloth = body.get("cloth") as RobeCloth
	var rig: Skeleton3D = body.get("skeleton") as Skeleton3D
	check(cloth != null, "The cultist wears the robe")
	if cloth == null:
		return
	check(rig.get_child(rig.get_child_count() - 1) == cloth.push and cloth.push.get_index() == cloth.get_index() + 1 and cloth.stride.get_index() == cloth.get_index() - 1, "The robe runs after every other modifier: stride, springs, push")
	check(cloth.gait.get_index() < (rig.get_node("FootPlanner") as Node).get_index(), "The robe's shorter stride comes before foot planting")
	check(not cloth.active and not cloth.stride.active and cloth.push.tent == 1.0, "Standing, nothing is simulated: the shader tents the robe")
	check(rig.find_bone("thigh_l") >= 0 and rig.find_bone("foot_r") >= 0, "The legs are back under the robe")
	var garments: MeshInstance3D = cloth.push.garments
	var shaded: bool = garments != null
	for surface: int in range(garments.mesh.get_surface_count() if shaded else 0):
		var material: ShaderMaterial = garments.get_surface_override_material(surface) as ShaderMaterial
		shaded = shaded and material != null and material.shader == RobeCloth.PUSH_SHADER
	check(shaded, "Every garment surface draws with the robe shader")
	await frames(60)
	# Jog toward -Z (the visual's forward) for three seconds.
	body.call("show_state", 1, 60, false, false)
	var worst_clear: float = INF
	var worst_track: float = 0.0
	var hem: float = -INF
	var all_finite: bool = true
	for frame: int in range(180):
		body.position += Vector3.FORWARD * JOG / 60.0
		var poses: Array[Transform3D] = await posed(rig)
		var points: PackedVector3Array = skirt(rig, poses)
		all_finite = all_finite and finite(points)
		var to_rig: Transform3D = rig.global_transform.affine_inverse()
		for index: int in range(6): # hips, knees, ankles: the shader's ends are this frame's joints
			worst_track = maxf(worst_track, cloth.push.ends[index].distance_to(to_rig * poses[cloth.push.bones[index]].origin))
		if frame > 20:
			# What the shader does to each skirt vertex, done here to the skirt's joints and the
			# points between them, all the way round.
			var samples: PackedVector3Array = PackedVector3Array()
			var per: int = RobeCloth.JOINTS + 1
			for column: int in range(RobeCloth.COLUMNS):
				for joint: int in range(1, per):
					var here: Vector3 = points[column * per + joint]
					var next: Vector3 = points[((column + 1) % RobeCloth.COLUMNS) * per + joint]
					for share: float in [0.0, 0.25, 0.5, 0.75]:
						samples.append(here.lerp(next, share))
					if joint < per - 1:
						samples.append(here.lerp(points[column * per + joint + 1], 0.5))
					else:
						hem = maxf(hem, here.y - body.global_position.y + 0.9)
			var kept: PackedVector3Array = PackedVector3Array()
			for point: Vector3 in samples:
				kept.append(rig.global_transform * tented(to_rig * point, cloth.push.ends))
			worst_clear = minf(worst_clear, outside(rig, poses, kept))
	check(all_finite, "The jogging robe stays finite")
	check(worst_track < 0.001, "The robe shader gets this frame's legs (off by %.4f m)" % worst_track)
	check(worst_clear > 0.0, "Tented, the robe stays outside the striding legs (closest %.3f m outside)" % worst_clear)
	check(hem < 0.2, "The hem hangs down to the feet (highest %.3f m above the ground)" % hem)
	print("ROBE_JOG: tented robe %.3f m outside the legs at the closest, hem at most %.3f m up" % [worst_clear, hem])
	body.queue_free()

# robe_shape.gdshaderinc's standing tent, for one point in the garment mesh's space.
func tent_reach(a: Vector3, b: Vector3, reach: float, center: Vector2, direction: Vector2, height: float) -> float:
	var best: float = -1.0
	for end: Vector3 in [a, b]:
		if end.y >= height:
			best = maxf(best, Vector2(end.x, end.z).dot(direction) - center.dot(direction) - 0.12 * (end.y - height))
	if (a.y - height) * (b.y - height) < 0.0:
		var crossing: Vector3 = a.lerp(b, (height - a.y) / (b.y - a.y))
		best = maxf(best, (Vector2(crossing.x, crossing.z) - center).dot(direction))
	var upright: float = maxf(absf((b - a).normalized().y), 0.5)
	return -1.0 if best < 0.0 else best + reach / upright + 0.045

func tented(point: Vector3, ends: PackedVector3Array) -> Vector3:
	var center: Vector2 = (Vector2(ends[0].x, ends[0].z) + Vector2(ends[3].x, ends[3].z)) * 0.5
	var hips: float = (ends[0].y + ends[3].y) * 0.5
	var strength: float = clampf((hips - point.y) / 0.05, 0.0, 1.0)
	var offset: Vector2 = Vector2(point.x, point.z) - center
	var radius: float = offset.length()
	if strength <= 0.0 or radius < 0.0001:
		return point
	var direction: Vector2 = offset / radius
	var reach: float = maxf(maxf(tent_reach(ends[0], ends[1], 0.12, center, direction, point.y), tent_reach(ends[1], ends[2], 0.1, center, direction, point.y)), maxf(tent_reach(ends[3], ends[4], 0.12, center, direction, point.y), tent_reach(ends[4], ends[5], 0.1, center, direction, point.y)))
	var blend: float = maxf(0.06 - absf(reach - radius), 0.0) / 0.06
	var wanted: float = maxf(reach, radius) + blend * blend * 0.06 * 0.25
	var moved: Vector2 = center + direction * lerpf(radius, wanted, strength)
	return Vector3(moved.x, point.y, moved.y)

func death() -> void:
	var body: Node3D = cultist(Vector3(-4, 0.9, 0))
	await frames(40)
	var rig: Skeleton3D = body.get("skeleton") as Skeleton3D
	body.set("last_push", Vector3(0, 0, 2.5))
	body.set("push_age", 0.0)
	body.call("show_state", 3, 0, false, false)
	await frames(2)
	var cloth: RobeCloth = body.get("cloth") as RobeCloth
	check(body.get("ragdoll") != null and cloth != null and cloth.draped, "A dead cultist ragdolls and its robe drapes")
	check(rig.get_child(rig.get_child_count() - 1) == cloth.push and cloth.stride.get_index() > (body.get("ragdoll") as Node).get_index() and cloth.active, "The draped robe simulates, after the ragdoll")
	await settled(rig, "dead cultist")

# Within two seconds every hem tip lies near the ground and stops moving.
# Drift is measured in the pelvis's frame: the cloth must have stopped moving on the body, whatever
# the ragdoll still rolls.
func settled(rig: Skeleton3D, label: String) -> void:
	await frames(110)
	var first: Array[Transform3D] = await posed(rig)
	var before: PackedVector3Array = skirt(rig, first)
	await frames(2)
	var last: Array[Transform3D] = await posed(rig)
	var after: PackedVector3Array = skirt(rig, last)
	var pelvis: int = rig.find_bone("pelvis")
	check(finite(after), "The %s's robe stays finite" % label)
	var highest: float = -INF
	var lowest: float = INF
	var drift: float = 0.0
	var per: int = RobeCloth.JOINTS + 1
	for column: int in range(RobeCloth.COLUMNS):
		var tip: Vector3 = after[column * per + per - 1]
		highest = maxf(highest, tip.y)
		lowest = minf(lowest, tip.y)
	for index: int in range(after.size()):
		drift = maxf(drift, (first[pelvis].affine_inverse() * before[index]).distance_to(last[pelvis].affine_inverse() * after[index]) / 3.0)
	check(lowest > -0.08, "The %s's hem stays above the ground (lowest %.3f m)" % [label, lowest])
	check(highest < 0.6, "The %s's hem has fallen to the ground (highest %.3f m)" % [label, highest])
	check(drift < 0.01, "The %s's robe has settled (%.4f m per frame)" % [label, drift])
	print("ROBE_DRAPE: %s hem %.3f to %.3f m, drift %.4f m per frame" % [label, lowest, highest, drift])

func cut() -> void:
	var body: Node3D = cultist(Vector3(4, 0.9, 0))
	await frames(40)
	var rig: Skeleton3D = body.get("skeleton") as Skeleton3D
	var chest: Vector3 = (body.call("bone_world", rig.find_bone("spine_02")) as Transform3D).origin
	var before: int = find_children("RaiderHalf*", "", false, false).size()
	body.call("bisect", chest, Vector3(0.3, 1, 0).normalized(), Vector3(3, 2, 0))
	await frames(2)
	var halves: Array[Node] = find_children("RaiderHalf*", "", false, false)
	check(halves.size() == before + 2, "A bisect leaves two halves")
	var lower: Skeleton3D
	for half: Node in halves:
		var half_rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var robe: RobeCloth = half_rig.get_node_or_null("RobeCloth") as RobeCloth
		var ragdoll: PhysicalBoneSimulator3D = half_rig.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
		check(robe != null and robe.draped, "Each half's robe drapes")
		check(robe != null and robe.push != null and robe.push.garments != null and robe.push.garments.get_parent() == half_rig, "Each half's robe keeps its legs out of the cloth (the cut shader pushes)")
		check(ragdoll != null and ragdoll.is_simulating_physics(), "Each half is still a ragdoll")
		var capped: bool = false
		for node: Node in half.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for surface: int in range(mesh.get_surface_count()):
				capped = capped or mesh.surface_get_name(surface) == MobRagdoll.CAP
		check(capped, "Each half's cut is capped")
		if ragdoll != null and ragdoll.has_node("Body_thigh_l"):
			lower = half_rig
	check(lower != null, "One half keeps the legs")
	if lower != null:
		await settled(lower, "cut cultist's lower half")

func perf() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 9, 14), Vector3.ZERO)
	var runners: Array[Node3D] = []
	for index: int in range(5):
		var angle: float = TAU * float(index) / 5.0
		runners.append(cultist(Vector3(cos(angle) * 6.0, 0.9, sin(angle) * 6.0)))
	var cut_ones: Array[Node3D] = [cultist(Vector3(-2, 0.9, 0)), cultist(Vector3(2, 0.9, 0))]
	await frames(30)
	for body: Node3D in runners:
		body.call("show_state", 1, 60, false, false)
	for body: Node3D in cut_ones:
		var rig: Skeleton3D = body.get("skeleton") as Skeleton3D
		var chest: Vector3 = (body.call("bone_world", rig.find_bone("spine_02")) as Transform3D).origin
		body.call("bisect", chest, Vector3(0.3, 1, 0).normalized(), Vector3(1, 1, 0))
	await frames(60)
	for label: String in ["robe on", "robe off", "robe on again"]:
		for skeleton: Node in find_children("*", "Skeleton3D", true, false):
			for child: Node in skeleton.get_children():
				if child.name.begins_with("Robe"):
					(child as SkeletonModifier3D).active = label != "robe off"
		var started: int = Time.get_ticks_usec()
		var count: int = 600
		for frame: int in range(count):
			for body: Node3D in runners:
				var angle: float = atan2(body.position.z, body.position.x) + 2.7 / 6.0 / 60.0
				body.position = Vector3(cos(angle) * 6.0, 0.9, sin(angle) * 6.0)
				body.rotation.y = -angle # running round the circle
			await get_tree().process_frame
		print("ROBE_PERF %s: frame %.3f ms" % [label, float(Time.get_ticks_usec() - started) / count / 1000.0])
