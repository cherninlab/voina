extends Node3D

const MODEL: PackedScene = preload("res://content/characters/quaternius/Superhero_Male_FullBody.gltf")
const CLIPS: AnimationLibrary = preload("res://content/animations/quaternius/male.res")
var playback: AnimationPlayer = AnimationPlayer.new()
var label: Label3D = Label3D.new()
var tint: StandardMaterial3D = StandardMaterial3D.new()
var meshes: Array[MeshInstance3D] = []
var clip: StringName = &""

func _ready() -> void:
	var model: Node3D = MODEL.instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI
	model.position.y = -0.9
	add_child(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = tint
	add_child(playback)
	playback.add_animation_library(&"", CLIPS)
	label.position.y = 1.35
	label.font_size = 28
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func show_state(state: int, health: int, staggered: bool, windup: bool) -> void:
	label.text = "RAIDER · %d" % health if health > 0 else "DEFEATED"
	tint.albedo_color = Color(1.0, 0.75, 0.1, 0.65) if windup else Color(0.85, 0.12, 0.12, 0.25)
	label.modulate = Color("ffd052") if windup else Color("ff8888")
	var next: StringName = &"Idle"
	if health <= 0:
		rotation.z = lerp_angle(rotation.z, PI / 2.0, 0.15)
	elif staggered:
		next = &"Hit_Chest"
	elif state == HostileMob.State.ACT:
		next = &"Punch_Jab"
	elif state == HostileMob.State.MOVE:
		next = &"Jog_Fwd"
	if clip != next:
		clip = next
		playback.play(clip, 0.12)
