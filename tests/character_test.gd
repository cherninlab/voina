extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for variant: String in ["male", "female"]:
		var scene: PackedScene = load("res://content/characters/quaternius/%s.tscn" % variant) as PackedScene
		assert(scene != null)
		var visual: CharacterVisual = scene.instantiate() as CharacterVisual
		root.add_child(visual)
		assert(visual.skeleton != null and visual.skeleton.get_bone_count() == 65)
		assert(visual.meshes.size() == 3)
		var shoulder: int = visual.skeleton.find_bone("upperarm_l")
		var hand: int = visual.skeleton.find_bone("hand_l")
		assert(visual.skeleton.get_bone_global_pose(hand).origin.y < visual.skeleton.get_bone_global_pose(shoulder).origin.y - 0.3, "Idle pose must lower the hand")
		visual.set_first_person(true)
		for mesh: MeshInstance3D in visual.meshes:
			assert(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		visual.set_first_person(false)
		for mesh: MeshInstance3D in visual.meshes:
			assert(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		visual.queue_free()
	print("CHARACTER_OK: both models, 65-bone rigs, idle arms, first-person shadows")
	quit()
