extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var forest: TreePack = (load("res://gameplay/environment/tree_pack.tscn") as PackedScene).instantiate() as TreePack
	root.add_child(forest)
	assert(forest.plants.size() == 36, "Arena decoration must include 24 trees and 12 bushes")
	for plant: Node3D in forest.plants:
		assert(Vector2(plant.position.x, plant.position.z).length() >= 17.0)
		assert(plant.scale.is_equal_approx(Vector3.ONE * plant.scale.x), "Use uniform visual scaling")
	assert(forest.find_children("*", "CollisionObject3D", true, false).is_empty(), "Scenery must not change combat or movement collision")
	for prefix: String in ["tree", "bush"]:
		for index: int in range(1, 37 if prefix == "tree" else 9):
			var plant: Node3D = forest.add_plant("%s%02d" % [prefix, index], Vector3(30, 0, 30), 4.0)
			var meshes: Array[Node] = plant.find_children("*", "MeshInstance3D", true, false)
			assert(not meshes.is_empty())
			for node: Node in meshes:
				var mesh: MeshInstance3D = node as MeshInstance3D
				var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
				assert(material.albedo_texture != null)
				assert(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
				assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED)
				assert(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
				var bounds: AABB = mesh.global_transform * mesh.get_aabb()
				assert(absf(bounds.size.y - 4.0) < 0.01 and absf(bounds.position.y) < 0.01, "Normalize plant height and ground its base")
	print("TREES_OK: 44 model/texture pairs, alpha cutouts, uniform scale, grounded bases, deterministic collision-free scenery")
	quit()
