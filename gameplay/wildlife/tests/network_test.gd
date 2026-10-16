extends Node3D

var players: Node3D = Node3D.new()
var failed: bool = false

func _ready() -> void:
	players.name = "Players"
	add_child(players)
	add_to_group("match_world")
	multiplayer.peer_disconnected.connect(disconnected)
	NetworkManager.start_from_arguments()
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("WILDLIFE_NETWORK_FAIL: " + message)
		get_tree().quit(1)

func run() -> void:
	if multiplayer.is_server():
		# Reach a changed state before the client exists: this is a true late join.
		var player: Node3D = Node3D.new()
		player.position = BirdFlock.HOMES[0]
		players.add_child(player)
		await get_tree().create_timer(2.0).timeout
		check(Wildlife.active and Wildlife.flock_states[0] == BirdFlock.State.FLEEING, "The host starts and simulates its flock")
		Wildlife.set_physics_process(false)
		print("WILDLIFE_NETWORK_READY")
	else:
		for frame: int in range(300):
			await get_tree().physics_frame
			if Wildlife.active:
				break
		await get_tree().create_timer(0.3).timeout
		check(Wildlife.active and Wildlife.flock_positions.size() == 4, "Late join receives the active flock")
		check(Wildlife.flock_states[0] == BirdFlock.State.FLEEING and Wildlife.flock_positions[0].distance_to(BirdFlock.HOMES[0]) > 2.0, "Late join receives current behavior and position")
		var positions: PackedVector3Array = Wildlife.flock_positions.duplicate()
		Wildlife.start()
		Wildlife._physics_process(1.0)
		check(Wildlife.flock_positions == positions, "A client cannot restart or simulate the authoritative flock")
		request_clear.rpc_id(1)
		for frame: int in range(180):
			await get_tree().physics_frame
			if not Wildlife.active:
				break
		check(not Wildlife.active, "Host cleanup replicates")
		if not failed:
			print("WILDLIFE_NETWORK_OK: late join, current pose/state, authority, cleanup")
			get_tree().quit()

# Test-only lifecycle advance. Production wildlife exposes no client request RPC.
@rpc("any_peer", "call_remote", "reliable")
func request_clear() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() in multiplayer.get_peers():
		Wildlife.clear_players()

func disconnected(_peer: int) -> void:
	if multiplayer.is_server() and not failed:
		print("WILDLIFE_NETWORK_HOST_OK")
		get_tree().quit()
