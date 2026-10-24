extends SceneTree
## Standalone material review; uses the scoped stochastic shader candidate without scene placement.

const BASE: String = "res://content/environments/stone_brick_materials_v1/"
const SHADER: Shader = preload("res://content/environments/stone_brick_materials_v1/stone_brick_stochastic.gdshader")
var _camera: Camera3D
var _panel: MeshInstance3D
var _label: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.025, 0.029, 0.034)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.52, 0.60, 0.70)
	world.environment.ambient_light_energy = 0.38
	stage.add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-20.0, -55.0, 0.0)
	key.light_color = Color(1.0, 0.83, 0.65)
	key.light_energy = 2.4
	stage.add_child(key)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 100.0
	stage.add_child(_camera)
	_camera.make_current()
	_panel = MeshInstance3D.new()
	stage.add_child(_panel)
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(20.0, 12.0)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(_label)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "materials.json")) as Dictionary
	var materials: Dictionary = data["materials"] as Dictionary
	var ids: Array = materials.keys()
	ids.sort()
	var report: Dictionary = {"engine": Engine.get_version_info(), "shader": SHADER.resource_path, "materials": []}
	for asset_id: String in ids:
		var entry: Dictionary = materials[asset_id] as Dictionary
		var size: Array = entry["size"] as Array
		var folder: String = BASE + "materials/" + asset_id + "/"
		var material: ShaderMaterial = load(folder + "surface.tres") as ShaderMaterial
		if material == null:
			push_error("Material preset failed: " + asset_id)
			quit(1)
			return
		material = material.duplicate() as ShaderMaterial
		var valid: bool = material.shader == SHADER
		for map_name: String in ["albedo", "normal_gl", "roughness", "height", "ao"]:
			var parameter: String = "normal_map" if map_name == "normal_gl" else map_name + "_map"
			var texture: Texture2D = material.get_shader_parameter(parameter) as Texture2D
			valid = valid and texture != null and texture.resource_path == folder + map_name + ".png"
			valid = valid and texture.get_width() == int(size[0]) and texture.get_height() == int(size[1])
		if not valid:
			push_error("Material texture import failed: " + asset_id)
			quit(1)
			return
		material.set_shader_parameter("wet_map", load("res://content/environments/bridge_well_v1/masks/wet_patches.png"))
		material.set_shader_parameter("aspect", 1.0)
		material.set_shader_parameter("scale", float(entry["density"]))
		material.set_shader_parameter("relief_m", float(entry["recommended_relief_m"]))
		var tile_m: float = float(entry["tile_m"])
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE * tile_m * 3.0
		_panel.mesh = quad
		_panel.material_override = material
		_camera.size = tile_m * 3.45
		_camera.position = Vector3(0.0, 0.0, tile_m * 5.0)
		_camera.look_at(Vector3.ZERO)
		var captures: Array[String] = []
		for mode: String in ["repeat", "varied", "wet"]:
			material.set_shader_parameter("normal_strength", float(entry["recommended_normal_strength"]))
			material.set_shader_parameter("anti_tile", mode != "repeat")
			material.set_shader_parameter("wetness", 0.70 if mode == "wet" else 0.0)
			_label.text = asset_id + "  |  " + mode.to_upper() + "  |  3 x 3 repeats\nActual Godot Mobile / T-183 stochastic material"
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = "review/stochastic/" + asset_id + "-" + mode + ".png"
			var absolute: String = ProjectSettings.globalize_path(BASE + path)
			DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
			if root.get_texture().get_image().save_png(absolute) != OK:
				push_error("Material capture failed: " + path)
				quit(1)
				return
			captures.append(path)
		(report["materials"] as Array).append({"id": asset_id, "maps_imported": 5, "captures": captures, "ok": valid})
	var file: FileAccess = FileAccess.open(BASE + "review/godot-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("MATERIAL_ENGINE_OK: ", ids.size(), " materials, 45 maps, 27 native captures")
	quit(0)
