class_name RemoteMotion
extends RefCounted
## How a peer draws a body it does not own. The latest movement snapshot is projected forward by
## the time since it arrived, so a moving player is not drawn an extra smoothing delay behind.
## When a new snapshot disagrees with what is on screen, the difference fades out instead of
## snapping; only teleport-sized disagreements snap.

const MAX_PROJECTION: float = 0.1
const CORRECTION_RATE: float = 15.0
const SNAP_DISTANCE: float = 2.0
const GRAVITY: float = 20.0

var snapshot_position: Vector3 = Vector3.ZERO
var snapshot_velocity: Vector3 = Vector3.ZERO
var received_at: float = 0.0
var offset: Vector3 = Vector3.ZERO
var snapshots: int = 0

func reset(location: Vector3, now: float) -> void:
	snapshot_position = location
	snapshot_velocity = Vector3.ZERO
	received_at = now
	offset = Vector3.ZERO

func receive(location: Vector3, velocity: Vector3, now: float, shown_now: Vector3) -> void:
	snapshot_position = location
	snapshot_velocity = velocity
	received_at = now
	snapshots += 1
	offset = shown_now - projected(now)
	if offset.length() > SNAP_DISTANCE:
		offset = Vector3.ZERO

func projected(now: float) -> Vector3:
	var age: float = clampf(now - received_at, 0.0, MAX_PROJECTION)
	var point: Vector3 = snapshot_position + snapshot_velocity * age
	if absf(snapshot_velocity.y) > 0.01:
		point.y -= 0.5 * GRAVITY * age * age
	return point

func shown(now: float, delta: float) -> Vector3:
	offset *= exp(-CORRECTION_RATE * delta)
	return projected(now) + offset
