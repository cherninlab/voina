extends SceneTree
## Real Mobile/Metal frames; use godot_bg.sh with --dungeon --shading-ephemeral.
## --stone-rooms replaces the views with every room built stone by stone
## (add --no-stone-rooms for the same frames of the old box walls).

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/red-descent"
	var dressing_views: bool = "--dressing" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1440, 900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	for frame: int in range(90):
		await process_frame
	# Hide presentation UI while preserving the map's full-screen shading pass.
	world.get_node("GameUI").set_process(false)
	root.disable_3d = false # The offline title normally suspends 3D rendering.
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		var script: Script = node.get_script() as Script
		(node as CanvasLayer).visible = script != null and script.resource_path == "res://ui/shading.gd"
	var dungeon: RedDescentDungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	var stone: ShaderMaterial = dungeon.architecture.materials["stone"] as ShaderMaterial
	print("CAPTURE_STONE: ", (stone.get_shader_parameter("albedo_map") as Texture2D).resource_path, " scale ", stone.get_shader_parameter("scale"))
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 78
	var views: Array[Array] = [
		["01-high-crossing", RedDescentLayout.at(Vector3(36.8, 1.05, 35.5)), RedDescentLayout.at(Vector3(55, -6, 47))],
		["02-central-wall", RedDescentLayout.at(Vector3(48.5, -11.35, 41)), RedDescentLayout.at(Vector3(32, -9, 42))],
		["03-low-crossing", RedDescentLayout.at(Vector3(47, -23.35, 54)), RedDescentLayout.at(Vector3(59, -18, 61))],
		["04-broken-nave", RedDescentLayout.at(Vector3(57, -16.35, 79)), RedDescentLayout.at(Vector3(52, -12, 94))],
		["05-deep-choir", RedDescentLayout.at(Vector3(86, -26.35, 54)), RedDescentLayout.at(Vector3(88, -23, 41))],
		["06-descent-overlook", RedDescentLayout.at(Vector3(64, -1.3, 35)), RedDescentLayout.at(Vector3(46, -16, 54))],
		["07-timber-detail", RedDescentLayout.at(Vector3(38.6, 0.9, 36.8)), RedDescentLayout.at(Vector3(41, -0.6, 39)), 58.0],
		["08-nave-materials", RedDescentLayout.at(Vector3(46, -16.35, 87)), RedDescentLayout.at(Vector3(39, -15.7, 90)), 65.0],
	]
	var metrics: Array[Dictionary] = []
	if "--stone-rooms" in OS.get_cmdline_user_args():
		views = stone_room_views()
	if dressing_views:
		views.append_array([
			["09-entry-floor", Vector3(-41, 1.65, -24), Vector3(-43, 0.3, -29), 65.0],
			["10-restraint-frame", Vector3(40, -2.35, -8), Vector3(40, -1.8, -13), 65.0],
			["11-nave-framing", Vector3(0, -3.5, 31), Vector3(0, -1.4, 38.5), 78.0],
			["12-bell-hangings", Vector3(32, -16.35, 34), Vector3(32, -11.3, 38), 78.0],
			["13-chapel-spill", Vector3(3, -8.35, -37), Vector3(3, -9.6, -41.4), 65.0],
			["14-choir-debris", Vector3(33, -26.35, -4), Vector3(30, -27.7, -8), 65.0],
		])
	for view: Array in views:
		camera.fov = float(view[3]) if view.size() > 3 else 78.0
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(36):
			await process_frame
		# What sits in the middle of the frame, to trace stray geometry to its builder.
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 60.0)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			print("CAPTURE_CENTRE_HIT: %s %s at %s" % [view[0], (hit["collider"] as Node).get_path(), hit["position"]])
		var intervals: Array[float] = []
		for frame: int in range(20):
			var started: int = Time.get_ticks_usec()
			await process_frame
			intervals.append(float(Time.get_ticks_usec() - started) / 1000.0)
		intervals.sort()
		metrics.append({"view": String(view[0]), "capture_frame_median_ms": intervals[10], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		# Explicit draw also completes captures while macOS throttles an unfocused window.
		RenderingServer.force_draw()
		var file: String = directory.path_join(String(view[0]) + ".png")
		var frame_image: Image = root.get_texture().get_image()
		var low: float = 1.0
		var high: float = 0.0
		for y: int in range(0, frame_image.get_height(), 48):
			for x: int in range(0, frame_image.get_width(), 48):
				var value: float = frame_image.get_pixel(x, y).get_luminance()
				low = minf(low, value)
				high = maxf(high, value)
		if high - low < 0.04:
			printerr("DUNGEON_CAPTURE_FAIL: blank frame " + file)
			quit(1)
			return
		if frame_image.save_png(file) != OK:
			printerr("DUNGEON_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("DUNGEON_CAPTURE: " + file)
	var metrics_file: FileAccess = FileAccess.open(directory.path_join("render-metrics.json"), FileAccess.WRITE)
	metrics_file.store_string(JSON.stringify(metrics, "\t"))
	# Let the audio thread retire active Ogg playbacks before this scripted capture exits.
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()

## For each room with a stone build: from the middle at eye height towards each
## of its four longest walls, a corner view up the full height, and a close look
## at every wall a route passes through.
func stone_room_views() -> Array[Array]:
	var result: Array[Array] = []
	for room: Dictionary in RedDescentLayout.rooms():
		var id: String = String(room["id"])
		if not ResourceLoader.exists(RedDescentGeometry.STONE_ROOMS + id + ".glb"):
			continue
		var polygon: PackedVector2Array = room["points"] as PackedVector2Array
		var floor_y: float = float(room["floor"])
		var centre: Vector2 = Vector2.ZERO
		for point: Vector2 in polygon:
			centre += point / float(polygon.size())
		var walls: Array[int] = []
		walls.assign(range(polygon.size()))
		walls.sort_custom(func(a: int, b: int) -> bool: return polygon[a].distance_to(polygon[(a + 1) % polygon.size()]) > polygon[b].distance_to(polygon[(b + 1) % polygon.size()]))
		var eye: Vector3 = Vector3(centre.x, floor_y + 1.6, centre.y)
		for index: int in walls.slice(0, 4):
			var middle: Vector2 = (polygon[index] + polygon[(index + 1) % polygon.size()]) * 0.5
			result.append(["%s-wall-%d" % [id, index], eye, Vector3(middle.x, floor_y + 2.2, middle.y), 70.0])
			var inward: Vector2 = (centre - middle).normalized()
			var close: Vector2 = middle + inward * 3.2
			result.append(["%s-wall-%d-close" % [id, index], Vector3(close.x, floor_y + 1.6, close.y), Vector3(middle.x, floor_y + 1.9, middle.y), 62.0])
		# Walls that face the open shaft, seen from out in the void.
		for index: int in range(polygon.size()):
			var middle: Vector2 = (polygon[index] + polygon[(index + 1) % polygon.size()]) * 0.5
			var outward: Vector2 = (middle - centre).normalized()
			var probe: Vector2 = middle + outward * 2.0
			if not Geometry2D.is_point_in_polygon(probe, RedDescentLayout.outline()):
				continue
			var from_void: Vector2 = middle + outward * 8.0
			result.append(["%s-outside-%d" % [id, index], Vector3(from_void.x, floor_y + 2.5, from_void.y), Vector3(middle.x, floor_y + 3.0, middle.y), 70.0])
		var corner: Vector2 = polygon[walls[0]].lerp(centre, 0.22)
		result.append(["%s-corner-up" % id, Vector3(corner.x, floor_y + 1.4, corner.y), Vector3(centre.x * 2.0 - corner.x, floor_y + float(room["height"]) * 0.7, centre.y * 2.0 - corner.y), 82.0])
	# Inside each stone passage, both ways, and from just outside each end.
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(RedDescentGeometry.STONE_INDEX)) if FileAccess.file_exists(RedDescentGeometry.STONE_INDEX) else null
	if index is Dictionary:
		for entry: Variant in (index as Dictionary).get("passages", []) as Array:
			var passage: Dictionary = entry as Dictionary
			for path: Dictionary in RedDescentLayout.routes():
				if String(path["id"]) != String(passage["route"]):
					continue
				var points: PackedVector3Array = path["points"] as PackedVector3Array
				var a: Vector3 = points[int(passage["segment"])]
				var b: Vector3 = points[int(passage["segment"]) + 1]
				var start: Vector3 = a.lerp(b, float(passage["t0"]))
				var finish: Vector3 = a.lerp(b, float(passage["t1"]))
				var middle: Vector3 = (start + finish) * 0.5
				var along: Vector3 = (finish - start).normalized()
				var label: String = String(passage["file"]).get_file().get_basename()
				result.append([label + "-forward", middle - along * 0.6 + Vector3.UP * 1.6, finish + along * 3.0 + Vector3.UP * 1.8, 72.0])
				result.append([label + "-back", middle + along * 0.6 + Vector3.UP * 1.6, start - along * 3.0 + Vector3.UP * 1.8, 72.0])
				result.append([label + "-approach", start - along * 4.5 + Vector3.UP * 1.6, middle + Vector3.UP * 1.9, 70.0])
				result.append([label + "-leave", finish + along * 4.5 + Vector3.UP * 1.6, middle + Vector3.UP * 1.9, 70.0])
	return result
