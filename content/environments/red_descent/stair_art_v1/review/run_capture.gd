extends SceneTree

func _initialize() -> void:
	var node: Node = load("res://content/environments/red_descent/stair_art_v1/review/capture.gd").new()
	root.add_child.call_deferred(node)
