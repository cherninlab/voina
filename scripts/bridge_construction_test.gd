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
	var deck: Dictionary = deck_agreement(dungeon, routes, failures)
	for gap: Dictionary in gaps:
		failures.append("Capsule leaves %s (%s, node/segment %d) into the void from %s heading %s" % [gap["route"], gap["kind"], gap["segment"], gap["at"], gap["direction"]])
	var report: Dictionary = {"probes": probes, "gaps": gaps, "deck": deck, "failures": failures}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures:
		printerr("BRIDGE_CONSTRUCTION_FAIL: " + failure)
	if failures.is_empty():
		print("BRIDGE_CONSTRUCTION_OK: %d capsule sweeps held on open crossings and their joins; %d baked decks within %.3f m of the walking surface at %d lane samples" % [probes, deck["bridges"], deck["max_m"], deck["samples"]])
	else:
		printerr("BRIDGE_CONSTRUCTION_FAIL: %d of %d sweeps reached the void" % [gaps.size(), probes])
	dungeon.queue_free()
	for frame: int in range(4):
		await process_frame
	quit(0 if failures.is_empty() else 1)

## Every open wooden route uses its current bake, and the visible boards sit
## within 3 cm of the collision ribbon along the walking lanes.
func deck_agreement(dungeon: RedDescentDungeon, routes: Array[Dictionary], failures: Array[String]) -> Dictionary:
	var structure: DungeonStructure = dungeon.architecture.structure
	var wooden: int = 0
	for path: Dictionary in routes:
		if bool(path["wood"]) and not bool(path["enclosed"]):
			wooden += 1
	if structure.bridges.size() != wooden:
		failures.append("Only %d of %d wooden crossings use a current bake (stale layout_hash or missing GLB)" % [structure.bridges.size(), wooden])
	# Board triangles bucketed per metre in plan for top-down rays.
	var cells: Dictionary[Vector2i, PackedVector3Array] = {}
	for bridge: Node3D in structure.bridges:
		for node: Node in bridge.find_children("Wood_*", "MeshInstance3D", true, false):
			var visual: MeshInstance3D = node as MeshInstance3D
			var faces: PackedVector3Array = visual.mesh.get_faces()
			for index: int in range(0, faces.size(), 3):
				var a: Vector3 = visual.global_transform * faces[index]
				var b: Vector3 = visual.global_transform * faces[index + 1]
				var c: Vector3 = visual.global_transform * faces[index + 2]
				var low: Vector2i = Vector2i(floori(minf(a.x, minf(b.x, c.x))), floori(minf(a.z, minf(b.z, c.z))))
				var high: Vector2i = Vector2i(floori(maxf(a.x, maxf(b.x, c.x))), floori(maxf(a.z, maxf(b.z, c.z))))
				for x: int in range(low.x, high.x + 1):
					for z: int in range(low.y, high.y + 1):
						var cell: Vector2i = Vector2i(x, z)
						if not cells.has(cell):
							cells[cell] = PackedVector3Array()
						cells[cell].append_array(PackedVector3Array([a, b, c]))
	var worst: float = 0.0
	var samples: int = 0
	for path: Dictionary in routes:
		if not bool(path["wood"]) or bool(path["enclosed"]):
			continue
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		var gone: Array[PackedVector2Array] = missing_boards(String(path["id"]))
		for index: int in range(points.size() - 1):
			var along: Vector3 = flat(points[index + 1] - points[index])
			var lateral: Vector3 = Vector3(-along.z, 0, along.x)
			var count: int = ceili(points[index].distance_to(points[index + 1]) / 0.6)
			for sample: int in range(1, count):
				for offset: float in [-0.75, 0.0, 0.75]:
					var best: float = INF
					# Three rays 10 cm apart: at least one lands on a board, not a gap.
					for shift: float in [0.0, 0.1, 0.2]:
						var at: Vector3 = points[index].lerp(points[index + 1], float(sample) / float(count)) + lateral * offset + along * shift
						if missing_board(gone, at):
							continue
						var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at - Vector3.UP * 0.5)
						var hit: Dictionary = space.intersect_ray(ray)
						var board: float = board_top(cells, at)
						if not hit.is_empty() and board > -INF:
							best = minf(best, absf(board - (hit["position"] as Vector3).y))
					if best == INF:
						continue
					samples += 1
					if best > 0.03:
						failures.append("Baked deck of %s segment %d is %.3f m off the walking surface near %s" % [path["id"], index, best, points[index].lerp(points[index + 1], float(sample) / float(count))])
					elif best < INF:
						worst = maxf(worst, best)
	return {"bridges": structure.bridges.size(), "samples": samples, "max_m": snappedf(worst, 0.001)}

## Boards the physics-aged bake left out on purpose (rot or knocked off),
## from the bake report: footprints in the Godot XZ plane.
func missing_boards(route: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(DungeonStructure.BRIDGE_ROOT + route + ".json"))
	if report is Dictionary:
		for quad: Variant in (report as Dictionary).get("missing_boards_godot_xz", []):
			var polygon: PackedVector2Array = PackedVector2Array()
			for corner: Variant in quad as Array:
				polygon.append(Vector2(float((corner as Array)[0]), float((corner as Array)[1])))
			result.append(polygon)
	return result

func missing_board(gone: Array[PackedVector2Array], at: Vector3) -> bool:
	for polygon: PackedVector2Array in gone:
		if Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), polygon):
			return true
	return false

func board_top(cells: Dictionary[Vector2i, PackedVector3Array], at: Vector3) -> float:
	var faces: PackedVector3Array = cells.get(Vector2i(floori(at.x), floori(at.z)), PackedVector3Array())
	var top: float = -INF
	for index: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(at + Vector3.UP * 0.5, Vector3.DOWN, faces[index], faces[index + 1], faces[index + 2])
		if hit != null and (hit as Vector3).y > top and (hit as Vector3).y < at.y + 0.3:
			top = (hit as Vector3).y
	return top

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
