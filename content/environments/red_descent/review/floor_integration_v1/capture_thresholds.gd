extends SceneTree
## Actual match-world captures, run windowed through scripts/godot_bg.sh -- --host --dungeon.

const REVIEW: String = "res://content/environments/red_descent/review/floor_integration_v1/"
const VIEWS: Array[Array] = [
	["entry-threshold", Vector3(-34.0, 1.65, -23.5), Vector3(-28.5, 0.0, -23.2)],
	["antechamber-threshold", Vector3(-29.6, 1.65, -23.1), Vector3(-23.0, 0.0, -23.1)],
	["nave-threshold", Vector3(7.0, -16.35, 26.2), Vector3(7.0, -18.0, 31.5)],
	["cells-threshold", Vector3(34.0, -2.35, -1.7), Vector3(34.0, -4.0, 3.0)],
	["nave-far-floor", Vector3(7.0, -16.35, 26.2), Vector3(0.0, -18.0, 46.0)],
	["chapel-far-floor", Vector3(21.5, -8.35, -31.0), Vector3(-8.0, -10.0, -34.0)],
]

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var folder: String = "after"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			folder = argument.trim_prefix("--output=")
	var directory: String = REVIEW + folder
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1440, 900)
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
	camera.fov = 70.0
	world.add_child(camera)
	var metrics: Array[Dictionary] = []
	for view: Array in VIEWS:
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for frame: int in range(36):
			await process_frame
		var intervals: Array[float] = []
		for frame: int in range(20):
			var started: int = Time.get_ticks_usec()
			await process_frame
			intervals.append(float(Time.get_ticks_usec() - started) / 1000.0)
		intervals.sort()
		metrics.append({"view": view[0], "eye": str(camera.position), "target": str(view[2]), "capture_frame_median_ms": intervals[10], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		await RenderingServer.frame_post_draw
		var destination: String = directory.path_join(String(view[0]) + ".png")
		root.get_texture().get_image().save_png(destination)
		print("FLOOR_CAPTURE: " + destination)
	var file: FileAccess = FileAccess.open(directory.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t") + "\n")
	file.close()
	world.queue_free()
	for frame: int in range(12):
		await process_frame
	quit()
