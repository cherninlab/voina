extends SceneTree

var wall: StaticBody3D = StaticBody3D.new()

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("HIT_RESOLVER_FAIL: " + message)
		quit(1)

func run() -> void:
	var history: HitResolver.PositionHistory = HitResolver.PositionHistory.new()
	check(history.sample(1.0, Vector3.ONE) == Vector3.ONE, "Empty history falls back to the present")
	for tick: int in range(60):
		history.record(tick / 60.0, Vector3(tick / 60.0 * 6.0, 0, 0))
	check(history.times.size() <= int(HitResolver.HISTORY_SECONDS * 60.0) + 2, "History is pruned to its window")
	check(is_equal_approx(history.sample(0.9, Vector3.ZERO).x, 5.4), "Samples land on recorded ticks")
	check(is_equal_approx(history.sample(59.5 / 60.0 - 0.1, Vector3.ZERO).x, 5.35), "Samples interpolate between ticks")
	check(history.sample(0.0, Vector3.ZERO) == history.positions[0], "Older times clamp to the oldest sample")
	check(history.sample(5.0, Vector3.ZERO) == history.positions[-1], "Future times clamp to the newest sample")

	check(is_equal_approx(HitResolver.rewind_seconds(0.0), HitResolver.VIEW_LAG), "Host attacker rewinds only its view lag")
	check(is_equal_approx(HitResolver.rewind_seconds(0.06), 0.06 + HitResolver.VIEW_LAG), "Client rewind adds its round trip")
	check(HitResolver.rewind_seconds(5.0) == HitResolver.MAX_REWIND, "Inflated round trips are capped")
	check(HitResolver.head_start_seconds(0.06) == 0.03 and HitResolver.head_start_seconds(1.0) == HitResolver.MAX_HEAD_START, "Swing head start is one-way and capped")

	var combat: CombatController = CombatController.new()
	root.add_child(combat)
	combat.set_physics_process(false)
	check(combat.begin_attack(false, HitResolver.head_start_seconds(0.08)), "Back-dated swing starts")
	for tick: int in range(14):
		combat.step(1.0 / 120.0)
	check(combat.phase == CombatController.Phase.ACTIVE, "Head start shortens the host windup")

	var origin: Vector3 = Vector3(0, 0.65, 0)
	var end: Vector3 = Vector3(0, 0.65, -40)
	check(HitResolver.segment_hits_capsule(origin, end, Vector3(0, 0, -10)) > 9.0, "Beam through the capsule hits")
	check(HitResolver.segment_hits_capsule(origin, end, Vector3(0.35, 0, -10)) >= 0.0, "Beam grazing the shoulder hits")
	check(HitResolver.segment_hits_capsule(origin, end, Vector3(0.5, 0, -10)) < 0.0, "Beam outside the radius misses")
	check(HitResolver.segment_hits_capsule(origin, end, Vector3(0, 0, 10)) < 0.0, "Targets behind the shooter are missed")
	check(HitResolver.in_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -2), 2.2, deg_to_rad(35)), "Melee cone hits ahead")
	check(not HitResolver.in_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(2, 0, -1), 2.2, deg_to_rad(35)), "Melee cone misses wide")
	check(not HitResolver.in_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -3), 2.2, deg_to_rad(35)), "Melee cone misses far")

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 0, -5)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = wall.get_world_3d().direct_space_state
	var none: Array[RID] = []
	var centers: PackedVector3Array = PackedVector3Array([Vector3(0, 0, -10), Vector3(0, 0, -3), Vector3(3, 0, -8)])
	check(HitResolver.first_ray_target(space, origin, end, centers, none) == 1, "Nearest target in front of the wall is chosen")
	centers = PackedVector3Array([Vector3(0, 0, -10)])
	check(HitResolver.first_ray_target(space, origin, end, centers, none) == -1, "Rewound targets behind cover are protected")
	var exclude: Array[RID] = [wall.get_rid()]
	check(HitResolver.first_ray_target(space, origin, end, centers, exclude) == 0, "Excluded bodies do not block")
	print("HIT_RESOLVER_OK: history, rewind caps, head start, capsule ray, cone, cover")
	quit()
