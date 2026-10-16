extends PanelContainer

var actions: OptionButton = OptionButton.new()
var bind_button: Button = Button.new()
var message: Label = Label.new()
var sensitivity: HSlider = HSlider.new()
var waiting: bool = false

func _ready() -> void:
	position = Vector2(440, 80)
	custom_minimum_size.x = 340
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title: Label = Label.new()
	title.text = "CONTROLS · Esc releases the cursor"
	column.add_child(title)
	for action: StringName in InputSettings.DEFAULTS:
		actions.add_item(String(action).replace("_", " ").capitalize())
		actions.set_item_metadata(actions.item_count - 1, action)
	actions.item_selected.connect(func(_index: int) -> void: refresh())
	column.add_child(actions)
	bind_button.pressed.connect(func() -> void:
		waiting = true
		message.text = "Press a key · Esc cancels"
	)
	column.add_child(bind_button)
	column.add_child(message)
	var look_label: Label = Label.new()
	look_label.text = "Look sensitivity"
	column.add_child(look_label)
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.01
	sensitivity.step = 0.0001
	sensitivity.value = InputSettings.sensitivity
	sensitivity.custom_minimum_size.x = 300
	sensitivity.value_changed.connect(func(value: float) -> void:
		InputSettings.sensitivity = value
		InputSettings.save_settings()
	)
	column.add_child(sensitivity)
	var reset: Button = Button.new()
	reset.text = "Restore defaults"
	reset.pressed.connect(func() -> void:
		InputSettings.reset_defaults()
		sensitivity.value = InputSettings.sensitivity
		refresh()
	)
	column.add_child(reset)
	var close: Button = Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		waiting = false
		hide()
	)
	column.add_child(close)
	refresh()
	hide()

func refresh() -> void:
	var action: StringName = actions.get_item_metadata(actions.selected)
	bind_button.text = "Rebind: " + InputSettings.key_label(action)
	message.text = "Hold left click / melee key + drag to swing\nRelease to rearm · Right click: block"

func _input(event: InputEvent) -> void:
	if not visible or not waiting or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode == KEY_ESCAPE:
		waiting = false
		refresh()
		return
	var action: StringName = actions.get_item_metadata(actions.selected)
	if InputSettings.rebind(action, key.physical_keycode):
		waiting = false
		refresh()
	else:
		message.text = "Key already assigned; try another"
