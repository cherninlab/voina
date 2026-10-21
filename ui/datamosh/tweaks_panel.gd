extends PanelContainer

# Collapsible live tuning for the MPEG datamosh effect (ui/datamosh.gd), shown with the pause
# menu like the sword tweaks. Values are per machine and cosmetic: they persist in
# user://mpeg_tweaks.cfg. "Print values" logs them in a form that pastes into SPECS defaults.
const SAVE_PATH: String = "user://mpeg_tweaks.cfg"

var mosh: CanvasLayer
var toggle: Button = Button.new()
var body: VBoxContainer = VBoxContainer.new()
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}
var checks: Dictionary[String, CheckBox] = {}
var view: OptionButton = OptionButton.new()

func _init(owner_layer: CanvasLayer) -> void:
	mosh = owner_layer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	position = Vector2(-24, 24)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		refresh_toggle()
	)
	column.add_child(toggle)
	body.visible = false
	body.add_theme_constant_override("separation", 2)
	column.add_child(body)

	for spec: Dictionary in mosh.call("toggle_specs") as Array[Dictionary]:
		var name: String = spec["name"] as String
		var check: CheckBox = CheckBox.new()
		check.text = spec["label"] as String
		check.toggled.connect(func(on: bool) -> void:
			(mosh.get("flags") as Dictionary)[name] = on
			save()
		)
		checks[name] = check
		body.add_child(check)
	var view_row: HBoxContainer = HBoxContainer.new()
	var view_label: Label = Label.new()
	view_label.text = "Debug view (F7)"
	view_label.custom_minimum_size.x = 170
	view_row.add_child(view_label)
	for item: String in DatamoshEffect.DEBUG_VIEWS:
		view.add_item(item)
	view.item_selected.connect(func(index: int) -> void: effect().debug_view = index)
	view_row.add_child(view)
	body.add_child(view_row)

	for spec: Dictionary in mosh.call("specs") as Array[Dictionary]:
		if spec.has("group"):
			var heading: Label = Label.new()
			heading.text = spec["group"] as String
			heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
			body.add_child(heading)
			continue
		var name: String = spec["name"] as String
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = spec["label"] as String
		label.custom_minimum_size.x = 170
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = spec["min"] as float
		slider.max_value = spec["max"] as float
		slider.step = spec["step"] as float
		slider.custom_minimum_size.x = 180
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			(mosh.get("values") as Dictionary)[name] = value
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
	add_button(buttons, "Mosh now (F6)", func() -> void: mosh.call("manual_burst"))
	add_button(buttons, "Defaults", func() -> void:
		mosh.call("reset_defaults")
		refresh()
		save()
	)
	add_button(buttons, "Print values", func() -> void: print("MPEG_TWEAKS " + summary()))
	body.add_child(buttons)
	if DisplayServer.get_name() != "headless":
		load_saved()
	refresh()
	refresh_toggle()

func effect() -> DatamoshEffect:
	return mosh.get("effect") as DatamoshEffect

func add_button(parent: Container, text: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func format(value: float) -> String:
	return "%.0f" % value if absf(value) >= 10.0 else "%.2f" % value

## Pull every control from the effect's current values (after keys, defaults or loading).
func refresh() -> void:
	var values: Dictionary = mosh.get("values") as Dictionary
	var flags: Dictionary = mosh.get("flags") as Dictionary
	for name: String in sliders:
		sliders[name].set_value_no_signal(values[name] as float)
		readouts[name].text = format(values[name] as float)
	for name: String in checks:
		checks[name].set_pressed_no_signal(flags[name] as bool)
	view.select(effect().debug_view)

func refresh_toggle() -> void:
	toggle.text = "MPEG tweaks " + ("▾" if body.visible else "▸")

func _process(_delta: float) -> void:
	# Shown with the pause menu (Esc), like the sword tweaks; the HUD theme is borrowed once.
	var game_ui: Node = mosh.get_parent().get_node_or_null("GameUI")
	var pause: Control = game_ui.get("pause_panel") as Control if game_ui != null else null
	visible = pause != null and pause.visible
	if theme == null and game_ui != null:
		var screen: Control = game_ui.get("screen") as Control
		if screen != null:
			theme = screen.theme

func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var flags: Dictionary = mosh.get("flags") as Dictionary
	var values: Dictionary = mosh.get("values") as Dictionary
	for name: String in flags:
		parts.append("%s=%s" % [name, flags[name]])
	for name: String in values:
		parts.append("%s=%s" % [name, format(values[name] as float)])
	return " ".join(parts)

func save() -> void:
	var config: ConfigFile = ConfigFile.new()
	var flags: Dictionary = mosh.get("flags") as Dictionary
	var values: Dictionary = mosh.get("values") as Dictionary
	for name: String in flags:
		config.set_value("flags", name, flags[name])
	for name: String in values:
		config.set_value("values", name, values[name])
	config.save(SAVE_PATH)

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var flags: Dictionary = mosh.get("flags") as Dictionary
	var values: Dictionary = mosh.get("values") as Dictionary
	for name: String in flags:
		flags[name] = bool(config.get_value("flags", name, flags[name]))
	for spec: Dictionary in mosh.call("specs") as Array[Dictionary]:
		if spec.has("name"):
			var name: String = spec["name"] as String
			var saved: float = float(config.get_value("values", name, values[name]))
			values[name] = clampf(saved, spec["min"] as float, spec["max"] as float)
