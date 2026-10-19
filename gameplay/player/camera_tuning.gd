class_name CameraTuning
extends RefCounted
## Every number that moves the local player's camera: the swing follow-through (SwingCamera), hit
## shake, the walking handheld shake (WalkCamera), the third-person rig and aim friction. All are
## live-tunable from the Camera tweaks panel (ui/camera_tweaks_panel.gd) and persist per machine.
## Cosmetic and local: only the owner's camera reads them, nothing is networked. The field of view
## stays with the Fisheye control, which must match the fisheye remap.

static var values: Dictionary[String, float] = defaults()

static func specs() -> Array[Dictionary]:
	return [
		{"group": "Swing follow-through"},
		{"name": "swing_yaw", "label": "Swing turn (rad)", "min": 0.0, "max": 0.2, "default": SwingCamera.MAX_YAW},
		{"name": "swing_roll", "label": "Swing bank (rad)", "min": 0.0, "max": 0.25, "default": SwingCamera.MAX_ROLL},
		{"name": "swing_pitch", "label": "Swing nod (rad)", "min": 0.0, "max": 0.15, "default": SwingCamera.MAX_PITCH},
		{"name": "swing_stiffness", "label": "Swing spring", "min": 10.0, "max": 300.0, "default": SwingCamera.STIFFNESS},
		{"name": "swing_damping", "label": "Swing damp", "min": 1.0, "max": 40.0, "default": SwingCamera.DAMPING},
		{"group": "Hit shake"},
		{"name": "shake_dealt", "label": "Shake dealing (s)", "min": 0.0, "max": 0.6, "default": 0.14},
		{"name": "shake_taken", "label": "Shake when hit (s)", "min": 0.0, "max": 1.0, "default": 0.3},
		{"name": "shake_side", "label": "Shake sideways", "min": 0.0, "max": 0.5, "default": 0.12},
		{"name": "shake_lift", "label": "Shake vertical", "min": 0.0, "max": 0.5, "default": 0.1},
		{"name": "shake_rate", "label": "Shake rate", "min": 10.0, "max": 200.0, "default": 70.0},
		{"group": "Walking shake"},
		{"name": "walk_bob", "label": "Walk bob (m)", "min": 0.0, "max": 0.1, "default": 0.02},
		{"name": "walk_sway", "label": "Walk sway (m)", "min": 0.0, "max": 0.1, "default": 0.012},
		{"name": "walk_roll", "label": "Walk roll (rad)", "min": 0.0, "max": 0.05, "default": 0.008},
		{"name": "walk_steps", "label": "Step rate (Hz)", "min": 0.5, "max": 4.0, "default": 1.8},
		{"name": "walk_jitter", "label": "Jitter (rad)", "min": 0.0, "max": 0.03, "default": 0.004},
		{"name": "walk_jitter_rate", "label": "Jitter rate", "min": 0.1, "max": 5.0, "default": 1.2},
		{"name": "walk_full_speed", "label": "Full speed (m/s)", "min": 1.0, "max": 16.0, "default": 6.5},
		{"name": "walk_speed_curve", "label": "Speed curve", "min": 0.25, "max": 3.0, "default": 1.0},
		{"name": "walk_max_scale", "label": "Fast cap (x)", "min": 1.0, "max": 3.0, "default": 1.5},
		{"name": "walk_fade", "label": "Fade rate (/s)", "min": 0.5, "max": 20.0, "default": 5.0},
		{"group": "Rig and look"},
		{"name": "arm_length", "label": "Distance (m)", "min": 0.5, "max": 6.0, "default": 2.6},
		{"name": "shoulder", "label": "Shoulder (m)", "min": -1.5, "max": 1.5, "default": 0.55},
		{"name": "aim_friction", "label": "Aim friction", "min": 0.2, "max": 1.0, "default": AimAssist.FRICTION},
	]

static func defaults() -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	for spec: Dictionary in specs():
		if spec.has("name"):
			result[spec["name"] as String] = spec["default"] as float
	return result

static func value(name: String) -> float:
	return values.get(name, 0.0) as float

static func set_value(name: String, number: float) -> void:
	if values.has(name) and is_finite(number):
		values[name] = number

static func reset() -> void:
	values = defaults()
