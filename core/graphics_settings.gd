extends Node

# Local graphics options (Settings > Graphics, ui/graphics_panel.gd), saved in user://graphics.cfg.
# A preset sets render scale, anti-aliasing, shadows and grass distance; changing one afterwards
# reads as Custom. Frame cap and fullscreen are personal and stay out of the presets.
# The M2 Air benchmark behind the presets is in docs/rendering.md (Graphics settings): the sun's
# shadow pass drew three times the visible pass's triangles, and the Retina frame is 7.3M pixels.
# The world half (sun shadows, ground cover) needs the match world: match_world.gd registers it once
# its builders are done. Ground cover multimeshes span the whole village, so a visibility range on
# them would never cull; they are split into CELL-sized pieces that each get the range.

enum Shadows { OFF, LOW, HIGH }
enum Grass { NEAR, MEDIUM, FAR }
const AA_LABELS: PackedStringArray = ["Off", "FXAA", "MSAA 2× + FXAA", "MSAA 4× + FXAA"]
const SHADOW_LABELS: PackedStringArray = ["Off", "Low", "High"]
const GRASS_LABELS: PackedStringArray = ["Near", "Medium", "Far"]
const GRASS_RANGES: Array[float] = [30.0, 45.0, 0.0] # metres; 0 draws ground cover at any distance
const FRAME_CAPS: Array[int] = [30, 60, 120, 0] # 0 = uncapped
const PRESET_NAMES: PackedStringArray = ["Low", "Medium", "High"]
const PRESETS: Array[Dictionary] = [
	{"render_scale": 0.5, "antialiasing": 1, "shadows": Shadows.LOW, "grass": Grass.NEAR},
	{"render_scale": 0.7, "antialiasing": 2, "shadows": Shadows.LOW, "grass": Grass.MEDIUM},
	{"render_scale": 1.0, "antialiasing": 2, "shadows": Shadows.HIGH, "grass": Grass.FAR},
]
const DEFAULT_PRESET: int = 1
const LOW_SHADOW_DISTANCE: float = 50.0
const CELL: float = 16.0
# Ground cover: a multimesh of at least this many instances whose mesh is under this height.
const GROUND_MIN_INSTANCES: int = 50
const GROUND_MAX_HEIGHT: float = 0.7
const WORLD_SETTLE_FRAMES: int = 30 # church clearing and the forest grade edit the village multimeshes late
# Ground cover built in chunks already (LongGrass fields) carries this meta: half a chunk's length in
# metres, added to the grass distance. It is never split and keeps its own fade and shadow setting.
const CHUNK_MARGIN: StringName = &"graphics_chunk_margin"

var config_path: String = "user://graphics.cfg"
var render_scale: float = 0.7
var antialiasing: int = 2
var shadows: int = Shadows.LOW
var grass: int = Grass.MEDIUM
var frame_cap: int = 1
var fullscreen: bool = false
# Originals, so High restores the built look: shadowed sun -> [shadow mode, max distance].
var suns: Dictionary[DirectionalLight3D, Array] = {}
# Ground cover pieces -> the cast_shadow their source multimesh was built with.
var ground: Dictionary[MultiMeshInstance3D, int] = {}
var chunks: Array[MultiMeshInstance3D] = []
var registration: int = 0 # counts register_world calls; only the latest one scans

func _ready() -> void:
	set_preset(DEFAULT_PRESET, false)
	load_settings()
	apply()
	if fullscreen and not headless():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

## FSR 1 is Forward+ only (Mobile falls back to bilinear with a warning); MetalFX spatial works on
## Mobile/Metal and sharpens the upscale.
static func upscaler() -> Viewport.Scaling3DMode:
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	return Viewport.SCALING_3D_MODE_BILINEAR

static func headless() -> bool:
	return DisplayServer.get_name() == "headless"

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(config_path) != OK:
		return
	render_scale = clampf(float(config.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	antialiasing = clampi(int(config.get_value("graphics", "antialiasing", antialiasing)), 0, AA_LABELS.size() - 1)
	shadows = clampi(int(config.get_value("graphics", "shadows", shadows)), 0, SHADOW_LABELS.size() - 1)
	grass = clampi(int(config.get_value("graphics", "grass", grass)), 0, GRASS_LABELS.size() - 1)
	frame_cap = clampi(int(config.get_value("graphics", "frame_cap", frame_cap)), 0, FRAME_CAPS.size() - 1)
	fullscreen = bool(config.get_value("graphics", "fullscreen", fullscreen))

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "antialiasing", antialiasing)
	config.set_value("graphics", "shadows", shadows)
	config.set_value("graphics", "grass", grass)
	config.set_value("graphics", "frame_cap", frame_cap)
	config.set_value("graphics", "fullscreen", fullscreen)
	var error: Error = config.save(config_path)
	if error != OK:
		push_warning("Could not save graphics settings: " + error_string(error))

## Index into PRESET_NAMES the current values match, or -1 (Custom).
func preset_index() -> int:
	for index: int in range(PRESETS.size()):
		var preset: Dictionary = PRESETS[index]
		if is_equal_approx(render_scale, float(preset["render_scale"])) and antialiasing == int(preset["antialiasing"]) \
				and shadows == int(preset["shadows"]) and grass == int(preset["grass"]):
			return index
	return -1

func set_preset(index: int, store: bool = true) -> void:
	var preset: Dictionary = PRESETS[clampi(index, 0, PRESETS.size() - 1)]
	render_scale = float(preset["render_scale"])
	antialiasing = int(preset["antialiasing"])
	shadows = int(preset["shadows"])
	grass = int(preset["grass"])
	if store:
		changed()

## Set one option by name ("render_scale", "antialiasing", "shadows", "grass", "frame_cap").
func set_option(option: String, value: float) -> void:
	if option == "render_scale":
		render_scale = clampf(snappedf(value, 0.05), 0.5, 1.0)
	else:
		set(option, int(value))
	changed()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	if not headless():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()

func changed() -> void:
	apply()
	# The green button, a system shortcut or --fullscreen change the window without set_fullscreen.
	fullscreen = window_fullscreen()
	save_settings()

## Whether the window is fullscreen right now; headless has no window and keeps the saved choice.
func window_fullscreen() -> bool:
	if headless():
		return fullscreen
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

func apply() -> void:
	# A dedicated or headless server keeps the 60 Hz loop whatever the local choice.
	Engine.max_fps = 60 if headless() else FRAME_CAPS[frame_cap]
	var viewport: Viewport = get_tree().root
	viewport.scaling_3d_scale = render_scale
	viewport.scaling_3d_mode = upscaler() if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][antialiasing] as Viewport.MSAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if antialiasing == 0 else Viewport.SCREEN_SPACE_AA_FXAA
	apply_world()

## The match world calls this after its environment builders, again on every map change. Calls
## overlap while the world settles: only the latest one scans, so a sun is captured as built, not
## as an earlier call's shadow level left it, and ground cover is split once.
func register_world(world: Node3D) -> void:
	registration += 1
	var latest: int = registration
	for frame: int in range(WORLD_SETTLE_FRAMES):
		await get_tree().process_frame
	if latest != registration or not is_instance_valid(world):
		return
	suns.clear()
	for node: Node in world.find_children("*", "DirectionalLight3D", true, false):
		var light: DirectionalLight3D = node as DirectionalLight3D
		if light.shadow_enabled:
			suns[light] = [light.directional_shadow_mode, light.directional_shadow_max_distance]
	ground.clear()
	chunks.clear()
	for node: Node in world.find_children("*", "MultiMeshInstance3D", true, false):
		if node.has_meta(CHUNK_MARGIN):
			chunks.append(node as MultiMeshInstance3D)
	# The headless dummy renderer keeps no multimesh buffers to split.
	if not headless():
		for visual: MultiMeshInstance3D in find_ground_cover(world):
			split_ground_cover(visual)
	apply_world()

static func find_ground_cover(world: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for node: Node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var visual: MultiMeshInstance3D = node as MultiMeshInstance3D
		var multi: MultiMesh = visual.multimesh
		if visual.has_meta(CHUNK_MARGIN) or not visual.is_visible_in_tree() or multi == null or multi.mesh == null or multi.transform_format != MultiMesh.TRANSFORM_3D:
			continue
		if multi.instance_count >= GROUND_MIN_INSTANCES and multi.mesh.get_aabb().size.y < GROUND_MAX_HEIGHT:
			found.append(visual)
	return found

## Replace a village-wide ground cover multimesh with one piece per CELL x CELL square. Instances
## collapsed to nothing (church yard, bog pools) are dropped. The source stays, hidden.
func split_ground_cover(visual: MultiMeshInstance3D) -> void:
	var multi: MultiMesh = visual.multimesh
	var cells: Dictionary[Vector2i, PackedInt32Array] = {}
	for index: int in range(multi.instance_count):
		var placement: Transform3D = multi.get_instance_transform(index)
		if placement.basis.x.length_squared() < 0.000001:
			continue
		var point: Vector3 = visual.global_transform * placement.origin
		var key: Vector2i = Vector2i(floori(point.x / CELL), floori(point.z / CELL))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(index)
	for key: Vector2i in cells:
		var indices: PackedInt32Array = cells[key]
		var part: MultiMesh = MultiMesh.new()
		part.transform_format = MultiMesh.TRANSFORM_3D
		part.use_colors = multi.use_colors
		part.use_custom_data = multi.use_custom_data
		part.mesh = multi.mesh
		part.instance_count = indices.size()
		for slot: int in range(indices.size()):
			part.set_instance_transform(slot, multi.get_instance_transform(indices[slot]))
			if multi.use_colors:
				part.set_instance_color(slot, multi.get_instance_color(indices[slot]))
			if multi.use_custom_data:
				part.set_instance_custom_data(slot, multi.get_instance_custom_data(indices[slot]))
		var piece: MultiMeshInstance3D = MultiMeshInstance3D.new()
		piece.name = "%sCell" % visual.name
		piece.multimesh = part
		piece.material_override = visual.material_override
		piece.gi_mode = visual.gi_mode
		piece.layers = visual.layers
		visual.get_parent().add_child(piece)
		piece.transform = visual.transform
		ground[piece] = visual.cast_shadow
	visual.visible = false

func apply_world() -> void:
	for light: DirectionalLight3D in suns:
		if not is_instance_valid(light):
			continue
		var original: Array = suns[light]
		light.shadow_enabled = shadows != Shadows.OFF
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadows == Shadows.LOW else original[0] as DirectionalLight3D.ShadowMode
		light.directional_shadow_max_distance = minf(float(original[1]), LOW_SHADOW_DISTANCE) if shadows == Shadows.LOW else float(original[1])
	for piece: MultiMeshInstance3D in ground:
		if not is_instance_valid(piece):
			continue
		piece.cast_shadow = ground[piece] as GeometryInstance3D.ShadowCastingSetting if shadows == Shadows.HIGH else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.visibility_range_end = GRASS_RANGES[grass]
	for chunk: MultiMeshInstance3D in chunks:
		if not is_instance_valid(chunk):
			continue
		var reach: float = GRASS_RANGES[grass] + float(chunk.get_meta(CHUNK_MARGIN))
		chunk.visibility_range_end = 0.0 if GRASS_RANGES[grass] <= 0.0 else reach
