extends SceneTree


func _initialize() -> void:
	call_deferred("_probe")


func _probe() -> void:
	var results: Array[Dictionary] = []
	for filename: String in ["e01_crawling_lod0.glb", "e01_crawling_lod1.glb"]:
		var packed: PackedScene = load("res://" + filename) as PackedScene
		assert(packed != null, "GLB must import as PackedScene")
		var instance: Node = packed.instantiate()
		root.add_child(instance)
		var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "One static mesh expected")
		var visual: MeshInstance3D = meshes[0] as MeshInstance3D
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		assert((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0)
		assert((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0)
		assert((arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() > 0)
		assert((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0)
		var material: StandardMaterial3D = visual.mesh.surface_get_material(0) as StandardMaterial3D
		assert(material != null and material.albedo_texture != null)
		assert(material.normal_enabled and material.normal_texture != null)
		assert(material.roughness_texture != null)
		assert(material.ao_enabled and material.ao_texture != null)
		results.append({"file": filename, "vertices": visual.mesh.surface_get_array_len(0),
			"indices": visual.mesh.surface_get_array_index_len(0), "normal_uv_tangent": true,
			"albedo_roughness_normal_ao": true, "aabb": str(visual.get_aabb())})
		instance.free()
	print("STATUE_GODOT_OK ", JSON.stringify({"engine": Engine.get_version_info().string, "assets": results}))
	quit()
