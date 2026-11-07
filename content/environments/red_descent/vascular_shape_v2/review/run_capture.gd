extends SceneTree

func _initialize() -> void:
	var capture: Node = load("res://content/environments/red_descent/vascular_shape_v2/review/capture.gd").new() as Node
	root.add_child.call_deferred(capture)
