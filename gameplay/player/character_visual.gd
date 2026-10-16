class_name CharacterVisual
extends Node3D

@export var model_scene: PackedScene

var meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var highlight: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
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
	if skeleton != null:
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
