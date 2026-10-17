class_name HeavySwordMotion
extends RefCounted

# Stylized angular inertia, independent of hand/body constraint corrections. The blade has
# a heading and elevation with bounded speeds; the body follows, but cannot feed energy back
# into the weapon. Exported world-space tip velocity is for contact, never solver input.
# Combat authorization stays with the host.
const BLADE: float = 1.65
const TIP_RADIUS: float = 0.03
const MAX_PULL: float = 1.8
const MAX_TIP_SPEED: float = 30.0
const MAX_SWEEP: float = 2.45 # one gesture can sweep broadly, never orbit the character
const MAX_ELEVATION: float = 0.95 # clear overhead lift without the vertical heading singularity
const MAX_ANGULAR_SPEED: float = 12.0
const FOLLOW_THROUGH_TIME: float = 0.45
const HOLD_BEARING: float = 1.9 # the hands stay beside or ahead of the hips
const ANCHOR_HOLD_SPEED: float = 0.6 # below this a resting tip sticks

# Tunables: the in-game Sword tweaks panel edits these live; tests use the defaults.
static var gravity: float = 9.8
static var follow_spring: float = 60.0 # gesture impulse gain; never a spring toward the camera
static var follow_damping: float = 1.5
static var body_stiffness: float = 160.0 # how hard the body follows the blade while swinging
static var body_top_speed: float = 14.0 # rad/s cap on the body's turn while swinging
static var strike_turn: float = 8.0 # launch strength from the approved cut
static var air_damping: float = 0.3
static var lift_gain: float = 3.0 # tip m/s per radian of camera pitch while dragging
static var drag_friction: float = 3.0 # angular braking on ground contact
static var anchor_friction: float = 14.0 # braking when the blade lands
static var rest_reach: float = 0.3 # nominal hilt distance ahead of the hips
static var max_reach: float = 0.44 # arms plus lean reach this far before the anchor breaks
static var rest_height: float = 0.12
static var raised_height: float = 0.36
static var resist_pull: float = 1.0 # m/s the owner is pulled toward a stretched anchored blade
static var pull_gain: float = 0.1 # owner follow-through per m/s of tip speed while attacking

static func tunable_specs() -> Array[Dictionary]:
	return [
		{"name": "follow_spring", "label": "Gesture drive", "min": 0.0, "max": 200.0, "default": 60.0},
		{"name": "follow_damping", "label": "Gesture damping", "min": 0.0, "max": 10.0, "default": 1.5},
		{"name": "body_stiffness", "label": "Body follow", "min": 10.0, "max": 400.0, "default": 160.0},
		{"name": "body_top_speed", "label": "Body turn cap", "min": 2.0, "max": 30.0, "default": 14.0},
		{"name": "strike_turn", "label": "Cut kick", "min": 0.0, "max": 20.0, "default": 8.0},
		{"name": "air_damping", "label": "Air damping", "min": 0.0, "max": 3.0, "default": 0.3},
		{"name": "gravity", "label": "Gravity", "min": 1.0, "max": 30.0, "default": 9.8},
		{"name": "lift_gain", "label": "Mouse lift", "min": 0.0, "max": 12.0, "default": 3.0},
		{"name": "drag_friction", "label": "Floor drag", "min": 0.0, "max": 20.0, "default": 3.0},
		{"name": "anchor_friction", "label": "Landing brake", "min": 0.0, "max": 40.0, "default": 14.0},
		{"name": "max_reach", "label": "Max reach", "min": 0.3, "max": 0.8, "default": 0.44},
		{"name": "rest_height", "label": "Hilt rest height", "min": -0.2, "max": 0.5, "default": 0.12},
		{"name": "raised_height", "label": "Hilt raised height", "min": 0.0, "max": 0.8, "default": 0.36},
		{"name": "resist_pull", "label": "Anchor pull-back", "min": 0.0, "max": 4.0, "default": 1.0},
		{"name": "pull_gain", "label": "Swing follow-through", "min": 0.0, "max": 0.5, "default": 0.1},
	]

static func get_tunable(name: String) -> float:
	match name:
		"gravity": return gravity
		"follow_spring": return follow_spring
		"follow_damping": return follow_damping
		"body_stiffness": return body_stiffness
		"body_top_speed": return body_top_speed
		"strike_turn": return strike_turn
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
		"strike_turn": strike_turn = value
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
var sweep_origin: float = 0.0
var planted: bool = true
var was_holding: bool = false
var stroke_age: float = FOLLOW_THROUGH_TIME
var stroke_pull: Vector3 = Vector3.ZERO

func reset(camera_yaw: float, origin: Vector3 = anchor, floor_y: float = ground) -> void:
	anchor = origin
	ground = floor_y
	body_yaw = camera_yaw
	body_yaw_speed = 0.0
	heading = camera_yaw
	sweep_origin = heading
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
	sweep_origin = heading
	# A broad launch plus a pronounced pickup. A down-cut already aloft drives straight down;
	# from the floor it first picks up the blade, instead of burying the impulse in the ground.
	heading_speed = clampf(-cut.x * strike_turn * 1.25, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
	elevation_speed = -9.0 if cut.y > 0.5 and elevation > 0.1 else 8.5 + lift_gain * 0.35 - cut.y
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
		sweep_origin = heading
	was_holding = holding
	if blocking:
		sweep_origin = heading
		stroke_age = FOLLOW_THROUGH_TIME
	var driving: bool = holding and not blocking and absf(turn) < 1.2 and absf(tilt) < 1.2 and absf(turn) + absf(tilt) > 0.00001
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
				sweep_origin = heading
			var fraction: float = dt / duration
			heading_speed += turn * follow_spring * 0.08 * fraction
			elevation_speed += (tilt * lift_gain * 2.0 + absf(turn) * lift_gain * 3.0) * fraction
			if elevation_speed > 0.0 or absf(heading_speed) > 0.01:
				planted = false
		if blocking:
			planted = false
			# Bracing has its own damped target; it never changes the next cut's origin.
			heading_speed += (angle_difference(heading, camera_yaw + 0.35) * 60.0 - heading_speed * 16.0) * dt
			elevation_speed += ((0.85 - elevation) * 80.0 - elevation_speed * 18.0) * dt
		else:
			elevation_speed -= gravity / BLADE * 2.4 * maxf(0.7, cos(elevation)) * dt
			heading_speed *= exp(-(1.1 + air_damping + (follow_damping * 0.2 if driving else 0.0)) * dt)
			elevation_speed *= exp(-(0.6 + air_damping) * dt)
		heading_speed = clampf(heading_speed, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
		elevation_speed = clampf(elevation_speed, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
		if not planted:
			var travel: float = heading_speed * dt
			if not blocking:
				var offset: float = angle_difference(sweep_origin, heading)
				# Brake only outward travel near the end of the arc. Never reverse it toward the view.
				if signf(heading_speed) == signf(offset):
					var room: float = maxf(0.0, MAX_SWEEP - absf(offset))
					heading_speed = signf(heading_speed) * minf(absf(heading_speed), room * 12.0)
				travel = clampf(heading_speed * dt, -MAX_SWEEP - offset, MAX_SWEEP - offset)
			heading = wrapf(heading + travel, -PI, PI)
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
			if tip.y <= ground + TIP_RADIUS and elevation_speed <= 0.0:
				elevation = rest_elevation()
				elevation_speed = 0.0
				heading_speed *= exp(-(anchor_friction + drag_friction) * dt)
				place_blade()
				if absf(heading_speed) * BLADE < ANCHOR_HOLD_SPEED:
					planted = true
					heading_speed = 0.0
		# Contact velocity is measured, but NEVER fed back into heading/elevation or body pull.
		tip_velocity = ((tip - previous_tip) / dt).limit_length(MAX_TIP_SPEED)
		update_follow_through(dt, attacking, blocking, velocity)

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
	var desired: Vector3 = tip + toward_body.normalized() * horizontal - anchor
	desired.y = 0.0
	stretch = clampf((desired.length() - rest_reach) / maxf(0.01, max_reach - rest_reach), 0.0, 1.0)
	var hold: Vector3 = desired.limit_length(max_reach)
	hilt = anchor + Vector3(hold.x, rest_height, hold.z)
	var flat: Vector3 = tip - hilt
	flat.y = 0.0
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD.rotated(Vector3.UP, heading)
	tip = hilt + flat.normalized() * horizontal
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
