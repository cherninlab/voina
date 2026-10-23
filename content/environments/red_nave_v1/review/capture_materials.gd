extends SceneTree
## Material response check, not a gameplay-level capture. Run through godot_bg.sh.

const BASE: String = "res://content/environments/red_nave_v1/"
const FAMILIES: Array[String] = [
	"red_lime_plaster", "rubble_masonry", "pale_limestone",
	"broken_stone_floor", "aged_oak", "oxidized_iron",
]

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	root.size = Vector2i(1800, 1200)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.043, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.87, 0.95)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_energy = 1.4
	light.light_color = Color(1.0, 0.97, 0.92)
	light.rotation_degrees = Vector3(-28, -36, 0)
	world.add_child(light)
	var materials: Array[StandardMaterial3D] = []
	for index: int in range(FAMILIES.size()):
		var family: String = FAMILIES[index]
		var material: StandardMaterial3D = load(BASE + family + "/material.tres") as StandardMaterial3D
		if material == null:
			printerr("MATERIAL_PREVIEW_FAIL: " + family)
			quit(1)
			return
		materials.append(material)
		var center: Vector3 = Vector3((index % 3 - 1) * 3.7, 1.8 - (index / 3) * 3.4, 0)
		var tile: MeshInstance3D = MeshInstance3D.new()
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = Vector2(3.2, 2.6)
		tile.mesh = mesh
		tile.material_override = material
		tile.position = center
		world.add_child(tile)
		var sphere: MeshInstance3D = MeshInstance3D.new()
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = 0.38
		sphere_mesh.height = 0.76
		sphere.mesh = sphere_mesh
		sphere.material_override = material
		sphere.position = center + Vector3(1.1, -0.9, 0.45)
		world.add_child(sphere)
		var label: Label3D = Label3D.new()
		label.text = family.replace("_", " ").to_upper()
		label.font_size = 42
		label.pixel_size = 0.008
		label.position = center + Vector3(0, -1.6, 0.05)
		label.no_depth_test = true
		world.add_child(label)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 0.05, 14)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.make_current()
	for mode: String in ["neutral", "repeat"]:
		if mode == "repeat":
			for material: StandardMaterial3D in materials:
				material.uv1_scale = Vector3(2, 2, 1)
		for frame: int in range(45):
			await process_frame
		await RenderingServer.frame_post_draw
		var output: String = BASE + "review/materials-" + mode + ".png"
		if root.get_texture().get_image().save_png(output) != OK:
			printerr("MATERIAL_PREVIEW_FAIL: cannot save " + output)
			quit(1)
			return
		print("MATERIAL_PREVIEW_OK: six materials, ", mode, ", ", output)
	quit()
