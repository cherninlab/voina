extends SceneTree
## Stage raider bodies and save frames: feet on a slope, a hit mid-flex, a ragdoll death and a
## bisect. Pass --capture-dir=DIR (outside the repository); needs a rendering display.

const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var stage: Node3D = Node3D.new()
var camera: Camera3D = Camera3D.new()
var directory: String = "user://mob_body"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.get_slice("=", 1)
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
