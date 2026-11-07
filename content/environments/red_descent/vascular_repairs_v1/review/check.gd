extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var architecture: RedDescentGeometry = world.get_node("CinderCrypt/Architecture") as RedDescentGeometry
	assert(architecture.find_children("*", "CollisionShape3D", true, false).size() == 620)
	assert(architecture.get_node("StairRitualArt").find_children("*", "MeshInstance3D", true, false).size() == 7)
	var count: int = 0
	var triangles: int = 0
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/environments/procedural_roots_v1/" + id + ".json")) as Dictionary
		var growth: Node3D = architecture.get_node("Roots_" + id) as Node3D
		assert(growth.find_children("*", "CollisionShape3D", true, false).is_empty())
		assert(growth.find_children("*", "Light3D", true, false).is_empty())
		var room_triangles: int = 0
		var meshes: Array[Node] = growth.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == (report["meshes"] as Array).size())
		for node: Node in meshes:
			var instance: MeshInstance3D = node as MeshInstance3D
			assert((report["meshes"] as Array).has(String(instance.name)))
			assert(instance.global_transform == Transform3D.IDENTITY)
			room_triangles += instance.mesh.get_faces().size() / 3
			var material: StandardMaterial3D = instance.material_override as StandardMaterial3D
			assert(material != null and material.albedo_color == Color(0.66, 0.045, 0.07))
			assert(material.albedo_texture.resource_path.ends_with("roots/albedo.png"))
		assert(room_triangles == int(report["triangles"]))
		count += meshes.size()
		triangles += room_triangles
	print("VASCULAR_RUNTIME_OK: %d regenerated batches, %d triangles; 620 architecture collision shapes and seven stair-art meshes retained; growth adds no collision/lights" % [count, triangles])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5): await process_frame
	quit()
