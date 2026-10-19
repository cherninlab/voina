extends CanvasLayer

# Shading themes: scene lighting (ui/shading_lighting.gd: sun, sky, fog, exposure, glow, a lantern,
# unshaded rendering) plus a full-screen pass (ui/shading.gdshader) over the 3D frame, above the
# fisheye (layer 0) and below the HUD (layer 2). Local presentation only; nothing is networked.
#   T        next theme, Shift+T previous (skipped if T is bound to a game action)
# Each theme is a set of shader values plus fixed colours (palette, ink, blood). The values are
# live-tunable per theme from the Shading tweaks panel (ui/shading_tweaks_panel.gd, shown with
# the pause menu) and persist in user://shading_tweaks.cfg. See docs/shading.md.

const SHADER: Shader = preload("res://ui/shading.gdshader")
const PALETTE_SIZE: int = 8
const SPECS: Array[Dictionary] = [
	{"group": "Lighting (switches the village to realtime light)"},
	{"name": "sun", "label": "Sun", "min": 0.0, "max": 3.0, "step": 0.05, "default": 1.0},
	{"name": "sun_angle", "label": "Sun height (deg)", "min": 2.0, "max": 89.0, "step": 1.0, "default": 32.0},
	{"name": "ambient", "label": "Ambient", "min": 0.0, "max": 4.0, "step": 0.05, "default": 1.0},
	{"name": "sky", "label": "Sky", "min": 0.0, "max": 2.0, "step": 0.01, "default": 1.0},
	{"name": "fog", "label": "Fog density", "min": 0.0, "max": 0.08, "step": 0.0005, "default": 0.0015},
	{"name": "scene_exposure", "label": "Scene exposure", "min": 0.1, "max": 4.0, "step": 0.05, "default": 1.0},
	{"name": "glow", "label": "Glow", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.0},
	{"name": "lantern", "label": "Lantern", "min": 0.0, "max": 8.0, "step": 0.1, "default": 0.0},
	{"group": "Image"},
	{"name": "strength", "label": "Strength", "min": 0.0, "max": 1.0, "step": 0.01, "default": 1.0},
	{"name": "exposure", "label": "Exposure", "min": -2.0, "max": 2.0, "step": 0.05, "default": 0.0},
	{"name": "contrast", "label": "Contrast", "min": 0.3, "max": 2.5, "step": 0.05, "default": 1.0},
	{"name": "saturation", "label": "Saturation", "min": 0.0, "max": 3.0, "step": 0.05, "default": 1.0},
	{"name": "hue_shift", "label": "Hue shift", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "hue_speed", "label": "Hue cycling", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.0},
	{"name": "tint", "label": "Tint", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "invert", "label": "Invert", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "vignette", "label": "Vignette", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "grain", "label": "Grain", "min": 0.0, "max": 0.4, "step": 0.01, "default": 0.0},
	{"group": "Stylize"},
	{"name": "pixel", "label": "Pixel size", "min": 1.0, "max": 8.0, "step": 1.0, "default": 1.0},
	{"name": "flat_radius", "label": "Flatten (paint)", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0},
	{"name": "bands", "label": "Cel bands", "min": 0.0, "max": 8.0, "step": 1.0, "default": 0.0},
	{"name": "levels", "label": "Posterize levels", "min": 0.0, "max": 16.0, "step": 1.0, "default": 0.0},
	{"name": "spectrum", "label": "Spectrum", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "spectrum_scale", "label": "Spectrum bands", "min": 0.5, "max": 6.0, "step": 0.1, "default": 1.5},
	{"name": "palette_mix", "label": "Palette mix", "min": 0.0, "max": 1.0, "step": 0.01, "default": 1.0},
	{"name": "dither", "label": "Dither", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "ink", "label": "Ink outlines", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "ink_threshold", "label": "Ink threshold", "min": 0.05, "max": 1.0, "step": 0.01, "default": 0.25},
	{"name": "outline_only", "label": "Outline only", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"group": "Blood"},
	{"name": "blood_keep", "label": "Blood override", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "blood_threshold", "label": "Blood redness", "min": 1.1, "max": 4.0, "step": 0.05, "default": 1.5},
	{"name": "blood_hue", "label": "Blood hue", "min": 0.9, "max": 1.6, "step": 0.01, "default": 1.12},
	{"name": "blood_shade", "label": "Blood shading", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
]
const INT_PARAMS: Array[String] = ["flat_radius"]
const LIGHT_PARAMS: Array[String] = ["sun", "sun_angle", "ambient", "sky", "fog", "scene_exposure", "glow", "lantern"]
const RENDER_MODES: Dictionary[String, int] = {"unshaded": Viewport.DEBUG_DRAW_UNSHADED}
# Each theme: "values" override SPECS defaults. Colours are sRGB hex: "palette" (with "mode"
# 0 = luminance ramp dark to light, 1 = nearest colour), "ink", "paper", "tint", "blood", and
# "light" (sun_color, ambient_color, fog_color, lantern_color). A "light" entry, or any Lighting
# slider off its default, switches the village to realtime light. "render": "unshaded" draws
# material colour only: true flat shading, no light at all.
const NIGHT: Dictionary = {"sun_color": "7d96ff", "ambient_color": "1a2a55", "fog_color": "0a1020",
	"lantern_color": "ffb060"}
const THEMES: Array[Dictionary] = [
	{"name": "Natural", "values": {"strength": 0.0}},
	# Lighting
	{"name": "Night", "light": NIGHT, "values": {"sun": 0.12, "sun_angle": 40.0, "ambient": 0.3, "sky": 0.05,
		"fog": 0.012, "scene_exposure": 1.3, "lantern": 3.0, "saturation": 0.8, "vignette": 0.35}},
	{"name": "Golden Hour", "light": {"sun_color": "ffaa55", "ambient_color": "7a5a4a", "fog_color": "ffcf9a"},
		"tint": "ffc890", "values": {"sun": 1.6, "sun_angle": 14.0, "ambient": 1.8, "sky": 0.9, "fog": 0.006,
		"scene_exposure": 1.25,
		"glow": 0.6, "saturation": 1.15, "contrast": 1.05, "tint": 0.12, "vignette": 0.2}},
	{"name": "Fog", "light": {"sun_color": "dfe6ea", "ambient_color": "8090a0", "fog_color": "b8c2c8"},
		"values": {"sun": 0.25, "sun_angle": 60.0, "ambient": 1.6, "sky": 0.7, "fog": 0.05, "saturation": 0.6,
		"contrast": 0.9}},
	{"name": "Overexposed", "light": {}, "values": {"sun": 2.2, "sun_angle": 70.0, "scene_exposure": 1.9,
		"glow": 1.2, "saturation": 0.85, "contrast": 1.15}},
	{"name": "Blood Moon", "light": {"sun_color": "ff3b2a", "ambient_color": "3a0808", "fog_color": "2a0505",
		"lantern_color": "ff5a3a"}, "values": {"sun": 0.35, "sun_angle": 25.0, "ambient": 0.5, "sky": 0.2,
		"fog": 0.006, "scene_exposure": 1.1, "lantern": 1.5, "glow": 0.4, "saturation": 0.75, "vignette": 0.4,
		"blood_keep": 0.6}, "blood": "ff0000"},
	{"name": "Night Vision", "light": NIGHT, "mode": 0, "palette": ["001100", "003b00", "00a000", "33ff33", "ccffcc"],
		"values": {"sun": 0.15, "ambient": 0.8, "sky": 0.15, "fog": 0.006, "scene_exposure": 4.0, "glow": 0.5,
		"exposure": 0.8, "contrast": 1.2, "grain": 0.12, "vignette": 0.6}},
	{"name": "Neon Noir", "light": {"sun_color": "8090ff", "ambient_color": "202040", "fog_color": "101018"},
		"ink": "00f0ff", "values": {"sun": 0.5, "sky": 0.3, "ambient": 0.9, "scene_exposure": 1.4, "glow": 0.8,
		"saturation": 0.3, "contrast": 1.3, "ink": 0.8, "ink_threshold": 0.2}},
	# Shading models
	{"name": "Flat", "render": "unshaded", "ink": "1a1a1a", "values": {"saturation": 1.1, "ink": 0.7,
		"ink_threshold": 0.2}},
	{"name": "Cel", "ink": "000000", "values": {"bands": 3.0, "saturation": 1.25, "contrast": 1.05, "ink": 0.85,
		"ink_threshold": 0.22}},
	{"name": "Outline", "paper": "f4f1ea", "ink": "111111", "values": {"outline_only": 1.0, "ink": 1.0,
		"ink_threshold": 0.35}},
	{"name": "Blueprint", "paper": "103a7a", "ink": "e8f0ff", "values": {"outline_only": 1.0, "ink": 1.0,
		"ink_threshold": 0.3, "grain": 0.04}},
	{"name": "Painterly", "values": {"flat_radius": 4.0, "saturation": 1.4, "contrast": 1.2, "levels": 10.0}},
	# Colour
	{"name": "Spectrum", "ink": "000000", "values": {"spectrum": 1.0, "spectrum_scale": 2.0, "hue_speed": 0.05,
		"contrast": 1.1, "ink": 0.5}},
	{"name": "Inverted", "values": {"invert": 1.0, "contrast": 1.1}},
	{"name": "Acid Trip", "ink": "1b0033", "values": {"saturation": 2.2, "contrast": 1.3, "levels": 3.0,
		"hue_speed": 0.08, "ink": 0.4}},
	{"name": "Thermal", "mode": 0, "palette": ["000000", "1a0a5c", "4a148c", "7b1fa2", "ff9800", "ffeb3b", "ffffff"],
		"values": {"contrast": 1.2, "dither": 0.2}},
	{"name": "Silent Film", "tint": "d8c39a", "values": {"saturation": 0.0, "tint": 1.0, "contrast": 1.3,
		"vignette": 0.6, "grain": 0.15}},
	{"name": "Pastel", "light": {}, "tint": "ffd6e8", "values": {"sun": 0.8, "ambient": 1.8, "scene_exposure": 1.25,
		"saturation": 0.65, "contrast": 0.75, "flat_radius": 2.0, "tint": 0.15}},
	{"name": "Bleach Bypass", "values": {"saturation": 0.3, "contrast": 1.4, "levels": 6.0, "dither": 0.2}},
	{"name": "Vaporwave", "light": {"sun_color": "ff71ce", "ambient_color": "5a2a8a"}, "mode": 1,
		"palette": ["2d1b4e", "ff71ce", "01cdfe", "05ffa1", "b967ff", "fffb96"],
		"values": {"sun_angle": 15.0, "pixel": 2.0, "saturation": 1.5, "dither": 0.45, "palette_mix": 0.85}},
	# Lo-fi with a red accent
	{"name": "Red Only", "values": {"saturation": 0.0, "contrast": 1.45, "exposure": -0.1, "blood_keep": 1.0,
		"blood_shade": 0.55}, "blood": "ff1a1a"},
	{"name": "Concrete", "mode": 0, "palette": ["141414", "3d3d3d", "6e6e6b", "a3a39e", "d6d6d0", "f4f4ef"],
		"values": {"flat_radius": 3.0, "contrast": 1.2, "ink": 1.0, "ink_threshold": 0.22, "blood_keep": 1.0},
		"ink": "0a0a0a", "blood": "ff0a0a"},
	{"name": "Brutalist Web", "mode": 1, "palette": ["000000", "ffffff", "0000ff", "ffff00", "c0c0c0", "ff00ff"],
		"values": {"pixel": 2.0, "flat_radius": 2.0, "saturation": 1.8, "contrast": 1.2, "dither": 0.35,
			"ink": 0.85, "ink_threshold": 0.3, "blood_keep": 1.0}, "ink": "000000", "blood": "ff0000"},
	{"name": "Risograph", "mode": 1, "palette": ["f6f1e6", "ff48b0", "0078bf", "ffe800", "1a1a1a"],
		"values": {"pixel": 2.0, "saturation": 1.3, "dither": 0.6, "ink": 0.3, "palette_mix": 0.9},
		"ink": "1a1a1a"},
	{"name": "1-Bit", "mode": 0, "palette": ["000000", "ffffff"],
		"values": {"pixel": 2.0, "contrast": 1.2, "dither": 1.0, "blood_keep": 1.0}, "blood": "ff0000"},
]

var rect: ColorRect = ColorRect.new()
var copy: BackBufferCopy = BackBufferCopy.new()
var material: ShaderMaterial = ShaderMaterial.new()
var overlay: CanvasLayer = CanvasLayer.new()
var label: Label = Label.new()
var label_until: float = 0.0
var tweaks: PanelContainer
var lighting: Node = preload("res://ui/shading_lighting.gd").new()
var theme_index: int = 0
var ephemeral: bool = "--shading-ephemeral" in OS.get_cmdline_user_args() # captures: no load, no save
var values: Dictionary[String, float] = {}
# Per-theme slider overrides the player made: theme name -> {param: value}.
var overrides: Dictionary[String, Dictionary] = {}

func _init() -> void:
	values = theme_defaults(theme_index)

func specs() -> Array[Dictionary]:
	return SPECS

func theme_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for theme: Dictionary in THEMES:
		names.append(theme["name"] as String)
	return names

func theme_name() -> String:
	return THEMES[theme_index]["name"] as String

static func theme_defaults(index: int) -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	for spec: Dictionary in SPECS:
		if spec.has("name"):
			result[spec["name"] as String] = spec["default"] as float
	var theme_values: Dictionary = THEMES[index].get("values", {}) as Dictionary
	for name: String in theme_values:
		result[name] = float(theme_values[name])
	return result

func _ready() -> void:
	layer = 1
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	material.shader = SHADER
	rect.material = material
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	add_child(lighting)
	# Status text and the panel sit above the HUD's pause shade (layer 2), like the MPEG tweaks.
	overlay.layer = 3
	add_child(overlay)
	label.position = Vector2(16, 34)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	overlay.add_child(label)
	tweaks = preload("res://ui/shading_tweaks_panel.gd").new(self)
	overlay.add_child(tweaks)
	var headless: bool = DisplayServer.get_name() == "headless"
	if not headless and not ephemeral:
		tweaks.call("load_saved")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shading="):
			var wanted: String = arg.get_slice("=", 1)
			var found: int = theme_names().find(wanted)
			set_theme(found if found >= 0 else clampi(wanted.to_int(), 0, THEMES.size() - 1))
	if headless:
		set_process(false)
		set_process_unhandled_input(false)
		lighting.set_process(false)
		rect.visible = false
		tweaks.visible = false
	apply()

## Switch theme: its defaults plus whatever the player tuned for it earlier.
func set_theme(index: int) -> void:
	theme_index = posmod(index, THEMES.size())
	values = theme_defaults(theme_index)
	var saved: Dictionary = overrides.get(theme_name(), {}) as Dictionary
	for name: String in saved:
		if values.has(name):
			values[name] = float(saved[name])
	apply()

func set_value(name: String, value: float) -> void:
	values[name] = value
	if not overrides.has(theme_name()):
		overrides[theme_name()] = {}
	overrides[theme_name()][name] = value
	apply()

func reset_theme() -> void:
	overrides.erase(theme_name())
	set_theme(theme_index)

func cycle(direction: int) -> void:
	set_theme(theme_index + direction)
	show_status("Shading: %s" % theme_name())
	tweaks.call("refresh")
	tweaks.call("save")

func apply() -> void:
	var theme: Dictionary = THEMES[theme_index]
	for name: String in values:
		if name in LIGHT_PARAMS:
			continue
		if name in INT_PARAMS:
			material.set_shader_parameter(name, roundi(values[name]))
		else:
			material.set_shader_parameter(name, values[name])
	var colours: Array = theme.get("palette", []) as Array
	var palette: PackedVector3Array = PackedVector3Array()
	palette.resize(PALETTE_SIZE)
	for index: int in range(mini(colours.size(), PALETTE_SIZE)):
		var colour: Color = Color(colours[index] as String)
		palette[index] = Vector3(colour.r, colour.g, colour.b)
	material.set_shader_parameter("palette", palette)
	material.set_shader_parameter("palette_count", mini(colours.size(), PALETTE_SIZE))
	material.set_shader_parameter("palette_mode", int(theme.get("mode", 0)))
	material.set_shader_parameter("ink_color", colour_vector(theme.get("ink", "000000") as String))
	material.set_shader_parameter("blood_color", colour_vector(theme.get("blood", "ff0000") as String))
	material.set_shader_parameter("paper_color", colour_vector(theme.get("paper", "ffffff") as String))
	material.set_shader_parameter("tint_color", colour_vector(theme.get("tint", "ffffff") as String))
	rect.visible = values["strength"] > 0.001 and DisplayServer.get_name() != "headless"
	var light_settings: Dictionary = {}
	var realtime: bool = theme.has("light")
	for spec: Dictionary in SPECS:
		var name: String = spec.get("name", "") as String
		if name in LIGHT_PARAMS:
			light_settings["exposure" if name == "scene_exposure" else name] = values[name]
			realtime = realtime or not is_equal_approx(values[name], spec["default"] as float)
	var render_mode: int = RENDER_MODES.get(theme.get("render", ""), Viewport.DEBUG_DRAW_DISABLED)
	if lighting.is_inside_tree():
		lighting.call("apply", light_settings, theme.get("light", {}) as Dictionary, realtime, render_mode)

func colour_vector(hex: String) -> Vector3:
	var colour: Color = Color(hex)
	return Vector3(colour.r, colour.g, colour.b)

func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_T:
		return
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed or KEY_T in InputSettings.keys.values():
		return
	cycle(-1 if key.shift_pressed else 1)
	get_viewport().set_input_as_handled()

func show_status(text: String) -> void:
	label.text = text
	label.visible = true
	label_until = Time.get_ticks_msec() + 1500.0

func _process(_delta: float) -> void:
	if label.visible and Time.get_ticks_msec() > label_until:
		label.visible = false
