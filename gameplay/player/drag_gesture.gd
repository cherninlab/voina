class_name DragGesture
extends RefCounted

# Screen pixels, independent of camera sensitivity, aim friction and event frequency.
const THRESHOLD: float = 36.0
var held: bool = false
var fired: bool = false
var displacement: Vector2 = Vector2.ZERO

func begin() -> void:
	if held:
		return
	held = true
	fired = false
	displacement = Vector2.ZERO

func move(relative: Vector2) -> Vector2:
	if not held or fired or not relative.is_finite():
		return Vector2.ZERO
	displacement += relative.limit_length(4096.0)
	if displacement.length() < THRESHOLD:
		return Vector2.ZERO
	fired = true
	return displacement.normalized()

func cancel() -> void:
	held = false
	fired = false
	displacement = Vector2.ZERO
