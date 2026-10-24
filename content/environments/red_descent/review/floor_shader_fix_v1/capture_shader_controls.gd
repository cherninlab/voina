extends SceneTree
## Reproduce under Mobile/Metal through scripts/godot_bg.sh -- --dungeon --shading-ephemeral.
const REVIEW: String = "res://content/environments/red_descent/review/floor_shader_fix_v1/"
var views: Array[Array] = [
	["13-chapel-spill", Vector3(3, -8.35, -37), Vector3(3, -9.6, -41.4), 65.0],
	["10-restraint-frame", Vector3(40, -2.35, -8), Vector3(40, -1.8, -13), 65.0],
	["04-broken-nave", RedDescentLayout.at(Vector3(57, -16.35, 79)), RedDescentLayout.at(Vector3(52, -12, 94)), 78.0],
]

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
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
	var materials: Array[ShaderMaterial] = []
	for floor_node: Node in get_nodes_in_group("flagstone_room_floors"):
		for node: Node in floor_node.find_children("*", "MeshInstance3D", true, false):
			var material: ShaderMaterial = (node as MeshInstance3D).material_override as ShaderMaterial
			if material != null and not material in materials:
				materials.append(material)
	if materials.is_empty():
		printerr("SHADER_CAPTURE_FAIL: no room floor materials; scene did not build")
		quit(1)
		return
	var original_shaders: Array[Shader] = []
	var clipped: Array[bool] = []
	for material: ShaderMaterial in materials:
		original_shaders.append(material.shader)
		clipped.append(material.shader.resource_path.ends_with("flagstone_clipped.gdshader"))
	var dungeon: Node = world.get_node("CinderCrypt")
	var original_shadows: Dictionary[Light3D, bool] = {}
	for light_node: Node in root.find_children("*", "Light3D", true, false):
		var light: Light3D = light_node as Light3D
		original_shadows[light] = light.shadow_enabled
	var source: String = FileAccess.get_file_as_string(REVIEW + "baseline.gdshaderinc.txt")
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var modes: PackedStringArray = PackedStringArray(["baseline", "no-ao", "no-noise", "flat-texture"])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--modes="):
			modes = argument.trim_prefix("--modes=").split(",")
	for mode: String in modes:
		for environment_node: Node in root.find_children("*", "WorldEnvironment", true, false):
			var environment: Environment = (environment_node as WorldEnvironment).environment
			if environment != null:
				environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if mode == "linear-tonemap" else Environment.TONE_MAPPER_FILMIC
		for layer: Node in root.find_children("*", "CanvasLayer", true, false):
			var layer_script: Script = layer.get_script() as Script
			if layer_script != null and layer_script.resource_path == "res://ui/shading.gd":
				(layer as CanvasLayer).visible = mode != "no-grade" and mode != "albedo-only" and mode != "texture-only"
		dungeon.set_process(mode != "no-shadows")
		for light: Light3D in original_shadows:
			light.shadow_enabled = false if mode == "no-shadows" else original_shadows[light]
		var body: String = source
		if mode == "no-ao":
			body = body.replace("ALBEDO = color * mix(1.0, COLOR.r, ao_albedo);", "ALBEDO = color;")
			body = body.replace("AO = COLOR.r;", "AO = 1.0;")
		elif mode == "no-noise":
			body = body.replace("color *= mix(1.0 - grime, 1.0, broad) * mix(0.93, 1.04, fine);", "color *= 1.0;")
		elif mode == "flat-texture":
			body = body.replace("vec3 base = texture(albedo_map, uv).rgb;", "vec3 base = vec3(0.5);")
		elif mode == "material-calibration":
			body = body.replace("vec3(0.7, 0.66, 0.6)", "vec3(0.88, 0.85, 0.80)")
			body = body.replace("uniform float variation = 0.26;", "uniform float variation = 0.14;")
			body = body.replace("uniform float ao_albedo = 0.75;", "uniform float ao_albedo = 0.25;")
			body = body.replace("uniform float grime = 0.28;", "uniform float grime = 0.15;")
		elif mode == "constant-albedo":
			body = body.replace("ALBEDO = color * mix(1.0, COLOR.r, ao_albedo);", "ALBEDO = vec3(0.3);")
		elif mode == "albedo-only":
			body = "render_mode unshaded;\n" + body
		elif mode == "texture-only":
			body = "render_mode unshaded;\n" + body.replace("ALBEDO = color * mix(1.0, COLOR.r, ao_albedo);", "ALBEDO = base;")
		elif mode == "no-normal":
			body = body.replace("NORMAL_MAP = texture(normal_map, uv).xyz;", "")
			body = body.replace("NORMAL_MAP_DEPTH = normal_strength * (dirt ? 2.0 : 1.0);", "")
		elif mode == "no-specular":
			body = body.replace("SPECULAR = 0.35;", "SPECULAR = 0.0;")
		elif mode == "rough-one":
			body = body.replace("ROUGHNESS = dirt ? mix(0.8, 1.0, rough) : mix(roughness_min, 0.98, rough) * mix(1.0, 0.88, COLOR.b);", "ROUGHNESS = 1.0;")
		elif mode == "no-specular-rough-one":
			body = body.replace("SPECULAR = 0.35;", "SPECULAR = 0.0;")
			body = body.replace("ROUGHNESS = dirt ? mix(0.8, 1.0, rough) : mix(roughness_min, 0.98, rough) * mix(1.0, 0.88, COLOR.b);", "ROUGHNESS = 1.0;")
		var regular_shader: Shader = Shader.new()
		regular_shader.code = "shader_type spatial;\n" + body
		var clipped_shader: Shader = Shader.new()
		clipped_shader.code = "shader_type spatial;\n#define CLIP\n" + body
		for index: int in range(materials.size()):
			materials[index].shader = original_shaders[index] if mode == "production" else (clipped_shader if clipped[index] else regular_shader)
		var directory: String = REVIEW + mode
		DirAccess.make_dir_recursive_absolute(directory)
		for view: Array in views:
			camera.fov = float(view[3])
			camera.position = view[1] as Vector3
			camera.look_at(view[2] as Vector3)
			camera.make_current()
			for frame: int in range(36):
				await process_frame
			if mode == "no-shadows":
				assert(not dungeon.is_processing())
				for light: Light3D in original_shadows:
					assert(not light.shadow_enabled, "SHADER_CAPTURE_FAIL: shadows re-enabled")
				print("SHADER_SHADOWS_ASSERT_OK: ", original_shadows.size(), " lights remain off; dungeon processing frozen")
			if mode == "material-calibration" or mode == "production":
				assert(dungeon.is_processing(), "SHADER_CAPTURE_FAIL: dungeon updater frozen")
				var shadow_lights: int = 0
				for light: Light3D in original_shadows:
					shadow_lights += 1 if light.shadow_enabled else 0
				assert(shadow_lights > 0, "SHADER_CAPTURE_FAIL: live shadows absent")
				print("SHADER_LIVE_LIGHTS_ASSERT_OK: ", shadow_lights, " shadow lights; dungeon processing enabled")
			RenderingServer.force_draw()
			var destination: String = directory.path_join(String(view[0]) + ".png")
			var capture_image: Image = root.get_texture().get_image()
			var low: float = 1.0
			var high: float = 0.0
			for y: int in range(0, capture_image.get_height(), 48):
				for x: int in range(0, capture_image.get_width(), 48):
					var value: float = capture_image.get_pixel(x, y).get_luminance()
					low = minf(low, value)
					high = maxf(high, value)
			if high - low < 0.04:
				printerr("SHADER_CAPTURE_FAIL: blank frame " + destination)
				quit(1)
				return
			if capture_image.save_png(destination) != OK:
				printerr("SHADER_CAPTURE_FAIL: " + destination)
				quit(1)
				return
			print("SHADER_CAPTURE: " + destination)
	root.get_node("Audio").set_process(false)
	for audio_node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	for audio_node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(audio_node as AudioStreamPlayer3D).stop()
	world.queue_free()
	materials.clear()
	FlagstoneFloor.surfaces.clear()
	FlagstoneFloor.meshes.clear()
	for frame: int in range(12):
		await process_frame
	quit.call_deferred()
