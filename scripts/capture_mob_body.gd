extends SceneTree
## Stage raider bodies and save frames: feet on a slope, a hit mid-flex, a ragdoll death and a
## bisect. Pass --capture-dir=DIR (outside the repository); needs a rendering display.
## --bisect-only stages just the cuts: waist, shoulder-to-hip diagonal, chest-high and lengthwise.
## --model=male or --model=female stages every raider in that body (ids whose replicated choice
## gives it); without it the staged ids pick their bodies as in play.

const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var stage: Node3D = Node3D.new()
var camera: Camera3D = Camera3D.new()
var directory: String = "user://mob_body"
var bisect_only: bool = false
var model: String = ""
var used: Dictionary[int, bool] = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.get_slice("=", 1)
		elif argument == "--bisect-only":
			bisect_only = true
		elif argument.begins_with("--model="):
			model = argument.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(directory)
	capture.call_deferred()

func block(size: Vector3, location: Vector3, tilt: Vector3 = Vector3.ZERO, color: Color = Color("6d7a4f")) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = location
	body.rotation = tilt
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	cube.material = material
	mesh.mesh = cube
	body.add_child(mesh)
	stage.add_child(body)

func spawn(id: int, location: Vector3, yaw: float) -> HostileMob:
	while model != "" and (used.has(id) or HostileMob.is_female(id) != (model == "female")):
		id += 1
	used[id] = true
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = id
	mob.name = "Mob%d" % id
	mob.position = location
	mob.sync_position = location
	mob.yaw = yaw
	stage.add_child(mob)
	return mob

func shot(file: String, eye: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(eye, target)
	await process_frame
	await process_frame
	# Draw even while the window is hidden or occluded, when the main loop skips drawing and the
	# texture would still hold an older shot.
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(directory.path_join(file))
	print("CAPTURED ", directory.path_join(file))

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func capture() -> void:
	root.size = Vector2i(1280, 800)
	root.add_child(stage)
	current_scene = stage
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("9bb3c9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	stage.add_child(environment)
	stage.add_child(camera)
	camera.fov = 50
	block(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	if bisect_only:
		# Patchy dirt under the cuts, so the way blood sits in a textured ground shows.
		var floor_mesh: MeshInstance3D = stage.get_child(stage.get_child_count() - 1).get_child(1) as MeshInstance3D
		var dirt: StandardMaterial3D = StandardMaterial3D.new()
		var noise: NoiseTexture2D = NoiseTexture2D.new()
		noise.noise = FastNoiseLite.new()
		noise.noise.frequency = 0.05
		noise.seamless = true
		noise.color_ramp = Gradient.new()
		noise.color_ramp.set_color(0, Color("4a3a28"))
		noise.color_ramp.set_color(1, Color("8b7a5a"))
		dirt.albedo_texture = noise
		dirt.uv1_scale = Vector3(40, 40, 40)
		dirt.roughness = 0.95
		floor_mesh.material_override = dirt
		await cuts()
		quit()
		return
	# A 22 degree slope rising to +X, and a stone under one foot of a second raider.
	block(Vector3(6, 1, 6), Vector3(10, -0.3, 0), Vector3(0, 0, deg_to_rad(22.0)), Color("7c6f4f"))
	block(Vector3(0.5, 0.22, 0.5), Vector3(-5.12, 0.11, -0.05), Vector3(0, 0.3, 0), Color("8a8a84"))
	var sloped: HostileMob = spawn(1, Vector3(10, 1.5, 0), 0.0)
	var stoned: HostileMob = spawn(2, Vector3(-5, 1.0, 0), 0.0)
	await wait(1.5)
	await shot("slope_front.png", Vector3(10, 1.2, -3.2), Vector3(10, 0.6, 0))
	await shot("slope_side.png", Vector3(12.8, 1.4, -1.2), Vector3(10, 0.5, 0))
	await shot("stone.png", Vector3(-5, 0.9, -2.6), Vector3(-5, 0.4, 0))
	# A blade crossing the left arm and chest sideways, left to right from the raider's view.
	var flat: HostileMob = spawn(3, Vector3(0, 0.95, 0), 0.0)
	await wait(0.6)
	await shot("hit_before.png", Vector3(0, 1.3, -3.0), Vector3(0, 0.9, 0))
	var skeleton: Skeleton3D = flat.visual.get("skeleton") as Skeleton3D
	var arm: Vector3 = (flat.visual.call("bone_world", skeleton.find_bone("upperarm_r")) as Transform3D).origin
	flat.slashed(Vector3.LEFT * 4.0, arm, Vector3.UP, Vector3.LEFT, 10.0)
	await wait(0.09)
	await shot("hit_flex.png", Vector3(0, 1.3, -3.0), Vector3(0, 0.9, 0))
	await wait(0.15)
	await shot("hit_swing_back.png", Vector3(0, 1.3, -3.0), Vector3(0, 0.9, 0))
	await wait(1.5)
	# A chest-high hit from the front, the struck spine folding back.
	var chest: Vector3 = (flat.visual.call("bone_world", skeleton.find_bone("spine_03")) as Transform3D).origin + Vector3(0, 0, -0.15)
	flat.slashed(Vector3.BACK * 4.0, chest, Vector3.RIGHT, Vector3.BACK, 12.0)
	await wait(0.1)
	await shot("hit_chest_side.png", Vector3(3.0, 1.3, 0.0), Vector3(0, 0.9, 0))
	await wait(1.5)
	# Death by a non-blade blow: the body collapses as a ragdoll and outlives the raider node.
	flat.slashed(Vector3.BACK * 4.0, chest, Vector3.RIGHT, Vector3.BACK, 8.0)
	flat.receive_hit(999, Vector3.BACK)
	await wait(0.35)
	await shot("death_falling.png", Vector3(3.2, 1.4, -2.0), Vector3(0, 0.6, 0.5))
	await wait(2.0)
	await shot("death_rest.png", Vector3(2.6, 1.8, -1.8), Vector3(0, 0.2, 0.6))
	# Death on the slope.
	sloped.slashed(Vector3.LEFT * 3.0, (sloped.visual.call("bone_world", skeleton.find_bone("spine_03")) as Transform3D).origin, Vector3.UP, Vector3.LEFT, 8.0)
	sloped.receive_hit(999, Vector3.LEFT)
	await wait(2.5)
	await shot("death_slope.png", Vector3(10, 2.2, -3.4), Vector3(10, 0.4, 0))
	# Bisect through the waist: two jointed halves.
	var waist: Vector3 = (stoned.visual.call("bone_world", skeleton.find_bone("spine_02")) as Transform3D).origin
	stoned.bisected(waist, Vector3(0.25, 1, 0.1).normalized(), Vector3(3.5, 2, 0.5), Vector3.RIGHT)
	await wait(0.25)
	await shot("bisect_flying.png", Vector3(-5, 1.4, -3.5), Vector3(-4.5, 0.6, 0))
	await wait(2.5)
	await shot("bisect_rest.png", Vector3(-4, 2.4, -3.0), Vector3(-4, 0.2, 0.3))
	quit()

# One raider per cut, each seen flying, landing and at rest, plus a close look at the cut faces.
func cuts() -> void:
	var plans: Array[Dictionary] = [
		{"name": "waist", "bone": "spine_02", "normal": Vector3(0.25, 1, 0.1), "impulse": Vector3(3.5, 2, 0.5)},
		{"name": "diagonal", "bone": "spine_03", "normal": Vector3(1, 1.1, 0.15), "impulse": Vector3(2.5, 2, 1.5)},
		{"name": "chest", "bone": "spine_03", "normal": Vector3(0.05, 1, -0.2), "impulse": Vector3(-1, 2, 3.5)},
		{"name": "lengthwise", "bone": "spine_02", "normal": Vector3(1, 0.15, 0.1), "impulse": Vector3(3, 2, 0)},
	]
	for index: int in range(plans.size()):
		var plan: Dictionary = plans[index]
		var spot: Vector3 = Vector3(index * 8.0 - 12.0, 0.95, 0)
		# A crate beside each raider: splatter landing on it must stop at its edges.
		block(Vector3(0.6, 0.5, 0.6), Vector3(spot.x + 1.1, 0.25, 0.5), Vector3.ZERO, Color("8a6a45"))
		var mob: HostileMob = spawn(10 + index, spot, 0.0)
		await wait(0.8)
		var skeleton: Skeleton3D = mob.visual.get("skeleton") as Skeleton3D
		var point: Vector3 = (mob.visual.call("bone_world", skeleton.find_bone(String(plan["bone"]))) as Transform3D).origin
		var normal: Vector3 = (plan["normal"] as Vector3).normalized()
		# The blade meets the skin on the camera's side, as in play, not at the bone.
		var skin: Vector3 = Vector3(0, 0, -0.18)
		mob.bisected(point + skin - normal * normal.dot(skin), normal, plan["impulse"] as Vector3, normal.cross(Vector3.FORWARD).normalized())
		var name: String = String(plan["name"])
		# Each cut face straight on, the other half hidden, before the halves move apart.
		await process_frame
		var fresh: Array[Node] = stage.find_children("RaiderHalf*", "", false, false).filter(func(node: Node) -> bool: return not node.has_meta("cut_index"))
		for face: float in [1.0, -1.0]:
			for node: Node in fresh:
				(node as Node3D).visible = float(node.get_meta("side")) != face
			var aside: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized() * 0.35
			await shot("cut_%s_face%s.png" % [name, "top" if face > 0.0 else "bottom"], point + normal * face * 1.1 + aside, point)
		for node: Node in fresh:
			(node as Node3D).visible = true
		await wait(0.12)
		await shot("cut_%s_0hit.png" % name, spot + Vector3(0.6, 0.7, -3.2), spot + Vector3(0, 0.1, 0))
		await wait(0.3)
		await shot("cut_%s_1flying.png" % name, spot + Vector3(1.5, 1.2, -4.0), spot + Vector3(0.6, 0.2, 0.3))
		await wait(1.0)
		await shot("cut_%s_2landed.png" % name, spot + Vector3(1.5, 2.2, -3.6), spot + Vector3(0.8, -0.6, 0.4))
		await wait(2.0)
		await shot("cut_%s_3rest.png" % name, spot + Vector3(1.0, 3.2, -3.2), spot + Vector3(1.0, -0.6, 0.6))
		# The pools low and close, where their edges and reflection show.
		await shot("cut_%s_6pool.png" % name, spot + Vector3(-0.6, 0.9, -2.2), spot + Vector3(0.7, -0.9, 0.4))
		var faces: Array[Vector3] = []
		for node: Node in stage.find_children("RaiderHalf*", "", false, false):
			if node.get_meta("cut_index", index) == index:
				node.set_meta("cut_index", index)
				var rig: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var ragdoll: Node = rig.get_node_or_null("Ragdoll")
				# The part that carried the cut, where the cap face is.
				var nearest: Vector3 = Vector3.INF
				for body: Node in ragdoll.get_children() if ragdoll != null else []:
					var where: Vector3 = (body as Node3D).global_position
					if not nearest.is_finite() or where.distance_to(point) < nearest.distance_to(point):
						nearest = where
				faces.append(nearest)
		for face: int in range(faces.size()):
			await shot("cut_%s_4close%d.png" % [name, face], faces[face] + Vector3(-0.5, 0.7, -0.5), faces[face])
			await shot("cut_%s_5close%d.png" % [name, face], faces[face] + Vector3(0.55, 0.6, 0.5), faces[face])
