extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
var players: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var hud: Label = Label.new()
var menu: VBoxContainer = VBoxContainer.new()
var address: LineEdit = LineEdit.new()

func _ready() -> void:
	add_to_group("match_world")
	Engine.max_fps = 60
	players.name = "Players"
	add_child(players)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_limit = 4
	spawner.spawn_function = create_player
	add_child(spawner)
	build_arena()
	build_ui()
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	NetworkManager.start_from_arguments()
	if "--smoke-client" in OS.get_cmdline_user_args():
		smoke_client()

func create_player(data: Variant) -> Node:
	var info: Array = data as Array
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = str(int(info[0]))
	player.set_multiplayer_authority(int(info[0]))
	player.position = Vector3(0, 0.95, 3.0 if int(info[1]) % 2 == 0 else -3.0)
	player.set("sync_position", player.position)
	player.set("yaw", 0.0 if int(info[1]) % 2 == 0 else PI)
	return player

func host_started() -> void:
	menu.hide()
	if not NetworkManager.dedicated:
		spawner.spawn([1, 0])

func peer_connected(peer_id: int) -> void:
	menu.hide()
	if multiplayer.is_server():
		spawner.spawn([peer_id, players.get_child_count()])
		print("SPAWNED ", peer_id)

func peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		var player: Node = players.get_node_or_null(str(peer_id))
		if player != null:
			player.queue_free()
			print("DESPAWNED ", peer_id)

func clear_players() -> void:
	for player: Node in players.get_children():
		player.queue_free()

func build_arena() -> void:
	box(Vector3(24, 1, 24), Vector3(0, -0.5, 0), Color("243442"))
	for location: Vector3 in [Vector3(-5, 0.6, -4), Vector3(5, 0.6, 4), Vector3(-5, 0.6, 4), Vector3(5, 0.6, -4)]:
		box(Vector3(3, 1.2, 2), location, Color("45606c"))
	for location: Vector3 in [Vector3(-12, 1, 0), Vector3(12, 1, 0)]:
		box(Vector3(0.5, 2, 24), location, Color("304654"))
	for location: Vector3 in [Vector3(0, 1, -12), Vector3(0, 1, 12)]:
		box(Vector3(24, 2, 0.5), location, Color("304654"))
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101e2b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("acc7dc")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)

func box(size: Vector3, location: Vector3, color: Color) -> void:
	var block: CSGBox3D = CSGBox3D.new()
	block.size = size
	block.position = location
	block.use_collision = true
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	block.material = material
	add_child(block)

func build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	hud.position = Vector2(24, 20)
	hud.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hud)
	menu.position = Vector2(24, 150)
	menu.add_theme_constant_override("separation", 12)
	canvas.add_child(menu)
	var title: Label = Label.new()
	title.text = "MULTIPLAYER / GREYBOX\nConnect over LAN or Tailscale"
	menu.add_child(title)
	address.text = "127.0.0.1"
	address.custom_minimum_size = Vector2(320, 40)
	menu.add_child(address)
	var host: Button = Button.new()
	host.text = "Host game"
	host.pressed.connect(func() -> void: NetworkManager.host_game(NetworkManager.port))
	menu.add_child(host)
	var join: Button = Button.new()
	join.text = "Join game"
	join.pressed.connect(func() -> void: NetworkManager.join_game(address.text, NetworkManager.port))
	menu.add_child(join)
	var reticle: Label = Label.new()
	reticle.text = "+"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	canvas.add_child(reticle)

func _process(_delta: float) -> void:
	hud.text = "MultiPlayerProject · %s\nWASD move · trackpad look · F melee · E beam · C jump\nV camera · R turn · Esc release cursor" % NetworkManager.status
	var local: Node = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if local != null:
		hud.text += "\nHealth %d / 100 · players %d / 4" % [int(local.get("health")), players.get_child_count()]

func smoke_client() -> void:
	await get_tree().create_timer(2.0).timeout
	assert(players.get_child_count() == 2, "Both players must replicate")
	var local: Node = players.get_node(str(multiplayer.get_unique_id()))
	var host: Node = players.get_node("1")
	# A client cannot attack through another player's RPC, or burst past cooldown.
	host.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	await get_tree().create_timer(0.8).timeout
	assert(int(host.get("health")) == 85, "One validated hit must replicate")
	assert(int(local.get("health")) == 100, "Forged ownership must be rejected")
	for shot: int in range(6):
		local.rpc_id(1, "request_attack", true)
		await get_tree().create_timer(0.6).timeout
	assert(int(host.get("health")) == 100, "Lethal damage must respawn at full health")
	local.set("position", (host.get("position") as Vector3) + Vector3(0, 0, -1.5))
	local.set("velocity", Vector3.ZERO)
	await get_tree().create_timer(0.7).timeout
	local.rpc_id(1, "request_attack", false)
	await get_tree().create_timer(0.7).timeout
	assert(int(host.get("health")) == 75, "Delayed melee must hit inside its cone")
	print("SMOKE_OK: spawn, hitscan, cooldown, ownership, health, respawn, melee")
	get_tree().quit()
