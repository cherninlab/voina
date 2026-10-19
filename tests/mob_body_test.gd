extends Node3D

# Raider bodies: feet plant on a slope, a blow flexes the struck bones and springs back, a death
# collapses as a ragdoll that outlives the raider node, and a bisect leaves two jointed halves.
# Possessed villagers: each id picks a mild distortion; backward knees still plant the feet; the
# crawl puts the hands on flat and sloped ground; the coil, leap and stare pose; distorted bodies
# die and split into unscaled physics. Every check runs once on the male and once on the female body.
const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var failed: bool = false
var female: bool = false # the body under test
var last_id: int = 0
const STRETCH: float = 0.12

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("MOB_BODY_FAIL: [%s] %s" % ["female" if female else "male", message])

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func ground(size: Vector3, location: Vector3, tilt: float = 0.0) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = location
	body.rotation.z = tilt
	body.add_child(shape)
	add_child(body)

# The next unused id whose replicated choice is the body under test (and, given, the possession kind).
func spawn(location: Vector3, kind: int = -1) -> HostileMob:
	var id: int = last_id + 1
	while HostileMob.is_female(id) != female or (kind >= 0 and posmod(id - 1, MobPossession.Kind.size()) != kind):
		id += 1
	last_id = maxi(last_id, id) if kind < 0 else last_id
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = id
	mob.name = "Mob%d" % id
	mob.position = location
	mob.sync_position = location
	add_child(mob)
	check(mob.visual.get("female") == female and not mob.visual.find_children("Superhero_Female" if female else "SuperHero_Male", "MeshInstance3D", true, false).is_empty(), "Raider %d wears the %s body" % [id, "female" if female else "male"])
	return mob

func visual(mob: HostileMob) -> Node3D:
	return mob.visual

func bone(mob_visual: Node3D, bone_name: String) -> Transform3D:
	var rig: Skeleton3D = mob_visual.get("skeleton") as Skeleton3D
	return mob_visual.call("bone_world", rig.find_bone(bone_name)) as Transform3D

func height_under(point: Vector3) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 3.0, 1)
	var actors: Array[RID] = []
	for node: Node in get_children():
		if node is CharacterBody3D:
			actors.append((node as CharacterBody3D).get_rid())
	query.exclude = actors
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF

# How much longer (metres) the worst edge of the skin a half shows has grown from the bind pose.
# Folding joints stretch small triangles by centimetres; a part falling away from the skin it
# carries pulls them into long lines.
func stretch(half: Node) -> float:
	var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	await rig.skeleton_updated # modifiers' poses are only held during this signal
	var poses: Array[Transform3D] = []
	var capture: Callable = func() -> void:
		for bone_index: int in range(rig.get_bone_count()):
			poses.append(rig.get_bone_global_pose(bone_index))
	rig.skeleton_updated.connect(capture, CONNECT_ONE_SHOT)
	await rig.skeleton_updated
	var side: float = float(half.get_meta("side", 1.0))
	var worst: float = 0.0
	for node: Node in half.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var skinning: Array[Transform3D] = []
		for bind: int in range(mesh.skin.get_bind_count()):
			skinning.append(poses[MobRagdoll.bind_bone(mesh.skin, rig, bind)] * mesh.skin.get_bind_pose(bind))
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var distances: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per: int = bones.size() / vertices.size()
		var posed: PackedVector3Array = PackedVector3Array()
		for index: int in range(vertices.size()):
			var point: Vector3 = Vector3.ZERO
			for slot: int in range(per):
				point += skinning[bones[index * per + slot]] * vertices[index] * weights[index * per + slot]
			posed.append(point)
		for corner: int in range(0, indices.size(), 3):
			for edge: int in range(3):
				var a: int = indices[corner + edge]
				var b: int = indices[corner + (edge + 1) % 3]
				var rest: float = vertices[a].distance_to(vertices[b])
				if distances[a].x * side > 0.0 and distances[b].x * side > 0.0:
					var growth: float = posed[a].distance_to(posed[b]) - rest
					if growth > worst:
						worst = growth
	return worst

func run() -> void:
	ground(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	# A 20 degree slope across the raider's stance: its left foot sits uphill.
	ground(Vector3(6, 1, 6), Vector3(10, -0.35, 0), deg_to_rad(20.0))
	# The choice is a pure function of the id, and the first spawn wave of three shows both.
	check(HostileMob.is_female(1) == HostileMob.is_female(1) and [1, 2, 3].map(HostileMob.is_female).has(true) and [1, 2, 3].map(HostileMob.is_female).has(false), "Ids 1 to 3 give both bodies")
	for body_type: bool in [false, true]:
		female = body_type
		await bodies()
		for node: Node in get_children():
			if not node is StaticBody3D:
				node.queue_free()
		await frames(2)
		await possessed()
		# Clear the stage for the other body: raiders, ragdolls and halves, keeping the ground.
		for node: Node in get_children():
			if not node is StaticBody3D:
				node.queue_free()
		await frames(2)
	variants()
	if not failed:
		print("MOB_BODY_OK: male and female bodies; foot planting on a slope, hip drop, puppet flex and settle, ragdoll death, jointed bisect halves; possessed variants, backward knees, crawl, coil, leap, stare, unscaled distorted ragdolls")
	get_tree().quit(1 if failed else 0)

func bodies() -> void:
	var sloped: HostileMob = spawn(Vector3(10, 1.4, 0))
	sloped.yaw = 0.0 # facing -Z: the raider's right is +X, downhill
	await frames(90)
	var body: Node3D = visual(sloped)
	var feet: MobFeet = body.get("feet") as MobFeet
	var sloped_rig: Skeleton3D = body.get("skeleton") as Skeleton3D
	for side: String in ["l", "r"]:
		var foot: Vector3 = bone(body, "foot_" + side).origin
		var floor_height: float = height_under(foot)
		var ankle: float = sloped_rig.get_bone_global_rest(sloped_rig.find_bone("foot_" + side)).origin.y # 8.7 cm male, 7.1 cm female
		var possession: MobPossession = body.get("possession") as MobPossession
		var raised: float = possession.heel_rise(possession.toes) # a possessed villager on its toes
		check(absf(foot.y - floor_height - ankle - raised) < 0.06, "The %s foot plants on the slope (foot %.3f, ground %.3f)" % [side, foot.y, floor_height])
	check(feet.drop < -0.03, "Hips drop to let the downhill foot reach (%.3f)" % feet.drop)
	var flat: HostileMob = spawn(Vector3(0, 0.95, 0))
	await frames(30)
	var level: Node3D = visual(flat)
	var level_feet: MobFeet = level.get("feet") as MobFeet
	check(absf(level_feet.drop) < 0.02, "Level ground keeps the hips at their animated height")
	# A blade crossing the left forearm sideways flexes that arm, bends the chain, then settles.
	var arm_before: Transform3D = bone(level, "lowerarm_l")
	var leg_before: Vector3 = bone(level, "foot_r").origin
	var puppet: MobPuppet = level.get("puppet") as MobPuppet
	level.call("react", Vector3.RIGHT * 3.0, arm_before.origin, Vector3.RIGHT, 10.0)
	await frames(6)
	var arm_angle: float = 0.0
	var spine_angle: float = 0.0
	for index: int in range(puppet.bones.size()):
		var bone_name: String = (level.get("skeleton") as Skeleton3D).get_bone_name(puppet.bones[index])
		if bone_name == "upperarm_l":
			arm_angle = puppet.angles[index].length()
		elif bone_name == "spine_03":
			spine_angle = puppet.angles[index].length()
	check(arm_angle > 0.15, "The struck arm swings (%.3f rad)" % arm_angle)
	check(spine_angle > 0.02 and spine_angle < arm_angle, "The spine bends less than the struck arm (%.3f rad)" % spine_angle)
	check(bone(level, "lowerarm_l").origin.distance_to(arm_before.origin) > 0.03, "The final pose shows the flexed arm")
	check(bone(level, "foot_r").origin.distance_to(leg_before) < 0.05, "Planted feet stay put during a hit")
	await frames(150)
	check(puppet.settled(), "The springs settle back onto the animation")
	# A wound rides on the final pose of its bone.
	level.call("wound", bone(level, "spine_03").origin + Vector3(0, 0.05, -0.15), Vector3.UP, Vector3.RIGHT)
	# Death: the visual leaves the raider, ragdolls and stays after the raider node is freed.
	var head_alive: float = bone(level, "Head").origin.y
	flat.receive_hit(999, Vector3.FORWARD)
	await frames(4)
	check(level.get_parent() == self and level.get("ragdoll") != null, "A dead raider's body moves into the scene as a ragdoll")
	var simulator: PhysicalBoneSimulator3D = level.get("ragdoll") as PhysicalBoneSimulator3D
	check(simulator != null and simulator.is_simulating_physics() and simulator.get_child_count() == MobRagdoll.PARTS.size(), "Every ragdoll part simulates")
	await frames(150)
	check(not is_instance_valid(flat) and is_instance_valid(level), "The ragdoll outlives the raider node")
	var head_dead: float = bone(level, "Head").origin.y
	check(head_dead < head_alive - 0.9 and head_dead > -0.2, "The body collapses onto the ground (head %.2f -> %.2f)" % [head_alive, head_dead])
	var pelvis: Transform3D = bone(level, "pelvis")
	var thigh: Transform3D = bone(level, "thigh_l")
	check(pelvis.origin.distance_to(thigh.origin) < 0.2, "The skeleton stays jointed")
	var wounds: Array = level.get("wounds") as Array
	check(wounds.size() == 1, "The wound survives the fall")
	# Bisect: two halves, each a ragdoll of the parts on its side, collapsing as jointed bodies.
	var cut: HostileMob = spawn(Vector3(-4, 0.95, 0))
	await frames(20)
	var cut_visual: Node3D = visual(cut)
	var waist: Vector3 = bone(cut_visual, "spine_02").origin
	cut.bisected(waist, Vector3(0.3, 1, 0).normalized(), Vector3(3, 2, 0), Vector3.RIGHT)
	await frames(2)
	var halves: Array[Node] = find_children("RaiderHalf*", "", false, false)
	check(halves.size() == 2, "A bisect leaves two halves (%d)" % halves.size())
	var parts: PackedStringArray = PackedStringArray()
	for half: Node in halves:
		var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: PhysicalBoneSimulator3D = rig.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
		check(ragdoll != null and ragdoll.is_simulating_physics() and ragdoll.get_child_count() >= 3, "Each half is a jointed ragdoll")
		var capped: bool = false
		for node: Node in half.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for surface: int in range(mesh.get_surface_count()):
				capped = capped or (mesh.surface_get_name(surface) == MobRagdoll.CAP and (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() >= 60)
		check(capped, "Each half's cut is closed by a cap face")
		for node: Node in ragdoll.get_children() if ragdoll != null else []:
			if not parts.has((node as PhysicalBone3D).bone_name):
				parts.append((node as PhysicalBone3D).bone_name)
		# A half with skin on both sides of a joint simulates both parts, so nothing is left to hang.
		check(ragdoll == null or ragdoll.get_child_count() < MobRagdoll.PARTS.size(), "A half does not simulate the whole body")
	check(parts.size() == MobRagdoll.PARTS.size(), "Between them the halves simulate every part (%d)" % parts.size())
	await frames(120)
	for half: Node in halves:
		var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: PhysicalBoneSimulator3D = rig.get_node("Ragdoll") as PhysicalBoneSimulator3D
		for node: Node in ragdoll.get_children():
			var part: PhysicalBone3D = node as PhysicalBone3D
			check(part.global_position.y > -0.3 and part.global_position.y < 1.2, "Half part %s rests on the ground (%.2f)" % [part.bone_name, part.global_position.y])
		var worst: float = await stretch(half)
		check(worst < STRETCH, "A waist-cut half keeps its skin together (worst edge +%.2f m)" % worst)
	# Lengthwise: each half has torso skin, so each simulates a spine under it and stays together.
	var split: HostileMob = spawn(Vector3(4, 0.95, 0))
	await frames(20)
	split.bisected(bone(visual(split), "spine_02").origin, Vector3(1, 0.15, 0.1).normalized(), Vector3(3, 2, 0), Vector3.FORWARD)
	await frames(2)
	var sides: Array[Node] = find_children("RaiderHalf*", "", false, false).filter(func(node: Node) -> bool: return not halves.has(node))
	check(sides.size() == 2, "A lengthwise bisect leaves two halves (%d)" % sides.size())
	for half: Node in sides:
		var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: Node = rig.get_node_or_null("Ragdoll")
		check(ragdoll != null and ragdoll.has_node("Body_spine_02"), "Each lengthwise half simulates the spine under its torso")
	await frames(120)
	for half: Node in sides:
		var worst: float = await stretch(half)
		check(worst < STRETCH, "A lengthwise half keeps its skin together (worst edge +%.2f m)" % worst)

# The distortion is a pure function of the id, mild, and independent of the body.
func variants() -> void:
	var kinds: Dictionary[int, bool] = {}
	var bodies_by_kind: Dictionary[int, Dictionary] = {}
	for id: int in range(1, 41):
		var a: MobPossession = MobPossession.new()
		var b: MobPossession = MobPossession.new()
		a.configure(id)
		b.configure(id)
		check(a.describe() == b.describe() and a.skin == b.skin and a.streaks == b.streaks, "Villager %d's possession is a pure function of its id" % id)
		check(a.arm_length >= 1.0 and a.arm_length <= 1.2 and a.leg_length >= 0.86 and a.leg_length <= 1.0, "Villager %d's limbs stay mild (arms %.2f, legs %.2f)" % [id, a.arm_length, a.leg_length])
		check(a.neck_stretch <= 0.05 and absf(a.head_roll) <= 0.4 and a.hunch <= 0.55 and a.crouch <= 0.1, "Villager %d's neck, tilt and hunch stay mild" % id)
		if id <= 5:
			kinds[a.kind] = true
		if not bodies_by_kind.has(a.kind):
			bodies_by_kind[a.kind] = {}
		bodies_by_kind[a.kind][HostileMob.is_female(id)] = true
		a.free()
		b.free()
	check(kinds.size() == MobPossession.Kind.size(), "Five consecutive villagers are each possessed differently (%d kinds)" % kinds.size())
	for kind: int in bodies_by_kind:
		check(bodies_by_kind[kind].size() == 2, "Kind %s comes on both bodies" % MobPossession.KIND_NAMES[kind])

func forward_of(mob: HostileMob) -> Vector3:
	return -mob.visual.global_basis.z

# Every bone of the final pose and every ragdoll part is a pure rotation: no scale reaches physics.
func orthonormal(basis: Basis) -> bool:
	return absf(basis.x.length() - 1.0) < 0.002 and absf(basis.y.length() - 1.0) < 0.002 and absf(basis.z.length() - 1.0) < 0.002 and absf(basis.determinant() - 1.0) < 0.005

func unscaled_pose(mob_visual: Node3D) -> bool:
	for pose: Transform3D in mob_visual.get("poses") as Array[Transform3D]:
		if not orthonormal(pose.basis):
			return false
	return true

func unscaled_ragdoll(simulator: PhysicalBoneSimulator3D) -> bool:
	for node: Node in simulator.get_children():
		var part: PhysicalBone3D = node as PhysicalBone3D
		if not orthonormal(part.global_basis):
			return false
		for shape: Node in part.get_children():
			if (shape as Node3D).scale.distance_to(Vector3.ONE) > 0.0001:
				return false
	return true

func possessed() -> void:
	# Backward knees on level ground: each knee sits behind the line from hip to ankle, and the
	# feet still plant, raised onto their toes.
	var knees: HostileMob = spawn(Vector3(0, 0.95, 0), MobPossession.Kind.BACKWARD_KNEES)
	await frames(60)
	var knee_visual: Node3D = visual(knees)
	var rig: Skeleton3D = knee_visual.get("skeleton") as Skeleton3D
	for side: String in ["l", "r"]:
		var hip: Vector3 = bone(knee_visual, "thigh_" + side).origin
		var knee: Vector3 = bone(knee_visual, "calf_" + side).origin
		var foot: Vector3 = bone(knee_visual, "foot_" + side).origin
		var along: Vector3 = Geometry3D.get_closest_point_to_segment(knee, hip, foot)
		check((knee - along).dot(forward_of(knees)) < -0.02, "The %s knee bends backward (%.3f m)" % [side, (knee - along).dot(forward_of(knees))])
		var ankle: float = rig.get_bone_global_rest(rig.find_bone("foot_" + side)).origin.y
		var knee_possession: MobPossession = knee_visual.get("possession") as MobPossession
		var raised: float = knee_possession.heel_rise(knee_possession.toes)
		check(raised > 0.02 and absf(foot.y - height_under(foot) - ankle - raised) < 0.04, "The %s backward-kneed foot plants on its toes (foot %.3f, toes lift the ankle %.3f)" % [side, foot.y, raised])
	check(unscaled_pose(knee_visual), "A distorted pose holds no bone scale")
	# A hitch (quarter-second frames) with fresh twitches must not blow up the twitch springs.
	var knee_possession_hitch: MobPossession = knee_visual.get("possession") as MobPossession
	Engine.time_scale = 15.0
	for frame: int in range(12):
		knee_possession_hitch.twitch_spins[frame % knee_possession_hitch.twitch_spins.size()] += Vector3(0.3, 1.0, 0.2) * 9.0
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await frames(2)
	var settled_twitch: bool = true
	for twitch_angle: Vector3 in knee_possession_hitch.twitch_angles:
		settled_twitch = settled_twitch and twitch_angle.is_finite() and twitch_angle.length() <= MobPossession.TWITCH_MAX + 0.001
	var finite_pose: bool = true
	for pose: Transform3D in knee_visual.get("poses") as Array[Transform3D]:
		finite_pose = finite_pose and pose.is_finite()
	check(settled_twitch and finite_pose, "Twitches stay finite and small through long frames")
	# The crawl on flat ground, moving: hands down near the ground, hips low, head ahead.
	var crawler: HostileMob = spawn(Vector3(-4, 0.95, 4), MobPossession.Kind.LONG_ARMS)
	crawler.state = 5
	var crawl_visual: Node3D = visual(crawler)
	var possession: MobPossession = crawl_visual.get("possession") as MobPossession
	var lowest: float = INF
	for frame: int in range(70):
		crawler.kick_velocity = forward_of(crawler) * 2.4
		await get_tree().process_frame
		if frame >= 40:
			for side: String in ["l", "r"]:
				var hand: Vector3 = bone(crawl_visual, "hand_" + side).origin
				lowest = minf(lowest, hand.y - height_under(hand))
	check(possession.weights[MobPossession.Mode.CRAWL] > 0.95 and possession.stride > 0.8, "A crawling villager is fully on all fours and striding")
	check(lowest < 0.1, "Crawling hands reach the ground (lowest wrist %.3f m over it)" % lowest)
	var pelvis_world: Vector3 = bone(crawl_visual, "pelvis").origin
	var head_world: Vector3 = bone(crawl_visual, "Head").origin
	check(pelvis_world.y - crawler.global_position.y + 0.9 < 0.8 and (head_world - pelvis_world).dot(forward_of(crawler)) > 0.3, "On all fours the hips are low and the head leads (hips %.2f m)" % (pelvis_world.y - crawler.global_position.y + 0.9))
	check(unscaled_pose(crawl_visual), "The crawl pose holds no bone scale")
	# Standing still on the 20 degree slope: both hands planted on the slope.
	var sloped: HostileMob = spawn(Vector3(10, 1.4, 0), MobPossession.Kind.SHORT_LEGS)
	sloped.yaw = PI * 0.5 # facing -X, so the slope rises behind and below its right hand side
	sloped.state = 5
	await frames(80)
	var sloped_visual: Node3D = visual(sloped)
	for side: String in ["l", "r"]:
		var hand: Vector3 = bone(sloped_visual, "hand_" + side).origin
		check(absf(hand.y - height_under(hand) - MobPossession.WRIST) < 0.07, "On a slope the %s hand plants (%.3f m over the ground)" % [side, hand.y - height_under(hand)])
	# The coil: crouched on planted hands, eyes flaring, a telegraph read from the body.
	var coiled: HostileMob = spawn(Vector3(4, 0.95, 4), MobPossession.Kind.CROOKED_NECK)
	coiled.state = HostileMob.State.ACT
	coiled.attack_age = 0.0
	await frames(30)
	var coil_visual: Node3D = visual(coiled)
	var coil_possession: MobPossession = coil_visual.get("possession") as MobPossession
	check(coil_possession.weights[MobPossession.Mode.COIL] > 0.9 and coil_possession.flare() > 0.5, "The windup coils the body and flares the eyes")
	for side: String in ["l", "r"]:
		var hand: Vector3 = bone(coil_visual, "hand_" + side).origin
		check(hand.y - height_under(hand) < 0.12, "Coiled, the %s hand is planted" % side)
	# The leap: launched forward, arms reaching ahead of the head, legs trailing behind the hips.
	coiled.state = 6
	coiled.hop = 4.5
	for frame: int in range(14):
		coiled.kick_velocity = forward_of(coiled) * 7.0
		await get_tree().process_frame
	var ahead: Vector3 = forward_of(coiled)
	var leap_head: float = bone(coil_visual, "Head").origin.dot(ahead)
	var leap_hips: float = bone(coil_visual, "pelvis").origin.dot(ahead)
	check(bone(coil_visual, "hand_l").origin.dot(ahead) > leap_head and bone(coil_visual, "hand_r").origin.dot(ahead) > leap_head, "Leaping, both hands reach out ahead of the head")
	check(bone(coil_visual, "foot_l").origin.dot(ahead) < leap_hips and bone(coil_visual, "foot_r").origin.dot(ahead) < leap_hips, "Leaping, the feet trail behind the hips")
	# The stare: squatting, the head turns slowly to a target off to the side.
	var starer: HostileMob = spawn(Vector3(-4, 0.95, -4), MobPossession.Kind.HUNCHED)
	starer.state = 4
	var stare_visual: Node3D = visual(starer)
	var mark: Node3D = Node3D.new()
	add_child(mark)
	mark.global_position = starer.global_position + forward_of(starer) * 3.0 - starer.visual.global_basis.x * 2.0 + Vector3.UP * 0.4
	stare_visual.set("look_at_node", mark)
	await frames(10)
	var early: Vector3 = bone(stare_visual, "Head").basis.z.normalized()
	await frames(110)
	var head_frame: Transform3D = bone(stare_visual, "Head")
	var to_mark: Vector3 = (mark.global_position - head_frame.origin).normalized()
	check(head_frame.basis.z.normalized().dot(to_mark) > 0.85, "The staring head turns to its target (%.2f)" % head_frame.basis.z.normalized().dot(to_mark))
	check(early.dot(to_mark) < head_frame.basis.z.normalized().dot(to_mark) - 0.05, "The head turns slowly, not in one snap")
	check(pelvis_height(starer) < 0.8, "The stare squats (hips %.2f m)" % pelvis_height(starer))
	# Death from the crawl on long arms: the ragdoll keeps the arms' length and holds no scale.
	var arm_alive: float = bone(crawl_visual, "lowerarm_l").origin.distance_to(bone(crawl_visual, "upperarm_l").origin)
	crawler.receive_hit(999, Vector3.FORWARD)
	await frames(6)
	var simulator: PhysicalBoneSimulator3D = crawl_visual.get("ragdoll") as PhysicalBoneSimulator3D
	check(simulator != null and simulator.is_simulating_physics() and simulator.get_child_count() == MobRagdoll.PARTS.size(), "A crawling villager dies into a full ragdoll")
	check(simulator != null and unscaled_ragdoll(simulator), "The ragdoll of a distorted body has no scaled part or shape")
	await frames(60)
	var arm_dead: float = bone(crawl_visual, "lowerarm_l").origin.distance_to(bone(crawl_visual, "upperarm_l").origin)
	check(absf(arm_dead - arm_alive) < 0.02, "The long upper arm keeps its length in the ragdoll (%.3f -> %.3f)" % [arm_alive, arm_dead])
	check(simulator != null and unscaled_ragdoll(simulator), "The settled ragdoll still has no scale")
	# Bisect a staring short-legged villager: two jointed, unscaled halves.
	var halves_before: int = find_children("RaiderHalf*", "", false, false).size()
	sloped.bisected(bone(sloped_visual, "spine_02").origin, Vector3(0.2, 1, 0.1).normalized(), Vector3(3, 2, 0), Vector3.RIGHT)
	await frames(3)
	var halves: Array[Node] = find_children("RaiderHalf*", "", false, false)
	check(halves.size() == halves_before + 2, "A possessed villager bisects into two halves")
	for half: Node in halves:
		var half_rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: PhysicalBoneSimulator3D = half_rig.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
		check(ragdoll != null and ragdoll.get_child_count() >= 3 and unscaled_ragdoll(ragdoll), "Each possessed half is an unscaled jointed ragdoll")
	await frames(90)
	for half: Node in halves:
		var worst: float = await stretch(half)
		check(worst < STRETCH, "A possessed half keeps its skin together (worst edge +%.2f m)" % worst)

func pelvis_height(mob: HostileMob) -> float:
	return bone(visual(mob), "pelvis").origin.y - mob.global_position.y + 0.9
