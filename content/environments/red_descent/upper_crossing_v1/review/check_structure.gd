extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	var architecture: RedDescentGeometry = world.get_node("CinderCrypt/Architecture") as RedDescentGeometry
	assert(architecture.relief_walls == PackedInt32Array([3, 4, 5, 6]), "Current structure did not load")
	var structure: Node3D = architecture.get_node("StructuralRelief") as Node3D
	var matches: int = 0
	var samples: int = 0
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for node: Node in structure.find_children("ShaftRock*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var faces: PackedVector3Array = visual.mesh.get_faces()
		for index: int in range(0, mini(faces.size(), 90), 9):
			var a: Vector3 = visual.global_transform * faces[index]
			var b: Vector3 = visual.global_transform * faces[index + 1]
			var c: Vector3 = visual.global_transform * faces[index + 2]
			var normal: Vector3 = (c - a).cross(b - a).normalized()
			var centre: Vector3 = (a + b + c) / 3.0
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(centre + normal * 0.06, centre - normal * 0.06, 1))
			samples += 1
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(centre) < 0.008:
				matches += 1
	assert(samples > 100 and matches > samples * 0.85, "Relief collision does not follow the rendered triangles")
	var stale_route: RedDescentGeometry = RedDescentGeometry.new()
	root.add_child(stale_route)
	stale_route.paths[0]["width"] = float(stale_route.paths[0]["width"]) + 0.1
	stale_route.load_structural_relief()
	assert(stale_route.relief_walls.is_empty() and not stale_route.has_node("StructuralRelief"), "Stale route accepted")
	stale_route.queue_free()
	var stale_room: RedDescentGeometry = RedDescentGeometry.new()
	root.add_child(stale_room)
	stale_room.rooms[0]["height"] = float(stale_room.rooms[0]["height"]) + 0.1
	stale_room.load_structural_relief()
	assert(stale_room.relief_walls.is_empty() and not stale_room.has_node("StructuralRelief"), "Stale room accepted")
	stale_room.queue_free()
	print("STRUCTURE_CHECK_OK: %d/%d sampled render/collision rays, current load, stale route/room rejection" % [matches, samples])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5):
		await process_frame
	quit()
