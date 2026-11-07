extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	assert("--no-stair-art" in OS.get_cmdline_user_args(), "Check must start from the undecorated baseline")
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var architecture: RedDescentGeometry = world.get_node("CinderCrypt/Architecture") as RedDescentGeometry
	var colliders: Dictionary[NodePath, Array] = {}
	for node: Node in architecture.find_children("*", "CollisionShape3D", true, false):
		var collision: CollisionShape3D = node as CollisionShape3D
		colliders[collision.get_path()] = [collision.shape.get_rid(), collision.global_transform]
	var meshes: Dictionary[NodePath, RID] = {}
	var clips: Dictionary[NodePath, Array] = {}
	for node: Node in architecture.find_children("*", "MeshInstance3D", true, false):
		meshes[node.get_path()] = (node as MeshInstance3D).mesh.get_rid()
		var material: ShaderMaterial = (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null and material.shader.resource_path.ends_with("flagstone_clipped.gdshader"):
			clips[node.get_path()] = [material.get_shader_parameter("clip_count"), material.get_shader_parameter("clip_planes")]
	var lights: int = world.find_children("*", "Light3D", true, false).size()
	var choir: MeshInstance3D = architecture.get_node("StoneRoom_choir/Stone-stone_choir_0") as MeshInstance3D
	var unchanged: Material = choir.material_override
	RedDescentStairArt.install(architecture)
	var art: Node3D = architecture.get_node("StairRitualArt") as Node3D
	assert(art.find_children("*", "MeshInstance3D", true, false).size() == 7)
	assert(art.find_children("*", "CollisionShape3D", true, false).is_empty())
	assert(world.find_children("*", "Light3D", true, false).size() == lights, "Art pass added lights")
	assert(architecture.find_children("*", "CollisionShape3D", true, false).size() == colliders.size())
	for path: NodePath in colliders:
		var collision: CollisionShape3D = root.get_node(path) as CollisionShape3D
		assert([collision.shape.get_rid(), collision.global_transform] == colliders[path], "Existing collision changed")
	for path: NodePath in meshes:
		assert((root.get_node(path) as MeshInstance3D).mesh.get_rid() == meshes[path], "Existing visual geometry changed")
	for path: NodePath in clips:
		var material: ShaderMaterial = (root.get_node(path) as MeshInstance3D).material_override as ShaderMaterial
		assert([material.get_shader_parameter("clip_count"), material.get_shader_parameter("clip_planes")] == clips[path], "Floor clipping changed")
	var base_role: Variant = (unchanged as ShaderMaterial).get_shader_parameter("stair_art_role")
	assert(choir.material_override == unchanged and (base_role == null or base_role == 0), "Stair treatment leaked to choir")
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		for node: Node in architecture.get_node("StoneRoom_" + id).find_children("Stone*", "MeshInstance3D", true, false):
			var material: ShaderMaterial = (node as MeshInstance3D).material_override as ShaderMaterial
			assert(int(material.get_shader_parameter("stair_art_role")) > 0, "Stair material treatment missing")
	print("STAIR_ART_RUNTIME_OK: %d original visual meshes and%d collision shapes unchanged; seven decor batches, no new lights/collision, other-room material untouched" % [meshes.size(), colliders.size()])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5): await process_frame
	quit()
