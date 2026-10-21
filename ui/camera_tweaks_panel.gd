extends PanelContainer

# Collapsible live tuning for every number that moves the local camera (CameraTuning): swing
# follow-through, hit shake, walking handheld shake, rig and aim friction. Shown with the pause
# menu in GameUI's tweaks column, with the sword, MPEG and shading tweaks. Values are per machine
# and cosmetic: they persist in user://camera_tweaks.cfg and never reach the host. "Print values"
# logs them for the defaults.
const SAVE_PATH: String = "user://camera_tweaks.cfg"

var toggle: Button = Button.new()
var scroll: ScrollContainer = ScrollContainer.new()
var body: VBoxContainer = VBoxContainer.new()
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}

func _ready() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	toggle.pressed.connect(func() -> void:
		scroll.visible = not scroll.visible
		refresh_toggle()
	)
	column.add_child(toggle)
	body.add_theme_constant_override("separation", 2)
	# Over twenty sliders: they scroll inside a box that fits a 720 px window.
	scroll.visible = false
	scroll.custom_minimum_size = Vector2(330, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body)
	column.add_child(scroll)
	for spec: Dictionary in CameraTuning.specs():
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
		label.custom_minimum_size.x = 132
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = spec["min"] as float
		slider.max_value = spec["max"] as float
		slider.step = (slider.max_value - slider.min_value) / 200.0
		slider.custom_minimum_size.x = 100
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			CameraTuning.set_value(name, value)
			readouts[name].text = format(value)
			save()
		)
		row.add_child(slider)
		var readout: Label = Label.new()
		readout.custom_minimum_size.x = 44
		row.add_child(readout)
		sliders[name] = slider
		readouts[name] = readout
		body.add_child(row)
	var buttons: HBoxContainer = HBoxContainer.new()
	var reset: Button = Button.new()
	reset.text = "Defaults"
	reset.pressed.connect(func() -> void:
		CameraTuning.reset()
		refresh()
		save()
	)
	buttons.add_child(reset)
	var dump: Button = Button.new()
	dump.text = "Print values"
	dump.pressed.connect(func() -> void: print("CAMERA_TWEAKS " + summary()))
	buttons.add_child(dump)
	body.add_child(buttons)
	if DisplayServer.get_name() != "headless":
		load_saved()
	refresh()
	refresh_toggle()

func format(value: float) -> String:
	if absf(value) >= 10.0:
		return "%.0f" % value
	return "%.3f" % value if absf(value) < 0.1 else "%.2f" % value

func refresh() -> void:
	for name: String in sliders:
		sliders[name].set_value_no_signal(CameraTuning.value(name))
		readouts[name].text = format(CameraTuning.value(name))

func refresh_toggle() -> void:
	toggle.text = "Camera tweaks " + ("▾" if scroll.visible else "▸")

func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for name: String in CameraTuning.values:
		parts.append("%s=%.4f" % [name, CameraTuning.value(name)])
	return " ".join(parts)

func save() -> void:
	if DisplayServer.get_name() == "headless":
		return # tests drive the sliders; never overwrite this machine's tuning
	var config: ConfigFile = ConfigFile.new()
	for name: String in CameraTuning.values:
		config.set_value("camera", name, CameraTuning.value(name))
	config.save(SAVE_PATH)

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for spec: Dictionary in CameraTuning.specs():
		if not spec.has("name"):
			continue
		var name: String = spec["name"] as String
		var value: float = float(config.get_value("camera", name, CameraTuning.value(name)))
		CameraTuning.set_value(name, clampf(value, spec["min"] as float, spec["max"] as float))
