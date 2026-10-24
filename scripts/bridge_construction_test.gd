extends SceneTree
## Bridge contract: a standing player capsule cannot leave an open crossing
## into the void, measured against the real assembled collision.

const CAPSULE_RADIUS: float = 0.4
const CAPSULE_HEIGHT: float = 1.8
const PROBE_STEP: float = 0.5
const SIDE_ANGLES: Array[float] = [-40.0, 0.0, 40.0]
const END_ANGLES: Array[float] = [-50.0, -25.0, 0.0, 25.0, 50.0]

var space: PhysicsDirectSpaceState3D
var gaps: Array[Dictionary] = []
var probes: int = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	for frame: int in range(4):
		await physics_frame
	space = dungeon.get_world_3d().direct_space_state
	var routes: Array[Dictionary] = RedDescentLayout.routes()
	for path: Dictionary in routes:
		if bool(path["enclosed"]):
			continue
		var id: String = String(path["id"])
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		var width: float = float(path["width"])
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var count: int = maxi(1, ceili(a.distance_to(b) / PROBE_STEP))
			for sample: int in range(count + 1):
				var at: Vector3 = a.lerp(b, float(sample) / float(count))
				if dungeon.architecture.in_room(at):
					continue
				var along: Vector3 = flat(b - a)
				var normals: Array[Vector3] = [Vector3(-along.z, 0, along.x)]
				# At a bend the widest opening lies along the miter, not the segment normal.
				if sample == 0 and index > 0:
					normals.append(miter(points, index))
				if sample == count and index + 2 < points.size():
					normals.append(miter(points, index + 1))
				for normal: Vector3 in normals:
					for sign_value: float in [-1.0, 1.0]:
						for angle: float in SIDE_ANGLES:
							var direction: Vector3 = (normal * sign_value).rotated(Vector3.UP, deg_to_rad(angle))
							var slant: float = cos(deg_to_rad(angle))
							sweep(id, index, at, direction, (width * 0.5 + 1.6) / slant, (width * 0.5 + CAPSULE_RADIUS) / slant, "side")
		# Walk from inside each joining passage onto the crossing, across its full width.
		for end: int in [0, points.size() - 1]:
			var inward: Vector3 = flat(points[1] - points[0]) if end == 0 else flat(points[end - 1] - points[end])
			var joining: Dictionary = joined(routes, path, end)
			if joining.is_empty():
				continue
			var other: PackedVector3Array = joining["points"] as PackedVector3Array
			var into: Vector3 = flat(other[-1] - other[-2]) if other[-1].distance_to(points[end]) < 0.02 else flat(other[0] - other[1])
			var half: float = float(joining["width"]) * 0.5
			var lateral: Vector3 = Vector3(-into.z, 0, into.x)
			var offset: float = -half + 0.5
			while offset <= half - 0.5 + 0.001:
				var start: Vector3 = points[end] - into * 1.5 + lateral * offset
				if on_floor(start) and clear(start):
					for angle: float in END_ANGLES:
						sweep(id, end, start, inward.rotated(Vector3.UP, deg_to_rad(angle)), 4.5, 2.5, "end")
				offset += 0.5
	var failures: Array[String] = []
	for gap: Dictionary in gaps:
		failures.append("Capsule leaves %s (%s, node/segment %d) into the void from %s heading %s" % [gap["route"], gap["kind"], gap["segment"], gap["at"], gap["direction"]])
	var report: Dictionary = {"probes": probes, "gaps": gaps, "failures": failures}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures:
		printerr("BRIDGE_CONSTRUCTION_FAIL: " + failure)
	if failures.is_empty():
		print("BRIDGE_CONSTRUCTION_OK: %d capsule sweeps held on open crossings and their joins" % probes)
	else:
		printerr("BRIDGE_CONSTRUCTION_FAIL: %d of %d sweeps reached the void" % [gaps.size(), probes])
	dungeon.queue_free()
	for frame: int in range(4):
		await process_frame
	quit(0 if failures.is_empty() else 1)

func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0, vector.z).normalized()

func miter(points: PackedVector3Array, node: int) -> Vector3:
	var tangent: Vector3 = (flat(points[node] - points[node - 1]) + flat(points[node + 1] - points[node])).normalized()
	return Vector3(-tangent.z, 0, tangent.x)

func joined(routes: Array[Dictionary], path: Dictionary, end: int) -> Dictionary:
	var at: Vector3 = (path["points"] as PackedVector3Array)[end]
	for other: Dictionary in routes:
		if String(other["id"]) == String(path["id"]):
			continue
		var points: PackedVector3Array = other["points"] as PackedVector3Array
		if points[0].distance_to(at) < 0.02 or points[-1].distance_to(at) < 0.02:
			return other
	return {}

func on_floor(at: Vector3) -> bool:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at - Vector3.UP * 0.4)
	return not space.intersect_ray(ray).is_empty()

## A standing capsule at this floor point touches nothing, so sweeps start free.
func clear(at: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule()
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (CAPSULE_HEIGHT * 0.5 + 0.05))
	return space.intersect_shape(query, 1).is_empty()

func capsule() -> CapsuleShape3D:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	return shape

## Sweeps a standing capsule from a floor point. A sweep that travels at least
## `required` and ends with nothing walkable below it is a gap.
func sweep(route: String, segment: int, at: Vector3, direction: Vector3, reach: float, required: float, kind: String) -> void:
	probes += 1
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule()
	# The capsule floats 5 cm over the deck so only guards and walls can stop it.
	var start: Vector3 = at + Vector3.UP * (CAPSULE_HEIGHT * 0.5 + 0.05)
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = direction * reach
	var travelled: float = space.cast_motion(query)[0] * reach
	if travelled < required:
		return
	var end: Vector3 = start + direction * travelled
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(end, end - Vector3.UP * (CAPSULE_HEIGHT * 0.5 + 1.5))
	if not space.intersect_ray(ray).is_empty():
		return
	gaps.append({"route": route, "segment": segment, "kind": kind, "at": "%.2f, %.2f, %.2f" % [at.x, at.y, at.z], "direction": "%.2f, %.2f" % [direction.x, direction.z], "travelled_m": snappedf(travelled, 0.01)})
