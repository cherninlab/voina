class_name HeavySwordMotion
extends RefCounted

# The longsword is a separate physical object: its tip is a point mass on a rigid rod from the
# hilt, pulled by gravity, and it anchors in the ground wherever it lands. The hands only add
# momentum while dragging; the body turns to face the blade and follows its weight. Cosmetic
# only: no damage or combat authority lives here.
const BLADE: float = 1.65
const GRAVITY: float = 9.8
const TIP_RADIUS: float = 0.03
const MAX_PULL: float = 1.8
const MAX_TIP_SPEED: float = 26.0
const MAX_BEARING: float = 2.95 # radians from forward; past this the body is in the way
const HOLD_BEARING: float = 1.9 # the hands stay beside or ahead of the hips
const DRAG_GAIN: float = 7.0 # tip m/s per radian of camera turn while dragging
const LIFT_GAIN: float = 6.0 # tip m/s per radian of camera pitch while dragging
const STRIKE_SPEED: float = 9.0
const STRIKE_LIFT: float = 5.0
const AIR_DAMPING: float = 0.5
const DRAG_FRICTION: float = 3.0 # tip sliding on the floor while dragged
const ANCHOR_FRICTION: float = 14.0 # tip sliding on the floor with the hands at rest
const ANCHOR_HOLD_SPEED: float = 0.6 # below this a resting tip sticks
const REST_HEIGHT: float = 0.12
const RAISED_HEIGHT: float = 0.36
const REST_REACH: float = 0.3 # nominal hilt distance ahead of the hips
const MAX_REACH: float = 0.44 # the arms and a lean can stretch this far before the anchor breaks
const RESIST_PULL: float = 1.0 # m/s the owner is pulled back toward a stretched anchored blade

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
	var elevation: float = clampf((ground + TIP_RADIUS - anchor.y - REST_HEIGHT) / BLADE, -0.95, 0.0)
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
	var reach: float = lerpf(REST_REACH, MAX_REACH, stretch)
	var height: float = lerpf(REST_HEIGHT, RAISED_HEIGHT, clampf((local.y + 0.6) / 0.9, 0.0, 1.0))
	return Vector3(-sin(hold) * reach, height, -cos(hold) * reach).rotated(Vector3.UP, body_yaw)

func strike(direction: Vector2) -> void:
	# The host-approved cut adds one bounded impulse along the drag; horizontal cuts lift a little.
	if not direction.is_finite():
		return
	var tangent: Vector3 = Vector3.UP.cross(tip - hilt).normalized()
	tip_velocity += tangent * (-direction.x * STRIKE_SPEED)
	tip_velocity += Vector3.UP * (-direction.y * STRIKE_LIFT + absf(direction.x) * STRIKE_LIFT * 0.5)
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
	# Dragging: look motion while holding throws the tip. A quick turn is not a drag.
	if holding and not blocking and absf(turn) < 1.2 and absf(tilt) < 1.2:
		tip_velocity += Vector3.UP.cross(tip - hilt) * turn * DRAG_GAIN + Vector3.UP * tilt * BLADE * LIFT_GAIN
	var engaged: bool = holding or attacking or blocking
	var flat_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = flat_velocity.length()
	var remaining: float = minf(delta, 0.1)
	# Substeps keep the pendulum and springs stable at low frame rates.
	while remaining > 0.000001:
		var dt: float = minf(remaining, 1.0 / 120.0)
		remaining -= dt
		raised = move_toward(raised, 1.0 if engaged else 0.0, dt * (7.0 if engaged else 2.5))
		# The body faces the blade; walking with the blade at rest turns it toward the travel direction.
		var body_target: float = blade_yaw()
		if not engaged and speed > 0.5:
			body_target = lerp_angle(body_target, atan2(-flat_velocity.x, -flat_velocity.z), clampf((speed - 0.5) / 2.0, 0.0, 1.0))
		body_yaw_speed += (angle_difference(body_yaw, body_target) * 48.0 - body_yaw_speed * 11.0) * dt
		body_yaw_speed = clampf(body_yaw_speed, -5.0, 5.0)
		body_yaw = wrapf(body_yaw + body_yaw_speed * dt, -PI, PI)
		var anchored: bool = grounded() and not holding and not blocking
		hilt = anchor + hilt_offset(blade_direction())
		if anchored:
			reach_anchor()
		else:
			stretch = move_toward(stretch, 0.0, dt * 4.0)
		if blocking:
			# Bracing is the one time the arms hold the blade up, through a strong but finite spring,
			# toward the camera so the guard faces the attacker.
			var guard_direction: Vector3 = Vector3(0.0, 0.75, -0.66).rotated(Vector3.UP, camera_yaw + 0.35)
			var guard: Vector3 = hilt + guard_direction.normalized() * BLADE
			tip_velocity += ((guard - tip) * 60.0 - tip_velocity * 12.0) * dt
		tip_velocity.y -= GRAVITY * dt
		tip_velocity *= exp(-AIR_DAMPING * dt)
		tip_velocity = tip_velocity.limit_length(MAX_TIP_SPEED)
		tip += tip_velocity * dt
		block_body()
		var floor_level: float = ground + TIP_RADIUS
		if tip.y <= floor_level:
			tip.y = floor_level
			tip_velocity.y = maxf(tip_velocity.y, 0.0)
			var slide: float = exp(-(DRAG_FRICTION if holding else ANCHOR_FRICTION) * dt)
			tip_velocity.x *= slide
			tip_velocity.z *= slide
			if not holding and Vector2(tip_velocity.x, tip_velocity.z).length() < ANCHOR_HOLD_SPEED:
				tip_velocity.x = 0.0
				tip_velocity.z = 0.0
		var along: Vector3 = blade_direction()
		if tip.y <= floor_level + 0.001 and hilt.y - floor_level < BLADE:
			# A tip on the floor keeps the rod length by sliding, not by lifting off the ground.
			var drop: float = hilt.y - floor_level
			var flat_rod: Vector3 = Vector3(tip.x - hilt.x, 0.0, tip.z - hilt.z)
			if flat_rod.length_squared() < 0.000001:
				flat_rod = Vector3.FORWARD.rotated(Vector3.UP, body_yaw)
			tip = hilt + flat_rod.normalized() * sqrt(maxf(0.0, BLADE * BLADE - drop * drop)) + Vector3.DOWN * drop
			along = blade_direction()
		else:
			tip = hilt + along * BLADE
		tip_velocity -= along * tip_velocity.dot(along)
		# Follow-through and lean come from the blade's momentum; a stretched anchor pulls the owner back.
		var flat: Vector3 = Vector3(tip_velocity.x, 0.0, tip_velocity.z)
		var wanted_pull: Vector3 = (flat * 0.1).limit_length(MAX_PULL) if attacking and not blocking else Vector3.ZERO
		if anchored and stretch > 0.0 and speed > 0.3:
			var toward: Vector3 = tip - anchor
			toward.y = 0.0
			wanted_pull += toward.normalized() * RESIST_PULL * stretch
		pull_velocity = pull_velocity.lerp(wanted_pull.limit_length(MAX_PULL), 1.0 - exp(-dt * (5.0 if attacking else 4.0)))
		var local_pull: Vector3 = pull_velocity.rotated(Vector3.UP, -body_yaw)
		var lean_target: Vector2 = Vector2(-local_pull.z * 0.09, -local_pull.x * 0.12)
		lean_target.x += raised * 0.06 + stretch * 0.35
		lean_speed += ((lean_target - lean) * 40.0 - lean_speed * 10.0) * dt
		lean += lean_speed * dt

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
	if offset.length() <= REST_REACH:
		# Close enough for the nominal grip; a body walking into the blade pushes it along.
		stretch = move_toward(stretch, 0.0, 0.05)
		return
	stretch = clampf((offset.length() - REST_REACH) / (MAX_REACH - REST_REACH), 0.0, 1.0)
	var local: Vector3 = offset.rotated(Vector3.UP, -body_yaw)
	var hold: float = clampf(atan2(-local.x, -local.z), -HOLD_BEARING, HOLD_BEARING)
	var reach: float = minf(offset.length(), MAX_REACH)
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
	var tangent: Vector3 = Vector3.UP.cross(rod).normalized()
	if tip_velocity.dot(tangent) * signf(side) > 0.0:
		tip_velocity -= tangent * tip_velocity.dot(tangent)
