extends Node3D

var active: bool = false
var flock_positions: PackedVector3Array = PackedVector3Array(BirdFlock.HOMES)
var flock_states: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var flock: BirdFlock = BirdFlock.new()
var birds: Array[Node3D] = []
var visuals: Array[Node3D] = []

func _ready() -> void:
	# Existing lifecycle hooks let this stay separate from match and sword work.
	add_to_group("match_world")
	set_multiplayer_authority(1)
	for index: int in range(BirdFlock.HOMES.size()):
		var bird: Node3D = Node3D.new()
		bird.name = "Bird%d" % index
		bird.position = flock_positions[index]
		add_child(bird)
		var model: Node3D = preload("res://gameplay/wildlife/bird_visual.gd").new()
		bird.add_child(model)
		birds.append(bird)
		visuals.append(model)
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "FlockSync"
	sync.replication_interval = 0.05
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [^":active", ^":flock_positions", ^":flock_states"]:
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)
	visible = false

func host_started() -> void:
	var world: Node = get_tree().current_scene
	if world != null and world.has_node("Players"):
		start()

func start() -> void:
	if not multiplayer.is_server():
		return
	flock = BirdFlock.new()
	flock_positions = flock.positions.duplicate()
	flock_states = flock.states.duplicate()
	active = true
	for index: int in range(birds.size()):
		birds[index].position = flock_positions[index]

func clear_players() -> void:
	active = false
	visible = false

func _physics_process(delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	var players: PackedVector3Array = PackedVector3Array()
	var world: Node = get_tree().current_scene
	var root: Node = world.get_node_or_null("Players") if world != null else null
	if root != null:
		for player: Node in root.get_children():
			if player is Node3D and not player.is_queued_for_deletion():
				players.append((player as Node3D).global_position)
	flock.step(delta, players)
	flock_positions = flock.positions.duplicate()
	flock_states = flock.states.duplicate()

func _process(delta: float) -> void:
	visible = active
	if not active:
		return
	for index: int in range(birds.size()):
		var bird: Node3D = birds[index]
		var destination: Vector3 = flock_positions[index]
		var travel: Vector3 = destination - bird.position
		if Vector2(travel.x, travel.z).length() > 0.01:
			bird.rotation.y = lerp_angle(bird.rotation.y, atan2(-travel.x, -travel.z), minf(delta * 7.0, 1.0))
		bird.position = bird.position.lerp(destination, minf(delta * 18.0, 1.0))
		visuals[index].call("animate", delta, flock_states[index] != BirdFlock.State.PERCHED, float(index) * 1.7)
