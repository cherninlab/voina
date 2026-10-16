class_name HeavySwordMotion
extends RefCounted

# The longsword is a separate physical object: its tip is a point mass on a rigid rod from the
# hilt, pulled by gravity, and it anchors in the ground wherever it lands. The tip is integrated
# position-based (its velocity is whatever the constraints let it do), so swinging the hilt
# around the body lifts the blade by centrifugal force like a real pendulum. The hands only add
# torque toward the body's facing while swinging; the body turns to face the blade when idle.
# Cosmetic only: no damage or combat authority lives here.
const BLADE: float = 1.65
const TIP_RADIUS: float = 0.03
const MAX_PULL: float = 1.8
const MAX_TIP_SPEED: float = 30.0
const MAX_BEARING: float = 2.95 # radians from forward; past this the body is in the way
const HOLD_BEARING: float = 1.9 # the hands stay beside or ahead of the hips
const ANCHOR_HOLD_SPEED: float = 0.6 # below this a resting tip sticks

# Tunables: the in-game Sword tweaks panel edits these live; tests use the defaults.
static var gravity: float = 9.8
static var follow_spring: float = 60.0 # hands' torque pulling the blade after the body's facing while swinging
static var follow_damping: float = 1.5
static var body_stiffness: float = 160.0 # how hard the body chases the camera while swinging
static var body_top_speed: float = 14.0 # rad/s cap on the body's turn while swinging
static var strike_turn: float = 8.0 # rad/s kick to the body's turn from the approved cut
static var air_damping: float = 0.3
static var lift_gain: float = 3.0 # tip m/s per radian of camera pitch while dragging
static var drag_friction: float = 3.0 # tip sliding on the floor while swinging
static var anchor_friction: float = 14.0 # tip sliding on the floor with the hands at rest
static var rest_reach: float = 0.3 # nominal hilt distance ahead of the hips
static var max_reach: float = 0.44 # arms plus lean reach this far before the anchor breaks
static var rest_height: float = 0.12
static var raised_height: float = 0.36
static var resist_pull: float = 1.0 # m/s the owner is pulled toward a stretched anchored blade
static var pull_gain: float = 0.1 # owner follow-through per m/s of tip speed while attacking

static func tunable_specs() -> Array[Dictionary]:
	return [
		{"name": "follow_spring", "label": "Hands torque", "min": 0.0, "max": 200.0, "default": 60.0},
		{"name": "follow_damping", "label": "Hands damping", "min": 0.0, "max": 10.0, "default": 1.5},
		{"name": "body_stiffness", "label": "Body chase", "min": 10.0, "max": 400.0, "default": 160.0},
		{"name": "body_top_speed", "label": "Body turn cap", "min": 2.0, "max": 30.0, "default": 14.0},
		{"name": "strike_turn", "label": "Cut kick", "min": 0.0, "max": 20.0, "default": 8.0},
		{"name": "air_damping", "label": "Air damping", "min": 0.0, "max": 3.0, "default": 0.3},
		{"name": "gravity", "label": "Gravity", "min": 1.0, "max": 30.0, "default": 9.8},
		{"name": "lift_gain", "label": "Mouse lift", "min": 0.0, "max": 12.0, "default": 3.0},
		{"name": "drag_friction", "label": "Floor drag", "min": 0.0, "max": 20.0, "default": 3.0},
		{"name": "anchor_friction", "label": "Floor anchor", "min": 0.0, "max": 40.0, "default": 14.0},
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
var anchor: Vector3 = Vector3.ZERO # body center, world space
var ground: float = -0.9 # floor height under the player, world space
var body_yaw: float = 0.0
var body_yaw_speed: float = 0.0
var lean: Vector2 = Vector2.ZERO
var lean_speed: Vector2 = Vector2.ZERO
var pull_velocity: Vector3 = Vector3.ZERO
var raised: float = 0.0
var stretch: float = 0.0 # 0..1 how far the arms reach toward an anchored blade
var last_yaw: float = 0.0
var last_pitch: float = 0.0
var tracking: bool = false
var initialized: bool = false

func reset(camera_yaw: float, origin: Vector3 = anchor, floor_y: float = ground) -> void:
	anchor = origin
	ground = floor_y
	body_yaw = camera_yaw
	body_yaw_speed = 0.0
	lean = Vector2.ZERO
	lean_speed = Vector2.ZERO
	pull_velocity = Vector3.ZERO
	raised = 0.0
	stretch = 0.0
	tip_velocity = Vector3.ZERO
	tracking = false
	initialized = true
	# Rest: the blade stands ahead of the body with its tip in the ground.
	var elevation: float = clampf((ground + TIP_RADIUS - anchor.y - rest_height) / BLADE, -0.95, 0.0)
	var direction: Vector3 = direction_from(0.0, elevation)
	hilt = anchor + hilt_offset(direction)
	tip = hilt + direction * BLADE

func direction_from(bearing: float, elevation: float) -> Vector3:
	# Body-relative bearing (0 forward, positive left) and vertical component, as a world direction.
	var flat: float = sqrt(maxf(0.0, 1.0 - elevation * elevation))
	return Vector3(-sin(bearing) * flat, elevation, -cos(bearing) * flat).rotated(Vector3.UP, body_yaw)

func blade_direction() -> Vector3:
	var rod: Vector3 = tip - hilt
	return rod.normalized() if rod.length_squared() > 0.000001 else Vector3.DOWN

func blade_yaw() -> float:
	var direction: Vector3 = blade_direction()
	return atan2(-direction.x, -direction.z)

func bearing() -> float:
	return wrapf(blade_yaw() - body_yaw, -PI, PI)

func grounded() -> bool:
	return tip.y <= ground + TIP_RADIUS + 0.01

func hilt_offset(direction: Vector3) -> Vector3:
	# Where the hands hold the hilt for a blade direction: ahead of or beside the hips, rising
	# with the blade and reaching further when the arms stretch toward an anchored tip.
	var local: Vector3 = direction.rotated(Vector3.UP, -body_yaw)
	var hold: float = clampf(atan2(-local.x, -local.z), -HOLD_BEARING, HOLD_BEARING)
	var reach: float = lerpf(rest_reach, max_reach, stretch)
	var height: float = lerpf(rest_height, raised_height, clampf((local.y + 0.6) / 0.9, 0.0, 1.0))
	return Vector3(-sin(hold) * reach, height, -cos(hold) * reach).rotated(Vector3.UP, body_yaw)

func strike(direction: Vector2) -> void:
	# The host-approved cut kicks the body into the turn; the blade follows it. Vertical cuts lift the tip.
	if not direction.is_finite():
		return
	body_yaw_speed = clampf(body_yaw_speed - direction.x * strike_turn, -body_top_speed, body_top_speed)
	tip_velocity += Vector3.UP * (-direction.y * lift_gain * 1.5)
	tip_velocity = tip_velocity.limit_length(MAX_TIP_SPEED)

func step(delta: float, camera_yaw: float, camera_pitch: float, holding: bool, attacking: bool, blocking: bool = false, origin: Vector3 = anchor, floor_y: float = ground, velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_finite(camera_yaw) or not is_finite(camera_pitch) or not is_finite(delta) or delta <= 0.0 or not origin.is_finite() or not is_finite(floor_y) or not velocity.is_finite():
		return
	anchor = origin
	ground = floor_y
	if not initialized:
		reset(camera_yaw, origin, floor_y)
	var turn: float = angle_difference(last_yaw, camera_yaw) if tracking else 0.0
	var tilt: float = camera_pitch - last_pitch if tracking else 0.0
	last_yaw = camera_yaw
	last_pitch = camera_pitch
	tracking = true
	# Dragging: vertical look motion while holding lifts or drops the tip a little. A quick turn is not a drag.
	if holding and not blocking and absf(turn) < 1.2 and absf(tilt) < 1.2:
		tip_velocity += Vector3.UP * tilt * BLADE * lift_gain
	var engaged: bool = holding or attacking or blocking
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var remaining: float = minf(delta, 0.1)
	# Substeps keep the pendulum and springs stable at low frame rates.
	while remaining > 0.000001:
		var dt: float = minf(remaining, 1.0 / 120.0)
		remaining -= dt
		raised = move_toward(raised, 1.0 if engaged else 0.0, dt * (7.0 if engaged else 2.5))
		# Swinging: the body follows the camera and the blade trails the body. Idle: the body always
		# faces the blade, even while walking, so walking away from it is walking backwards.
		var body_target: float = camera_yaw if engaged else blade_yaw()
		body_yaw_speed += (angle_difference(body_yaw, body_target) * (body_stiffness if engaged else 48.0) - body_yaw_speed * 11.0) * dt
		var top_speed: float = body_top_speed if engaged else 5.0
		body_yaw_speed = clampf(body_yaw_speed, -top_speed, top_speed)
		body_yaw = wrapf(body_yaw + body_yaw_speed * dt, -PI, PI)
		var anchored: bool = grounded() and not engaged
		hilt = anchor + hilt_offset(blade_direction())
		if anchored:
			reach_anchor()
		else:
			stretch = move_toward(stretch, 0.0, dt * 4.0)
		if engaged and not blocking:
			# The hands torque the blade after the body's facing at its current height; the rod does the lifting.
			var ahead: Vector3 = hilt + direction_from(0.0, clampf(blade_direction().y, -0.95, 0.95)) * BLADE
			tip_velocity += ((ahead - tip) * follow_spring - tip_velocity * follow_damping) * dt
		if blocking:
			# Bracing is the one time the arms hold the blade up, through a strong but finite spring,
			# toward the camera so the guard faces the attacker.
			var guard_direction: Vector3 = Vector3(0.0, 0.75, -0.66).rotated(Vector3.UP, camera_yaw + 0.35)
			var guard: Vector3 = hilt + guard_direction.normalized() * BLADE
			tip_velocity += ((guard - tip) * 60.0 - tip_velocity * 12.0) * dt
		tip_velocity.y -= gravity * dt
		tip_velocity *= exp(-air_damping * dt)
		tip_velocity = tip_velocity.limit_length(MAX_TIP_SPEED)
		var previous: Vector3 = tip
		tip += tip_velocity * dt
		block_body()
		var floor_level: float = ground + TIP_RADIUS
		tip.y = maxf(tip.y, floor_level)
		var along: Vector3 = blade_direction()
		if tip.y <= floor_level + 0.001 and hilt.y - floor_level < BLADE and not lifts_off(floor_level):
			# A tip on the floor keeps the rod length by sliding, not by lifting off the ground.
			var drop: float = hilt.y - floor_level
			var flat_rod: Vector3 = Vector3(tip.x - hilt.x, 0.0, tip.z - hilt.z)
			if flat_rod.length_squared() < 0.000001:
				flat_rod = Vector3.FORWARD.rotated(Vector3.UP, body_yaw)
			tip = hilt + flat_rod.normalized() * sqrt(maxf(0.0, BLADE * BLADE - drop * drop)) + Vector3.DOWN * drop
		else:
			tip = hilt + along * BLADE
		# Position-based velocity: whatever the rod, floor and body let the tip do is its momentum,
		# including the centrifugal rise when the hilt is swung around the body.
		tip_velocity = ((tip - previous) / dt).limit_length(MAX_TIP_SPEED)
		if tip.y <= floor_level + 0.001:
			var slide: float = exp(-(drag_friction if engaged else anchor_friction) * dt)
			tip_velocity.x *= slide
			tip_velocity.z *= slide
			if not engaged and Vector2(tip_velocity.x, tip_velocity.z).length() < ANCHOR_HOLD_SPEED:
				tip_velocity.x = 0.0
				tip_velocity.z = 0.0
		# Follow-through and lean come from the blade's momentum; a stretched anchor pulls the owner back.
		var flat: Vector3 = Vector3(tip_velocity.x, 0.0, tip_velocity.z)
		var wanted_pull: Vector3 = (flat * pull_gain).limit_length(MAX_PULL) if attacking and not blocking else Vector3.ZERO
		if anchored and stretch > 0.0 and speed > 0.3:
			var toward: Vector3 = tip - anchor
			toward.y = 0.0
			wanted_pull += toward.normalized() * resist_pull * stretch
		pull_velocity = pull_velocity.lerp(wanted_pull.limit_length(MAX_PULL), 1.0 - exp(-dt * (5.0 if attacking else 4.0)))
		var local_pull: Vector3 = pull_velocity.rotated(Vector3.UP, -body_yaw)
		var lean_target: Vector2 = Vector2(-local_pull.z * 0.09, -local_pull.x * 0.12)
		lean_target.x += raised * 0.06 + stretch * 0.35
		lean_speed += ((lean_target - lean) * 40.0 - lean_speed * 10.0) * dt
		lean += lean_speed * dt

func lifts_off(floor_level: float) -> bool:
	# A grounded tip swung around the hilt leaves the floor once the centripetal demand, through
	# the rod's incline, exceeds gravity: v_t^2 / R * tan(incline) > g.
	var flat_rod: Vector3 = Vector3(tip.x - hilt.x, 0.0, tip.z - hilt.z)
	var radius: float = flat_rod.length()
	if radius < 0.05:
		return false
	var flat_velocity: Vector3 = Vector3(tip_velocity.x, 0.0, tip_velocity.z)
	var tangential: float = (flat_velocity - flat_rod / radius * flat_velocity.dot(flat_rod / radius)).length()
	var incline: float = (hilt.y - floor_level) / radius
	return tangential * tangential / radius * incline > gravity

func reach_anchor() -> void:
	# A grounded blade stays put. Beyond the rest reach the hands are placed on the rod sphere
	# around the tip, on the line toward the hips, so the tip does not move; past the longest
	# reach the rod projection drags the tip along the floor instead.
	# Hands stay at hip height while reaching; a higher hilt would shorten the reach and feed back.
	var height: float = anchor.y + hilt_offset(blade_direction()).y
	var drop: float = height - tip.y
	var horizontal: float = sqrt(maxf(0.0, BLADE * BLADE - drop * drop))
	var to_body: Vector3 = anchor - tip
	to_body.y = 0.0
	if to_body.length_squared() < 0.000001:
		to_body = Vector3.BACK.rotated(Vector3.UP, body_yaw)
	var offset: Vector3 = tip + to_body.normalized() * horizontal - anchor
	offset.y = 0.0
	if offset.length() <= rest_reach:
		# Close enough for the nominal grip; a body walking into the blade pushes it along.
		stretch = move_toward(stretch, 0.0, 0.05)
		return
	stretch = clampf((offset.length() - rest_reach) / maxf(0.01, max_reach - rest_reach), 0.0, 1.0)
	var local: Vector3 = offset.rotated(Vector3.UP, -body_yaw)
	var hold: float = clampf(atan2(-local.x, -local.z), -HOLD_BEARING, HOLD_BEARING)
	var reach: float = minf(offset.length(), max_reach)
	hilt = anchor + Vector3(-sin(hold) * reach, height - anchor.y, -cos(hold) * reach).rotated(Vector3.UP, body_yaw)

func block_body() -> void:
	# Keep the blade from sweeping through the back: stop it beside the body instead.
	var rod: Vector3 = tip - hilt
	var local: Vector3 = rod.rotated(Vector3.UP, -body_yaw)
	var side: float = atan2(-local.x, -local.z)
	if absf(side) <= MAX_BEARING:
		return
	var limit: float = MAX_BEARING * signf(side)
	tip = hilt + local.rotated(Vector3.UP, limit - side).rotated(Vector3.UP, body_yaw)
