class_name AimAssist
extends RefCounted
## Look-sensitivity friction while the crosshair rests on a hittable body. Players and mobs share
## a 0.4 m x 1.8 m capsule centred on the node, so a target counts when the aim ray passes within
## the old 0.35 m sweep radius of that capsule. One occlusion ray checks only the nearest candidate:
## sweeping a sphere 40 m through the village every tick cost up to 48 ms per frame.

const RANGE: float = 40.0
const TOLERANCE: float = 0.35 + 0.4 # sweep radius + capsule radius
const HALF_AXIS: float = 0.5 # capsule half height minus its radius
const FRICTION: float = 0.55

# Distance along the ray to its closest approach to the target's capsule axis, or -1 when it misses.
static func hit_distance(origin: Vector3, forward: Vector3, center: Vector3) -> float:
	var axis_low: Vector3 = center - Vector3.UP * HALF_AXIS
	var best_along: float = -1.0
	var best_gap: float = INF
	# Closest points between the ray and the axis segment, sampled along the short axis.
	for step: int in range(5):
		var point: Vector3 = axis_low + Vector3.UP * (HALF_AXIS * 0.5 * step)
		var along: float = (point - origin).dot(forward)
		if along <= 0.0 or along > RANGE:
			continue
		var gap: float = (origin + forward * along).distance_to(point)
		if gap < best_gap:
			best_gap = gap
			best_along = along
	return best_along if best_gap <= TOLERANCE else -1.0

# The nearest hittable body under the crosshair, ignoring walls; null when none.
static func nearest(origin: Vector3, forward: Vector3, candidates: Array[Node3D], exclude: Node3D) -> Node3D:
	var best: Node3D = null
	var best_along: float = INF
	for candidate: Node3D in candidates:
		if candidate == exclude or not is_instance_valid(candidate) or not candidate.is_inside_tree():
			continue
		var along: float = hit_distance(origin, forward, candidate.global_position)
		if along >= 0.0 and along < best_along:
			best_along = along
			best = candidate
	return best

static func friction(camera: Camera3D, candidates: Array[Node3D], exclude: CollisionObject3D) -> float:
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z.normalized()
	var target: Node3D = nearest(origin, forward, candidates, exclude)
	if target == null:
		return 1.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target.global_position)
	query.exclude = [exclude.get_rid()]
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") != target:
		return 1.0
	return FRICTION
