extends SceneTree
## Hangs T-164 dressing on a real Red Descent nave roof tie at runtime (no gameplay file is
## changed; T-162 owns placement) and saves Mobile/Metal frames. Sockets come from bake.json.
## scripts/godot_bg.sh --path . --script res://content/environments/procedural_hanging_v1/preview/capture_in_dungeon.gd -- --dungeon --shading-ephemeral --capture-dir=/abs/dir

const ROOT: String = "res://content/environments/procedural_hanging_v1/"

var assets: Dictionary[String, Dictionary] = {}

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var directory: String = "/tmp/hanging-dungeon"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "bake.json")) as Dictionary
	for entry: Variant in report["assets"]:
		var asset: Dictionary = entry as Dictionary
		assets["%s_%d" % [asset["type"], int(asset["variant"])]] = asset
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
	var dungeon: RedDescentDungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	var nave: Dictionary = {}
	for room: Dictionary in dungeon.architecture.rooms:
		if String(room["id"]) == "nave":
			nave = room
	# The middle roof tie of the nave trusses: 0.42 m wide x 0.55 m deep, wall to wall.
	var ties: Array[Dictionary] = []
	for member: Dictionary in dungeon.architecture.structure.members:
		if String(member["role"]) == "roof tie":
			ties.append(member)
	assert(ties.size() >= 2, "no nave roof ties")
	var tie: Dictionary = ties[ties.size() / 2]
	var a: Vector3 = tie["from"] as Vector3
	var b: Vector3 = tie["to"] as Vector3
	var along: Vector3 = (b - a).normalized()
	var middle: Vector3 = (a + b) * 0.5
	var depth: float = float(tie["depth"])
	assert(is_equal_approx(depth, 0.55) and is_equal_approx(float(tie["width"]), 0.42), "drape_1 is baked for the 0.42 x 0.55 m roof tie")
	var underside: float = middle.y - depth * 0.5
	var across: Vector3 = along.cross(Vector3.UP).normalized()
	var polygon: PackedVector2Array = nave["points"] as PackedVector2Array
	var probe: Vector3 = middle + across * 7.0
	if not Geometry2D.is_point_in_polygon(Vector2(probe.x, probe.z), polygon):
		across = -across
	var frame: Basis = Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var span: float = a.distance_to(b)
	# Along the tie from the left wall: banners, a drape, the tapestry with a lost nail.
	var parent: Node3D = dungeon
	hang(parent, "banner_1", a + along * (span * 0.22) + Vector3.UP * (underside - a.y), frame, "cloth_crimson")
	hang(parent, "drape_1", a + along * (span * 0.36), frame, "cloth_ash")
	hang(parent, "tapestry_1", a + along * (span * 0.66) + Vector3.UP * (underside - a.y), frame, "cloth_crimson")
	hang(parent, "banner_0", a + along * (span * 0.8) + Vector3.UP * (underside - a.y), frame, "cloth_ochre")
	# Corner web between the tie top and the king post side: the frame web turned upside down.
	var king_post_side: Vector3 = middle - along * 0.13 + Vector3.UP * (depth * 0.5)
	hang(parent, "web_corner_2", king_post_side, frame * Basis(Vector3(0, 0, 1), PI), "cobweb_corner")
	# The nave roof is 18 m above its torches: two capture-only warm lamps stand in for the
	# brazier light T-162 would need up there. They are not part of the assets.
	for fraction: float in [0.3, 0.72]:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.position = a + along * (span * fraction) + across * 2.6 - Vector3.UP * 2.2
		lamp.light_color = Color(1.0, 0.63, 0.3)
		lamp.light_energy = 3.0
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.2
		lamp.shadow_enabled = true
		world.add_child(lamp)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var views: Array[Dictionary] = [
		{"name": "11-nave-roof-tie", "from": a + along * (span * 0.5) + across * 8.0 - Vector3.UP * 3.2, "to": a + along * (span * 0.5) - Vector3.UP * 1.2, "fov": 70.0},
		{"name": "12-banner-on-nave-tie", "from": a + along * (span * 0.25) + across * 3.6 - Vector3.UP * 1.5, "to": a + along * (span * 0.235) - Vector3.UP * 1.0, "fov": 55.0},
	]
	for view: Dictionary in views:
		camera.fov = float(view["fov"])
		camera.position = view["from"] as Vector3
		camera.look_at(view["to"] as Vector3)
		camera.make_current()
		for wait: int in range(40):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var file: String = directory.path_join(String(view["name"]) + ".png")
		if image.save_png(file) != OK:
			printerr("HANGING_DUNGEON_FAIL: " + file)
			quit(1)
			return
		print("HANGING_DUNGEON_CAPTURE: " + file)
	print("HANGING_DUNGEON_TIE: from %s to %s underside %.3f" % [str(a), str(b), underside])
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for wait: int in range(10):
		await process_frame
	quit()

func hang(parent: Node3D, id: String, origin: Vector3, basis: Basis, material: String) -> void:
	var scene: Node3D = (load(ROOT + id + ".glb") as PackedScene).instantiate() as Node3D
	scene.transform = Transform3D(basis, origin)
	parent.add_child(scene)
	for mesh: Node in scene.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = load(ROOT + material + ".tres") as Material
	var sockets: Dictionary = assets[id]["sockets_godot"] as Dictionary
	print("HANGING_DUNGEON_PLACED: %s sockets %s" % [id, str(sockets.keys())])
