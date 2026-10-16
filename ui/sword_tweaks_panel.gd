extends PanelContainer

# Collapsible live tuning for HeavySwordMotion. Values are per machine and cosmetic: they persist
# in user://sword_tweaks.cfg and never reach the host's combat authority.
const SAVE_PATH: String = "user://sword_tweaks.cfg"
var toggle: Button = Button.new()
var body: VBoxContainer = VBoxContainer.new()
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}

func _ready() -> void:
	position = Vector2(24, 190)
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
	for spec: Dictionary in HeavySwordMotion.tunable_specs():
		var name: String = spec["name"] as String
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = spec["label"] as String
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = spec["min"] as float
		slider.max_value = spec["max"] as float
		slider.step = (slider.max_value - slider.min_value) / 200.0
		slider.value = HeavySwordMotion.get_tunable(name)
		slider.custom_minimum_size.x = 180
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			HeavySwordMotion.set_tunable(name, value)
			readouts[name].text = "%.2f" % value
			save()
		)
		row.add_child(slider)
		var readout: Label = Label.new()
		readout.text = "%.2f" % slider.value
		readout.custom_minimum_size.x = 56
		row.add_child(readout)
		sliders[name] = slider
		readouts[name] = readout
		body.add_child(row)
	var buttons: HBoxContainer = HBoxContainer.new()
	var reset: Button = Button.new()
	reset.text = "Defaults"
	reset.pressed.connect(func() -> void:
		HeavySwordMotion.reset_tunables()
		for name: String in sliders:
			sliders[name].set_value_no_signal(HeavySwordMotion.get_tunable(name))
			readouts[name].text = "%.2f" % HeavySwordMotion.get_tunable(name)
		save()
	)
	buttons.add_child(reset)
	var dump: Button = Button.new()
	dump.text = "Print values"
	dump.pressed.connect(func() -> void: print("SWORD_TWEAKS " + summary()))
	buttons.add_child(dump)
	body.add_child(buttons)
	if DisplayServer.get_name() != "headless":
		load_saved()
	refresh_toggle()

func refresh_toggle() -> void:
	toggle.text = "Sword tweaks " + ("▾" if body.visible else "▸")

func _process(_delta: float) -> void:
	# Like the Controls button: only reachable once Esc has released the cursor.
	visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for spec: Dictionary in HeavySwordMotion.tunable_specs():
		var name: String = spec["name"] as String
		parts.append("%s=%.3f" % [name, HeavySwordMotion.get_tunable(name)])
	return " ".join(parts)

func save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for spec: Dictionary in HeavySwordMotion.tunable_specs():
		var name: String = spec["name"] as String
		config.set_value("sword", name, HeavySwordMotion.get_tunable(name))
	config.save(SAVE_PATH)

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for spec: Dictionary in HeavySwordMotion.tunable_specs():
		var name: String = spec["name"] as String
		var value: float = float(config.get_value("sword", name, HeavySwordMotion.get_tunable(name)))
		HeavySwordMotion.set_tunable(name, clampf(value, spec["min"] as float, spec["max"] as float))
		sliders[name].set_value_no_signal(HeavySwordMotion.get_tunable(name))
		readouts[name].text = "%.2f" % HeavySwordMotion.get_tunable(name)
