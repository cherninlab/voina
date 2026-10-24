extends SceneTree
## Writes the real Red Descent routes, ribbons, supports and rooms to JSON for
## the Blender generators, in Godot coordinates (metres, Y up).
## godot --headless --path . -s scripts/art/export_dungeon_layout.gd -- --out=/abs/layout.json

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var out: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if out.is_empty():
		printerr("LAYOUT_EXPORT_FAIL: pass --out=/absolute/path.json")
		quit(1)
		return
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	# Only its build is needed; per-frame match logic expects a world parent.
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(dungeon)
	await process_frame
	var geometry: RedDescentGeometry = dungeon.architecture
	var routes: Array[Dictionary] = []
	for path: Dictionary in geometry.paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		var edges: PackedVector3Array = geometry.route_edges(path)
		var in_room: Array[bool] = []
		for point: Vector3 in points:
			in_room.append(geometry.in_room(point))
		var supports: Array[Dictionary] = []
		for bearing: Dictionary in geometry.structure.bearings:
			if String(bearing["route"]) == String(path["id"]):
				supports.append({"type": bearing["type"], "deck": vector(bearing["deck"]), "seat": vector(bearing["seat"])})
		routes.append({
			"id": path["id"], "width": path["width"], "wood": path["wood"], "enclosed": path["enclosed"],
			"points": vectors(points), "edges": vectors(edges), "in_room": in_room, "supports": supports,
			"layout_hash": DungeonStructure.layout_hash(path, edges),
		})
	var rooms: Array[Dictionary] = []
	for room: Dictionary in geometry.rooms:
		var polygon: Array = []
		for point: Vector2 in room["points"] as PackedVector2Array:
			polygon.append([point.x, point.y])
		rooms.append({"id": room["id"], "floor": room["floor"], "height": room["height"], "points": polygon})
	var layout: Dictionary = {
		"units": "metres, Godot axes (Y up)",
		"baked_seat_depth": DungeonStructure.BAKED_SEAT_DEPTH,
		"baked_stringer_bottom": DungeonStructure.BAKED_STRINGER_BOTTOM,
		"routes": routes, "rooms": rooms,
		"outline": polygon2(RedDescentLayout.outline()), "spine": polygon2(RedDescentLayout.spine()),
	}
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(layout, "\t"))
	file.close()
	print("LAYOUT_EXPORT_OK: %d routes, %d rooms -> %s" % [routes.size(), rooms.size(), out])
	dungeon.queue_free()
	await process_frame
	quit(0)

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func vectors(values: PackedVector3Array) -> Array:
	var result: Array = []
	for value: Vector3 in values:
		result.append(vector(value))
	return result

func polygon2(values: PackedVector2Array) -> Array:
	var result: Array = []
	for value: Vector2 in values:
		result.append([value.x, value.y])
	return result
