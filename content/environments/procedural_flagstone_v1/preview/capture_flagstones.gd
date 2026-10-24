extends SceneTree
## Re-checks the imported flagstone meshes and captures the 3 x 3 preview grids (T-165).
## Checks only:  "$GODOT" --headless --path . --script res://content/environments/procedural_flagstone_v1/preview/capture_flagstones.gd
## Captures:     scripts/godot_bg.sh --path . --script res://content/environments/procedural_flagstone_v1/preview/capture_flagstones.gd -- --capture-dir=/abs/dir

const PREVIEW: String = "res://content/environments/procedural_flagstone_v1/preview/flagstone_preview.tscn"
const BUDGET: Array[int] = [20000, 10000, 2500]
## name, family, variant ("" mixes variants), camera eye, camera target, torch, corner markers
const SHOTS: Array[Array] = [
	["laid_a_grid", "laid", "laid_a", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), false],
	["laid_a_grid_marked", "laid", "laid_a", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), true],
	["laid_mixed_grid", "laid", "", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), false],
	["laid_mixed_torch", "laid", "", Vector3(1.7, 1.7, 1.4), Vector3(4.6, 0.0, 4.5), Vector3(6.2, 0.5, 3.4), false],
	["laid_mixed_torch_marked", "laid", "", Vector3(1.7, 1.7, 1.4), Vector3(4.6, 0.0, 4.5), Vector3(6.2, 0.5, 3.4), true],
	["coursed_a_grid", "coursed", "coursed_a", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), false],
	["coursed_mixed_grid", "coursed", "", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), false],
	["coursed_mixed_grid_marked", "coursed", "", Vector3(6.0, 8.6, -2.6), Vector3(6.0, 0.0, 6.4), Vector3(6.4, 0.45, 5.2), true],
	["coursed_mixed_torch", "coursed", "", Vector3(1.7, 1.7, 1.4), Vector3(4.6, 0.0, 4.5), Vector3(6.2, 0.5, 3.4), false],
	["border_mixed", "border", "", Vector3(6.0, 2.4, -2.2), Vector3(6.0, 0.0, 1.0), Vector3(6.3, 0.5, 2.2), false],
]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var directory: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	var failures: Array[String] = []
	var modules: Dictionary = {}
	for family: String in FlagstoneFloor.FAMILIES:
		for id: String in FlagstoneFloor.FAMILIES[family]:
			modules[id] = check_module(family, id, failures)
	var report: Dictionary = {"modules": modules, "failures": failures, "shots": []}
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		root.size = Vector2i(1280, 720)
		for shot: Array in SHOTS:
			report["shots"].append(await capture(shot, directory))
		var file: FileAccess = FileAccess.open(directory.path_join("godot-check.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t", false) + "\n")
		file.close()
	for failure: String in failures:
		push_error("FLAGSTONE_CHECK: " + failure)
	print("FLAGSTONE_CHECK_", "OK" if failures.is_empty() else "FAILED", ": ", JSON.stringify(summary(modules)))
	quit(0 if failures.is_empty() else 1)

func summary(modules: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in modules:
		var levels: Array = modules[id]["levels"] as Array
		result[id] = {"tris": levels.map(func(level: Dictionary) -> int: return int(level["triangles"])),
			"seam_mm": levels.map(func(level: Dictionary) -> float: return float(level["seam_mm"]))}
	return result

func check_module(family: String, id: String, failures: Array[String]) -> Dictionary:
	var depth: float = FlagstoneFloor.BORDER_WIDTH if family == "border" else FlagstoneFloor.SIZE
	var levels: Array[Dictionary] = []
	for level: int in range(3):
		var triangles: int = 0
		var seam: float = 0.0
		var low: Vector3 = Vector3.INF
		var high: Vector3 = -Vector3.INF
		var bedding_green: Array[float] = []
		var ao_low: float = 1.0
		for part: String in FlagstoneFloor.PARTS:
			var mesh: Mesh = FlagstoneFloor.mesh(id, part, level)
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
				if colors.size() != vertices.size() or uvs.size() != vertices.size():
					failures.append("%s %s lod%d lacks colours or UVs" % [id, part, level])
					continue
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				for index: int in range(vertices.size()):
					low = low.min(vertices[index])
					high = high.max(vertices[index])
					ao_low = minf(ao_low, colors[index].r)
					if part == "dirt" and absf(vertices[index].y + 0.019) < 0.0002:
						bedding_green.append(colors[index].g)
				seam = maxf(seam, border_mismatch(vertices, 0, FlagstoneFloor.SIZE))
				if family != "border":
					seam = maxf(seam, border_mismatch(vertices, 2, depth))
		if triangles > BUDGET[level]:
			failures.append("%s lod%d has %d triangles" % [id, level, triangles])
		if seam > 1.0:
			failures.append("%s lod%d border mismatch %.3f mm" % [id, level, seam])
		if low.x < -0.0005 or low.z < -0.0005 or high.x > FlagstoneFloor.SIZE + 0.0005 or high.z > depth + 0.0005:
			failures.append("%s lod%d leaves its footprint: %s..%s" % [id, level, low, high])
		if low.y < -0.0215 or high.y > 0.0205:
			failures.append("%s lod%d height %.4f..%.4f m exceeds +/-2 cm" % [id, level, low.y, high.y])
		var green: float = 0.0
		for value: float in bedding_green:
			green += value / float(bedding_green.size())
		levels.append({"level": level, "triangles": triangles, "seam_mm": snappedf(seam, 0.0001),
			"aabb_min": [low.x, low.y, low.z], "aabb_max": [high.x, high.y, high.z],
			"ao_min": snappedf(ao_low, 0.001), "bedding_green": snappedf(green, 0.001)})
	return {"family": family, "levels": levels}

## Largest distance (mm) from a vertex on one border to the nearest vertex on the opposite
## border, translated by one module: the module is tiled against itself.
func border_mismatch(vertices: PackedVector3Array, axis: int, size: float) -> float:
	var other: int = 2 - axis
	var buckets: Dictionary[int, Array] = {}
	var near: PackedVector2Array = PackedVector2Array()
	for vertex: Vector3 in vertices:
		var point: Vector2 = Vector2(vertex[other], vertex.y)
		if absf(vertex[axis] - size) < 0.0002:
			var key: int = floori(point.x / 0.02)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(point)
		elif absf(vertex[axis]) < 0.0002:
			near.append(point)
	if near.is_empty() and buckets.is_empty():
		return 0.0
	var worst: float = 0.0
	for point: Vector2 in near:
		var best: float = INF
		var key: int = floori(point.x / 0.02)
		for k: int in [key - 1, key, key + 1]:
			if buckets.has(k):
				for candidate: Vector2 in buckets[k]:
					best = minf(best, point.distance_to(candidate))
		worst = maxf(worst, best)
	return worst * 1000.0

func capture(shot: Array, directory: String) -> Dictionary:
	var preview: Node3D = (load(PREVIEW) as PackedScene).instantiate() as Node3D
	preview.set("family", String(shot[1]))
	preview.set("variant", String(shot[2]))
	preview.set("grid", Vector2i(3, 6) if String(shot[1]) == "border" else Vector2i(3, 3))
	preview.set("torch_position", shot[5] as Vector3)
	preview.set("markers", bool(shot[6]))
	preview.set("fill", String(shot[0]).contains("grid") or String(shot[1]) == "border")
	root.add_child(preview)
	current_scene = preview
	var camera: Camera3D = preview.get_node("Camera3D") as Camera3D
	camera.fov = 55.0 if String(shot[0]).ends_with("grid") or String(shot[0]).ends_with("grid_marked") else 62.0
	camera.position = shot[3] as Vector3
	camera.look_at(shot[4] as Vector3)
	camera.make_current()
	for frame: int in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = directory.path_join("godot_%s.png" % String(shot[0]))
	var error: Error = root.get_texture().get_image().save_png(path)
	preview.queue_free()
	await process_frame
	print("FLAGSTONE_CAPTURE: ", path, " ", error)
	return {"shot": String(shot[0]), "file": path.get_file(), "saved": error == OK}
