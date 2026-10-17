extends SceneTree
## Measure uncapped frame time (vsync off) of the village scenery per Environment feature set.
## Run windowed (not --headless) once per renderer via scripts/renderer_benchmark.py.

const WARMUP_FRAMES: int = 120
const SAMPLE_FRAMES: int = 300
## The window is capped by display pacing, so each frame draws the view this many times offscreen
## to make the GPU the bottleneck; divide frame time by this for a per-view estimate. Override with -- --passes=N.
var passes: int = 20
const VIEWS: Array[Vector3] = [Vector3(0, 1.7, 14), Vector3(-18, 2.3, 17), Vector3(33, 28, 37)]
const TARGETS: Array[Vector3] = [Vector3(0, 1.5, -20), Vector3(-18, 2.6, -5), Vector3(0, 0, -2)]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--passes="):
			passes = argument.trim_prefix("--passes=").to_int()
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	# macOS stops drawing covered windows, which silently turns samples into idle frames.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	root.size = Vector2i(1600, 1000)
	var village: Node3D = (load("res://gameplay/environment/village_arena.gd") as GDScript).new() as Node3D
	root.add_child(village)
	var cameras: Array[Camera3D] = []
	for index: int in range(passes):
		var pass_viewport: SubViewport = SubViewport.new()
		pass_viewport.size = root.size
		pass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		pass_viewport.msaa_3d = Viewport.MSAA_2X
		pass_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		root.add_child(pass_viewport)
		var camera: Camera3D = Camera3D.new()
		camera.fov = 68.0
		camera.far = 300.0
		pass_viewport.add_child(camera)
		camera.make_current()
		cameras.append(camera)
	var environment: Environment = find_environment(village)
	if environment == null:
		printerr("BENCH_FAIL: village has no WorldEnvironment")
		quit(1)
		return
	var viewport: RID = cameras[0].get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("BENCH_RENDERER ", RenderingServer.get_current_rendering_method(), " (project ", method, ") ", RenderingServer.get_video_adapter_name(), " ", root.size, " x", passes, " passes")
	for config: String in ["baseline", "glow_agx", "ssao", "ssil", "ssr", "sdfgi", "volumetric_fog", "all"]:
		configure(environment, config)
		for view: int in range(VIEWS.size()):
			for camera: Camera3D in cameras:
				camera.position = VIEWS[view]
				camera.look_at(TARGETS[view])
			for frame: int in range(WARMUP_FRAMES):
				await process_frame
			# Metal returns zero GPU timestamps here, so wall-clock frame deltas stand in for GPU cost.
			var frame_ms: Array[float] = []
			var cpu: Array[float] = []
			var last: int = Time.get_ticks_usec()
			var drawn_before: int = Engine.get_frames_drawn()
			for frame: int in range(SAMPLE_FRAMES):
				await process_frame
				var now: int = Time.get_ticks_usec()
				frame_ms.append(float(now - last) / 1000.0)
				last = now
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
			var drawn: float = float(Engine.get_frames_drawn() - drawn_before) / float(SAMPLE_FRAMES)
			print("BENCH_RESULT config=%s view=%d frame_median_ms=%.2f frame_p95_ms=%.2f cpu_median_ms=%.2f drawn=%.2f" % [config, view, percentile(frame_ms, 0.5), percentile(frame_ms, 0.95), percentile(cpu, 0.5), drawn])
	print("BENCH_DONE")
	quit(0)

func find_environment(node: Node) -> Environment:
	for child: Node in node.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null

func configure(environment: Environment, config: String) -> void:
	var all: bool = config == "all"
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX if config == "glow_agx" or all else Environment.TONE_MAPPER_ACES
	environment.glow_enabled = config == "glow_agx" or all
	environment.ssao_enabled = config == "ssao" or all
	environment.ssil_enabled = config == "ssil" or all
	environment.ssr_enabled = config == "ssr" or all
	environment.sdfgi_enabled = config == "sdfgi" or all
	environment.volumetric_fog_enabled = config == "volumetric_fog" or all
	environment.volumetric_fog_density = 0.01
	environment.volumetric_fog_anisotropy = 0.7

func percentile(values: Array[float], fraction: float) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(fraction * float(sorted.size() - 1)), 0, sorted.size() - 1)]
