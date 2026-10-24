extends SceneTree
## Run headless; --baseline records the untouched collision and visible threshold overlap.

const REVIEW: String = "res://content/environments/red_descent/review/floor_integration_v1/"

func _initialize() -> void:
	run.call_deferred()

func polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(polygon.size()):
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(area) * 0.5

func run() -> void:
	var baseline: bool = "--baseline" in OS.get_cmdline_user_args()
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	for frame: int in range(4):
		await physics_frame
	var failures: Array[String] = []
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var collision_vertices: int = 0
	for node: Node in dungeon.architecture.find_children("*", "CollisionShape3D", true, false):
		var shape: ConcavePolygonShape3D = (node as CollisionShape3D).shape as ConcavePolygonShape3D
		if shape != null:
			var vertices: PackedVector3Array = shape.get_faces()
			collision_vertices += vertices.size()
			digest.update(vertices.to_byte_array())
	var collision_sha256: String = digest.finish().hex_encode()
	var overlap_m2: float = 0.0
	var overlapping_triangles: int = 0
	var floor_triangles: int = 0
	for node: Node in dungeon.architecture.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.material_override != dungeon.architecture.materials["floor"]:
			continue
		var vertices: PackedVector3Array = visual.mesh.get_faces()
		floor_triangles += vertices.size() / 3
		for index: int in range(0, vertices.size(), 3):
			var a: Vector3 = vertices[index]
			var b: Vector3 = vertices[index + 1]
			var c: Vector3 = vertices[index + 2]
			if not is_equal_approx(a.y, b.y) or not is_equal_approx(a.y, c.y):
				continue
			var triangle: PackedVector2Array = PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
			for room: Dictionary in RedDescentLayout.rooms():
				if not is_equal_approx(a.y, float(room["floor"])):
					continue
				var area: float = 0.0
				for polygon: PackedVector2Array in Geometry2D.intersect_polygons(triangle, room["points"] as PackedVector2Array):
					area += polygon_area(polygon)
				if area > 0.00001:
					overlap_m2 += area
					overlapping_triangles += 1
	var floors: Array[Dictionary] = []
	var total_modules: int = 0
	var mesh_nodes: int = 0
	var lod_mesh_counts: Array[int] = [0, 0, 0]
	var shadow_casting_meshes: int = 0
	for node: Node in get_nodes_in_group("flagstone_room_floors"):
		var floor: Node3D = node as Node3D
		var count: int = int(floor.get_meta("module_count"))
		total_modules += count
		mesh_nodes += floor.find_children("*", "MeshInstance3D", true, false).size()
		floors.append({"room": floor.get_meta("room_id"), "family": floor.get_meta("family"), "modules": count, "children": floor.get_child_count(), "at": str(floor.position)})
		if floor.transform != Transform3D.IDENTITY or floor.get_child_count() != count:
			failures.append("Unexpected floor transform/count: " + String(floor.name))
		for child: Node in floor.find_children("*", "MeshInstance3D", true, false):
			var visual: MeshInstance3D = child as MeshInstance3D
			var level: int = int(String(visual.name).right(1))
			lod_mesh_counts[level] += 1
			if visual.visibility_range_begin != FlagstoneFloor.LOD_RANGES[level].x or visual.visibility_range_end != FlagstoneFloor.LOD_RANGES[level].y:
				failures.append("Unexpected floor LOD range: " + String(visual.name))
			if visual.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_casting_meshes += 1
	if not baseline:
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REVIEW + "baseline.json")) as Dictionary
		if collision_sha256 != String(previous["collision_sha256"]):
			failures.append("Original architecture collision changed")
		if overlap_m2 > 0.00001:
			failures.append("Legacy horizontal route visuals still overlap rooms: %.8f m2" % overlap_m2)
		if floors.size() != RedDescentLayout.rooms().size():
			failures.append("Expected 11 room floors, got %d" % floors.size())
	var report: Dictionary = {"collision_sha256": collision_sha256, "collision_vertices": collision_vertices, "legacy_floor_triangles": floor_triangles, "horizontal_floor_room_overlap_m2": overlap_m2, "overlapping_triangles": overlapping_triangles, "room_floors": floors, "total_modules": total_modules, "mesh_nodes": mesh_nodes, "lod_ranges_m": [[0, 14], [14, 32], [32, 90]], "lod_mesh_counts": lod_mesh_counts, "shadow_casting_meshes": shadow_casting_meshes, "failures": failures}
	var destination: String = REVIEW + ("baseline.json" if baseline else "audit.json")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	for failure: String in failures:
		printerr("FLOOR_INTEGRATION_FAIL: " + failure)
	print("FLOOR_INTEGRATION_%s: %d rooms, %d modules, collision %s, legacy overlap %.8f m2" % ["OK" if failures.is_empty() else "FAIL", floors.size(), total_modules, collision_sha256, overlap_m2])
	dungeon.queue_free()
	for frame: int in range(4):
		await process_frame
	quit(0 if failures.is_empty() else 1)
