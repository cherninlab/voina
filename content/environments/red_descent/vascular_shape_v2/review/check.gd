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
	var base_material: StandardMaterial3D = architecture.materials["roots"] as StandardMaterial3D
	assert(base_material.roughness_texture == null and is_equal_approx(base_material.roughness, 0.62))
	for child: Node in architecture.get_children():
		if String(child.name).begins_with("Roots_") and String(child.name) not in ["Roots_first_stair_hall", "Roots_second_stair_hall"]:
			for mesh: Node in child.find_children("*", "MeshInstance3D", true, false):
				assert((mesh as MeshInstance3D).material_override == base_material, "Tissue material leaked to other rooms")
	var count: int = 0
	var triangles: int = 0
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/environments/procedural_roots_v1/" + id + ".json")) as Dictionary
		var growth: Node3D = architecture.get_node("Roots_" + id) as Node3D
		assert(growth.find_children("*", "CollisionShape3D", true, false).is_empty())
		assert(growth.find_children("*", "Light3D", true, false).is_empty())
		assert(growth.find_children("Graft_*", "MeshInstance3D", true, false).size() == 1)
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
			assert(material.roughness_texture.resource_path.ends_with("roots/roughness.png"))
			assert(material != base_material)
			assert(is_equal_approx(material.roughness, 0.52 if String(instance.name).begins_with("Graft_") else 0.68))
		assert(room_triangles == int(report["triangles"]))
		count += meshes.size()
		triangles += room_triangles
	print("VASCULAR_SHAPE_RUNTIME_OK: %d regenerated batches, %d triangles; 620 architecture collision shapes and seven stair-art meshes retained; growth adds no collision/lights; tissue roughness isolated to both stair halls" % [count, triangles])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5): await process_frame
	quit()
