extends SceneTree

func _initialize() -> void:
	var node: Node3D = load("res://content/environments/red_descent/masonry_repairs_v1/review/traversal_probe.gd").new() as Node3D
	root.add_child.call_deferred(node)
