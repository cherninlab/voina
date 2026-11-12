class_name HitResolver
extends RefCounted
## Host-side lag compensation. The host keeps a short history of every player's position and
## judges an attack against where targets were on the attacker's screen, capped by MAX_REWIND.
## The rewind comes from the ENet-measured round trip, never from client-sent timestamps.

const HISTORY_SECONDS: float = 0.4
const MAX_REWIND: float = 0.2
## Remote bodies show their latest 60 Hz snapshot projected to the present (RemoteMotion), so the
## attacker's screen trails targets only by network transit, which the round trip already covers.
const VIEW_LAG: float = 0.0
const MAX_HEAD_START: float = 0.06
const CAPSULE_RADIUS: float = 0.4
const CAPSULE_HALF_SEGMENT: float = 0.5
const CHEST_HEIGHT: float = 0.65

class PositionHistory:
	var times: PackedFloat64Array = PackedFloat64Array()
	var positions: PackedVector3Array = PackedVector3Array()

	func record(time: float, position: Vector3) -> void:
		times.append(time)
		positions.append(position)
		var drop: int = 0
		while drop < times.size() - 1 and times[drop] < time - HitResolver.HISTORY_SECONDS:
			drop += 1
		if drop > 0:
			times = times.slice(drop)
			positions = positions.slice(drop)

	func clear() -> void:
		times.clear()
		positions.clear()

	## Position at `time`, interpolated between samples and clamped to the recorded range.
	func sample(time: float, fallback: Vector3) -> Vector3:
		if times.is_empty():
			return fallback
		for index: int in range(times.size() - 1, 0, -1):
			if times[index - 1] <= time:
				if time >= times[index]:
					return positions[index]
				var weight: float = (time - times[index - 1]) / (times[index] - times[index - 1])
				return positions[index - 1].lerp(positions[index], weight)
		return positions[0]

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

## How far back the attacker's screen showed other players. The host's own player has no round trip.
static func rewind_seconds(attacker_round_trip: float) -> float:
	return clampf(attacker_round_trip + VIEW_LAG, 0.0, MAX_REWIND)

## A client's melee swing started one-way latency before its request reached the host.
static func head_start_seconds(attacker_round_trip: float) -> float:
	return clampf(attacker_round_trip * 0.5, 0.0, MAX_HEAD_START)

static func in_cone(origin: Vector3, forward: Vector3, target: Vector3, reach: float, half_angle: float) -> bool:
	var offset: Vector3 = target - origin
	return offset.length() <= reach and forward.dot(offset.normalized()) >= cos(half_angle)

## Distance along the segment to where it passes within the capsule, or -1.0 if it misses.
static func segment_hits_capsule(from: Vector3, to: Vector3, center: Vector3) -> float:
	var offset: Vector3 = from - center
	var axis_point: Vector3 = Vector3(0, clampf(offset.y, -CAPSULE_HALF_SEGMENT, CAPSULE_HALF_SEGMENT), 0)
	if offset.distance_squared_to(axis_point) <= CAPSULE_RADIUS * CAPSULE_RADIUS:
		return 0.0
	var length: float = from.distance_to(to)
	if length <= 0.000001:
		return -1.0
	var direction: Vector3 = (to - from) / length
	var entry: float = INF
	# The capsule is the union of a cylinder and its two spherical caps. A grazing
	# ray enters later than closest-distance minus radius, which could put it before cover.
	var heights: Array[float] = [-CAPSULE_HALF_SEGMENT, CAPSULE_HALF_SEGMENT]
	for height: float in heights:
		var relative: Vector3 = offset - Vector3.UP * height
		var along: float = relative.dot(direction)
		var discriminant: float = along * along - relative.length_squared() + CAPSULE_RADIUS * CAPSULE_RADIUS
		if discriminant >= -0.0000001:
			var distance: float = -along - sqrt(maxf(0.0, discriminant))
			if distance >= 0.0 and distance <= length:
				entry = minf(entry, distance)
	var flat: float = direction.x * direction.x + direction.z * direction.z
	if flat > 0.000001:
		var along: float = offset.x * direction.x + offset.z * direction.z
		var radial: float = offset.x * offset.x + offset.z * offset.z - CAPSULE_RADIUS * CAPSULE_RADIUS
		var discriminant: float = along * along - flat * radial
		if discriminant >= -0.0000001:
			var distances: Array[float] = [(-along - sqrt(maxf(0.0, discriminant))) / flat, (-along + sqrt(maxf(0.0, discriminant))) / flat]
			for distance: float in distances:
				if distance >= 0.0 and distance <= length and absf(offset.y + direction.y * distance) <= CAPSULE_HALF_SEGMENT:
					entry = minf(entry, distance)
	return entry if is_finite(entry) else -1.0

## Distance to the first static obstacle; players are excluded because their bodies are in the present.
static func wall_distance(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return from.distance_to(to)
	return from.distance_to(result["position"] as Vector3)

## Index of the nearest target the ray reaches before a wall, or -1.
static func first_ray_target(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, centers: PackedVector3Array, exclude: Array[RID]) -> int:
	var best: int = -1
	var best_distance: float = wall_distance(space, from, to, exclude)
	for index: int in range(centers.size()):
		var distance: float = segment_hits_capsule(from, to, centers[index])
		if distance >= 0.0 and distance < best_distance:
			best = index
			best_distance = distance
	return best
