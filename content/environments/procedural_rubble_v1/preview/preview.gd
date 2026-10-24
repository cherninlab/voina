extends Node3D
## Rubble preview room (T-163): one pile per recipe in a torch-lit dungeon corner,
## with Red Descent materials (Rocks025 stone through dungeon_surface.gdshader,
## Wood035 oak on the boards' own along-grain UVs).
## Open preview.tscn and run it, or capture real Mobile/Metal frames:
## scripts/godot_bg.sh --path . res://content/environments/procedural_rubble_v1/preview/preview.tscn -- --capture-dir=/abs/dir
## Walls come from rubble.json: each wall pile's recorded wall plane is put on a real wall face.

const FOLDER: String = "res://content/environments/procedural_rubble_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
const BACK_WALL_Z: float = -3.0
const SIDE_WALL_X: float = -6.0
const SPOTS: Dictionary = {
	"wall_spill": Vector3(-2.2, 0.0, BACK_WALL_Z),
	"corner_heap": Vector3(SIDE_WALL_X, 0.0, BACK_WALL_Z),
	"bridge_debris": Vector3(2.6, 0.0, 0.2),
	"floor_scatter": Vector3(-2.6, 0.0, 2.2),
}

var report: Dictionary = {}
var stone: ShaderMaterial
var wood: StandardMaterial3D
var piles: Array[Node3D] = []
var camera: Camera3D = Camera3D.new()

func _ready() -> void:
	report = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "rubble.json")) as Dictionary
	var maker: RedDescentDungeon = RedDescentDungeon.new()
	# Rocks025 reads as the same grey-brown stone as the walls and floor; the
	# dungeon's marble_rock_03 "rock" turned rubble chocolate-brown and veined.
	stone = maker.surface(PBR + "Rocks025/", 0.526, 0.8, 0.3)
	var wall: ShaderMaterial = maker.surface(PBR + "Bricks089/", 0.16, 0.7, 0.5)
	var ground: ShaderMaterial = maker.surface(PBR + "Rocks025/", 0.526, 0.8, 0.4)
	for material: ShaderMaterial in [wall, ground]:
		material.set_shader_parameter("algae", 0.6)
	maker.free()
	# Boards keep their along-grain UVs (metres), so the oak scan follows each broken plank.
	wood = StandardMaterial3D.new()
	wood.albedo_texture = load(PBR + "Wood035/albedo.png") as Texture2D
	wood.normal_enabled = true
	wood.normal_texture = load(PBR + "Wood035/normal_gl.png") as Texture2D
	wood.roughness_texture = load(PBR + "Wood035/roughness.png") as Texture2D
	wood.vertex_color_use_as_albedo = true
	wood.albedo_color = Color(0.62, 0.6, 0.58)
	wood.uv1_scale = Vector3(0.6, 0.6, 1.0)
	atmosphere()
	slab(Vector3(16.0, 0.4, 13.0), Vector3(0.0, -0.2, 3.5), ground)
	slab(Vector3(16.0, 5.0, 0.6), Vector3(0.0, 2.5, BACK_WALL_Z - 0.3), wall)
	slab(Vector3(0.6, 5.0, 13.0), Vector3(SIDE_WALL_X - 0.3, 2.5, 3.5), wall)
	for at: Vector3 in [Vector3(-4.2, 2.1, BACK_WALL_Z + 0.35), Vector3(1.2, 2.1, BACK_WALL_Z + 0.35)]:
		torch(at)
	add_child(camera)
	camera.fov = 62.0
	camera.position = Vector3(1.6, 2.4, 6.6)
	camera.look_at(Vector3(-1.8, 0.3, -0.6))
	camera.make_current()
	show_seed(1)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture.call_deferred(argument.trim_prefix("--capture-dir="))

func show_seed(pile_seed: int) -> void:
	for pile: Node3D in piles:
		pile.queue_free()
	piles.clear()
	for entry: Variant in report["piles"] as Array:
		var pile_info: Dictionary = entry as Dictionary
		if int(pile_info["seed"]) != pile_seed:
			continue
		var pile: Node3D = (load(FOLDER + String(pile_info["id"]) + ".glb") as PackedScene).instantiate() as Node3D
		var spot: Vector3 = SPOTS[String(pile_info["recipe"])] as Vector3
		# A recorded wall plane (normal +Z: back wall, +X: side wall) lands on that wall face.
		for wall_info: Variant in pile_info["walls_godot"] as Array:
			var plane: Dictionary = wall_info as Dictionary
			var normal: Array = plane["normal"] as Array
			var point: Array = plane["point"] as Array
			if float(normal[2]) > 0.5:
				spot.z -= float(point[2])
			elif float(normal[0]) > 0.5:
				spot.x -= float(point[0])
		pile.position = spot
		for node: Node in pile.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			mesh.material_override = wood if mesh.name.begins_with("Wood") else stone
		add_child(pile)
		piles.append(pile)

func capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	get_window().size = Vector2i(1440, 900)
	# A failed frame must not leave a window running behind the user's apps.
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		printerr("RUBBLE_CAPTURE_FAIL: timed out")
		get_tree().quit(2))
	var views: Array[Array] = [
		["01-overview-seed1", 1, Vector3(1.6, 2.4, 6.6), Vector3(-1.8, 0.3, -0.6), 62.0],
		["02-wall-spill", 1, Vector3(-1.2, 1.55, 0.4), Vector3(-2.2, 0.25, -2.5), 58.0],
		["03-corner-heap", 1, Vector3(-3.6, 1.55, -0.5), Vector3(-5.4, 0.25, -2.4), 58.0],
		["04-bridge-debris", 1, Vector3(4.2, 1.6, 2.9), Vector3(2.6, 0.15, 0.2), 58.0],
		["05-floor-scatter", 1, Vector3(-1.0, 1.6, 4.6), Vector3(-2.6, 0.1, 2.2), 58.0],
		["06-overview-seed2", 2, Vector3(1.6, 2.4, 6.6), Vector3(-1.8, 0.3, -0.6), 62.0],
		["07-overview-seed3", 3, Vector3(1.6, 2.4, 6.6), Vector3(-1.8, 0.3, -0.6), 62.0],
	]
	var shown: int = 1
	for view: Array in views:
		if int(view[1]) != shown:
			shown = int(view[1])
			show_seed(shown)
		camera.fov = float(view[4])
		camera.position = view[2] as Vector3
		camera.look_at(view[3] as Vector3)
		for frame: int in range(40):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var file: String = directory.path_join(String(view[0]) + ".png")
		if image.save_png(file) != OK:
			printerr("RUBBLE_CAPTURE_FAIL: " + file)
			get_tree().quit(1)
			return
		print("RUBBLE_CAPTURE: " + file)
	get_tree().quit(0)

func slab(size: Vector3, at: Vector3, material: Material) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = at
	add_child(instance)

func torch(at: Vector3) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = at
	light.light_color = Color(1.0, 0.63, 0.3)
	light.light_energy = 3.6
	light.omni_range = 10.5
	light.omni_attenuation = 1.25
	light.shadow_enabled = true
	add_child(light)

func atmosphere() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.009, 0.005, 0.005)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.43, 0.46)
	environment.ambient_light_energy = 0.36
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.009, 0.005)
	environment.fog_light_energy = 0.8
	environment.fog_density = 0.009
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
