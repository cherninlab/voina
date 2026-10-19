extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dt: float = 1.0 / 60.0
	var walk: WalkCamera = WalkCamera.new()
	for frame: int in range(60):
		walk.step(dt, 0.0, true)
	assert(walk.shift == Vector2.ZERO and walk.turn == Vector3.ZERO, "Standing still leaves the view exactly still")
	# Walking builds a bob, sway, roll and jitter; peaks grow with speed.
	var slow: float = peak(walk, 3.0, true)
	var full: float = peak(walk, 6.5, true)
	assert(full > 0.01 and full <= CameraTuning.value("walk_bob") * 1.01 + 0.0001, "Walking bobs the view within its amplitude")
	assert(slow < full * 0.7, "Shake scales with ground speed")
	assert(absf(walk.turn.z) > 0.0 or absf(walk.turn.x) > 0.0, "Walking rolls and jitters the view")
	# Airborne or stopping, it fades to exactly zero.
	for frame: int in range(60):
		walk.step(dt, 6.5, false)
	assert(walk.intensity == 0.0 and walk.shift == Vector2.ZERO and walk.turn == Vector3.ZERO, "Airborne fades the shake out")
	peak(walk, 6.5, true)
	for frame: int in range(60):
		walk.step(dt, 0.0, true)
	assert(walk.shift == Vector2.ZERO and walk.turn == Vector3.ZERO, "Stopping fades the shake out")
	assert(walk.intensity == 0.0, "Fade reaches zero")
	walk.step(dt, NAN, true)
	walk.step(NAN, 6.5, true)
	assert(walk.shift.is_finite() and walk.turn.is_finite(), "Bad input never corrupts the view")

	# The panel builds a slider per tunable, and each slider writes the live value.
	var panel: PanelContainer = preload("res://ui/camera_tweaks_panel.gd").new()
	root.add_child(panel)
	var sliders: Dictionary = panel.get("sliders") as Dictionary
	var count: int = 0
	for spec: Dictionary in CameraTuning.specs():
		if not spec.has("name"):
			continue
		count += 1
		var name: String = spec["name"] as String
		var slider: HSlider = sliders[name] as HSlider
		slider.value = slider.max_value
		assert(is_equal_approx(CameraTuning.value(name), slider.max_value), "Slider %s drives the live value" % name)
	assert(sliders.size() == count, "One slider per tunable")
	# Live values reach the cameras: a bigger bob shakes more, zero swing bank leaves no roll.
	CameraTuning.reset()
	var base_peak: float = peak(WalkCamera.new(), 6.5, true)
	CameraTuning.set_value("walk_bob", CameraTuning.value("walk_bob") * 2.0)
	assert(peak(WalkCamera.new(), 6.5, true) > base_peak * 1.8, "Walk bob slider scales the live shake")
	CameraTuning.set_value("swing_roll", 0.0)
	var swing: SwingCamera = SwingCamera.new()
	for frame: int in range(30):
		swing.step(dt, HeavySwordMotion.MAX_ANGULAR_SPEED, 0.0)
	assert(absf(swing.offset.z) < 0.000001 and swing.offset.y > 0.0, "Swing sliders drive the live sway")
	CameraTuning.reset()
	panel.queue_free()
	print("WALK_CAMERA_OK: still at rest, %.1f cm bob at walking speed (%.1f cm slow), fades out airborne and stopped, %d sliders drive live values" % [full * 100.0, slow * 100.0, count])
	quit()

# Largest vertical offset over two seconds of steady movement.
func peak(walk: WalkCamera, speed: float, grounded: bool) -> float:
	var result: float = 0.0
	for frame: int in range(120):
		walk.step(1.0 / 60.0, speed, grounded)
		result = maxf(result, absf(walk.shift.y))
	return result
