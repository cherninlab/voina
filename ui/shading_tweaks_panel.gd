extends PanelContainer

# Collapsible live tuning for the shading themes (ui/shading.gd), shown with the pause menu like
# the sword and MPEG tweaks. Sliders edit the current theme only; each theme keeps its own
# tuning. Values are per machine and cosmetic: they persist in user://shading_tweaks.cfg.
# "Print values" logs the current theme in a form that pastes into THEMES.
const SAVE_PATH: String = "user://shading_tweaks.cfg"

var shading: CanvasLayer
var toggle: Button = Button.new()
var scroll: ScrollContainer = ScrollContainer.new()
var body: VBoxContainer = VBoxContainer.new()
var picker: OptionButton = OptionButton.new()
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}

func _init(owner_layer: CanvasLayer) -> void:
	shading = owner_layer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -24
	offset_bottom = -24
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	toggle.pressed.connect(func() -> void:
		scroll.visible = not scroll.visible
		refresh_toggle()
	)
	column.add_child(toggle)
	body.add_theme_constant_override("separation", 2)
	# Over thirty sliders: they scroll inside a box that fits a 720 px window.
	scroll.visible = false
	scroll.custom_minimum_size = Vector2(430, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body)
	column.add_child(scroll)

	var picker_row: HBoxContainer = HBoxContainer.new()
	var picker_label: Label = Label.new()
	picker_label.text = "Theme (T)"
	picker_label.custom_minimum_size.x = 150
	picker_row.add_child(picker_label)
	for name: String in shading.call("theme_names") as PackedStringArray:
		picker.add_item(name)
	picker.item_selected.connect(func(index: int) -> void:
		shading.call("set_theme", index)
		refresh()
		save()
	)
	picker_row.add_child(picker)
	body.add_child(picker_row)

	for spec: Dictionary in shading.call("specs") as Array[Dictionary]:
		if spec.has("group"):
			var heading: Label = Label.new()
			heading.text = spec["group"] as String
			heading.add_theme_color_override("font_color", Color("9eb1a6"))
			body.add_child(heading)
			continue
		var name: String = spec["name"] as String
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = spec["label"] as String
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = spec["min"] as float
		slider.max_value = spec["max"] as float
		slider.step = spec["step"] as float
		slider.custom_minimum_size.x = 180
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			shading.call("set_value", name, value)
			readouts[name].text = format(value)
			save()
		)
		row.add_child(slider)
		var readout: Label = Label.new()
		readout.custom_minimum_size.x = 56
		row.add_child(readout)
		sliders[name] = slider
		readouts[name] = readout
		body.add_child(row)

	var buttons: HBoxContainer = HBoxContainer.new()
	add_button(buttons, "Theme defaults", func() -> void:
		shading.call("reset_theme")
		refresh()
		save()
	)
	add_button(buttons, "Print values", func() -> void: print("SHADING_TWEAKS " + summary()))
	body.add_child(buttons)
	refresh()
	refresh_toggle()

func add_button(parent: Container, text: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func format(value: float) -> String:
	if absf(value) >= 10.0 or is_equal_approx(value, roundf(value)):
		return "%.0f" % value
	return "%.4f" % value if absf(value) < 0.1 else "%.2f" % value

## Pull every control from the current theme's values (after T, defaults or loading).
func refresh() -> void:
	var values: Dictionary = shading.get("values") as Dictionary
	for name: String in sliders:
		sliders[name].set_value_no_signal(values[name] as float)
		readouts[name].text = format(values[name] as float)
	picker.select(shading.get("theme_index") as int)

func refresh_toggle() -> void:
	toggle.text = "Shading tweaks " + ("▾" if scroll.visible else "▸")

func _process(_delta: float) -> void:
	# Shown with the pause menu (Esc); the HUD theme is borrowed once.
	var game_ui: Node = shading.get_parent().get_node_or_null("GameUI")
	var pause: Control = game_ui.get("pause_panel") as Control if game_ui != null else null
	visible = pause != null and pause.visible
	if theme == null and game_ui != null:
		var screen: Control = game_ui.get("screen") as Control
		if screen != null:
			theme = screen.theme

func summary() -> String:
	var parts: PackedStringArray = PackedStringArray(["theme=%s" % shading.call("theme_name")])
	var values: Dictionary = shading.get("values") as Dictionary
	for name: String in values:
		parts.append("\"%s\": %s" % [name, format(values[name] as float)])
	return ", ".join(parts)

func save() -> void:
	if bool(shading.get("ephemeral")):
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("shading", "theme", shading.call("theme_name"))
	var overrides: Dictionary = shading.get("overrides") as Dictionary
	for theme_name: String in overrides:
		var tuned: Dictionary = overrides[theme_name] as Dictionary
		for name: String in tuned:
			config.set_value("theme " + theme_name, name, tuned[name])
	config.save(SAVE_PATH)

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var overrides: Dictionary = shading.get("overrides") as Dictionary
	var names: PackedStringArray = shading.call("theme_names") as PackedStringArray
	var ranges: Dictionary[String, Vector2] = {}
	for spec: Dictionary in shading.call("specs") as Array[Dictionary]:
		if not spec.has("name"):
			continue
		ranges[spec["name"] as String] = Vector2(spec["min"] as float, spec["max"] as float)
	for theme_name: String in names:
		var section: String = "theme " + theme_name
		if not config.has_section(section):
			continue
		var tuned: Dictionary = {}
		for name: String in config.get_section_keys(section):
			if ranges.has(name):
				tuned[name] = clampf(float(config.get_value(section, name)), ranges[name].x, ranges[name].y)
		overrides[theme_name] = tuned
	var index: int = names.find(String(config.get_value("shading", "theme", names[0])))
	shading.call("set_theme", maxi(index, 0))
	refresh()
