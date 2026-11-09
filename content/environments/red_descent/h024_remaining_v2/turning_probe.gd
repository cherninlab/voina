extends SceneTree
## Actual Jolt queries at the formerly open root-to-bridge endpoint.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	dungeon.set_process(false) # Fixture has no player/camera; only native geometry and Jolt.
	for frame: int in range(4):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = dungeon.get_world_3d().direct_space_state
	var eye: Vector3 = Vector3(-26.9093914, -21.4, -11.811367)
	var direction: Vector3 = Vector3(0.405960917, 0.073457457, -0.910933495)
	var closed: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + direction * 80.0))
	if closed.is_empty() or eye.distance_to(closed["position"] as Vector3) > 12.0:
		push_error("Former void ray still escapes the chamber")
		quit(1)
		return
	var entry: Vector3 = Vector3(-24.8, -21.4, -16)
	var doorway: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(entry, entry + Vector3.RIGHT * 3.5))
	if not doorway.is_empty():
		push_error("Bridge-facing doorway blocked: " + str(doorway))
		quit(1)
		return
	var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-26.6, -22, -16), Vector3(-26.6, -24, -16)))
	if floor_hit.is_empty() or absf((floor_hit["position"] as Vector3).y + 23.0) > 0.01:
		push_error("Turning chamber floor is not at walking level")
		quit(1)
		return
	print("ROOT_TURNING_PHYSICS_OK: former void blocked at ", closed["position"], "; bridge doorway clear; walking floor ", floor_hit["position"])
	quit(0)
