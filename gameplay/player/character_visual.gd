class_name CharacterVisual
extends Node3D

@export var model_scene: PackedScene
@export var animation_library: AnimationLibrary

var meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var highlight: StandardMaterial3D = StandardMaterial3D.new()
var playback: AnimationPlayer = AnimationPlayer.new()
var clip: StringName = &""
var action_left: float = 0.0

func _ready() -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
	model.name = "Model"
	# Pack faces +Z, while the game faces -Z. Feet start at ground level in the source.
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "", true, false):
		if node is MeshInstance3D:
			meshes.append(node as MeshInstance3D)
		elif node is Skeleton3D:
			skeleton = node as Skeleton3D
	# The Standard pack has no clips. Lower the T-pose arms into a static neutral pose.
	if animation_library != null:
		playback.name = "Playback"
		add_child(playback)
		playback.add_animation_library(&"", animation_library)
		select_clip(&"Idle")
		playback.advance(0.0)
	elif skeleton != null:
		relax_arm("upperarm_l", -70.0)
		relax_arm("upperarm_r", 70.0)
	highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func relax_arm(bone_name: String, degrees: float) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index < 0:
		return
	var rest: Basis = skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var local_rest: Basis = skeleton.get_bone_rest(index).basis.orthonormalized()
	var rotation: Basis = Basis(Vector3.BACK, deg_to_rad(degrees))
	skeleton.set_bone_pose_rotation(index, (local_rest * rest.inverse() * rotation * rest).get_rotation_quaternion())

func set_first_person(enabled: bool) -> void:
	for mesh: MeshInstance3D in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func set_highlight(enabled: bool, color: Color) -> void:
	highlight.albedo_color = Color(color, 0.35)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = highlight if enabled else null

func select_clip(next: StringName, speed: float = 1.0) -> void:
	if clip == next:
		return
	clip = next
	playback.play(clip, 0.08, speed)

func play_attack(ranged: bool) -> void:
	if animation_library == null:
		return
	action_left = 0.4 if ranged else 0.52
	clip = &""
	var action: StringName = &"Pistol_Shoot" if ranged else &"Punch_Jab"
	select_clip(action, animation_library.get_animation(action).length / action_left)

func animate(delta: float, motion: Vector3, grounded: bool, phase: int, blocking: bool, frozen: bool) -> void:
	if animation_library == null:
		return
	playback.speed_scale = 0.0 if frozen else 1.0
	if not frozen:
		action_left = maxf(0.0, action_left - delta)
	if phase == CombatController.Phase.STAGGERED:
		action_left = 0.0
		select_clip(&"Hit_Chest")
	elif phase == CombatController.Phase.DASHING:
		action_left = 0.0
		select_clip(&"Sprint", 1.5)
	elif blocking:
		select_clip(&"Sword_Idle")
	elif action_left > 0:
		return
	elif not grounded:
		select_clip(&"Jump")
	elif Vector2(motion.x, motion.z).length() > 0.3:
		select_clip(&"Jog_Fwd")
	else:
		select_clip(&"Idle")
