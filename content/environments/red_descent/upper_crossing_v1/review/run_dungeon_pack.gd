extends SceneTree
func _initialize() -> void:
	start.call_deferred()
func start() -> void:
	var node: Node = load("res://content/environments/red_descent/upper_crossing_v1/review/capture_dungeon_pack.gd").new()
	node.name = "DungeonExplorer"
	root.add_child(node)
	current_scene = node
