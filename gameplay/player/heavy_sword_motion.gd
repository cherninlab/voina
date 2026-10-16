class_name HeavySwordMotion
extends RefCounted

# A dragged pendulum: the blade tip is a point mass on a rigid rod from the hilt. Gravity and
# ground friction act every frame; the hands only add momentum while dragging and cannot hold
# the blade up. The body blocks the blade from passing behind the back, so a swing carries it
# around the front and leaves it resting on the other side. Cosmetic only: no damage or combat
# authority lives here.
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
const GROUND_FRICTION: float = 3.5
const REST_HEIGHT: float = 0.12
const RAISED_HEIGHT: float = 0.36

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
	tip_velocity = Vector3.ZERO
	tracking = false
	initialized = true
	# Rest: the blade trails behind the right hip with its tip on the ground.
	var elevation: float = clampf((ground + TIP_RADIUS - anchor.y - REST_HEIGHT) / BLADE, -0.95, 0.0)
	var direction: Vector3 = direction_from(-MAX_BEARING + 0.05, elevation)
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

func hilt_offset(direction: Vector3) -> Vector3:
	# Where the hands hold the hilt for a blade direction: beside or ahead of the hips, rising with the blade.
	var local: Vector3 = direction.rotated(Vector3.UP, -body_yaw)
	var hold: float = clampf(atan2(-local.x, -local.z), -HOLD_BEARING, HOLD_BEARING)
	var reach: float = lerpf(0.28, 0.38, raised)
	var height: float = lerpf(REST_HEIGHT, RAISED_HEIGHT, clampf((local.y + 0.6) / 0.9, 0.0, 1.0))
	return Vector3(-sin(hold) * reach, height, -cos(hold) * reach).rotated(Vector3.UP, body_yaw)

func strike(direction: Vector2) -> void:
	# The host-approved cut adds one bounded impulse; horizontal cuts lift a little so they clear the floor.
	if not direction.is_finite():
		return
	var tangent: Vector3 = Vector3.UP.cross(tip - hilt).normalized()
	tip_velocity += tangent * (-direction.x * STRIKE_SPEED)
	tip_velocity += Vector3.UP * (-direction.y * STRIKE_LIFT + absf(direction.x) * STRIKE_LIFT * 0.5)
	tip_velocity = tip_velocity.limit_length(MAX_TIP_SPEED)

func can_swing(direction: Vector2) -> bool:
	# A blade resting against the body on one side can only be dragged toward the front.
	var side: float = bearing()
	if absf(side) < HOLD_BEARING or absf(direction.x) < 0.5:
		return true
	return signf(-direction.x) != signf(side)

func step(delta: float, camera_yaw: float, camera_pitch: float, holding: bool, attacking: bool, blocking: bool = false, origin: Vector3 = anchor, floor_y: float = ground) -> void:
	if not is_finite(camera_yaw) or not is_finite(camera_pitch) or not is_finite(delta) or delta <= 0.0 or not origin.is_finite() or not is_finite(floor_y):
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
	var remaining: float = minf(delta, 0.1)
	# Substeps keep the pendulum and springs stable at low frame rates.
	while remaining > 0.000001:
		var dt: float = minf(remaining, 1.0 / 120.0)
		remaining -= dt
		raised = move_toward(raised, 1.0 if engaged else 0.0, dt * (7.0 if engaged else 2.5))
		# The torso follows the weapon with a slower spring rather than snapping to the camera.
		var weapon_twist: float = clampf(angle_difference(camera_yaw, blade_yaw()), -0.85, 0.85) * raised
		var body_target: float = camera_yaw + weapon_twist * 0.7
		body_yaw_speed += (angle_difference(body_yaw, body_target) * 48.0 - body_yaw_speed * 11.0) * dt
		body_yaw_speed = clampf(body_yaw_speed, -5.0, 5.0)
		body_yaw = wrapf(body_yaw + body_yaw_speed * dt, -PI, PI)
		hilt = anchor + hilt_offset(blade_direction())
		if blocking:
			# Bracing is the one time the arms hold the blade up, through a strong but finite spring.
			var guard: Vector3 = hilt + direction_from(0.35, 0.75) * BLADE
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
			var slide: float = exp(-GROUND_FRICTION * dt)
			tip_velocity.x *= slide
			tip_velocity.z *= slide
		var along: Vector3 = blade_direction()
		tip = hilt + along * BLADE
		tip_velocity -= along * tip_velocity.dot(along)
		# Follow-through and lean come from the blade's horizontal momentum.
		var flat: Vector3 = Vector3(tip_velocity.x, 0.0, tip_velocity.z)
		var wanted_pull: Vector3 = (flat * 0.1).limit_length(MAX_PULL) if attacking and not blocking else Vector3.ZERO
		pull_velocity = pull_velocity.lerp(wanted_pull, 1.0 - exp(-dt * (5.0 if attacking else 4.0)))
		var local_pull: Vector3 = pull_velocity.rotated(Vector3.UP, -body_yaw)
		var lean_target: Vector2 = Vector2(-local_pull.z * 0.09, -local_pull.x * 0.12)
		lean_target.x += raised * 0.06
		lean_speed += ((lean_target - lean) * 40.0 - lean_speed * 10.0) * dt
		lean += lean_speed * dt

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
