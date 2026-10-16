extends SceneTree

var failed: bool = false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("WILDLIFE_FAIL: " + message)

func _initialize() -> void:
	var flock: BirdFlock = BirdFlock.new(42)
	check(flock.positions.size() == 4 and flock.states.size() == 4, "Four birds have fixed perch identities")
	flock.step(0.1, PackedVector3Array())
	check(flock.positions[0] == BirdFlock.HOMES[0], "Birds idle at their perches")
	flock.waits[0] = 0
	flock.step(0.01, PackedVector3Array())
	check(flock.states[0] == BirdFlock.State.FLYING, "An idle timer starts a flight")
	var returned: bool = false
	for frame: int in range(600):
		var before: Vector3 = flock.positions[0]
		flock.step(1.0 / 60.0, PackedVector3Array())
		var after: Vector3 = flock.positions[0]
		if Vector2(after.x - before.x, after.z - before.z).length() > 0.001:
			check(after.y >= BirdFlock.FLIGHT_HEIGHT - 0.01, "Horizontal travel stays above static arena cover")
		if flock.states[0] == BirdFlock.State.PERCHED:
			returned = true
			break
	check(returned and flock.positions[0].distance_to(BirdFlock.HOMES[0]) < 0.01, "An idle flight returns home")
	var players: PackedVector3Array = PackedVector3Array([BirdFlock.HOMES[0]])
	flock.step(1.0 / 60.0, players)
	check(flock.states[0] == BirdFlock.State.FLEEING, "A nearby player scares a perched bird")
	for frame: int in range(360):
		flock.step(1.0 / 60.0, players)
	check(flock.positions[0].y == BirdFlock.FLIGHT_HEIGHT and flock.states[0] == BirdFlock.State.FLEEING, "A bird stays away while its perch is occupied")
	for frame: int in range(600):
		flock.step(1.0 / 60.0, PackedVector3Array())
		if flock.states[0] == BirdFlock.State.PERCHED:
			break
	check(flock.states[0] == BirdFlock.State.PERCHED and flock.positions[0].distance_to(BirdFlock.HOMES[0]) < 0.01, "A frightened bird returns after players leave")
	flock.positions[0] = Vector3(9.5, BirdFlock.FLIGHT_HEIGHT, 9.5)
	flock.states[0] = BirdFlock.State.FLEEING
	flock.routes[0].clear()
	var corner: Vector3 = flock.positions[0]
	for frame: int in range(120):
		flock.step(1.0 / 60.0, PackedVector3Array([Vector3(9, 1, 9)]))
		check(flock.positions[0].is_finite() and absf(flock.positions[0].x) <= 9.5 and absf(flock.positions[0].z) <= 9.5, "Fleeing stays finite and inside the arena")
	check(flock.positions[0].distance_to(corner) > 2.0, "A cornered bird escapes along the edge")
	if not failed:
		print("WILDLIFE_OK: perch, wander, takeoff clearance, flee, occupied home, return, bounds")
	quit(1 if failed else 0)
