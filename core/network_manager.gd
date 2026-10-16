extends Node

signal status_changed(message: String)

var dedicated: bool = false
var status: String = "Choose Host or Join"
var port: int = 7777

func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: report("Connected"))
	multiplayer.connection_failed.connect(func() -> void: stop("Connection failed"))
	multiplayer.server_disconnected.connect(func() -> void: stop("Host disconnected; restart to reconnect"))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = argument.get_slice("=", 1).to_int()

func start_from_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	dedicated = "--server" in args
	if dedicated or "--host" in args:
		host_game(port)
	for argument: String in args:
		if argument.begins_with("--join="):
			join_game(argument.trim_prefix("--join="), port)

func host_game(listen_port: int = 7777) -> void:
	if not valid_port(listen_port):
		return
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(listen_port, 3 if not dedicated else 4)
	if error != OK:
		report("Cannot host: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	report("Hosting on UDP %d" % listen_port)
	get_tree().call_group("match_world", "host_started")

func join_game(address: String, target_port: int = 7777) -> void:
	if address.strip_edges().is_empty() or not valid_port(target_port):
		report("Enter a host address and valid port")
		return
	var resolved: String = IP.resolve_hostname(address.strip_edges(), IP.TYPE_IPV4)
	if resolved.is_empty():
		report("Could not resolve " + address)
		return
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(resolved, target_port)
	if error != OK:
		report("Cannot join: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	report("Connecting to " + address)

func valid_port(value: int) -> bool:
	if value < 1024 or value > 65535:
		report("Port must be between 1024 and 65535")
		return false
	return true

func report(message: String) -> void:
	status = message
	print(message)
	status_changed.emit(message)

func stop(message: String) -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().call_group("match_world", "clear_players")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	report(message)
