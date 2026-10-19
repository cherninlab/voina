class_name SwingCamera
extends RefCounted
## Owner-only view sway from the sword. The blade's own angular speed (the cut's torque, not
## mouse look) sets a small target turn, bank and nod; a soft, slightly underdamped spring
## chases it, so the view leans into a cut a beat late and settles back once the blade lands.

const MAX_YAW: float = 0.05 # rad of view turn toward the blade at full cut speed
const MAX_ROLL: float = 0.07 # rad of bank into the cut
const MAX_PITCH: float = 0.03 # rad of nod with the blade's lift or chop
const STIFFNESS: float = 90.0
const DAMPING: float = 11.0 # about 0.6 of critical: a small overshoot on the way back

var offset: Vector3 = Vector3.ZERO # pitch, yaw, roll in radians, for Camera3D.rotation
var speed: Vector3 = Vector3.ZERO

func reset() -> void:
	offset = Vector3.ZERO
	speed = Vector3.ZERO

func target(heading_speed: float, elevation_speed: float) -> Vector3:
	var turn: float = clampf(heading_speed / HeavySwordMotion.MAX_ANGULAR_SPEED, -1.0, 1.0)
	var lift: float = clampf(elevation_speed / HeavySwordMotion.MAX_ANGULAR_SPEED, -1.0, 1.0)
	# Positive heading speed sweeps the blade to the left; the view turns and banks left with it.
	return Vector3(lift * MAX_PITCH, turn * MAX_YAW, turn * MAX_ROLL)

func step(delta: float, heading_speed: float, elevation_speed: float) -> Vector3:
	if not is_finite(delta) or delta <= 0.0 or not is_finite(heading_speed) or not is_finite(elevation_speed):
		return offset
	var goal: Vector3 = target(heading_speed, elevation_speed)
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.000001:
		var dt: float = minf(remaining, 1.0 / 120.0)
		remaining -= dt
		speed += ((goal - offset) * STIFFNESS - speed * DAMPING) * dt
		offset += speed * dt
	return offset
