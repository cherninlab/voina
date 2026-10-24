extends SceneTree
## Audit assembled construction, including real wall and foundation intersections.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	for frame: int in range(4):
		await physics_frame
	var structure: DungeonStructure = dungeon.architecture.structure
	var failures: Array[String] = []
	var supports: Array[Dictionary] = []
	var expected: int = 0
	for path: Dictionary in RedDescentLayout.routes():
		if not bool(path["enclosed"]):
			for at: Vector3 in path["points"] as PackedVector3Array:
				if not dungeon.architecture.in_room(at):
					expected += 1
	if structure.bearings.size() != expected:
		failures.append("Missing load-bearing joints: %d of %d" % [structure.bearings.size(), expected])
	for bearing: Dictionary in structure.bearings:
		var base: Vector3 = bearing["base"] as Vector3
		var deck: Vector3 = bearing["deck"] as Vector3
		if String(bearing["type"]) == "foundation pier":
			if not is_equal_approx(base.y, -60.0):
				failures.append("Pier does not reach existing foundation: " + str(base))
			# The radius includes the wider foot of the tapered pier. Verify each
			# lower passage with independent dense centerline samples.
			for path: Dictionary in RedDescentLayout.routes():
				var route: PackedVector3Array = path["points"] as PackedVector3Array
				for segment: int in range(route.size() - 1):
					var count: int = ceili(route[segment].distance_to(route[segment + 1]) / 0.25)
					for sample: int in range(count + 1):
						var at: Vector3 = route[segment].lerp(route[segment + 1], float(sample) / float(count))
						if at.y < deck.y - 2.3 and Vector2(at.x - base.x, at.z - base.z).length() < float(path["width"]) * 0.5 + 1.1:
							failures.append("Pier intersects lower route " + String(path["id"]))
		else:
			var horizontal: Vector3 = structure.nearest_wall(deck) - deck
			horizontal.y = 0
			horizontal = horizontal.normalized()
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(base - horizontal * 2.0, base + horizontal * 2.0)
			var hit: Dictionary = dungeon.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				failures.append("Wall brace has no actual masonry at " + str(base))
		supports.append({"route": bearing["route"], "type": bearing["type"], "base": str(base), "deck": str(deck)})
	# Roof rafters must terminate on the same node as the tie or king post.
	for member: Dictionary in structure.members:
		if String(member["role"]) in ["wall brace", "wall bearer", "knee brace", "pier cap"]:
			var from: Vector3 = member["from"] as Vector3
			var to: Vector3 = member["to"] as Vector3
			var count: int = ceili(from.distance_to(to) / 0.2)
			for sample: int in range(count + 1):
				var at: Vector3 = from.lerp(to, float(sample) / float(count))
				for path: Dictionary in RedDescentLayout.routes():
					var route: PackedVector3Array = path["points"] as PackedVector3Array
					for index: int in range(route.size() - 1):
						var a: Vector3 = route[index]
						var b: Vector3 = route[index + 1]
						var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
						var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)
						var floor_y: float = lerpf(a.y, b.y, t)
						if at.y > floor_y - 0.1 and at.y < floor_y + 2.3 and near.distance_to(Vector2(at.x, at.z)) < float(path["width"]) * 0.5 + 0.15:
							failures.append("Support timber intrudes into " + String(path["id"]) + " " + str(at))
		if String(member["role"]) != "rafter":
			continue
		for end: String in ["from", "to"]:
			var touches: bool = false
			for other: Dictionary in structure.members:
				if String(other["role"]) in ["roof tie", "king post"]:
					if (member[end] as Vector3).distance_to(other["from"] as Vector3) < 0.01 or (member[end] as Vector3).distance_to(other["to"] as Vector3) < 0.01:
						touches = true
			if not touches:
				failures.append("Rafter end is not joined: " + str(member[end]))
	var report: Dictionary = {"supports": supports, "member_count": structure.members.size(), "cloth_pins": structure.cloth_pins.size(), "failures": failures}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures:
		printerr("DUNGEON_STRUCTURE_FAIL: " + failure)
	if failures.is_empty():
		print("DUNGEON_STRUCTURE_OK: %d fitted bearings, %d framing/board members, %d baked cloth pins; lower routes clear" % [supports.size(), structure.members.size(), structure.cloth_pins.size()])
	dungeon.queue_free()
	for frame: int in range(4):
		await process_frame
	quit(0 if failures.is_empty() else 1)
