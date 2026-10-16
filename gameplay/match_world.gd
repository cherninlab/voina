extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
var players: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var hud: Label = Label.new()
var menu: VBoxContainer = VBoxContainer.new()
var address: LineEdit = LineEdit.new()
var controls_button: Button = Button.new()
var controls_panel: PanelContainer = preload("res://ui/controls_panel.gd").new()
var pve_toggle: CheckButton = CheckButton.new()
var mobs: MobSystem = MobSystem.new()

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
	mobs.name = "Mobs"
	mobs.players = players
	add_child(mobs)
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
	if pve_toggle.button_pressed or "--pve" in OS.get_cmdline_user_args():
		mobs.start()

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
	mobs.clear()
	for player: Node in players.get_children():
		player.queue_free()

func build_arena() -> void:
	add_child(preload("res://gameplay/environment/tree_pack.tscn").instantiate())
	add_prototype_props()
	add_parked_cars()
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
	controls_button.text = "Controls"
	controls_button.position = Vector2(24, 150)
	controls_button.pressed.connect(func() -> void: controls_panel.visible = not controls_panel.visible)
	canvas.add_child(controls_button)
	canvas.add_child(controls_panel)
	menu.position = Vector2(24, 195)
	menu.add_theme_constant_override("separation", 12)
	canvas.add_child(menu)
	var title: Label = Label.new()
	title.text = "MULTIPLAYER / GREYBOX\nConnect over LAN or Tailscale"
	menu.add_child(title)
	address.text = "127.0.0.1"
	address.custom_minimum_size = Vector2(320, 40)
	menu.add_child(address)
	pve_toggle.text = "PvE · 3 hostile raiders"
	menu.add_child(pve_toggle)
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
	controls_button.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if not controls_button.visible:
		controls_panel.hide()
	hud.text = "VOINA · %s\n%s melee · %s beam · %s block · %s dash · %s jump\n%s camera · %s turn · Esc release cursor" % [NetworkManager.status, InputSettings.key_label(&"melee"), InputSettings.key_label(&"beam"), InputSettings.key_label(&"block"), InputSettings.key_label(&"dash"), InputSettings.key_label(&"jump"), InputSettings.key_label(&"camera_toggle"), InputSettings.key_label(&"quick_turn")]
	var local: Node = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if local != null:
		var combat: CombatController = local.get("combat") as CombatController
		hud.text += "\nHealth %d · Stamina %d · Poise %d · %s · players %d / 4" % [combat.health, int(combat.stamina), int(combat.poise), CombatController.Phase.keys()[combat.phase], players.get_child_count()]
		if float(local.get("feedback_left")) > 0:
			hud.text += " · " + String(local.get("feedback"))
	if mobs.bodies.get_child_count() > 0 or mobs.started:
		hud.text += "\nPvE · %d raiders remaining · yellow = attack windup" % mobs.living_count()

func smoke_client() -> void:
	await get_tree().create_timer(2.0).timeout
	check(players.get_child_count() == 2, "Both players must replicate")
	var local: Node = players.get_node(str(multiplayer.get_unique_id()))
	var host: Node = players.get_node("1")
	var host_combat: CombatController = host.get_node("Combat") as CombatController
	var local_combat: CombatController = local.get_node("Combat") as CombatController
	# A client cannot attack through another player's RPC, or burst past cooldown.
	host.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	local.rpc_id(1, "request_attack", true)
	await get_tree().create_timer(0.8).timeout
	check(host_combat.health == 85, "One validated hit must replicate")
	check(local_combat.health == 100, "Forged ownership must be rejected")
	for shot: int in range(6):
		local.rpc_id(1, "request_attack", true)
		await get_tree().create_timer(0.6).timeout
	check(host_combat.health == 100, "Lethal damage must respawn at full health")
	local.set("position", (host.get("position") as Vector3) + Vector3(0, 0, -1.5))
	local.set("velocity", Vector3.ZERO)
	await get_tree().create_timer(0.7).timeout
	local.rpc_id(1, "request_attack", false)
	await get_tree().create_timer(0.7).timeout
	check(host_combat.health == 75, "A multi-tick melee swing hits each target once")
	host.rpc_id(1, "request_block", true)
	host.rpc_id(1, "request_dash", Vector3.RIGHT)
	local.rpc_id(1, "request_dash", Vector3(NAN, 0, 0))
	await get_tree().create_timer(0.2).timeout
	check(not host_combat.blocking and host_combat.phase == CombatController.Phase.IDLE, "Forged block/dash must be rejected")
	check(local_combat.phase == CombatController.Phase.IDLE, "Invalid dash vector must be rejected")
	var before_dash: float = local_combat.stamina
	var before_position: Vector3 = local.get("position") as Vector3
	local.rpc_id(1, "request_dash", Vector3.RIGHT)
	local.rpc_id(1, "request_dash", Vector3.RIGHT)
	await get_tree().create_timer(0.35).timeout
	check(local_combat.stamina <= before_dash - 33.0 and local_combat.stamina >= before_dash - 37.0, "Only one dash cost is charged")
	check((local.get("position") as Vector3).x > before_position.x + 2.0, "Accepted dash must move its owner")
	# Host rejection undoes an owner's predicted dash once stamina cannot pay for it.
	while local_combat.stamina >= CombatController.DASH_COST:
		local.rpc_id(1, "request_dash", Vector3.LEFT)
		await get_tree().create_timer(0.3).timeout
	local.set("dash_pending", true)
	local.set("dash_left", CombatController.DASH_DURATION)
	local.rpc_id(1, "request_dash", Vector3.RIGHT)
	await get_tree().create_timer(0.15).timeout
	check(float(local.get("dash_left")) == 0.0 and not bool(local.get("dash_pending")), "Rejected prediction must be cancelled")
	while local_combat.stamina < 40.0 or local_combat.phase != CombatController.Phase.IDLE:
		await get_tree().physics_frame
	await get_tree().create_timer(0.4).timeout
	local.rpc_id(1, "request_block", true)
	await get_tree().create_timer(0.15).timeout
	check(local_combat.blocking, "Block must replicate from the host")
	local.rpc_id(1, "request_block", false)
	await get_tree().create_timer(0.15).timeout
	check(not local_combat.blocking, "Block release must replicate")
	print("SMOKE_OK: spawn, hitscan, cooldown, ownership, health, respawn, melee, dash, rejection, block")
	get_tree().quit()

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("SMOKE_FAIL: " + message)
		get_tree().quit(1)

func add_prototype_props() -> void:
	var locations: Array[Vector3] = [Vector3(-8, 0, -8), Vector3(8, 0, 8), Vector3(-9, 0, 5), Vector3(9, 0, -5)]
	var names: Array[String] = ["box", "box", "pillar", "stairs"]
	for index: int in range(names.size()):
		var prop: PrototypeProp = PrototypeProp.new()
		prop.model_scene = load("res://content/environments/rgsdev/Pieces/%s.fbx" % names[index]) as PackedScene
		prop.position = locations[index]
		add_child(prop)

func add_parked_cars() -> void:
	var cars: Array[CarProp] = [
		CarProp.create("Car 05/Car5_Police.obj", "Car 05/car5_police.png"),
		CarProp.create("Car 06/Car6.obj", "Car 06/car6.png"),
		CarProp.create("Car 05/Car5_Taxi.obj", "Car 05/car5_taxi.png"),
		CarProp.create("Car 07/Car7.obj", "Car 07/car7_red.png"),
	]
	var placements: Array[Vector4] = [Vector4(0, 0, -8, 90), Vector4(0, 0, 8, 75), Vector4(-9.5, 0, -1, 4), Vector4(9.5, 0, 1, 180)]
	for index: int in range(cars.size()):
		cars[index].position = Vector3(placements[index].x, placements[index].y, placements[index].z)
		cars[index].rotation_degrees.y = placements[index].w
		add_child(cars[index])
