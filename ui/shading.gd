extends CanvasLayer

# Shading themes: a full-screen pass (ui/shading.gdshader) over the 3D frame, above the fisheye
# (layer 0) and below the HUD (layer 2). Local presentation only; nothing here is networked.
#   T        next theme, Shift+T previous (skipped if T is bound to a game action)
# Each theme is a set of shader values plus fixed colours (palette, ink, blood). The values are
# live-tunable per theme from the Shading tweaks panel (ui/shading_tweaks_panel.gd, shown with
# the pause menu) and persist in user://shading_tweaks.cfg. See docs/shading.md.

const SHADER: Shader = preload("res://ui/shading.gdshader")
const PALETTE_SIZE: int = 8
const SPECS: Array[Dictionary] = [
	{"name": "strength", "label": "Strength", "min": 0.0, "max": 1.0, "step": 0.01, "default": 1.0},
	{"name": "pixel", "label": "Pixel size", "min": 1.0, "max": 8.0, "step": 1.0, "default": 1.0},
	{"name": "flat_radius", "label": "Flat shading", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0},
	{"name": "exposure", "label": "Exposure", "min": -2.0, "max": 2.0, "step": 0.05, "default": 0.0},
	{"name": "contrast", "label": "Contrast", "min": 0.3, "max": 2.5, "step": 0.05, "default": 1.0},
	{"name": "saturation", "label": "Saturation", "min": 0.0, "max": 3.0, "step": 0.05, "default": 1.0},
	{"name": "levels", "label": "Posterize levels", "min": 0.0, "max": 16.0, "step": 1.0, "default": 0.0},
	{"name": "palette_mix", "label": "Palette mix", "min": 0.0, "max": 1.0, "step": 0.01, "default": 1.0},
	{"name": "dither", "label": "Dither", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "ink", "label": "Ink outlines", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
	{"name": "ink_threshold", "label": "Ink threshold", "min": 0.05, "max": 1.0, "step": 0.01, "default": 0.25},
	{"name": "blood_keep", "label": "Blood override", "min": 0.0, "max": 1.0, "step": 0.01, "default": 1.0},
	{"name": "blood_threshold", "label": "Blood redness", "min": 1.1, "max": 4.0, "step": 0.05, "default": 1.5},
	{"name": "blood_hue", "label": "Blood hue", "min": 0.9, "max": 1.6, "step": 0.01, "default": 1.12},
	{"name": "blood_shade", "label": "Blood shading", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.0},
]
const INT_PARAMS: Array[String] = ["flat_radius"]
# "values" override SPECS defaults; "palette" is sRGB hex, "mode" is 0 = luminance ramp
# (dark to light), 1 = nearest colour.
const THEMES: Array[Dictionary] = [
	{"name": "Natural", "values": {"strength": 0.0}},
	{"name": "Red Only", "values": {"saturation": 0.0, "contrast": 1.45, "exposure": -0.1,
		"blood_shade": 0.55}, "blood": "ff1a1a"},
	{"name": "Brutalist Web", "mode": 1, "palette": ["000000", "ffffff", "0000ff", "ffff00", "c0c0c0", "ff00ff"],
		"values": {"pixel": 2.0, "flat_radius": 2.0, "saturation": 1.8, "contrast": 1.2, "dither": 0.35,
			"ink": 0.85, "ink_threshold": 0.3}, "ink": "000000", "blood": "ff0000"},
	{"name": "Concrete", "mode": 0, "palette": ["141414", "3d3d3d", "6e6e6b", "a3a39e", "d6d6d0", "f4f4ef"],
		"values": {"flat_radius": 3.0, "contrast": 1.2, "ink": 1.0, "ink_threshold": 0.22},
		"ink": "0a0a0a", "blood": "ff0a0a"},
	{"name": "Acid Poster", "values": {"saturation": 2.2, "contrast": 1.3, "levels": 3.0, "dither": 0.5,
		"flat_radius": 1.0, "ink": 0.4}, "ink": "1b0033", "blood": "ff0040"},
	{"name": "Terminal", "mode": 0, "palette": ["001100", "003b00", "00a000", "33ff33", "ccffcc"],
		"values": {"pixel": 3.0, "contrast": 1.25, "dither": 0.8, "blood_shade": 0.4}, "blood": "ff2020"},
	{"name": "Risograph", "mode": 1, "palette": ["f6f1e6", "ff48b0", "0078bf", "ffe800", "1a1a1a"],
		"values": {"pixel": 2.0, "saturation": 1.3, "dither": 0.6, "ink": 0.3, "palette_mix": 0.9,
			"blood_keep": 0.95}, "ink": "1a1a1a", "blood": "ff0000"},
	{"name": "Bleach Bypass", "values": {"saturation": 0.3, "contrast": 1.4, "levels": 6.0, "dither": 0.2,
		"blood_keep": 0.75, "blood_shade": 0.8}, "blood": "e00000"},
	{"name": "Hyper Flat", "values": {"saturation": 1.2, "contrast": 1.15, "levels": 5.0, "flat_radius": 3.0,
		"ink": 0.9, "ink_threshold": 0.2}, "ink": "000000", "blood": "ff0000"},
]

var rect: ColorRect = ColorRect.new()
var copy: BackBufferCopy = BackBufferCopy.new()
var material: ShaderMaterial = ShaderMaterial.new()
var overlay: CanvasLayer = CanvasLayer.new()
var label: Label = Label.new()
var label_until: float = 0.0
var tweaks: PanelContainer
var theme_index: int = 0
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
	if not headless:
		tweaks.call("load_saved")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shading="):
			var wanted: String = arg.get_slice("=", 1)
			var found: int = theme_names().find(wanted)
			set_theme(found if found >= 0 else clampi(wanted.to_int(), 0, THEMES.size() - 1))
	if headless:
		set_process(false)
		set_process_unhandled_input(false)
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
	rect.visible = values["strength"] > 0.001 and DisplayServer.get_name() != "headless"

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
