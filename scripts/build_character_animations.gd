extends SceneTree

const SOURCE: String = "res://content/animations/quaternius/UAL1_Standard.glb"
const CLIPS: Array[StringName] = [&"Idle", &"Jog_Fwd", &"Walk", &"Jump", &"Sprint", &"Sword_Idle", &"Punch_Jab", &"Pistol_Shoot", &"Hit_Chest"]
const LOOPS: Array[StringName] = [&"Idle", &"Jog_Fwd", &"Walk", &"Jump", &"Sprint", &"Sword_Idle"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source: Node3D = (load(SOURCE) as PackedScene).instantiate() as Node3D
	root.add_child(source)
	var source_rig: Skeleton3D = source.find_child("Skeleton3D", true, false) as Skeleton3D
	var player: AnimationPlayer = source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(player != null and source_rig != null)
	player.play("A_TPose")
	player.seek(0.0, true)
	player.pause()
	for variant: String in ["Male", "Female"]:
		var path: String = "res://content/characters/quaternius/Superhero_%s_FullBody.gltf" % variant
		var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var target_rig: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
		assert(target_rig != null and target_rig.get_bone_count() == source_rig.get_bone_count())
		var library: AnimationLibrary = AnimationLibrary.new()
		for clip: StringName in CLIPS:
			var animation: Animation = player.get_animation(clip).duplicate(true) as Animation
			for track: int in range(animation.get_track_count() - 1, -1, -1):
				var bone: String = animation.track_get_path(track).get_subname(0)
				var target_index: int = target_rig.find_bone(bone)
				var source_index: int = source_rig.find_bone(bone)
				assert(target_index >= 0 and source_index >= 0, "Every animation bone must map")
				var kind: int = animation.track_get_type(track)
				if kind == Animation.TYPE_SCALE_3D or (kind == Animation.TYPE_POSITION_3D and bone != "pelvis"):
					animation.remove_track(track)
					continue
				# Every wrapper names its model Model, and this pack's rig is Armature/Skeleton3D.
				animation.track_set_path(track, NodePath("Model/Armature/Skeleton3D:" + bone))
				var target_rest: Transform3D = target_rig.get_bone_global_rest(target_index)
				var source_reference: Transform3D = source_rig.get_bone_global_pose(source_index)
				var source_parent: int = source_rig.get_bone_parent(source_index)
				var target_parent: int = target_rig.get_bone_parent(target_index)
				var source_parent_basis: Basis = source_rig.get_bone_global_pose(source_parent).basis if source_parent >= 0 else Basis.IDENTITY
				var target_parent_basis: Basis = target_rig.get_bone_global_rest(target_parent).basis if target_parent >= 0 else Basis.IDENTITY
				var left: Basis = target_parent_basis.inverse() * source_parent_basis
				var right: Basis = source_reference.basis.inverse() * target_rest.basis
				for key: int in range(animation.track_get_key_count(track)):
					if kind == Animation.TYPE_ROTATION_3D:
						var rotation: Quaternion = animation.track_get_key_value(track, key) as Quaternion
						animation.track_set_key_value(track, key, (left * Basis(rotation) * right).orthonormalized().get_rotation_quaternion())
					elif kind == Animation.TYPE_POSITION_3D:
						var value: Vector3 = animation.track_get_key_value(track, key) as Vector3
						var reference: Vector3 = source_rig.get_bone_pose_position(source_index)
						var ratio: float = target_rest.origin.y / maxf(0.01, source_reference.origin.y)
						animation.track_set_key_value(track, key, target_rig.get_bone_rest(target_index).origin + left * (value - reference) * ratio)
			animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPS else Animation.LOOP_NONE
			library.add_animation(clip, animation)
		var output: String = "res://content/animations/quaternius/%s.res" % variant.to_lower()
		assert(ResourceSaver.save(library, output) == OK)
		model.free()
		print("ANIMATIONS_BUILT: ", output, " (", CLIPS.size(), " clips)")
	source.free()
	quit()
