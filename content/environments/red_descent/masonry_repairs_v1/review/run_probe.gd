extends SceneTree
func _initialize() -> void:
	start.call_deferred()
func start() -> void:
	var node: Node = load("res://content/environments/red_descent/masonry_repairs_v1/review/probe.gd").new()
	root.add_child(node)
	current_scene = node
