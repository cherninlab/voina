extends Node

# Scene lighting for the shading themes (ui/shading.gd). The village's bounce light is baked into
# a LightmapGI; only the sun's direct light is realtime. Dimming the sun alone would leave the
# baked bounce lighting the village, so a lit theme detaches the lightmap data (and keeps the sun
# BAKE_DYNAMIC). Sun, ambient, sky, fog, exposure, glow and a lantern on the current camera then
# all follow the theme. Natural restores the baked look.
# Local presentation only; every original value is kept and put back.

var sun: DirectionalLight3D
var environment: Environment
var lightmap: LightmapGI
var lantern: OmniLight3D = OmniLight3D.new()
var original: Dictionary = {}
var lightmap_data: LightmapGIData
var realtime: bool = false
var settings: Dictionary = {}
var colours: Dictionary = {}
var render_mode: int = Viewport.DEBUG_DRAW_DISABLED
var next_scan: float = 0.0

func _ready() -> void:
	lantern.name = "ShadingLantern"
	lantern.omni_range = 16.0
	lantern.omni_attenuation = 1.4
	lantern.shadow_enabled = false
	lantern.light_bake_mode = Light3D.BAKE_DISABLED

## settings: sun, sun_angle, ambient, sky, fog, exposure, glow, lantern (see SPECS in shading.gd).
## colours: optional sun_color, ambient_color, fog_color, lantern_color (hex). realtime: whether
## the theme needs the realtime path at all.
func apply(new_settings: Dictionary, new_colours: Dictionary, want_realtime: bool, new_render_mode: int) -> void:
	settings = new_settings
	colours = new_colours
	realtime = want_realtime
	render_mode = new_render_mode
	refresh()

func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec()
	if now >= next_scan:
		next_scan = now + 1000.0
		if not is_instance_valid(sun) or not is_instance_valid(environment):
			refresh()
	attach_lantern()

func find_scene() -> void:
	var tree_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	sun = null
	environment = null
	lightmap = null
	for node: Node in tree_root.find_children("*", "DirectionalLight3D", true, false):
		sun = node as DirectionalLight3D
		break
	for node: Node in tree_root.find_children("*", "WorldEnvironment", true, false):
		environment = (node as WorldEnvironment).environment
		break
	for node: Node in tree_root.find_children("*", "LightmapGI", true, false):
		lightmap = node as LightmapGI
		break
	if sun != null and not original.has("sun_energy"):
		original["sun_energy"] = sun.light_energy
		original["sun_color"] = sun.light_color
		original["sun_rotation"] = sun.rotation
		original["sun_bake"] = sun.light_bake_mode
	if environment != null and not original.has("ambient_energy"):
		original["ambient_energy"] = environment.ambient_light_energy
		original["ambient_color"] = environment.ambient_light_color
		original["sky_energy"] = environment.background_energy_multiplier
		original["fog_density"] = environment.fog_density
		original["fog_color"] = environment.fog_light_color
		original["exposure"] = environment.tonemap_exposure
		original["glow"] = environment.glow_enabled
		original["glow_intensity"] = environment.glow_intensity
	if lightmap != null and lightmap_data == null:
		lightmap_data = lightmap.light_data

func refresh() -> void:
	find_scene()
	get_viewport().debug_draw = render_mode as Viewport.DebugDraw
	if sun != null:
		if realtime:
			sun.light_bake_mode = Light3D.BAKE_DYNAMIC
			sun.light_energy = float(original["sun_energy"]) * float(settings.get("sun", 1.0))
			sun.light_color = colour("sun_color", original["sun_color"] as Color)
			var rotation: Vector3 = original["sun_rotation"] as Vector3
			rotation.x = -deg_to_rad(float(settings.get("sun_angle", 32.0)))
			sun.rotation = rotation
		else:
			sun.light_bake_mode = original["sun_bake"] as Light3D.BakeMode
			sun.light_energy = original["sun_energy"] as float
			sun.light_color = original["sun_color"] as Color
			sun.rotation = original["sun_rotation"] as Vector3
	if lightmap != null:
		lightmap.light_data = null if realtime else lightmap_data
	if environment != null:
		var lit: bool = realtime
		environment.ambient_light_energy = float(original["ambient_energy"]) * (float(settings.get("ambient", 1.0)) if lit else 1.0)
		environment.ambient_light_color = colour("ambient_color", original["ambient_color"] as Color) if lit else original["ambient_color"] as Color
		environment.background_energy_multiplier = float(original["sky_energy"]) * (float(settings.get("sky", 1.0)) if lit else 1.0)
		environment.fog_density = float(settings.get("fog", original["fog_density"])) if lit else float(original["fog_density"])
		environment.fog_light_color = colour("fog_color", original["fog_color"] as Color) if lit else original["fog_color"] as Color
		environment.tonemap_exposure = float(original["exposure"]) * (float(settings.get("exposure", 1.0)) if lit else 1.0)
		var glow: float = float(settings.get("glow", 0.0)) if lit else 0.0
		environment.glow_enabled = glow > 0.001 or bool(original["glow"])
		environment.glow_intensity = glow if glow > 0.001 else float(original["glow_intensity"])
	lantern.light_energy = float(settings.get("lantern", 0.0)) if realtime else 0.0
	lantern.light_color = colour("lantern_color", Color("ffb060"))
	lantern.visible = lantern.light_energy > 0.001

func colour(key: String, fallback: Color) -> Color:
	return Color(colours[key] as String) if colours.has(key) else fallback

func attach_lantern() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or lantern.get_parent() == camera:
		return
	if lantern.get_parent() != null:
		lantern.get_parent().remove_child(lantern)
	camera.add_child(lantern)
	lantern.position = Vector3(0.35, 0.1, 0.2)

func _exit_tree() -> void:
	# The lantern lives under the camera, or nowhere yet (headless, or no camera so far).
	if not is_instance_valid(lantern):
		return
	if lantern.get_parent() == null:
		lantern.free()
	else:
		lantern.queue_free()
