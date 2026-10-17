extends Node

var world: Node3D
var failed: bool = false
var root: Window

func _ready() -> void:
	root = get_tree().root
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("SESSION_FAIL: " + message)
		get_tree().quit(1)

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func wait_for(condition: Callable) -> bool:
	for frame: int in range(600):
		if condition.call():
			return true
		await get_tree().physics_frame
	return false

func clean_lobby() -> void:
	check((world.get("menu") as Control).visible, "Disconnect restores the lobby menu")
	check(root.get_camera_3d() != null and root.get_camera_3d() == world.get("lobby_camera"), "The lobby has a current camera")
	check((world.get("players") as Node).get_child_count() == 0, "Old players are removed")
	check((world.get("mobs") as MobSystem).bodies.get_child_count() == 0, "Old mobs are removed")
	check((world.get("match_flow") as MatchFlow).state == MatchFlow.State.OFF, "Old match presentation stops")
	check(not Wildlife.active and Projectiles.bolts.is_empty() and Projectiles.predicted.is_empty(), "Ambient and projectile state clears")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The cursor is released")

func ready_players(count: int) -> bool:
	return (world.get("players") as Node).get_child_count() == count

func encounter_ready() -> bool:
	return ready_players(2) and (world.get("mobs") as MobSystem).bodies.get_child_count() == 3

func run() -> void:
	world = preload("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	get_tree().current_scene = world
	await get_tree().process_frame
	if "--session-host" in OS.get_cmdline_user_args():
		await network_host()
	elif "--session-client" in OS.get_cmdline_user_args():
		await network_client()
	else:
		await local_checks()

func local_checks() -> void:
	check(root.get_camera_3d() != null, "Startup lobby has a camera")
	if failed:
		return
	(world.get("pve_toggle") as BaseButton).button_pressed = true
	(world.get("match_toggle") as BaseButton).button_pressed = true
	NetworkManager.host_game(NetworkManager.port)
	await frames(10)
	check(ready_players(1) and Wildlife.active, "A fresh host has a player and birds")
	var player: CharacterBody3D = (world.get("players") as Node).get_node("1") as CharacterBody3D
	var ui: CanvasLayer = world.get_node("GameUI") as CanvasLayer
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	ui.call("_input", escape)
	check(bool(ui.get("paused")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause releases local input")
	check(not get_tree().paused, "Pause menu never freezes multiplayer simulation")
	ui.call("show_controls")
	check((world.get("controls_panel") as Control).visible, "Pause opens existing controls")
	ui.call("resume")
	check(not bool(ui.get("paused")) and not (world.get("controls_panel") as Control).visible, "Resume closes menus")
	ui.call("_input", escape)
	ui.call("_input", escape)
	check(not bool(ui.get("paused")), "Escape toggles pause and resume")
	check(Projectiles.handle_fire(1, 0, player.position + HostileMob.CHEST, Vector3.UP), "Create an in-flight bolt for cleanup")
	(world.get("leave_button") as BaseButton).pressed.emit()
	await frames(4)
	clean_lobby()
	NetworkManager.host_game(NetworkManager.port)
	await frames(10)
	check(ready_players(1) and (world.get("mobs") as MobSystem).bodies.get_child_count() == 3, "The same process can host a clean encounter again")
	NetworkManager.stop("Left game")
	await frames(4)
	NetworkManager.join_game("127.0.0.1", NetworkManager.port)
	await frames(2)
	check((ui.get("loader_panel") as Control).visible, "Pending join displays an indeterminate loader")
	check((world.get("leave_button") as Button).text == "Cancel connection" and (world.get("host_button") as Button).disabled, "A pending join can be cancelled and cannot overlap another host attempt")
	(ui.get("cancel_button") as Button).pressed.emit()
	await frames(4)
	clean_lobby()
	NetworkManager.join_game("127.0.0.1", NetworkManager.port)
	await frames(2)
	# Exercise the actual failure signal handler without waiting for ENet's retry timeout.
	root.multiplayer.connection_failed.emit()
	await frames(4)
	clean_lobby()
	check(NetworkManager.status == "Connection failed", "Failure explains why the lobby returned")
	if not failed:
		print("SESSION_OK: startup camera, leave, clean rehost, cancel join, failed join recovery")
		get_tree().quit()

func network_host() -> void:
	(world.get("pve_toggle") as BaseButton).button_pressed = true
	(world.get("match_toggle") as BaseButton).button_pressed = true
	NetworkManager.host_game(NetworkManager.port)
	print("SESSION_HOST_READY")
	check(await wait_for(encounter_ready), "First client joins the encounter")
	await get_tree().create_timer(0.5).timeout
	NetworkManager.stop("Left game")
	await frames(4)
	clean_lobby()
	await get_tree().create_timer(0.25).timeout
	NetworkManager.host_game(NetworkManager.port)
	check(await wait_for(encounter_ready), "Client rejoins the restarted host")
	check(await wait_for(func() -> bool: return ready_players(1)), "The reconnected client leaves cleanly")
	if not failed:
		print("SESSION_HOST_OK: host leave, rehost, reconnect and disconnect cleanup")
		get_tree().quit()

func network_client() -> void:
	NetworkManager.join_game("127.0.0.1", NetworkManager.port)
	check(await wait_for(encounter_ready), "Initial authenticated join replicates players and mobs")
	check(await wait_for(func() -> bool: return root.multiplayer.multiplayer_peer is OfflineMultiplayerPeer), "Host leaving returns the client to offline mode")
	await frames(4)
	clean_lobby()
	await get_tree().create_timer(0.5).timeout
	NetworkManager.join_game("127.0.0.1", NetworkManager.port)
	check(await wait_for(encounter_ready), "Same client process rejoins with fresh replication")
	check(await wait_for(func() -> bool: return Wildlife.active), "Bird state returns on reconnect")
	NetworkManager.stop("Left game")
	await frames(4)
	clean_lobby()
	if not failed:
		print("SESSION_CLIENT_OK: host loss, restored lobby, authenticated reconnect and leave")
		get_tree().quit()
