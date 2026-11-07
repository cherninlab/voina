extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var fixture: RedDescentGeometry = RedDescentGeometry.new()
	fixture.paving_bed(Vector3.ZERO, Vector3(0, 0, 2), Vector3(2, 1, 0))
	var all_faces: PackedVector3Array = PackedVector3Array()
	for vertices: PackedVector3Array in fixture.surfaces.values():
		all_faces.append_array(vertices)
	assert(all_faces.size() == 24 and fixture.collision_faces.size() == 24, "Bedding must have closed render and collision prisms")
	var incidents: Dictionary[String, int] = {}
	for index: int in range(0, all_faces.size(), 3):
		for side: int in range(3):
			var a: String = str(all_faces[index + side].snapped(Vector3.ONE * 0.00001))
			var b: String = str(all_faces[index + (side + 1) % 3].snapped(Vector3.ONE * 0.00001))
			var key: String = a + "/" + b if a < b else b + "/" + a
			incidents[key] = incidents.get(key, 0) + 1
	assert(incidents.values().all(func(count: int) -> bool: return count == 2), "Open bedding edge")
	fixture.free()
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	var architecture: RedDescentGeometry = world.get_node("CinderCrypt/Architecture") as RedDescentGeometry
	assert(architecture.relief_walls == PackedInt32Array([3, 4, 5, 6]), "Current structure did not load")
	var gallery: Node3D = architecture.get_node("StonePassage_return_gallery") as Node3D
	var bonded: Array[Node] = gallery.find_children("BondedGallery*", "MeshInstance3D", true, false)
	assert(bonded.size() == 5, "Expected one bonded wall object per section")
	var cement_rays: int = 0
	var cement_hits: int = 0
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for node: Node in bonded:
		var wall: MeshInstance3D = node as MeshInstance3D
		assert(wall.mesh.get_surface_count() == 2, "Stone and cement surfaces must stay separate materials on one object")
		var cement_surfaces: int = 0
		for surface: int in range(wall.mesh.get_surface_count()):
			var material: ShaderMaterial = wall.get_surface_override_material(surface) as ShaderMaterial
			assert(material != null)
			if material.get_shader_parameter("mapped") == false:
				cement_surfaces += 1
				var arrays: Array = wall.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				for index: int in range(0, indices.size(), 12):
					var a: Vector3 = wall.global_transform * vertices[indices[index]]
					var b: Vector3 = wall.global_transform * vertices[indices[index + 1]]
					var c: Vector3 = wall.global_transform * vertices[indices[index + 2]]
					var normal: Vector3 = (c - a).cross(b - a).normalized()
					var centre: Vector3 = (a + b + c) / 3.0
					var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(centre + normal * 0.02, centre - normal * 0.02, 1))
					cement_rays += 1
					if not hit.is_empty() and (hit["position"] as Vector3).distance_to(centre) < 0.005:
						cement_hits += 1
		assert(cement_surfaces == 1, "Missing solid cement material")
	assert(cement_rays > 200 and cement_hits > cement_rays * 0.95, "Cement collision missing from wall/floor/roof")
	print("CEMENT_COLLISION_OK: %d/%d surface rays" % [cement_hits, cement_rays])
	var structure: Node3D = architecture.get_node("StructuralRelief") as Node3D
	var matches: int = 0
	var samples: int = 0
	assert(structure.find_children("*UpperPostSocket*", "MeshInstance3D", true, false).size() == 2)
	assert(structure.find_children("Foundation_UpperBridgeBearing", "MeshInstance3D", true, false).size() == 1)
	for node: Node in structure.find_children("*", "MeshInstance3D", true, false):
		if not (node.name.begins_with("ShaftRock") or "UpperPostSocket" in String(node.name) or node.name == "Foundation_UpperBridgeBearing"):
			continue
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
	print("STRUCTURE_CHECK_OK: %d/%d sampled render/collision rays, closed sloped bedding, current load, stale route/room rejection" % [matches, samples])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5):
		await process_frame
	quit()
