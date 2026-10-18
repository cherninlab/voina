extends Node3D

# Raider bodies: feet plant on a slope, a blow flexes the struck bones and springs back, a death
# collapses as a ragdoll that outlives the raider node, and a bisect leaves two jointed halves.
const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("MOB_BODY_FAIL: " + message)

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

func spawn(id: int, location: Vector3) -> HostileMob:
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = id
	mob.name = "Mob%d" % id
	mob.position = location
	mob.sync_position = location
	add_child(mob)
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

func run() -> void:
	ground(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	# A 20 degree slope across the raider's stance: its left foot sits uphill.
	ground(Vector3(6, 1, 6), Vector3(10, -0.35, 0), deg_to_rad(20.0))
	var sloped: HostileMob = spawn(1, Vector3(10, 1.4, 0))
	sloped.yaw = 0.0 # facing -Z: the raider's right is +X, downhill
	await frames(90)
	var body: Node3D = visual(sloped)
	var feet: MobFeet = body.get("feet") as MobFeet
	for side: String in ["l", "r"]:
		var foot: Vector3 = bone(body, "foot_" + side).origin
		var floor_height: float = height_under(foot)
		check(absf(foot.y - floor_height - 0.0865) < 0.06, "The %s foot plants on the slope (foot %.3f, ground %.3f)" % [side, foot.y, floor_height])
	check(feet.drop < -0.03, "Hips drop to let the downhill foot reach (%.3f)" % feet.drop)
	var flat: HostileMob = spawn(2, Vector3(0, 0.95, 0))
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
	var cut: HostileMob = spawn(3, Vector3(-4, 0.95, 0))
	await frames(20)
	var cut_visual: Node3D = visual(cut)
	var waist: Vector3 = bone(cut_visual, "spine_02").origin
	cut.bisected(waist, Vector3(0.3, 1, 0).normalized(), Vector3(3, 2, 0), Vector3.RIGHT)
	await frames(2)
	var halves: Array[Node] = find_children("RaiderHalf*", "", false, false)
	check(halves.size() == 2, "A bisect leaves two halves (%d)" % halves.size())
	var parts: int = 0
	for half: Node in halves:
		var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: PhysicalBoneSimulator3D = rig.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
		check(ragdoll != null and ragdoll.is_simulating_physics() and ragdoll.get_child_count() >= 3, "Each half is a jointed ragdoll")
		parts += ragdoll.get_child_count() if ragdoll != null else 0
	check(parts == MobRagdoll.PARTS.size(), "The halves split the body's parts between them (%d)" % parts)
	await frames(120)
	for half: Node in halves:
		var rig: Skeleton3D = half.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ragdoll: PhysicalBoneSimulator3D = rig.get_node("Ragdoll") as PhysicalBoneSimulator3D
		for node: Node in ragdoll.get_children():
			var part: PhysicalBone3D = node as PhysicalBone3D
			check(part.global_position.y > -0.3 and part.global_position.y < 1.2, "Half part %s rests on the ground (%.2f)" % [part.bone_name, part.global_position.y])
	if not failed:
		print("MOB_BODY_OK: foot planting on a slope, hip drop, puppet flex and settle, ragdoll death, jointed bisect halves")
	get_tree().quit(1 if failed else 0)
