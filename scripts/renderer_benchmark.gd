extends SceneTree
## Measure uncapped frame time (vsync off) of the village scenery per Environment feature set.
## Run windowed (not --headless) once per renderer via scripts/renderer_benchmark.py.

const WARMUP_FRAMES: int = 120
const SAMPLE_FRAMES: int = 300
## Each frame draws the view this many times offscreen so GPU work dominates the per-frame overhead;
## divide frame time by this for a per-view estimate. Override with -- --passes=N.
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
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("BENCH_RENDERER ", RenderingServer.get_current_rendering_method(), " (project ", method, ") ", RenderingServer.get_video_adapter_name(), " ", root.size, " x", passes, " passes")
	for config: String in ["baseline", "glow_agx", "ssao", "ssil", "ssr", "sdfgi", "volumetric_fog", "all"]:
		configure(environment, config)
		for view: int in range(VIEWS.size()):
			for camera: Camera3D in cameras:
				camera.position = VIEWS[view]
				camera.look_at(TARGETS[view])
			# macOS skips the normal draw while the window counts as hidden (behind a full-screen app,
			# another Space, a locked screen), so frames are forced; without a present the loop waits on
			# the GPU every few frames, and wall-clock deltas stand in for Metal's missing GPU timestamps.
			RenderingServer.render_loop_enabled = false
			for frame: int in range(WARMUP_FRAMES):
				RenderingServer.force_draw(false, 0.0)
			var frame_ms: Array[float] = []
			var last: int = Time.get_ticks_usec()
			for frame: int in range(SAMPLE_FRAMES):
				RenderingServer.force_draw(false, 0.0)
				var now: int = Time.get_ticks_usec()
				frame_ms.append(float(now - last) / 1000.0)
				last = now
			RenderingServer.render_loop_enabled = true
			await process_frame
			print("BENCH_RESULT config=%s view=%d frame_median_ms=%.2f frame_p95_ms=%.2f" % [config, view, percentile(frame_ms, 0.5), percentile(frame_ms, 0.95)])
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
