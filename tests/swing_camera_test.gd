extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dt: float = 1.0 / 60.0
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	var view: SwingCamera = SwingCamera.new()
	motion.reset(0.0, Vector3.ZERO, -0.9)
	for frame: int in range(30):
		view.step(dt, motion.heading_speed, motion.elevation_speed)
	assert(view.offset.is_zero_approx(), "A resting blade leaves the view still")
	# Looking around without holding the sword never sways the view.
	for frame: int in range(60):
		motion.step(dt, frame * 0.05, 0.0, false, false)
		view.step(dt, motion.heading_speed, motion.elevation_speed)
	assert(view.offset.length() < 0.001, "Mouse look alone does not sway the view")
	# A leftward cut turns and banks the view left, a beat behind the blade, within its bounds.
	motion.strike(Vector2.LEFT)
	var peak: Vector3 = Vector3.ZERO
	var peak_time: float = 0.0
	var blade_peak_time: float = 0.0
	var blade_peak: float = 0.0
	var landed_at: float = -1.0
	var time: float = 0.0
	while time < 3.0:
		motion.step(dt, 0.0, 0.0, false, true)
		view.step(dt, motion.heading_speed, motion.elevation_speed)
		time += dt
		if absf(motion.heading_speed) > blade_peak:
			blade_peak = absf(motion.heading_speed)
			blade_peak_time = time
		if view.offset.z > peak.z:
			peak = view.offset
			peak_time = time
		if landed_at < 0.0 and not motion.stroke_live:
			landed_at = time
	assert(peak.y > SwingCamera.MAX_YAW * 0.4 and peak.z > SwingCamera.MAX_ROLL * 0.4, "A cut visibly turns and banks the view toward the blade")
	assert(absf(peak.x) <= SwingCamera.MAX_PITCH * 1.3 and peak.y <= SwingCamera.MAX_YAW * 1.3 and peak.z <= SwingCamera.MAX_ROLL * 1.3, "Sway stays slight")
	assert(peak_time > blade_peak_time, "The view follows the blade rather than leading it")
	assert(landed_at > 0.0, "The cut lands")
	assert(view.offset.length() < 0.002, "The view settles back after the blade lands")
	# A rightward cut mirrors it.
	view.reset()
	motion.strike(Vector2.RIGHT)
	var low: float = 0.0
	for frame: int in range(40):
		motion.step(dt, 0.0, 0.0, false, true)
		low = minf(low, view.step(dt, motion.heading_speed, motion.elevation_speed).z)
	assert(low < -SwingCamera.MAX_ROLL * 0.4, "A rightward cut banks the other way")
	assert(view.step(dt, NAN, 0.0).is_finite(), "Bad input never corrupts the view")
	print("SWING_CAMERA_OK: still at rest, ignores mouse look, follows a cut %.1f/%.1f deg yaw/roll, settles after landing, mirrors" % [rad_to_deg(peak.y), rad_to_deg(peak.z)])
	quit()
