extends SceneTree
## Standalone asset validation. Does not load the game or register a mob.

const MODEL: String = "res://content/mobs/hooded_cultist/hooded_cultist.tscn"


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var packed: PackedScene = load(MODEL) as PackedScene
	assert(packed != null, "Cultist scene must import")
	var model: Node3D = packed.instantiate() as Node3D
	root.add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	assert(skeletons.size() == 1, "One deform skeleton")
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	assert(skeleton.get_bone_count() == 65, "Keep the raider's original 65-bone skeleton")
	for bone_name: String in ["root", "pelvis", "Head", "hand_l", "hand_r",
			"foot_l", "foot_r", "spine_03", "neck_01", "lowerarm_l"]:
		assert(skeleton.find_bone(bone_name) >= 0, "Missing bone: " + bone_name)
	var base_packed: PackedScene = load("res://content/characters/quaternius/Superhero_Male_FullBody.gltf") as PackedScene
	var base: Node3D = base_packed.instantiate() as Node3D
	var base_skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for bone_index: int in range(base_skeleton.get_bone_count()):
		var bone_name: String = base_skeleton.get_bone_name(bone_index)
		var index: int = skeleton.find_bone(bone_name)
		assert(index >= 0, "Preserved bone: " + bone_name)
		var expected: Transform3D = base_skeleton.get_bone_rest(bone_index)
		var actual: Transform3D = skeleton.get_bone_rest(index)
		assert(expected.origin.distance_to(actual.origin) < 0.0001, "Preserved rest origin: " + bone_name)
		assert(expected.basis.is_equal_approx(actual.basis), "Preserved rest rotation: " + bone_name)
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 4, "Original three human meshes plus one garment mesh")
	for base_node: Node in base.find_children("*", "MeshInstance3D", true, false):
		var original_mesh: MeshInstance3D = base_node as MeshInstance3D
		var preserved_mesh: MeshInstance3D = skeleton.find_child(str(base_node.name), true, false) as MeshInstance3D
		assert(preserved_mesh != null, "Preserved original human mesh")
		assert(preserved_mesh.mesh.get_surface_count() == original_mesh.mesh.get_surface_count())
		var original_bounds: AABB = original_mesh.mesh.get_aabb()
		var preserved_bounds: AABB = preserved_mesh.mesh.get_aabb()
		# The legs and feet under the gown are removed (build_hooded_cultist.py LEG_HIDE): the body
		# keeps its height at the top and its arm span; only its bottom rises to the hips.
		assert(absf(original_bounds.end.y - preserved_bounds.end.y) < 0.001, "Original body proportions (top)")
		assert(absf(original_bounds.position.x - preserved_bounds.position.x) < 0.001 and absf(original_bounds.size.x - preserved_bounds.size.x) < 0.001, "Original arm span")
		assert(preserved_bounds.position.y <= 0.96 or preserved_mesh.name != &"SuperHero_Male", "Body kept from the hips up")
	for node: Node in meshes:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		assert(mesh_node.skin != null, "Mesh must have skin bind data")
		assert(mesh_node.get_node(mesh_node.skeleton) == skeleton, "Skin must target the skeleton")
		for surface_index: int in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface_index)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			assert(weights.size() == positions.size() * 4, "Four skin slots per vertex")
			for vertex_index: int in range(positions.size()):
				var weight_sum: float = 0.0
				for influence: int in range(4):
					weight_sum += weights[vertex_index * 4 + influence]
				assert(absf(weight_sum - 1.0) < 0.002, "Normalized skin weights")
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	assert(players.size() == 1, "One animation player")
	var player: AnimationPlayer = players[0] as AnimationPlayer
	for clip: String in ["Idle", "Walk", "Jog_Fwd", "Punch_Jab", "Hit_Chest"]:
		assert(player.has_animation(clip), "Missing inspection clip: " + clip)
		player.play(clip)
		var animation: Animation = player.get_animation(clip)
		assert(animation.length > 0.1, "Nonempty animation")
		for sample: int in range(9):
			player.seek(animation.length * float(sample) / 8.0, true)
			for bone_index: int in range(skeleton.get_bone_count()):
				var transform: Transform3D = skeleton.get_bone_global_pose(bone_index)
				assert(transform.is_finite(), "Finite animated bone transforms")
				assert(transform.origin.length() < 4.0, "No exploding bone translations")
	var hand_index: int = skeleton.find_bone("hand_l")
	player.play("Idle")
	player.seek(0.0, true)
	var idle_hand: Vector3 = skeleton.get_bone_global_pose(hand_index).origin
	player.play("Punch_Jab")
	player.seek(player.current_animation_length * 0.5, true)
	var reach_hand: Vector3 = skeleton.get_bone_global_pose(hand_index).origin
	assert(idle_hand.distance_to(reach_hand) > 0.1, "Existing jab must articulate the arm")
	print("CULTIST_OK: original 65-bone rest rig, human plus garments, normalized weights, existing raider clips")
	base.free()
	model.queue_free()
	quit()
