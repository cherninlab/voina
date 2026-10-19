extends SceneTree
## Real-render audit: one uncapped Mobile viewport, fixed cameras, no synthetic multipass load.
## Run windowed: Godot --path . --script scripts/grim_render_check.gd -- --shading-ephemeral

var output: String = "/tmp/secha-render-audit"
var world: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	assert(DisplayServer.get_name() != "headless" or "--audit-invariants-only" in OS.get_cmdline_user_args(), "Timing/captures require the real renderer")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-dir="):
			output = arg.trim_prefix("--audit-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	Engine.max_fps = 0
	for frame: int in range(100):
		await process_frame
	var ui: CanvasLayer = world.get_node("GameUI") as CanvasLayer
	ui.set_process(false)
	var art: Node3D = world.get_node("WoodlandVillage/AshenVillage") as Node3D
	var effects: CanvasLayer
	for child: Node in world.get_children():
		if child.get_script() != null and (child.get_script() as Script).resource_path == "res://ui/shading.gd":
			effects = child as CanvasLayer
	assert(effects != null)
	var scene_environment: Environment = (world.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	assert(scene_environment.sky.sky_material == art.get("storm"))
	assert(scene_environment.fog_light_color.get_luminance() < 0.3, "Haze must not wash mountains pale")
	var lamps: Array = art.get("lamps") as Array
	assert(lamps.size() >= 4)
	assert(art.find_children("*", "MeshInstance3D", true, false).size() <= lamps.size() * 2, "Fixture geometry must stay locally batched")
	print("AUDIT_DEVICE ", RenderingServer.get_video_adapter_name(), " renderer=", RenderingServer.get_current_rendering_method(), " size=", root.size)
	print("AUDIT_FIXTURE_MESHES ", art.find_children("*", "MeshInstance3D", true, false).size())
	print("AUDIT_THEME ", effects.call("theme_name"), " expected_fog=", (effects.get("values") as Dictionary)["fog"], " actual_fog=", scene_environment.fog_density)
	if "--audit-invariants-only" in OS.get_cmdline_user_args():
		assert(is_equal_approx(scene_environment.fog_density, float((effects.get("values") as Dictionary)["fog"])), "Late village dressing must preserve the selected theme")
		print("GRIM_INVARIANTS_OK")
		quit.call_deferred()
		return
	root.disable_3d = false
	await measure("menu_world_on")
	root.disable_3d = true
	await measure("menu_world_off")
	# Actual host transition must restore the 3D viewport, and leaving must restore the menu.
	ui.set_process(true)
	if "--audit-baseline" in OS.get_cmdline_user_args():
		root.disable_3d = false
	(root.get_node("NetworkManager") as Node).call("host_game", 7794)
	for frame: int in range(20):
		await process_frame
	assert(not root.disable_3d, "Hosting must restore rendering")
	ui.set_process(false)
	ui.visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2.8, 8)
	camera.look_at(Vector3(0, 2.1, -14))
	camera.fov = 75.0
	camera.far = 650.0
	camera.make_current()
	for frame: int in range(20):
		await process_frame
	await measure("game_dynamic_sky")

	var storm: ShaderMaterial = art.get("storm") as ShaderMaterial
	var original_shader: Shader = storm.shader
	var fixed_shader: Shader = original_shader.duplicate() as Shader
	fixed_shader.code = fixed_shader.code.replace("TIME*0.00012", "0.0")
	art.set_process(false)
	storm.shader = fixed_shader
	await measure("game_static_sky")
	storm.shader = original_shader
	art.set_process(true)
	# The controlled 75-degree timing view above is not the live fisheye source projection.
	var player: Node = (world.get("players") as Node3D).get_child(0)
	camera.fov = (player.get("camera") as Camera3D).fov
	for frame: int in range(20):
		await process_frame
	await measure("game_owner_projection")
	await capture("game.png")
	# Switching presets must continue to address the real sun, not the lightning light.
	effects.call("set_theme", 1)
	var lighting: Node = effects.get("lighting") as Node
	assert((lighting.get("sun") as Light3D).name != "DistantRedSheetLightning")
	effects.call("set_theme", (effects.call("theme_names") as PackedStringArray).size() - 1)
	ui.visible = true
	ui.set_process(true)
	(root.get_node("NetworkManager") as Node).call("stop", "Audit complete")
	for frame: int in range(20):
		await process_frame
	assert((ui.get("title_screen") as Control).visible)
	assert(root.disable_3d or "--audit-baseline" in OS.get_cmdline_user_args(), "Offline image menu must skip 3D rendering")
	await capture("menu.png")
	print("GRIM_RENDER_CHECK_OK")
	world.queue_free()
	for frame: int in range(4):
		await process_frame
	quit.call_deferred()

func measure(label: String) -> void:
	if "--audit-captures-only" in OS.get_cmdline_user_args():
		return
	if not graphics_competitors().is_empty():
		print("AUDIT_TIMING_SKIPPED ", label, " other graphical Godot processes: ", graphics_competitors())
		return
	RenderingServer.render_loop_enabled = false
	for frame: int in range(40):
		RenderingServer.force_draw(false, 0.0)
	var times: Array[float] = []
	for frame: int in range(160):
		var start: int = Time.get_ticks_usec()
		RenderingServer.force_draw(false, 0.0)
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	RenderingServer.render_loop_enabled = true
	await process_frame
	if not graphics_competitors().is_empty():
		print("AUDIT_TIMING_SKIPPED ", label, " graphical capture started during sample")
		return
	print("AUDIT_FRAME ", label, " p50_ms=", snappedf(times[79],0.01), " p95_ms=", snappedf(times[151],0.01), " draws=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), " primitives=", int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))

func capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(file)) == OK)

func graphics_competitors() -> PackedStringArray:
	var processes: Array[String] = []
	var result: PackedStringArray = PackedStringArray()
	OS.execute("pgrep", PackedStringArray(["-x", "Godot"]), processes)
	if processes.is_empty():
		return result
	for pid: String in processes[0].strip_edges().split("\n"):
		if pid.to_int() == OS.get_process_id():
			continue
		var command: Array[String] = []
		OS.execute("ps", PackedStringArray(["-p", pid, "-o", "command="]), command)
		if not command.is_empty() and not command[0].contains("--headless"):
			result.append(pid)
	return result
