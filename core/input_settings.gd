extends Node

const DEFAULTS: Dictionary[StringName, int] = {
	&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
	&"melee": KEY_F, &"beam": KEY_E, &"block": KEY_CTRL, &"dash": KEY_SHIFT,
	&"jump": KEY_SPACE, &"camera_toggle": KEY_V, &"quick_turn": KEY_R, &"bolt": KEY_Q,
}
var keys: Dictionary[StringName, int] = DEFAULTS.duplicate()
var sensitivity: float = 0.0024

func _ready() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://controls.cfg") == OK:
		sensitivity = clampf(float(config.get_value("look", "sensitivity", sensitivity)), 0.0005, 0.01)
		for action: StringName in DEFAULTS:
			var value: int = int(config.get_value("keys", action, DEFAULTS[action]))
			if value > 0 and value != KEY_ESCAPE:
				keys[action] = value
	apply_bindings()

func apply_bindings() -> void:
	for action: StringName in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = keys[action] as Key
		InputMap.action_add_event(action, key)
	add_mouse(&"melee", MOUSE_BUTTON_LEFT)
	add_mouse(&"block", MOUSE_BUTTON_RIGHT)

func add_mouse(action: StringName, button_index: MouseButton) -> void:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = button_index
	InputMap.action_add_event(action, button)

func rebind(action: StringName, keycode: int) -> bool:
	if not keys.has(action) or keycode <= 0 or keycode == KEY_ESCAPE:
		return false
	for existing: StringName in keys:
		if existing != action and keys[existing] == keycode:
			return false
	keys[action] = keycode
	apply_bindings()
	save_settings()
	return true

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	for action: StringName in keys:
		config.set_value("keys", action, keys[action])
	config.set_value("look", "sensitivity", sensitivity)
	var error: Error = config.save("user://controls.cfg")
	if error != OK:
		push_warning("Could not save controls: " + error_string(error))

func reset_defaults() -> void:
	keys = DEFAULTS.duplicate()
	sensitivity = 0.0024
	apply_bindings()
	save_settings()

func key_label(action: StringName) -> String:
	return OS.get_keycode_string(keys[action])
