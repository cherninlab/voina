extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func near(a: Vector3, b: Vector3, tolerance: float = 0.001) -> bool:
	return a.distance_to(b) <= tolerance

func run() -> void:
	var motion: RemoteMotion = RemoteMotion.new()
	motion.reset(Vector3(0, 1, 0), 10.0)
	assert(near(motion.shown(10.5, 1.0 / 60.0), Vector3(0, 1, 0)), "A reset body holds still")
	# Running at 6.5 m/s: drawn where the snapshot says, projected by the time since it arrived.
	motion.receive(Vector3(0, 1, 0), Vector3(6.5, 0, 0), 11.0, Vector3(0, 1, 0))
	assert(near(motion.shown(11.05, 1.0 / 60.0), Vector3(0.325, 1, 0)), "Moving bodies are not drawn a smoothing delay behind")
	assert(near(motion.projected(12.0), Vector3(6.5 * RemoteMotion.MAX_PROJECTION, 1, 0)), "Projection stops after packet loss")
	# A late snapshot that disagrees with the screen fades in instead of snapping.
	var before: Vector3 = motion.shown(11.06, 1.0 / 60.0)
	motion.receive(Vector3(0.2, 1, 0), Vector3(6.5, 0, 0), 11.06, before)
	assert(near(motion.shown(11.06, 0.0), before), "A correction does not jump on arrival")
	var error: float = motion.offset.length()
	for frame: int in range(30):
		motion.shown(11.06, 1.0 / 60.0)
	assert(motion.offset.length() < error * 0.01, "Corrections fade within half a second")
	# Teleports such as respawns snap.
	motion.receive(Vector3(20, 1, 0), Vector3.ZERO, 12.0, Vector3(1, 1, 0))
	assert(near(motion.shown(12.0, 0.0), Vector3(20, 1, 0)), "Teleport-sized disagreements snap")
	# Airborne snapshots follow the jump arc instead of a straight line.
	motion.receive(Vector3(0, 2, 0), Vector3(0, 3, 0), 13.0, Vector3(0, 2, 0))
	assert(near(motion.projected(13.1), Vector3(0, 2.0 + 0.3 - 0.5 * RemoteMotion.GRAVITY * 0.01, 0)), "Jumps follow gravity")
	assert(motion.snapshots == 4, "Snapshots are counted for the net monitor")
	print("REMOTE_MOTION_OK: hold, projection, projection cap, faded correction, teleport snap, jump arc")
	quit()
