class_name BirdFlock
extends RefCounted

enum State { PERCHED, FLYING, FLEEING }
const HOMES: Array[Vector3] = [Vector3(-5, 1.35, -4), Vector3(5, 1.35, 4), Vector3(-5, 1.35, 4), Vector3(5, 1.35, -4)]
const FLIGHT_HEIGHT: float = 4.0
const FLEE_DISTANCE: float = 3.5
const RETURN_DISTANCE: float = 5.0
var positions: PackedVector3Array = PackedVector3Array()
var states: PackedInt32Array = PackedInt32Array()
var routes: Array[PackedVector3Array] = []
var waits: PackedFloat32Array = PackedFloat32Array()
var random: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		random.randomize()
	else:
		random.seed = seed_value
	for home: Vector3 in HOMES:
		positions.append(home)
		states.append(State.PERCHED)
		routes.append(PackedVector3Array())
		waits.append(random.randf_range(4.0, 9.0))

func nearby(location: Vector3, players: PackedVector3Array, radius: float) -> Vector3:
	var nearest: Vector3 = Vector3.INF
	var closest: float = radius
	for player: Vector3 in players:
		# Ground-plane distance also lets birds notice a player below their perch.
		var distance: float = Vector2(location.x - player.x, location.z - player.z).length()
		if distance < closest:
			closest = distance
			nearest = player
	return nearest

func flight_route(index: int, destination: Vector3, returning: bool) -> PackedVector3Array:
	var current: Vector3 = positions[index]
	var path: PackedVector3Array = PackedVector3Array([Vector3(current.x, FLIGHT_HEIGHT, current.z), Vector3(destination.x, FLIGHT_HEIGHT, destination.z)])
	if returning:
		path.append(HOMES[index])
	return path

func step(delta: float, players: PackedVector3Array) -> void:
	for index: int in range(HOMES.size()):
		var threat: Vector3 = nearby(positions[index], players, FLEE_DISTANCE)
		if threat.is_finite() and (states[index] != State.FLEEING or routes[index].is_empty()):
			var away: Vector3 = positions[index] - threat
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = Vector3.RIGHT
			var destination: Vector3 = positions[index] + away.normalized() * 5.0
			destination.x = clampf(destination.x, -9.5, 9.5)
			destination.z = clampf(destination.z, -9.5, 9.5)
			if Vector2(destination.x - positions[index].x, destination.z - positions[index].z).length() < 2.0:
				# Turn along the arena edge when the direct escape is blocked by our bounds.
				var tangent: Vector3 = away.normalized().rotated(Vector3.UP, PI / 2.0) * 5.0
				destination = positions[index] + tangent
				destination.x = clampf(destination.x, -9.5, 9.5)
				destination.z = clampf(destination.z, -9.5, 9.5)
			routes[index] = flight_route(index, destination, false)
			states[index] = State.FLEEING
		if not routes[index].is_empty():
			var point: Vector3 = routes[index][0]
			positions[index] = positions[index].move_toward(point, delta * (4.5 if states[index] == State.FLEEING else 2.5))
			if positions[index].distance_to(point) < 0.01:
				routes[index].remove_at(0)
			continue
		if states[index] == State.FLEEING:
			# Wait in the air until both the landing area and the bird itself are clear.
			if not nearby(HOMES[index], players, RETURN_DISTANCE).is_finite() and not threat.is_finite():
				routes[index] = flight_route(index, HOMES[index], true)
				states[index] = State.FLYING
		elif states[index] == State.FLYING:
			states[index] = State.PERCHED
			waits[index] = random.randf_range(4.0, 9.0)
		else:
			waits[index] -= delta
			if waits[index] <= 0:
				var destination: Vector3 = HOMES[index] + Vector3(random.randf_range(-2.5, 2.5), 0, random.randf_range(-2.5, 2.5))
				routes[index] = flight_route(index, destination, true)
				# Pass over the home at flight height before descending, rather than cutting through cover.
				routes[index].insert(2, Vector3(HOMES[index].x, FLIGHT_HEIGHT, HOMES[index].z))
				states[index] = State.FLYING
