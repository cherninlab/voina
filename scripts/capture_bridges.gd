extends SceneTree
## Bridge review frames: a fixed close set, or with --tour a full walk of every
## open wooden crossing (deck views both ways per segment, side views per span,
## close-ups of every missing board from the bake report).
## scripts/godot_bg.sh --path . --script scripts/capture_bridges.gd -- --dungeon --shading-ephemeral --capture-dir=/abs/dir [--tour] [--no-baked-bridges]

const VIEWS: Array[Array] = [
	# name, eye, target (level coordinates before RedDescentLayout.at), fov
	["b1-high-bend", Vector3(43.0, 0.3, 37.4), Vector3(50.0, -1.8, 36.6), 70.0],
	["b2-high-underside", Vector3(49.5, -5.2, 32.6), Vector3(53.0, -2.7, 35.0), 70.0],
	["b3-high-entry", Vector3(26.5, 1.6, 33.2), Vector3(34.0, -0.4, 35.2), 70.0],
	["b4-low-bend", Vector3(31.5, -22.4, 34.3), Vector3(38.5, -24.3, 38.5), 70.0],
	["b5-low-side", Vector3(44.0, -23.0, 61.5), Vector3(51.0, -26.0, 56.0), 70.0],
	["b6-rail-detail", Vector3(39.6, 0.4, 37.0), Vector3(41.8, -0.4, 38.9), 50.0],
]
const EYE: float = 1.6

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/red-descent-bridges"
	var tour: bool = "--tour" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1600, 1000) if tour else Vector2i(1440, 900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	for frame: int in range(90):
		await process_frame
	world.get_node("GameUI").set_process(false)
	root.disable_3d = false
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		var script: Script = node.get_script() as Script
		(node as CanvasLayer).visible = script != null and script.resource_path == "res://ui/shading.gd"
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var views: Array[Array] = []
	if tour:
		views = tour_views(world)
	else:
		for view: Array in VIEWS:
			views.append([view[0], RedDescentLayout.at(view[1] as Vector3), RedDescentLayout.at(view[2] as Vector3), view[3]])
	for view: Array in views:
		camera.fov = float(view[3])
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		# The window runs unfocused (godot_bg.sh), where macOS throttles it; a
		# dozen frames is enough for lights and shadows to settle.
		for frame: int in range(12 if tour else 30):
			await process_frame
		await RenderingServer.frame_post_draw
		var file: String = directory.path_join(String(view[0]) + ".png")
		if root.get_texture().get_image().save_png(file) != OK:
			printerr("BRIDGE_CAPTURE_FAIL: " + file)
			quit(1)
			return
		print("BRIDGE_CAPTURE: " + file)
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10):
		await process_frame
	quit()

## Every open wooden crossing, in world coordinates: [name, eye, target, fov].
func tour_views(world: Node3D) -> Array[Array]:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var result: Array[Array] = []
	for path: Dictionary in RedDescentLayout.routes():
		if not bool(path["wood"]) or bool(path["enclosed"]):
			continue
		var id: String = String(path["id"])
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		var width: float = float(path["width"])
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var along: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var side: Vector3 = Vector3(-along.z, 0, along.x)
			var label: String = "%s_%02d" % [id, index]
			# Walking the deck both ways, a little off centre like a player would.
			result.append([label + "_walk_forward", a + along * 0.6 + side * 0.4 + Vector3.UP * EYE, b + Vector3.UP * 0.6, 72.0])
			result.append([label + "_walk_back", b - along * 0.6 - side * 0.4 + Vector3.UP * EYE, a + Vector3.UP * 0.6, 72.0])
			# Broadside from whichever side has room, slightly above the deck.
			var middle: Vector3 = (a + b) * 0.5
			for sign_value: float in [1.0, -1.0]:
				var eye: Vector3 = middle + side * sign_value * (width * 0.5 + 5.5) + Vector3.UP * 1.2
				eye = unblocked(space, middle + Vector3.UP * 0.5, eye)
				if eye.distance_to(middle) > width * 0.5 + 2.5:
					result.append([label + "_side_" + ("right" if sign_value > 0 else "left"), eye, middle - Vector3.UP * 0.3, 70.0])
					break
			# Looking down at the deck from the rail, to read boards and gaps.
			result.append([label + "_deck_down", middle + side * (width * 0.5 - 0.3) + Vector3.UP * 1.9, middle - side * 0.5, 75.0])
		var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(DungeonStructure.BRIDGE_ROOT + id + ".json"))
		if report is Dictionary:
			var gaps: Array = (report as Dictionary).get("missing_boards_godot_xz", [])
			for number: int in range(gaps.size()):
				var centre: Vector2 = Vector2.ZERO
				for corner: Variant in gaps[number] as Array:
					centre += Vector2(float((corner as Array)[0]), float((corner as Array)[1])) * 0.25
				var deck: Vector3 = nearest_on_route(points, Vector3(centre.x, 0, centre.y))
				var target: Vector3 = Vector3(centre.x, deck.y, centre.y)
				var back: Vector3 = (Vector3(points[0].x, 0, points[0].z) - Vector3(target.x, 0, target.z)).normalized()
				result.append(["%s_missing_board_%d" % [id, number], target + back * 1.4 + Vector3.UP * 1.5, target, 70.0])
	return result

## Pull a camera in front of any wall between it and what it looks at.
func unblocked(space: PhysicsDirectSpaceState3D, target: Vector3, eye: Vector3) -> Vector3:
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(target, eye))
	if hit.is_empty():
		return eye
	return (hit["position"] as Vector3).move_toward(target, 0.4)

func nearest_on_route(points: PackedVector3Array, at: Vector3) -> Vector3:
	var best: Vector3 = points[0]
	var distance: float = INF
	for index: int in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
		var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)
		var candidate: Vector3 = Vector3(near.x, lerpf(a.y, b.y, t), near.y)
		if candidate.distance_to(at * Vector3(1, 0, 1) + Vector3.UP * candidate.y) < distance:
			distance = candidate.distance_to(at * Vector3(1, 0, 1) + Vector3.UP * candidate.y)
			best = candidate
	return best
