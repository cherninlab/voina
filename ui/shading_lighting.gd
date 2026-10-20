extends Node

# Scene lighting for the shading themes (ui/shading.gd). The village's bounce light is baked into
# a LightmapGI; only the sun's direct light is realtime. Dimming the sun alone would leave the
# baked bounce lighting the village, so a lit theme detaches the lightmap data (and keeps the sun
# BAKE_DYNAMIC). Sun, ambient, sky, fog, exposure, glow and a camera lantern then all follow the
# theme. Natural restores the baked look.
# The lantern is one tunable light carried at the camera: Spread 180 shines all around (an omni
# light, a carried lantern); anything narrower is a cone along the view (a spot light: a torch, or
# a point-and-shoot flash when wide, cold, strong and shadowed). Godot needs a different node type
# for each shape, so both exist and only the active one is lit.
# The lights hang on a rig that copies the current camera's transform every frame. They are never
# parented to a camera: players (and their cameras) are freed on leave or rejoin, which used to
# free the lantern with them.
# Local presentation only; every original value is kept and put back.

var sun: DirectionalLight3D
var environment: Environment
var lightmap: LightmapGI
var rig: Node3D = Node3D.new()
var omni: OmniLight3D = OmniLight3D.new()
var spot: SpotLight3D = SpotLight3D.new()
var lantern: Light3D = omni # whichever shape is active
var original: Dictionary = {}
var lightmap_data: LightmapGIData
var realtime: bool = false
var settings: Dictionary = {}
var colours: Dictionary = {}
var render_mode: int = Viewport.DEBUG_DRAW_DISABLED
var next_scan: float = 0.0

func _ready() -> void:
	# The haunted forest reads forest_fog / forest_ambient from settings (see forest_scale()).
	add_to_group(&"shading_lighting")
	omni.name = "ShadingLantern"
	spot.name = "ShadingLanternCone"
	for light: Light3D in [omni, spot]:
		light.light_bake_mode = Light3D.BAKE_DISABLED
		light.visible = false
	spot.spot_angle_attenuation = 0.6
	rig.name = "ShadingLightRig"
	rig.add_child(omni)
	rig.add_child(spot)
	add_child(rig)

## settings: sun, sun_angle, ambient, sky, fog, exposure, glow and the lantern_* values (see SPECS
## in shading.gd). colours: optional sun_color, ambient_color, fog_color. realtime: whether the
## theme needs the realtime path at all.
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
	follow_camera()

func find_scene() -> void:
	var tree_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	sun = null
	environment = null
	lightmap = null
	for node: Node in tree_root.find_children("*", "DirectionalLight3D", true, false):
		if node.name == "DistantRedSheetLightning":
			continue
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

## The live village replaces its atmosphere after this node's first scan. Adopt only those
## baseline fields; recapturing sun/energy here would compound an already-applied Night theme.
func set_atmosphere_base(ambient_colour: Color, fog_colour: Color, fog_density: float) -> void:
	original["ambient_color"] = ambient_colour
	original["fog_color"] = fog_colour
	original["fog_density"] = fog_density

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
	refresh_lantern()

## Warmth 0 is cold flash white, 1 is warm lantern orange.
const COLD: Color = Color("eef3ff")
const WARM: Color = Color("ffa850")

func refresh_lantern() -> void:
	var energy: float = float(settings.get("lantern", 0.0)) if realtime else 0.0
	var spread: float = float(settings.get("lantern_spread", 180.0))
	lantern = omni if spread >= 179.5 else spot
	var other: Light3D = spot if lantern == omni else omni
	other.visible = false
	other.light_energy = 0.0
	lantern.light_energy = energy
	lantern.visible = energy > 0.001
	lantern.light_color = COLD.lerp(WARM, clampf(float(settings.get("lantern_warmth", 1.0)), 0.0, 1.0))
	lantern.shadow_enabled = float(settings.get("lantern_shadows", 0.0)) >= 0.5
	lantern.position = Vector3(0.0, float(settings.get("lantern_height", 0.1)), 0.0)
	var reach: float = float(settings.get("lantern_range", 16.0))
	var falloff: float = float(settings.get("lantern_falloff", 1.4))
	omni.omni_range = reach
	omni.omni_attenuation = falloff
	spot.spot_range = reach
	spot.spot_attenuation = falloff
	spot.spot_angle = minf(spread * 0.5, 89.0)

## Brightness multiplier the haunted forest applies to its grade's fog or ambient colour: 1 keeps
## the grade as tuned (Folk Ink); night themes dim it so the forest does not glow blue-grey.
func forest_scale(key: String) -> float:
	return float(settings.get(key, 1.0))

func colour(key: String, fallback: Color) -> Color:
	return Color(colours[key] as String) if colours.has(key) else fallback

func follow_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		rig.global_transform = camera.global_transform
