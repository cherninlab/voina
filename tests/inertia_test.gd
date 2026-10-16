extends Node3D

var failures: int = 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("INERTIA_FAIL: " + message)

func run() -> void:
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	var origin: Vector3 = Vector3(0, 0.9, 0)
	motion.reset(0.0, origin, 0.0)
	check(absf(motion.tip.y - HeavySwordMotion.TIP_RADIUS) < 0.01 and motion.bearing() < -2.5, "Blade rests on the ground behind the right hip")
	for frame: int in range(120):
		motion.step(1.0 / 60.0, 0.0, 0.0, true, false, false, origin, 0.0)
	check(motion.tip.y < 0.1 and motion.raised > 0.99, "Holding without dragging cannot lift the blade")
	# A leftward drag (camera turning left) plus the approved cut carries the blade across the front.
	motion.strike(Vector2.LEFT)
	var crossed_front: bool = false
	var peak: float = 0.0
	var pulled: bool = false
	for frame: int in range(120):
		var yaw: float = minf(0.6, frame * 0.05)
		motion.step(1.0 / 60.0, yaw, 0.0, frame < 12, frame < 31, false, origin, 0.0)
		crossed_front = crossed_front or absf(motion.bearing()) < 0.3
		peak = maxf(peak, motion.tip.y)
		pulled = pulled or (motion.pull_velocity.length() > 0.01 and motion.pull_velocity.length() <= HeavySwordMotion.MAX_PULL)
	check(crossed_front, "Swing carries the blade across the front")
	check(peak > 0.4, "Swing lifts the tip off the ground")
	check(pulled, "Heavy blade produces bounded owner pull")
	check(motion.bearing() > HeavySwordMotion.HOLD_BEARING and motion.tip.y < 0.1, "Blade falls to the other side and rests on the ground")
	check(not motion.can_swing(Vector2.LEFT) and motion.can_swing(Vector2.RIGHT), "Next swing must drag the other way")
	motion.strike(Vector2.LEFT)
	for frame: int in range(60):
		motion.step(1.0 / 60.0, 0.6, 0.0, true, true, false, origin, 0.0)
	check(motion.bearing() > HeavySwordMotion.HOLD_BEARING, "Body blocks the blade from passing behind the back")
	for frame: int in range(180):
		motion.step(1.0 / 60.0, 0.6, 0.0, false, false, false, origin, 0.0)
	check(motion.tip_velocity.length() < 0.05 and motion.raised == 0.0 and motion.pull_velocity.length() < 0.001, "Released blade settles")
	var fine: HeavySwordMotion = HeavySwordMotion.new()
	var coarse: HeavySwordMotion = HeavySwordMotion.new()
	fine.reset(0.0, origin, 0.0)
	coarse.reset(0.0, origin, 0.0)
	fine.strike(Vector2.LEFT)
	coarse.strike(Vector2.LEFT)
	for frame: int in range(120):
		fine.step(1.0 / 120.0, 0.0, 0.0, true, true, false, origin, 0.0)
	for frame: int in range(30):
		coarse.step(1.0 / 30.0, 0.0, 0.0, true, true, false, origin, 0.0)
	check(fine.tip.distance_to(coarse.tip) < 0.01, "Substeps give consistent 30/120 Hz motion")
	coarse.step(5.0, -1000.0, 1000.0, true, true, false, origin, 0.0)
	check(coarse.tip.is_finite() and coarse.tip_velocity.length() <= HeavySwordMotion.MAX_TIP_SPEED + 0.01 and coarse.pull_velocity.length() <= HeavySwordMotion.MAX_PULL, "Long frame and extreme input stay bounded")
	coarse.reset(0.2, origin, 0.0)
	check(coarse.pull_velocity.is_zero_approx() and coarse.tip_velocity.is_zero_approx(), "Correction clears inertia")
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	await get_tree().physics_frame
	for variant: String in ["male", "female"]:
		var packed: PackedScene = load("res://content/characters/quaternius/%s.tscn" % variant) as PackedScene
		var visual: CharacterVisual = packed.instantiate() as CharacterVisual
		visual.position.y = 0.9
		add_child(visual)
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		var planted: Vector3 = visual.feet[0]
		visual.position.x += 0.1
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		check(visual.feet[0] == planted, variant + " support foot stays planted under small body shifts")
		visual.position.x += 0.35
		visual.update_feet(0.06, Vector3.RIGHT, true)
		check(visual.stepping >= 0 and visual.feet[visual.stepping].y > 0.05, variant + " displaced body triggers a lifted recovery step")
		for frame: int in range(60):
			visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
			visual.drive_sword(1.0 / 60.0, 0.0, 0.0, true, false, false, false)
			visual.update_pose(0.0, Vector3.ZERO, false, false)
		await get_tree().process_frame
		await get_tree().process_frame
		for index: int in range(2):
			check(visual.ik.last_feet[index].distance_to(visual.feet[index]) < 0.025, variant + " foot IK reaches planted ground target")
			check(absf(visual.feet[index].y - 0.085) < 0.01, variant + " feet respect ground height")
		visual.update_feet(1.0 / 60.0, Vector3.UP, false)
		check(visual.feet[0].y > 0.2, variant + " airborne legs tuck")
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		check(absf(visual.feet[0].y - 0.085) < 0.01, variant + " landing replants feet even without walking")
		visual.queue_free()
	await get_tree().process_frame
	var player: CharacterBody3D = (load("res://gameplay/player/player_character.tscn") as PackedScene).instantiate() as CharacterBody3D
	player.position = Vector3(0, 0.95, 0)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.set_physics_process(false)
	var combat: CombatController = player.get("combat") as CombatController
	combat.set_physics_process(false)
	# The blade rests on the right, so only a leftward cut can move it.
	player.call("attack", false, Vector2.LEFT)
	player.set("yaw", 0.8)
	var start: Vector3 = player.position
	for frame: int in range(20):
		player.call("_physics_process", 1.0 / 60.0)
	var displacement: Vector3 = player.position - start
	check(Vector2(displacement.x, displacement.z).length() > 0.02, "Sword momentum moves the owner without movement input")
	check(Vector2(player.velocity.x, player.velocity.z).length() <= HeavySwordMotion.MAX_PULL + 0.01, "Owner follow-through is capped")
	player.call("correct_position", start, Vector3.ZERO)
	var body: CharacterVisual = player.get("body") as CharacterVisual
	check(body.motion.pull_velocity.is_zero_approx(), "Host correction clears owner sword movement")
	if failures == 0:
		print("INERTIA_OK: rest, no hold-up, cross-front swing, opposite-side rest, body block, release, timestep stability, planted feet, owner pull/correction")
	get_tree().quit(0 if failures == 0 else 1)
