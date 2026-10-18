extends Node3D

var failures: int = 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("INERTIA_FAIL: " + message)

func run() -> void:
	check_heavy_swing()
	check_carry_through()
	check_gesture_rates()
	check_coupled_motion()
	check_view_frame_cut()
	check_walk_onto_blade()
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	var origin: Vector3 = Vector3(0, 0.9, 0)
	motion.reset(0.0, origin, 0.0)
	check(absf(motion.tip.y - HeavySwordMotion.TIP_RADIUS) < 0.01 and absf(motion.bearing()) < 0.3, "Blade rests with its tip in the ground ahead of the body")
	for frame: int in range(120):
		motion.step(1.0 / 60.0, 0.0, 0.0, true, false, false, origin, 0.0)
	check(motion.tip.y < 0.1 and motion.raised > 0.99, "Holding without dragging cannot lift the blade")
	for frame: int in range(120):
		motion.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin, 0.0)
	# Stepping back a little stretches the arms toward the anchored tip without moving it.
	var anchored_tip: Vector3 = motion.tip
	for frame: int in range(12):
		motion.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin + Vector3(0, 0, 0.1), 0.0)
	check(motion.tip.distance_to(anchored_tip) < 0.02 and motion.stretch > 0.2, "Small body shift stretches the arms while the tip stays anchored")
	# Walking away breaks the anchor, drags the blade along the floor and pulls the owner back toward it.
	var pulled_back: bool = false
	var faced_blade: bool = true
	for frame: int in range(60):
		motion.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin + Vector3(0, 0, 0.1 + frame * 0.05), 0.0, Vector3(0, 0, 3.0))
		pulled_back = pulled_back or motion.pull_velocity.z < -0.05
		faced_blade = faced_blade and absf(angle_difference(motion.body_yaw, motion.blade_yaw())) < 0.5
	check(motion.tip.z > anchored_tip.z + 0.5 and motion.tip.y < 0.1, "Walking away drags the anchored blade along the ground")
	check(pulled_back, "Dragging the anchored blade pulls the owner back toward it")
	check(faced_blade, "Walking away keeps facing the blade (walking backwards)")
	for frame: int in range(120):
		motion.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin + Vector3(0, 0, 3.05), 0.0)
	check(absf(angle_difference(motion.body_yaw, motion.blade_yaw())) < 0.2, "At rest the body turns to face the blade")
	# A drag plus the approved cut throws the tip along the mouse direction; the body follows it.
	var last_blade_yaw: float = motion.blade_yaw()
	var swept: float = 0.0
	var peak: float = 0.0
	var pulled: bool = false
	var body_followed: bool = false
	motion.strike(Vector2.LEFT)
	for frame: int in range(150):
		var yaw: float = minf(0.6, frame * 0.05)
		var pitch: float = minf(0.3, frame * 0.025) # the mouse also rises during the hold, lifting the tip
		motion.step(1.0 / 60.0, yaw, pitch, frame < 12, frame < 31, false, origin + Vector3(0, 0, 3.05), 0.0)
		swept += angle_difference(last_blade_yaw, motion.blade_yaw())
		last_blade_yaw = motion.blade_yaw()
		peak = maxf(peak, motion.tip.y)
		pulled = pulled or (motion.pull_velocity.length() > 0.01 and motion.pull_velocity.length() <= HeavySwordMotion.MAX_PULL)
		if frame == 8:
			body_followed = motion.body_yaw_speed > 0.0 and angle_difference(motion.body_yaw, motion.blade_yaw()) > 0.05
	check(swept > 0.4, "Camera turn and cut swing the blade along the mouse direction (swept %.2f rad)" % swept)
	check(body_followed, "While swinging the torso follows the blade in the cut direction")
	# A cut followed by sustained circular input stays aloft, but one gesture cannot cause an orbit.
	# (In play a held drag always fires its cut after 36 px; the circling then only steers.)
	var spin: HeavySwordMotion = HeavySwordMotion.new()
	spin.reset(0.0, origin, 0.0)
	spin.strike(Vector2.LEFT)
	var spin_peak: float = 0.0
	var spin_swept: float = 0.0
	var spin_last: float = spin.blade_yaw()
	for frame: int in range(90):
		spin.step(1.0 / 60.0, wrapf(frame * 0.1, -PI, PI), 0.0, true, true, false, origin, 0.0)
		spin_peak = maxf(spin_peak, spin.tip.y)
		spin_swept += angle_difference(spin_last, spin.blade_yaw())
		spin_last = spin.blade_yaw()
	check(spin_peak > 0.8, "A cut with circular input lifts the heavy blade (peak %.2f m)" % spin_peak)
	check(spin_swept > 1.0 and spin_swept <= HeavySwordMotion.MAX_SWEEP + HeavySwordMotion.MAX_CARRY + 0.01, "Continuous input stays within one broad arc, short of an orbit (swept %.2f rad)" % spin_swept)
	check(spin.tip_velocity.length() <= HeavySwordMotion.MAX_TIP_SPEED, "Spin speed stays bounded")
	check(pulled, "Heavy blade produces bounded owner pull")
	check(absf(angle_difference(motion.body_yaw, motion.blade_yaw())) < 0.3 and motion.tip.y < 0.1, "Body follows the blade and it settles back into the ground")
	for frame: int in range(120):
		motion.step(1.0 / 60.0, 0.6, 0.0, false, false, false, origin + Vector3(0, 0, 3.05), 0.0)
	check(motion.tip_velocity.length() < 0.05 and motion.raised == 0.0 and motion.pull_velocity.length() < 0.001, "Released blade settles")
	var fine: HeavySwordMotion = HeavySwordMotion.new()
	var coarse: HeavySwordMotion = HeavySwordMotion.new()
	fine.reset(0.0, origin, 0.0)
	coarse.reset(0.0, origin, 0.0)
	fine.strike(Vector2.LEFT)
	coarse.strike(Vector2.LEFT)
	for frame: int in range(120):
		fine.step(1.0 / 120.0, 0.0, 0.0, true, true, false, origin, 0.0)
	for frame: int in range(30):
		coarse.step(1.0 / 30.0, 0.0, 0.0, true, true, false, origin, 0.0)
	check(fine.tip.distance_to(coarse.tip) < 0.01, "Substeps give consistent 30/120 Hz motion")
	coarse.step(5.0, -1000.0, 1000.0, true, true, false, origin, 0.0)
	check(coarse.tip.is_finite() and coarse.tip_velocity.length() <= HeavySwordMotion.MAX_TIP_SPEED + 0.01 and coarse.pull_velocity.length() <= HeavySwordMotion.MAX_PULL, "Long frame and extreme input stay bounded")
	coarse.reset(0.2, origin, 0.0)
	check(coarse.pull_velocity.is_zero_approx() and coarse.tip_velocity.is_zero_approx(), "Correction clears inertia")
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	await get_tree().physics_frame
	for variant: String in ["male", "female"]:
		var packed: PackedScene = load("res://content/characters/quaternius/%s.tscn" % variant) as PackedScene
		var visual: CharacterVisual = packed.instantiate() as CharacterVisual
		visual.position.y = 0.9
		add_child(visual)
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		var planted: Vector3 = visual.feet[0]
		visual.position.x += 0.1
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		check(visual.feet[0] == planted, variant + " support foot stays planted under small body shifts")
		visual.position.x += 0.35
		visual.update_feet(0.06, Vector3.RIGHT, true)
		check(visual.stepping >= 0 and visual.feet[visual.stepping].y > 0.05, variant + " displaced body triggers a lifted recovery step")
		for frame: int in range(60):
			visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
			visual.drive_sword(1.0 / 60.0, 0.0, 0.0, true, false, false, false)
			visual.update_pose(0.0, Vector3.ZERO, false, false)
		await get_tree().process_frame
		await get_tree().process_frame
		for index: int in range(2):
			check(visual.ik.last_feet[index].distance_to(visual.feet[index]) < 0.025, variant + " foot IK reaches planted ground target")
			check(absf(visual.feet[index].y - 0.085) < 0.01, variant + " feet respect ground height")
		visual.update_feet(1.0 / 60.0, Vector3.UP, false)
		check(visual.feet[0].y > 0.2, variant + " airborne legs tuck")
		visual.update_feet(1.0 / 60.0, Vector3.ZERO, true)
		check(absf(visual.feet[0].y - 0.085) < 0.01, variant + " landing replants feet even without walking")
		visual.queue_free()
	await get_tree().process_frame
	var player: CharacterBody3D = (load("res://gameplay/player/player_character.tscn") as PackedScene).instantiate() as CharacterBody3D
	player.position = Vector3(0, 0.95, 0)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.set_physics_process(false)
	var combat: CombatController = player.get("combat") as CombatController
	combat.set_physics_process(false)
	# A cut launches the blade and its momentum pulls the owner along.
	player.call("attack", false, Vector2.LEFT)
	player.set("yaw", 0.8)
	var start: Vector3 = player.position
	for frame: int in range(20):
		player.call("_physics_process", 1.0 / 60.0)
	var displacement: Vector3 = player.position - start
	check(Vector2(displacement.x, displacement.z).length() > 0.02, "Sword momentum moves the owner without movement input")
	check(Vector2(player.velocity.x, player.velocity.z).length() <= HeavySwordMotion.MAX_PULL + 0.01, "Owner follow-through is capped")
	player.call("correct_position", start, Vector3.ZERO)
	var body: CharacterVisual = player.get("body") as CharacterVisual
	check(body.motion.pull_velocity.is_zero_approx(), "Host correction clears owner sword movement")
	if failures == 0:
		print("INERTIA_OK: anchored rest, no hold-up, arm stretch, dragged anchor, owner resistance, always facing the blade, gesture launch, uninterrupted follow-through, persistent landing, return cuts, half-turn heavy cut with ramped tip speed, bounded gesture arcs, release, timestep stability, planted feet, owner pull/correction")
	get_tree().quit(0 if failures == 0 else 1)

func check_heavy_swing() -> void:
	# One approved level cut from rest, no further mouse input: the blade winds up, accelerates
	# to a cutting speed mid-swing and carries through about half a turn before it lands.
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	for hz: int in [30, 60, 120]:
		for side: float in [-1.0, 1.0]:
			var motion: HeavySwordMotion = HeavySwordMotion.new()
			motion.reset(0.0, origin, 0.0)
			motion.strike(Vector2(side, 0.0))
			var previous_yaw: float = motion.blade_yaw()
			var swept: float = 0.0
			var peak: float = 0.0
			var peak_time: float = 0.0
			var early: float = 0.0
			var ramping: bool = true
			var last_speed: float = 0.0
			var mid_speed: float = 0.0
			for frame: int in range(hz * 2):
				var time: float = float(frame + 1) / hz
				motion.step(1.0 / hz, 0.0, 0.0, time <= 0.5, time < 0.52, false, origin, 0.0)
				swept += angle_difference(previous_yaw, motion.blade_yaw()) * -side
				previous_yaw = motion.blade_yaw()
				var speed: float = motion.tip_velocity.length()
				if time <= 0.1:
					early = maxf(early, speed)
				if time <= HeavySwordMotion.DRIVE_TIME:
					ramping = ramping and speed >= last_speed - 0.05
				if swept > deg_to_rad(45.0) and swept < deg_to_rad(120.0):
					mid_speed = maxf(mid_speed, speed)
				if speed > peak:
					peak = speed
					peak_time = time
				last_speed = speed
			var label: String = "%d Hz, cut %+.0f" % [hz, side]
			check(swept > deg_to_rad(170.0) and swept <= HeavySwordMotion.MAX_SWEEP + 0.01, "One approved cut sweeps about 180 degrees (%.0f deg): %s" % [rad_to_deg(swept), label])
			check(ramping and early < peak * 0.45 and peak_time > 0.15, "Tip speed builds up instead of peaking at launch (%.1f m/s by 0.1 s, peak %.1f m/s at %.2f s): %s" % [early, peak, peak_time, label])
			check(mid_speed >= 7.0 and peak <= 15.0, "Mid-swing tip speed can still cut a raider (%.1f m/s): %s" % [mid_speed, label])
			check(motion.planted and motion.tip_velocity.length() < 0.05, "The swing lands and settles: " + label)

func check_view_frame_cut() -> void:
	# The drag that fires a cut also turns the camera. The cut sweeps in the view's frame, so on
	# screen it still turns about half a turn however far the camera went (it was ~85 deg on a
	# 110 deg camera flick when the sweep was world-fixed).
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	for hz: int in [30, 60, 120]:
		for side: float in [-1.0, 1.0]:
			for camera_turn: float in [0.0, 1.0, 1.9]:
				var motion: HeavySwordMotion = HeavySwordMotion.new()
				motion.reset(0.0, origin, 0.0)
				motion.strike(Vector2(side, 0.0))
				var yaw: float = 0.0
				var last_body: float = motion.body_yaw
				var body_travel: float = 0.0
				var peak: float = 0.0
				for frame: int in range(hz * 2):
					var time: float = float(frame + 1) / hz
					yaw = -side * camera_turn * minf(1.0, time / 0.15)
					motion.step(1.0 / hz, yaw, 0.0, time <= 0.25, time < 0.52, false, origin, 0.0)
					body_travel += angle_difference(last_body, motion.body_yaw)
					last_body = motion.body_yaw
					peak = maxf(peak, motion.tip_velocity.length())
				var on_screen: float = (body_travel - yaw) * -side
				var label: String = "%d Hz, cut %+.0f, camera %.1f rad" % [hz, side, camera_turn]
				check(on_screen > deg_to_rad(170.0) and on_screen < HeavySwordMotion.MAX_SWEEP + 0.15, "A cut turns the body about half a turn relative to the view (%.0f deg): %s" % [rad_to_deg(on_screen), label])
				check(motion.planted and peak < HeavySwordMotion.MAX_TIP_SPEED, "A view-carried cut stays bounded and lands: " + label)

func check_walk_onto_blade() -> void:
	# Walking toward a planted tip must never fold the hilt (and the hands) back through the hips.
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	motion.reset(0.0, origin, 0.0)
	var start_tip: Vector3 = motion.tip
	var ahead: bool = true
	for frame: int in range(90):
		origin += Vector3(0.0, 0.0, -3.0 / 60.0)
		motion.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin, 0.0, Vector3(0.0, 0.0, -3.0))
		var to_tip: Vector3 = motion.tip - motion.anchor
		var to_hilt: Vector3 = motion.hilt - motion.anchor
		to_tip.y = 0.0
		to_hilt.y = 0.0
		ahead = ahead and to_hilt.dot(to_tip.normalized()) >= HeavySwordMotion.MIN_REACH - 0.01 and to_tip.length() > to_hilt.length()
	check(ahead, "Walking onto a planted blade keeps the hilt ahead of the hips and the tip beyond it")
	check(motion.tip.z < start_tip.z - 3.0 and motion.grounded(), "Walking onto a planted blade pushes the tip along the ground")

func check_carry_through() -> void:
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	for hz: int in [30, 60, 120]:
		for side: float in [-1.0, 1.0]:
			for keep_holding: bool in [false, true]:
				var motion: HeavySwordMotion = HeavySwordMotion.new()
				motion.reset(0.0, origin, 0.0)
				motion.strike(Vector2(side, 0.0))
				var previous_yaw: float = motion.blade_yaw()
				var swept: float = 0.0
				var peak: float = 0.0
				var reversed: bool = false
				for frame: int in range(hz * 2):
					motion.step(1.0 / hz, 0.0, 0.0, keep_holding, float(frame) / hz < 0.52, false, origin, 0.0)
					var travel: float = angle_difference(previous_yaw, motion.blade_yaw()) * -side
					reversed = reversed or travel < -0.002
					swept += travel
					peak = maxf(peak, motion.tip.y)
					previous_yaw = motion.blade_yaw()
				var label: String = "%d Hz, cut %+.0f, held=%s" % [hz, side, keep_holding]
				check(not reversed and swept > 1.0, "Cut carries past the stationary view without reversal: " + label)
				check(peak > 0.8 and motion.grounded() and motion.tip_velocity.length() < 0.05, "Blade rises to about hip height then lands and settles: " + label)
				var landing: Vector3 = motion.tip
				# Looking elsewhere without a drag must not undo the landed cut.
				for frame: int in range(hz):
					motion.step(1.0 / hz, 1.1, 0.0, false, false, false, origin, 0.0)
				check(motion.tip.distance_to(landing) < 0.015, "Camera look preserves the landing: " + label)
				motion.strike(Vector2(-side, 0.0))
				check(motion.tip.distance_to(landing) < 0.001, "Return cut begins at the landing without teleporting: " + label)
				var start_yaw: float = motion.blade_yaw()
				# The heavy blade winds up first, so give the return cut a third of a second.
				for frame: int in range(ceili(hz * 0.35)):
					motion.step(1.0 / hz, 1.1, 0.0, true, true, false, origin, 0.0)
				check(angle_difference(start_yaw, motion.blade_yaw()) * side > 0.2 and motion.tip.y > 0.1, "Return cut lifts and travels in the new direction: " + label)

func check_gesture_rates() -> void:
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	var landings: Array[Vector3] = []
	for hz: int in [30, 60, 120]:
		var motion: HeavySwordMotion = HeavySwordMotion.new()
		motion.reset(0.0, origin, 0.0)
		motion.step(1.0 / hz, 0.0, 0.0, true, false, false, origin, 0.0)
		motion.strike(Vector2.LEFT)
		for frame: int in range(hz * 3):
			var time: float = float(frame + 1) / hz
			motion.step(1.0 / hz, minf(0.6, time * 3.0), minf(0.3, time * 1.5), time <= 0.2, time < 0.52, false, origin, 0.0)
		landings.append(motion.tip)
	check(landings[0].distance_to(landings[2]) < 0.01 and landings[1].distance_to(landings[2]) < 0.01, "The same moving gesture lands consistently at 30/60/120 Hz")

func check_coupled_motion() -> void:
	# Feed owner displacement back into the solver, as PlayerCharacter does. Fixed-origin
	# tests alone missed the old hand-constraint -> tip velocity -> owner-pull feedback loop.
	for hz: int in [30, 60, 120]:
		for side: float in [-1.0, 1.0]:
			var motion: HeavySwordMotion = HeavySwordMotion.new()
			var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
			var velocity: Vector3 = Vector3.ZERO
			motion.reset(0.0, origin, 0.0)
			motion.strike(Vector2(side, 0.0))
			var last_heading: float = motion.heading
			var last_body: float = motion.body_yaw
			var blade_travel: float = 0.0
			var body_travel: float = 0.0
			var path_length: float = 0.0
			var peak_speed: float = 0.0
			for frame: int in range(hz * 5):
				var dt: float = 1.0 / hz
				# An abrupt look-back while still holding must not introduce another launch.
				motion.step(dt, PI if frame > hz else 0.0, 0.0, true, float(frame) / hz < 0.52, false, origin, 0.0, velocity)
				velocity.x = move_toward(velocity.x, motion.pull_velocity.x, dt * 24.0)
				velocity.z = move_toward(velocity.z, motion.pull_velocity.z, dt * 24.0)
				origin += velocity * dt
				path_length += velocity.length() * dt
				blade_travel += absf(angle_difference(last_heading, motion.heading))
				body_travel += absf(angle_difference(last_body, motion.body_yaw))
				last_heading = motion.heading
				last_body = motion.body_yaw
				peak_speed = maxf(peak_speed, motion.tip_velocity.length())
				check(absf(motion.body_yaw_speed) <= 6.01 and motion.tip.is_finite(), "Torso turn and blade position stay bounded during coupled motion")
			check(peak_speed > 10.0, "An ordinary swing has a forceful launch, without extra mouse input")
			check(path_length > 0.1 and path_length < 0.7, "Sword produces one short step, not a circling owner (%0.3f m)" % path_length)
			check(blade_travel < HeavySwordMotion.MAX_SWEEP + 0.15 and body_travel < HeavySwordMotion.MAX_SWEEP + 0.15, "Sword and body cannot spiral after one launch")
			check(motion.planted and motion.tip_velocity.length() < 0.05 and velocity.length() < 0.001, "Coupled sword/body motion comes fully to rest")
	# Repeated opposite cuts preserve a stable endpoint and can be chained before full settling.
	var chain: HeavySwordMotion = HeavySwordMotion.new()
	var origin: Vector3 = Vector3(0.0, 0.9, 0.0)
	chain.reset(0.0, origin, 0.0)
	for cut: int in range(12):
		chain.strike(Vector2.LEFT if cut % 2 == 0 else Vector2.RIGHT)
		for frame: int in range(42):
			chain.step(1.0 / 60.0, 0.0, 0.0, true, frame < 31, false, origin, 0.0, chain.pull_velocity)
			origin += chain.pull_velocity / 60.0
			check(chain.tip.is_finite() and chain.tip_velocity.length() <= HeavySwordMotion.MAX_TIP_SPEED + 0.01, "Alternating cuts never accumulate unbounded energy")
	for frame: int in range(180):
		chain.step(1.0 / 60.0, 0.0, 0.0, false, false, false, origin, 0.0, chain.pull_velocity)
		origin += chain.pull_velocity / 60.0
	check(chain.planted and chain.pull_velocity.length() < 0.001 and absf(chain.heading_speed) < 0.01, "A rapid chain stops cleanly after release")
