class_name HeavySwordMotion
extends RefCounted

# Stylized angular inertia, independent of hand/body constraint corrections. The blade has
# a heading and elevation with bounded speeds; the body follows, but cannot feed energy back
# into the weapon. An approved cut is a torque that builds over DRIVE_TIME, so the heavy blade
# starts slowly, accelerates through the arc and coasts on its momentum until it lands.
# Exported world-space tip velocity is for contact, never solver input.
# Combat authorization stays with the host.
const BLADE: float = 1.65
const TIP_RADIUS: float = 0.03
const MAX_PULL: float = 1.8
const MAX_TIP_SPEED: float = 30.0
const MAX_SWEEP: float = 3.4 # one gesture sweeps about half a turn, never orbits the character
const MAX_ELEVATION: float = 0.95 # clear overhead lift without the vertical heading singularity
const MAX_ANGULAR_SPEED: float = 7.5
const DRIVE_TIME: float = 0.20 # the cut's torque builds over this long, then the blade coasts
const FOLLOW_THROUGH_TIME: float = 0.6
const HOLD_BEARING: float = 1.9 # the hands stay beside or ahead of the hips
const ANCHOR_HOLD_SPEED: float = 0.6 # below this a resting tip sticks
const MIN_REACH: float = 0.22 # a planted hilt never comes closer to the hips than this
const CARRY_SPEED: float = 6.0 # rad/s at which a live cut catches up with the view's turn
const MAX_CARRY: float = 2.4 # view turn one cut can absorb, so a circling drag still never orbits

# Tunables: the in-game Sword tweaks panel edits these live; tests use the defaults.
static var gravity: float = 9.8
static var follow_spring: float = 60.0 # gesture impulse gain; never a spring toward the camera
static var follow_damping: float = 1.5
static var body_stiffness: float = 160.0 # how hard the body follows the blade while swinging
static var body_top_speed: float = 14.0 # rad/s cap on the body's turn while swinging
static var cut_speed: float = 7.5 # rad/s a level cut builds up to over DRIVE_TIME (was strike_turn)
static var air_damping: float = 0.3
static var lift_gain: float = 3.0 # tip m/s per radian of camera pitch while dragging
static var drag_friction: float = 3.0 # angular braking on ground contact
static var anchor_friction: float = 14.0 # braking when the blade lands
static var rest_reach: float = 0.3 # nominal hilt distance ahead of the hips
static var max_reach: float = 0.44 # arms plus lean reach this far before the anchor breaks
static var rest_height: float = 0.12
static var raised_height: float = 0.36
static var resist_pull: float = 1.0 # m/s the owner is pulled toward a stretched anchored blade
static var pull_gain: float = 0.5 # owner follow-through per m/s of tip speed while attacking (capped at MAX_PULL)

static func tunable_specs() -> Array[Dictionary]:
	return [
		{"name": "follow_spring", "label": "Gesture drive", "min": 0.0, "max": 200.0, "default": 60.0},
		{"name": "follow_damping", "label": "Gesture damping", "min": 0.0, "max": 10.0, "default": 1.5},
		{"name": "body_stiffness", "label": "Body follow", "min": 10.0, "max": 400.0, "default": 160.0},
		{"name": "body_top_speed", "label": "Body turn cap", "min": 2.0, "max": 30.0, "default": 14.0},
		{"name": "cut_speed", "label": "Cut speed", "min": 1.0, "max": 7.5, "default": 7.5},
		{"name": "air_damping", "label": "Air damping", "min": 0.0, "max": 3.0, "default": 0.3},
		{"name": "gravity", "label": "Gravity", "min": 1.0, "max": 30.0, "default": 9.8},
		{"name": "lift_gain", "label": "Mouse lift", "min": 0.0, "max": 12.0, "default": 3.0},
		{"name": "drag_friction", "label": "Floor drag", "min": 0.0, "max": 20.0, "default": 3.0},
		{"name": "anchor_friction", "label": "Landing brake", "min": 0.0, "max": 40.0, "default": 14.0},
		{"name": "max_reach", "label": "Max reach", "min": 0.3, "max": 0.8, "default": 0.44},
		{"name": "rest_height", "label": "Hilt rest height", "min": -0.2, "max": 0.5, "default": 0.12},
		{"name": "raised_height", "label": "Hilt raised height", "min": 0.0, "max": 0.8, "default": 0.36},
		{"name": "resist_pull", "label": "Anchor pull-back", "min": 0.0, "max": 4.0, "default": 1.0},
		{"name": "pull_gain", "label": "Swing follow-through", "min": 0.0, "max": 0.5, "default": 0.5},
	]

static func get_tunable(name: String) -> float:
	match name:
		"gravity": return gravity
		"follow_spring": return follow_spring
		"follow_damping": return follow_damping
		"body_stiffness": return body_stiffness
		"body_top_speed": return body_top_speed
		"cut_speed": return cut_speed
		"air_damping": return air_damping
		"lift_gain": return lift_gain
		"drag_friction": return drag_friction
		"anchor_friction": return anchor_friction
		"rest_reach": return rest_reach
		"max_reach": return max_reach
		"rest_height": return rest_height
		"raised_height": return raised_height
		"resist_pull": return resist_pull
		"pull_gain": return pull_gain
	return 0.0

static func set_tunable(name: String, value: float) -> void:
	if not is_finite(value):
		return
	match name:
		"gravity": gravity = value
		"follow_spring": follow_spring = value
		"follow_damping": follow_damping = value
		"body_stiffness": body_stiffness = value
		"body_top_speed": body_top_speed = value
		"cut_speed": cut_speed = value
		"air_damping": air_damping = value
		"lift_gain": lift_gain = value
		"drag_friction": drag_friction = value
		"anchor_friction": anchor_friction = value
		"rest_reach": rest_reach = value
		"max_reach": max_reach = value
		"rest_height": rest_height = value
		"raised_height": raised_height = value
		"resist_pull": resist_pull = value
		"pull_gain": pull_gain = value

static func reset_tunables() -> void:
	for spec: Dictionary in tunable_specs():
		set_tunable(spec["name"] as String, spec["default"] as float)

var tip: Vector3 = Vector3.ZERO
var tip_velocity: Vector3 = Vector3.ZERO
var hilt: Vector3 = Vector3.ZERO
var anchor: Vector3 = Vector3.ZERO
var ground: float = -0.9
var body_yaw: float = 0.0
var body_yaw_speed: float = 0.0
var lean: Vector2 = Vector2.ZERO
var lean_speed: Vector2 = Vector2.ZERO
var pull_velocity: Vector3 = Vector3.ZERO
var raised: float = 0.0
var stretch: float = 0.0
var last_yaw: float = 0.0
var last_pitch: float = 0.0
var tracking: bool = false
var initialized: bool = false
var heading: float = 0.0
var elevation: float = 0.0
var heading_speed: float = 0.0
var elevation_speed: float = 0.0
var sweep: float = 0.0 # signed heading travel of the current gesture; unwrapped, so it can pass PI
var planted: bool = true
var was_holding: bool = false
var stroke_age: float = FOLLOW_THROUGH_TIME
var stroke_pull: Vector3 = Vector3.ZERO
var drive_age: float = DRIVE_TIME
var drive_turn: float = 0.0 # signed peak heading torque of the current cut, rad/s^2
var drive_lift: float = 0.0 # elevation torque of the current cut, rad/s^2
var stroke_live: bool = false # an approved cut is still in the air; cleared when it lands
var carry: float = 0.0 # view turn a live cut still owes the blade and body, rad
var carry_left: float = 0.0 # how much more view turn the live cut may absorb, rad

func reset(camera_yaw: float, origin: Vector3 = anchor, floor_y: float = ground) -> void:
	anchor = origin
	ground = floor_y
	body_yaw = camera_yaw
	body_yaw_speed = 0.0
	heading = camera_yaw
	sweep = 0.0
	drive_age = DRIVE_TIME
	stroke_live = false
	carry = 0.0
	carry_left = 0.0
	elevation = rest_elevation()
	heading_speed = 0.0
	elevation_speed = 0.0
	lean = Vector2.ZERO
	lean_speed = Vector2.ZERO
	pull_velocity = Vector3.ZERO
	stroke_pull = Vector3.ZERO
	stroke_age = FOLLOW_THROUGH_TIME
	raised = 0.0
	stretch = 0.0
	tip_velocity = Vector3.ZERO
	tracking = false
	was_holding = false
	planted = true
	initialized = true
	place_blade()

func rest_elevation() -> float:
	return asin(clampf((ground + TIP_RADIUS - anchor.y - rest_height) / BLADE, -0.95, 0.95))

func direction_from(bearing_angle: float, vertical: float) -> Vector3:
	var flat: float = sqrt(maxf(0.0, 1.0 - vertical * vertical))
	return Vector3(-sin(bearing_angle) * flat, vertical, -cos(bearing_angle) * flat).rotated(Vector3.UP, body_yaw)

func blade_direction() -> Vector3:
	var rod: Vector3 = tip - hilt
	return rod.normalized() if rod.length_squared() > 0.000001 else Vector3.DOWN

func blade_yaw() -> float:
	return heading

func bearing() -> float:
	return angle_difference(body_yaw, heading)

func grounded() -> bool:
	return tip.y <= ground + TIP_RADIUS + 0.01

func hilt_offset(direction: Vector3) -> Vector3:
	var hold: float = clampf(bearing(), -HOLD_BEARING, HOLD_BEARING)
	var reach: float = lerpf(rest_reach, max_reach, stretch)
	var lift: float = clampf((direction.y - sin(rest_elevation())) / 1.0, 0.0, 1.0)
	var height: float = lerpf(rest_height, raised_height, lift)
	return Vector3(-sin(hold) * reach, height, -cos(hold) * reach).rotated(Vector3.UP, body_yaw)

func place_blade() -> void:
	var direction: Vector3 = Vector3(-sin(heading) * cos(elevation), sin(elevation), -cos(heading) * cos(elevation))
	hilt = anchor + hilt_offset(direction)
	tip = hilt + direction * BLADE

func strike(direction: Vector2) -> void:
	if not direction.is_finite() or direction.is_zero_approx():
		return
	var cut: Vector2 = direction.normalized()
	sweep = 0.0
	# No launch velocity: the cut is a torque that rises over DRIVE_TIME (see drive()), sized so
	# a level cut peaks near cut_speed rad/s and coasts to a landing about half a turn away.
	# Momentum already travelling in the cut direction is kept; the grip stops the opposite.
	var side: float = -cut.x
	heading_speed = side * maxf(heading_speed * signf(side), 0.0) if not is_zero_approx(side) else heading_speed * 0.5
	drive_turn = side * cut_speed / (0.65 * DRIVE_TIME)
	# A down-cut already aloft chops with gravity; from the floor it first picks the blade up.
	var chop: bool = cut.y > 0.5 and elevation > 0.1
	drive_lift = -12.0 if chop else (26.0 + lift_gain) * (1.0 - cut.y * 0.25)
	elevation_speed = minf(elevation_speed, 0.0) if chop else maxf(elevation_speed, 0.0) * 0.5
	drive_age = 0.0
	stroke_live = true
	carry = 0.0
	carry_left = MAX_CARRY
	planted = false
	stroke_age = 0.0
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, heading)
	var tangent: Vector3 = Vector3.UP.cross(forward) * -cut.x
	stroke_pull = (forward * 0.65 + tangent).normalized()

func step(delta: float, camera_yaw: float, camera_pitch: float, holding: bool, attacking: bool, blocking: bool = false, origin: Vector3 = anchor, floor_y: float = ground, velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_finite(camera_yaw) or not is_finite(camera_pitch) or not is_finite(delta) or delta <= 0.0 or not origin.is_finite() or not is_finite(floor_y) or not velocity.is_finite():
		return
	if not initialized:
		reset(camera_yaw, origin, floor_y)
	var duration: float = minf(delta, 0.1)
	var turn: float = angle_difference(last_yaw, camera_yaw) if tracking else 0.0
	var tilt: float = camera_pitch - last_pitch if tracking else 0.0
	last_yaw = camera_yaw
	last_pitch = camera_pitch
	tracking = true
	if holding and not was_holding and stroke_age >= FOLLOW_THROUGH_TIME:
		sweep = 0.0
	was_holding = holding
	if blocking:
		sweep = 0.0
		stroke_age = FOLLOW_THROUGH_TIME
		drive_age = DRIVE_TIME
		stroke_live = false
	var driving: bool = holding and not blocking and absf(turn) < 1.2 and absf(tilt) < 1.2 and absf(turn) + absf(tilt) > 0.00001
	# A live cut sweeps in the view's frame: the same drag that turns the camera also carries
	# the blade and body along, so the swing still reads as half a turn on screen.
	if stroke_live and not blocking and absf(turn) < 1.2:
		var absorbed: float = clampf(turn, -carry_left, carry_left)
		carry += absorbed
		carry_left -= absf(absorbed)
	var start_anchor: Vector3 = anchor
	var start_ground: float = ground
	var remaining: float = duration
	while remaining > 0.000001:
		var dt: float = minf(remaining, 1.0 / 120.0)
		remaining -= dt
		anchor = start_anchor.lerp(origin, (duration - remaining) / duration)
		ground = lerpf(start_ground, floor_y, (duration - remaining) / duration)
		var previous_tip: Vector3 = tip
		stroke_age = minf(stroke_age + dt, FOLLOW_THROUGH_TIME)
		var engaged: bool = holding or attacking or blocking
		raised = move_toward(raised, 1.0 if engaged else 0.0, dt * (7.0 if engaged else 2.5))
		if driving:
			if planted:
				sweep = 0.0
			# Mouse steering is a nudge, not a launch: while a cut's torque is still building,
			# the hands cannot yet whip the heavy blade, so the drag cannot skip the wind-up.
			var fraction: float = dt / duration * drive_ramp()
			heading_speed += turn * follow_spring * 0.08 * fraction
			elevation_speed += (tilt * lift_gain * 2.0 + absf(turn) * lift_gain * 0.5) * fraction
			if elevation_speed > 0.0 or absf(heading_speed) > 0.01:
				planted = false
		if blocking:
			planted = false
			# Bracing has its own damped target; it never changes the next cut's origin.
			heading_speed += (angle_difference(heading, camera_yaw + 0.35) * 60.0 - heading_speed * 16.0) * dt
			elevation_speed += ((0.85 - elevation) * 80.0 - elevation_speed * 18.0) * dt
		else:
			drive(dt)
			elevation_speed -= gravity / BLADE * 2.4 * maxf(0.7, cos(elevation)) * dt
			heading_speed *= exp(-(0.4 + air_damping + (follow_damping * 0.2 if driving else 0.0)) * dt)
			elevation_speed *= exp(-(0.6 + air_damping) * dt)
		heading_speed = clampf(heading_speed, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
		elevation_speed = clampf(elevation_speed, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
		if not planted:
			var travel: float = heading_speed * dt
			if not blocking:
				# Brake only outward travel near the end of the arc. Never reverse it toward the view.
				if signf(heading_speed) == signf(sweep):
					var room: float = maxf(0.0, MAX_SWEEP - absf(sweep))
					heading_speed = signf(heading_speed) * minf(absf(heading_speed), room * 14.0)
				travel = clampf(heading_speed * dt, -MAX_SWEEP - sweep, MAX_SWEEP - sweep)
				sweep += travel
			heading = wrapf(heading + travel, -PI, PI)
			if stroke_live and not blocking and carry != 0.0:
				# Bounded and ramped with the cut's torque, so the heavy wind-up is never skipped.
				var limit: float = CARRY_SPEED * (0.3 + 0.7 * drive_ramp()) * dt
				var caught: float = clampf(carry, -limit, limit)
				carry -= caught
				heading = wrapf(heading + caught, -PI, PI)
				body_yaw = wrapf(body_yaw + caught, -PI, PI)
			elevation += elevation_speed * dt
			if elevation > MAX_ELEVATION:
				elevation = MAX_ELEVATION
				elevation_speed = minf(elevation_speed, 0.0)
		update_body(dt, camera_yaw if blocking else heading, engaged)
		if planted and not blocking:
			place_planted()
		else:
			stretch = move_toward(stretch, 0.0, dt * 4.0)
			place_blade()
			# A rising cut leaves the floor; it only lands once its torque is spent or it chops down.
			if tip.y <= ground + TIP_RADIUS and elevation_speed <= 0.0 and (drive_age >= DRIVE_TIME or drive_lift < 0.0):
				elevation = rest_elevation()
				elevation_speed = 0.0
				stroke_live = false
				heading_speed *= exp(-(anchor_friction + drag_friction) * dt)
				place_blade()
				if absf(heading_speed) * BLADE < ANCHOR_HOLD_SPEED:
					planted = true
					heading_speed = 0.0
		# Contact velocity is measured, but NEVER fed back into heading/elevation or body pull.
		tip_velocity = ((tip - previous_tip) / dt).limit_length(MAX_TIP_SPEED)
		update_follow_through(dt, attacking, blocking, velocity)

func drive_ramp() -> float:
	return clampf(drive_age / DRIVE_TIME, 0.0, 1.0)

func drive(dt: float) -> void:
	# The cut's torque rises from a third of its peak to full, then stops: the blade gathers
	# speed through the first part of the arc and carries the rest on its own momentum. The
	# pickup leads slightly, so the blade clears the floor before the sweep gathers speed.
	if drive_age >= DRIVE_TIME:
		return
	var ramp: float = 0.3 + 0.7 * drive_ramp()
	drive_age = minf(drive_age + dt, DRIVE_TIME)
	heading_speed += drive_turn * ramp * dt
	elevation_speed += drive_lift * (1.3 - 0.6 * ramp) * dt

func update_body(dt: float, target: float, engaged: bool) -> void:
	var stiffness: float = body_stiffness if engaged else 48.0
	var error: float = angle_difference(body_yaw, target)
	body_yaw_speed += (error * stiffness - body_yaw_speed * 2.0 * sqrt(stiffness)) * dt
	body_yaw_speed = clampf(body_yaw_speed, -minf(body_top_speed, 6.0), minf(body_top_speed, 6.0))
	var travel: float = body_yaw_speed * dt
	if signf(travel) == signf(error) and absf(travel) > absf(error):
		travel = error
		body_yaw_speed = 0.0
	body_yaw = wrapf(body_yaw + travel, -PI, PI)

func place_planted() -> void:
	# Preserve the world-space landing while the arms can reach it. Walking beyond reach drags
	# it along the floor; this geometric correction cannot create angular momentum.
	var floor_level: float = ground + TIP_RADIUS
	var height: float = anchor.y + rest_height
	var drop: float = height - floor_level
	var horizontal: float = sqrt(maxf(0.0, BLADE * BLADE - drop * drop))
	var toward_body: Vector3 = anchor - tip
	toward_body.y = 0.0
	if toward_body.length_squared() < 0.000001:
		toward_body = Vector3.BACK.rotated(Vector3.UP, heading)
	# The hilt sits on the line from the hips to the tip. Walking onto the blade would put it
	# behind the hips, through the body, so the hands keep it MIN_REACH ahead and push the tip on.
	var ahead: float = maxf(toward_body.length() - horizontal, MIN_REACH)
	stretch = clampf((ahead - rest_reach) / maxf(0.01, max_reach - rest_reach), 0.0, 1.0)
	var hold: Vector3 = -toward_body.normalized() * minf(ahead, max_reach)
	hilt = anchor + Vector3(hold.x, rest_height, hold.z)
	# Along the hips-to-tip line, so a tip the body has walked onto is pushed ahead, never flipped behind.
	var flat: Vector3 = -toward_body.normalized()
	tip = hilt + flat * horizontal
	tip.y = floor_level
	heading = atan2(-flat.x, -flat.z)
	elevation = rest_elevation()
	elevation_speed = 0.0
	heading_speed = 0.0

func update_follow_through(dt: float, attacking: bool, blocking: bool, velocity: Vector3) -> void:
	# One short pull in the launch direction, never a constantly rotating tip-velocity chase.
	var pulse: float = sin(PI * stroke_age / FOLLOW_THROUGH_TIME)
	var wanted: Vector3 = stroke_pull * pulse * minf(MAX_PULL, pull_gain * 18.0) if attacking and not blocking else Vector3.ZERO
	if planted and stretch > 0.0 and not blocking:
		var toward: Vector3 = tip - anchor
		toward.y = 0.0
		if velocity.dot(toward.normalized()) < -0.3:
			wanted += toward.normalized() * resist_pull * stretch
	pull_velocity = pull_velocity.lerp(wanted.limit_length(MAX_PULL), 1.0 - exp(-dt * 12.0))
	var local_pull: Vector3 = pull_velocity.rotated(Vector3.UP, -body_yaw)
	var lean_target: Vector2 = Vector2(-local_pull.z * 0.12, -local_pull.x * 0.16)
	lean_target.x += stretch * 0.3 + (0.16 if elevation_speed < -1.0 else -0.08) * raised
	lean_target.y += clampf(heading_speed * 0.025, -0.22, 0.22)
	lean_speed += ((lean_target - lean) * 60.0 - lean_speed * 16.0) * dt
	lean += lean_speed * dt
