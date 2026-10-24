extends SceneTree
## Checks the assembled scene: sockets on framing, grounded hulls, route clearance.

func _initialize() -> void:
	run.call_deferred()

func triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal: Vector3 = (b - a).cross(c - a)
	var best: float = minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))
	if normal.length_squared() < 0.000000000001:
		return best
	normal = normal.normalized()
	var projected: Vector3 = point - normal * (point - a).dot(normal)
	if (b - a).cross(projected - a).dot(normal) >= -0.0000001 and (c - b).cross(projected - b).dot(normal) >= -0.0000001 and (a - c).cross(projected - c).dot(normal) >= -0.0000001:
		best = minf(best, point.distance_to(projected))
	return best

func timber_distance(point: Vector3, structure: DungeonStructure, actual: bool = false) -> float:
	var best: float = INF
	for index: int in range(structure.members.size()):
		var member: Dictionary = structure.members[index]
		var a: Vector3 = member["from"] as Vector3
		var b: Vector3 = member["to"] as Vector3
		var up: Vector3 = Vector3.FORWARD if absf((b - a).normalized().y) > 0.98 else Vector3.UP
		var basis: Basis = Basis.looking_at(b - a, up)
		var local: Vector3 = basis.inverse() * (point - (a + b) * 0.5)
		var half: Vector3 = Vector3(float(member["width"]), float(member["depth"]), a.distance_to(b)) * 0.5
		var excess: Vector3 = (local.abs() - half).max(Vector3.ZERO)
		if not actual:
			best = minf(best, excess.length())
		elif excess.length() < 0.10:
			# Match the runtime timber transform/variant, then measure the sculpted
			# surface rather than trusting its ideal rectangular bounding volume.
			var transform: Transform3D = Transform3D(basis * Basis.from_scale(half * 2.0), (a + b) * 0.5)
			var triangles: PackedVector3Array = structure.mesh("hewn_timber_%d" % (index % 3)).get_faces()
			for face: int in range(0, triangles.size(), 3):
				best = minf(best, triangle_distance(point, transform * triangles[face], transform * triangles[face + 1], transform * triangles[face + 2]))
	return best

func route_margin(bounds: AABB, hanging: bool = false) -> float:
	var clearance: float = INF
	for path: Dictionary in RedDescentLayout.routes():
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for segment: int in range(points.size() - 1):
			var count: int = maxi(1, ceili(points[segment].distance_to(points[segment + 1]) / 0.15))
			for sample: int in range(count + 1):
				var at: Vector3 = points[segment].lerp(points[segment + 1], float(sample) / float(count))
				if hanging:
					if at.y + 2.2 < bounds.position.y or at.y > bounds.end.y:
						continue
				elif absf(at.y - bounds.position.y) > 0.5:
					continue
				var dx: float = maxf(maxf(bounds.position.x - at.x, at.x - bounds.end.x), 0.0)
				var dz: float = maxf(maxf(bounds.position.z - at.z, at.z - bounds.end.z), 0.0)
				clearance = minf(clearance, Vector2(dx, dz).length() - float(path["width"]) * 0.5)
	return clearance

func run() -> void:
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	for frame: int in range(4):
		await physics_frame
	var failures: Array[String] = []
	var dressing: RedDescentDressing = dungeon.dressing
	var records: Array[Dictionary] = []
	var bodies: Array[RID] = []
	for body: Node in dressing.find_children("*", "StaticBody3D", true, false):
		bodies.append((body as StaticBody3D).get_rid())
		if not (body as StaticBody3D).global_basis.get_scale().is_equal_approx(Vector3.ONE):
			failures.append("Scaled rubble collision: " + str(body.get_path()))
	if dressing.piles.size() != 8 or dressing.hangings.size() != 10:
		failures.append("Missing generated dressing")
	if get_nodes_in_group("flagstone_room_floors").size() != 11:
		failures.append("Missing integrated room floors")
	var bracket_anchors: int = 0
	for mount: Dictionary in dressing.practical_mounts:
		var inward: Vector3 = mount["inward"] as Vector3
		for rise: float in [0.3, 1.15]:
			var anchor: Vector3 = (mount["wall"] as Vector3) + Vector3.UP * (rise - 4.0)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(anchor + inward * 1.1, anchor - inward)
			var hit: Dictionary = dungeon.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(anchor) > 0.85:
				failures.append("High practical bracket has no masonry backing: " + str(anchor))
			bracket_anchors += 1
	var max_socket_error: float = 0.0
	var max_pin_gap: float = 0.0
	var max_actual_gap: float = 0.0
	var max_web_gap: float = 0.0
	var min_route_clearance: float = INF
	var expected_hulls: int = 0
	for shape_node: Node in dressing.find_children("*", "CollisionShape3D", true, false):
		if not (shape_node as CollisionShape3D).global_basis.get_scale().is_equal_approx(Vector3.ONE):
			failures.append("Scaled rubble collision shape: " + str(shape_node.get_path()))
	for placement: Dictionary in dressing.placements:
		var node: Node3D = placement["node"] as Node3D
		var asset: Dictionary = placement["asset"] as Dictionary
		var bounds: Dictionary = asset["bounds_godot"] as Dictionary
		var minimum: Vector3 = RedDescentDressing.vector(bounds["min"] as Array)
		var maximum: Vector3 = RedDescentDressing.vector(bounds["max"] as Array)
		var world_bounds: AABB = node.global_transform * AABB(minimum, maximum - minimum)
		var record: Dictionary = {"id": placement["id"], "kind": placement["kind"], "origin": str(node.global_position), "asset": asset.get("glb", asset.get("file", ""))}
		if String(placement["kind"]) == "hanging":
			var sockets: Dictionary = asset["sockets_godot"] as Dictionary
			for key: String in sockets:
				var socket: Node3D = node.find_child("socket_" + key, true, false) as Node3D
				if socket == null:
					failures.append("Missing socket " + String(placement["id"]) + ":" + key)
					continue
				var expected: Vector3 = node.global_transform * RedDescentDressing.vector(sockets[key] as Array)
				var error: float = socket.global_position.distance_to(expected)
				var gap: float = timber_distance(socket.global_position, dungeon.architecture.structure)
				var actual_gap: float = timber_distance(socket.global_position, dungeon.architecture.structure, true)
				var web: bool = String(asset["type"]).begins_with("web")
				max_socket_error = maxf(max_socket_error, error)
				max_pin_gap = maxf(max_pin_gap, gap)
				max_actual_gap = maxf(max_actual_gap, actual_gap)
				if web:
					max_web_gap = maxf(max_web_gap, actual_gap)
				if error > 0.001 or gap > 0.016 or actual_gap > (0.008 if web else 0.03):
					failures.append("Unseated socket %s:%s (transform %.5fm, nominal %.5fm, sculpted %.5fm)" % [String(placement["id"]), key, error, gap, actual_gap])
			if not node.find_children("*", "CollisionShape3D", true, false).is_empty():
				failures.append("Decorative hanging gained collision: " + String(placement["id"]))
			record["material"] = placement["material"]
			if route_margin(world_bounds, true) < 0.35:
				failures.append("Hanging crosses character headroom: " + String(placement["id"]))
		else:
			expected_hulls += int((asset["collision"] as Dictionary)["convex_hulls"])
			# Exclude the pile itself so the support ray proves a real room floor.
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(node.global_position + Vector3.UP * 0.08, node.global_position - Vector3.UP * 0.12)
			query.exclude = bodies
			var hit: Dictionary = dungeon.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or absf((hit["position"] as Vector3).y - node.global_position.y) > 0.025:
				failures.append("Ungrounded pile " + String(placement["id"]))
			for plane: Dictionary in asset["walls_godot"] as Array:
				var point: Vector3 = node.global_transform * RedDescentDressing.vector(plane["point"] as Array) + Vector3.UP * 0.18
				var normal: Vector3 = node.global_basis * RedDescentDressing.vector(plane["normal"] as Array)
				var wall_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + normal * 0.2, point - normal * 0.2)
				wall_query.exclude = bodies
				var wall_hit: Dictionary = dungeon.get_world_3d().direct_space_state.intersect_ray(wall_query)
				if wall_hit.is_empty() or (wall_hit["position"] as Vector3).distance_to(point) > 0.03:
					failures.append("Wall pile misses actual inner face: " + String(placement["id"]))
			# Conservative world AABB against every route ribbon at this floor.
			var clearance: float = route_margin(world_bounds)
			min_route_clearance = minf(min_route_clearance, clearance)
			record["ribbon_clearance_m"] = clearance
			if clearance < 0.4:
				failures.append("Pile crowds walking ribbon: %s (%.3fm)" % [String(placement["id"]), clearance])
		records.append(record)
	if bodies.size() != expected_hulls:
		failures.append("Imported hull count differs from bake reports: %d vs %d" % [bodies.size(), expected_hulls])
	var report: Dictionary = {"placements": records, "piles": dressing.piles.size(), "hangings": dressing.hangings.size(), "convex_bodies": bodies.size(), "room_floors": get_nodes_in_group("flagstone_room_floors").size(), "practical_masonry_anchors": bracket_anchors, "max_socket_transform_error_m": max_socket_error, "max_pin_to_nominal_framing_gap_m": max_pin_gap, "max_pin_to_sculpted_surface_m": max_actual_gap, "max_web_to_sculpted_surface_m": max_web_gap, "min_pile_to_route_ribbon_m": min_route_clearance, "failures": failures}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures:
		printerr("DUNGEON_DRESSING_FAIL: " + failure)
	if failures.is_empty():
		print("DUNGEON_DRESSING_OK: 8 grounded rubble piles, 10 socket-mounted hangings, 11 room floors; sculpted pin gaps %.4fm, web gaps %.4fm, route margin %.3fm" % [max_actual_gap, max_web_gap, min_route_clearance])
	dungeon.queue_free()
	for frame: int in range(4):
		await process_frame
	quit(0 if failures.is_empty() else 1)
