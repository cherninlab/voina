extends PanelContainer

# Settings > Graphics: presets, then each option of core/graphics_settings.gd. Shown beside the
# controls panel on the title and pause menus; ui/game_ui.gd styles it like the other menus.

const FRAME_CAP_LABELS: PackedStringArray = ["30 fps", "60 fps", "120 fps", "Unlimited"]

var title: Label = Label.new()
var preset_label: Label = Label.new()
var hint: Label = Label.new()
var captions: Array[Label] = []
var preset_buttons: Array[Button] = []
var scale_label: Label = Label.new()
var scale_slider: HSlider = HSlider.new()
var options: Dictionary[String, OptionButton] = {}
var fullscreen: CheckButton = CheckButton.new()
var updating: bool = false

func _ready() -> void:
	custom_minimum_size.x = 340
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	title.text = "Graphics"
	column.add_child(title)
	var presets: HBoxContainer = HBoxContainer.new()
	for index: int in range(GraphicsSettings.PRESET_NAMES.size()):
		var preset: Button = Button.new()
		preset.text = GraphicsSettings.PRESET_NAMES[index]
		preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset.pressed.connect(func() -> void:
			GraphicsSettings.set_preset(index)
			refresh()
		)
		presets.add_child(preset)
		preset_buttons.append(preset)
	column.add_child(presets)
	column.add_child(preset_label)
	column.add_child(scale_label)
	captions.append(scale_label)
	scale_slider.min_value = 0.5
	scale_slider.max_value = 1.0
	scale_slider.step = 0.05
	scale_slider.custom_minimum_size.x = 300
	scale_slider.value_changed.connect(func(value: float) -> void:
		if not updating:
			GraphicsSettings.set_option("render_scale", value)
			refresh()
	)
	column.add_child(scale_slider)
	add_option(column, "antialiasing", "Anti-aliasing", GraphicsSettings.AA_LABELS)
	add_option(column, "shadows", "Shadows", GraphicsSettings.SHADOW_LABELS)
	add_option(column, "grass", "Grass distance", GraphicsSettings.GRASS_LABELS)
	add_option(column, "frame_cap", "Frame cap", FRAME_CAP_LABELS)
	fullscreen.text = "Fullscreen"
	fullscreen.toggled.connect(func(enabled: bool) -> void:
		if not updating:
			GraphicsSettings.set_fullscreen(enabled)
	)
	column.add_child(fullscreen)
	hint.text = "Shadows and render scale cost the most. Low suits a MacBook Air; High is the full look."
	column.add_child(hint)
	visibility_changed.connect(refresh)
	refresh()
	hide()

func add_option(column: VBoxContainer, option: String, label_text: String, labels: PackedStringArray) -> void:
	var caption: Label = Label.new()
	caption.text = label_text
	column.add_child(caption)
	captions.append(caption)
	var picker: OptionButton = OptionButton.new()
	for text: String in labels:
		picker.add_item(text)
	picker.item_selected.connect(func(index: int) -> void:
		if not updating:
			GraphicsSettings.set_option(option, index)
			refresh()
	)
	column.add_child(picker)
	options[option] = picker

func refresh() -> void:
	updating = true
	var preset: int = GraphicsSettings.preset_index()
	preset_label.text = "Preset: " + (GraphicsSettings.PRESET_NAMES[preset] if preset >= 0 else "Custom")
	for index: int in range(preset_buttons.size()):
		preset_buttons[index].disabled = index == preset
	scale_slider.value = GraphicsSettings.render_scale
	var frame: Vector2 = get_viewport().get_visible_rect().size * GraphicsSettings.render_scale if is_inside_tree() else Vector2.ZERO
	scale_label.text = "Render scale · %d %% · %d × %d" % [roundi(GraphicsSettings.render_scale * 100.0), roundi(frame.x), roundi(frame.y)]
	for option: String in options:
		options[option].select(int(GraphicsSettings.get(option)))
	fullscreen.button_pressed = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	updating = false
