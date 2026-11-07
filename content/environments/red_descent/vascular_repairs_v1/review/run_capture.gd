extends SceneTree

func _initialize() -> void:
	var node: Node = load("res://content/environments/red_descent/vascular_repairs_v1/review/capture.gd").new()
	root.add_child.call_deferred(node)
