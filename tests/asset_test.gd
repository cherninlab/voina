extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for variant: String in ["male", "female"]:
		var visual: CharacterVisual = (load("res://content/characters/quaternius/%s.tscn" % variant) as PackedScene).instantiate() as CharacterVisual
		root.add_child(visual)
		assert(visual.animation_library != null and visual.animation_library.get_animation_list().size() == 9)
		for clip: StringName in visual.animation_library.get_animation_list():
			var animation: Animation = visual.animation_library.get_animation(clip)
			for track: int in range(animation.get_track_count()):
				var path: NodePath = animation.track_get_path(track)
				assert(visual.get_node_or_null(NodePath(String(path).get_slice(":", 0))) == visual.skeleton, "Every track must bind to this character")
				assert(visual.skeleton.find_bone(path.get_subname(0)) >= 0)
		visual.select_clip(&"Jog_Fwd")
		visual.playback.advance(0.2)
		var foot: int = visual.skeleton.find_bone("foot_l")
		var before: Vector3 = visual.skeleton.get_bone_global_pose(foot).origin
		visual.playback.advance(0.2)
		assert(before.distance_to(visual.skeleton.get_bone_global_pose(foot).origin) > 0.01, "Jog must move the rig")
		visual.free()
	for piece: String in ["box", "pillar", "stairs"]:
		var prop: PrototypeProp = PrototypeProp.new()
		prop.model_scene = load("res://content/environments/rgsdev/Pieces/%s.fbx" % piece) as PackedScene
		root.add_child(prop)
		assert(prop.bounds.size.y > 0.5 and prop.bounds.size.y < 5.0, "FBX must import at usable scale")
		assert(prop.find_children("*", "StaticBody3D", true, false).size() > 0, "Arena props need collision")
		prop.free()
	print("ASSETS_OK: both animated rigs, bound tracks, moving bones, FBX scale and collision")
	quit()
