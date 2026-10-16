class_name PrototypeProp
extends Node3D

@export var model_scene: PackedScene
@export var collision_enabled: bool = true
var bounds: AABB

func _ready() -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
	add_child(model)
	var first: bool = true
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var relative: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds: AABB = relative * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
		if collision_enabled:
			mesh.create_trimesh_collision()
	# FBX pieces retain the author's arrangement offsets; center them and put the base on Y=0.
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
