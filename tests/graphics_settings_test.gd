extends Node
## Graphics settings (T-126): presets and Custom, the viewport options, save/load, the headless
## frame cap, ground cover detection and the sun shadow levels. Run as a scene so autoloads exist:
##   "$GODOT" --headless --path . res://tests/graphics_settings_test.tscn

var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and not failed:
		failed = true
		printerr("GRAPHICS_SETTINGS_FAIL: " + message)

func run() -> void:
	var settings: Node = GraphicsSettings
	settings.config_path = "user://graphics_settings_test.cfg"
	var viewport: Viewport = get_tree().root
	settings.set_preset(0)
	check(settings.preset_index() == 0, "Low preset is recognised")
	check(is_equal_approx(viewport.scaling_3d_scale, 0.5) and viewport.scaling_3d_mode == GraphicsSettings.upscaler(), "Low renders at half scale, upscaled")
	check(viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "Low uses FXAA only")
	settings.set_option("render_scale", 0.62)
	check(is_equal_approx(settings.render_scale, 0.6), "render scale snaps to 5 % steps")
	check(settings.preset_index() == -1, "an option off the preset reads as Custom")
	settings.set_preset(2)
	check(is_equal_approx(viewport.scaling_3d_scale, 1.0) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "High renders natively")
	settings.set_option("antialiasing", 3)
	check(viewport.msaa_3d == Viewport.MSAA_4X, "MSAA 4x option")
	settings.set_option("antialiasing", 0)
	check(viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "anti-aliasing off")
	settings.set_option("frame_cap", 0)
	check(Engine.max_fps == 60, "headless keeps the 60 Hz loop whatever the cap")
	settings.set_preset(1)
	settings.set_option("frame_cap", 2)
	settings.load_settings()
	settings.render_scale = 1.0
	settings.grass = 2
	settings.load_settings()
	check(settings.preset_index() == 1 and settings.frame_cap == 2, "settings survive save and load")
	# Headless has no window to read: saving an option keeps the stored fullscreen choice.
	settings.set_fullscreen(true)
	settings.set_option("frame_cap", 2)
	settings.fullscreen = false
	settings.load_settings()
	check(settings.fullscreen and settings.window_fullscreen(), "headless keeps the saved fullscreen choice")
	settings.set_fullscreen(false)

	# A tiny world: a shadowed sun, ground cover, a tall multimesh and a too-small scatter.
	var world: Node3D = Node3D.new()
	add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 100.0
	world.add_child(sun)
	var tufts: MultiMeshInstance3D = scatter(world, 0.3, 80)
	scatter(world, 4.0, 80)
	scatter(world, 0.3, 10)
	# A field built in chunks already (LongGrass): short and numerous, but marked, so never split.
	var chunk: MultiMeshInstance3D = scatter(world, 0.3, 80)
	chunk.visibility_range_end = 90.0
	chunk.set_meta(GraphicsSettings.CHUNK_MARGIN, 15.0)
	var found: Array[MultiMeshInstance3D] = settings.find_ground_cover(world)
	check(found.size() == 1 and found[0] == tufts, "only short, numerous multimeshes count as ground cover")
	await settings.register_world(world)
	settings.set_option("shadows", GraphicsSettings.Shadows.OFF)
	check(not sun.shadow_enabled, "shadows off")
	settings.set_option("shadows", GraphicsSettings.Shadows.LOW)
	check(sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS \
		and is_equal_approx(sun.directional_shadow_max_distance, 50.0), "low shadows: two splits to 50 m")
	settings.set_option("shadows", GraphicsSettings.Shadows.HIGH)
	check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
		and is_equal_approx(sun.directional_shadow_max_distance, 100.0), "high shadows restore the built sun")
	settings.set_option("grass", GraphicsSettings.Grass.NEAR)
	check(is_equal_approx(chunk.visibility_range_end, 45.0), "near grass: chunks end at 30 m plus their margin")
	settings.set_option("grass", GraphicsSettings.Grass.MEDIUM)
	check(is_equal_approx(chunk.visibility_range_end, 60.0), "medium grass: chunks end at 45 m plus their margin")
	settings.set_option("grass", GraphicsSettings.Grass.FAR)
	check(is_zero_approx(chunk.visibility_range_end) and chunk.visible, "far grass: chunks draw at any distance")
	# A map change registers the world again while an earlier call still waits for it to settle.
	# Only the latest call may capture the sun, or it records what the earlier one left behind.
	for level: int in [GraphicsSettings.Shadows.LOW, GraphicsSettings.Shadows.OFF]:
		settings.set_option("shadows", level)
		var next: Node3D = Node3D.new()
		add_child(next)
		var moon: DirectionalLight3D = DirectionalLight3D.new()
		moon.shadow_enabled = true
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		moon.directional_shadow_max_distance = 100.0
		next.add_child(moon)
		settings.register_world(next)
		for frame: int in range(5):
			await get_tree().process_frame
		await settings.register_world(next)
		var label: String = GraphicsSettings.SHADOW_LABELS[level]
		settings.set_option("shadows", GraphicsSettings.Shadows.LOW)
		check(moon.shadow_enabled and moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, \
			"overlapping registrations under %s: shadows can be turned back on" % label)
		settings.set_option("shadows", GraphicsSettings.Shadows.HIGH)
		check(moon.shadow_enabled and moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
			and is_equal_approx(moon.directional_shadow_max_distance, 100.0), "overlapping registrations under %s: High restores four splits to 100 m" % label)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))
	if not failed:
		print("GRAPHICS_SETTINGS_OK")
	get_tree().quit(1 if failed else 0)

func scatter(world: Node3D, height: float, count: int) -> MultiMeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.2, height, 0.2)
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.multimesh = multi
	world.add_child(visual)
	return visual
