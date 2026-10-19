class_name WalkCamera
extends RefCounted
## Owner-only handheld shake while walking, separate from the swing follow-through. Ground speed
## sets an intensity that fades linearly (so it reaches exactly zero) when standing still or
## airborne. The stride drives a vertical bob twice per stride, a side sway and roll once per
## stride, and a slow sum-of-sines jitter adds the handheld wobble. Never networked.

var intensity: float = 0.0
var stride: float = 0.0 # radians; one full turn is two steps
var clock: float = 0.0
var shift: Vector2 = Vector2.ZERO # h_offset, v_offset in metres
var turn: Vector3 = Vector3.ZERO # pitch, yaw, roll in radians, added to Camera3D.rotation

func reset() -> void:
	intensity = 0.0
	stride = 0.0
	clock = 0.0
	shift = Vector2.ZERO
	turn = Vector3.ZERO

func step(delta: float, ground_speed: float, grounded: bool) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_finite(ground_speed):
		return
	delta = minf(delta, 0.1)
	var ratio: float = clampf(ground_speed / CameraTuning.value("walk_full_speed"), 0.0, CameraTuning.value("walk_max_scale"))
	var goal: float = pow(ratio, CameraTuning.value("walk_speed_curve")) if grounded else 0.0
	intensity = move_toward(intensity, goal, CameraTuning.value("walk_fade") * delta)
	if intensity <= 0.0:
		shift = Vector2.ZERO
		turn = Vector3.ZERO
		return
	# Cadence rises more slowly than speed, as it does when people speed up.
	stride = fmod(stride + PI * CameraTuning.value("walk_steps") * sqrt(ratio) * delta, TAU)
	clock = fmod(clock + CameraTuning.value("walk_jitter_rate") * delta, 1000.0)
	var jitter: float = CameraTuning.value("walk_jitter")
	var t: float = clock * TAU
	shift = intensity * Vector2(sin(stride) * CameraTuning.value("walk_sway"), sin(stride * 2.0) * CameraTuning.value("walk_bob"))
	turn = intensity * Vector3(
		jitter * (sin(t * 1.3) * 0.6 + sin(t * 3.1 + 1.7) * 0.4),
		jitter * (sin(t * 0.9 + 0.4) * 0.6 + sin(t * 2.3 + 2.9) * 0.4),
		-sin(stride) * CameraTuning.value("walk_roll"))
