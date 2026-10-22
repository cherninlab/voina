extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const ARENA: float = 56.0 # greybox floor edge; walls sit at +/- ARENA / 2
var players: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var hud: Label = Label.new()
var menu: VBoxContainer = VBoxContainer.new()
var address: LineEdit = LineEdit.new()
var controls_button: Button = Button.new()
var controls_panel: PanelContainer = preload("res://ui/controls_panel.gd").new()
var pve_toggle: CheckButton = CheckButton.new() # possessed villagers at the church
var village_raiders_toggle: CheckButton = CheckButton.new()
var forest_raiders_toggle: CheckButton = CheckButton.new()
# The lobby's map choice; load_map() rebuilds the world for it. See gameplay/maps.gd.
var map_select: OptionButton = OptionButton.new()
var map_id: String = ""
var map_nodes: Array[Node] = []
var mobs: MobSystem
var match_toggle: CheckButton = CheckButton.new()
var match_flow: MatchFlow = MatchFlow.new()
var lobby_camera: Camera3D = Camera3D.new()
var leave_button: Button = Button.new()
var host_button: Button = Button.new()
var join_button: Button = Button.new()

func _ready() -> void:
	if "--full" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	add_to_group("match_world")
	players.name = "Players"
	add_child(players)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_limit = 4
	spawner.spawn_function = create_player
	add_child(spawner)
	lobby_camera.position = Vector3(34, 26, 38)
	add_child(lobby_camera)
	lobby_camera.look_at(Vector3.ZERO)
	lobby_camera.make_current()
	load_map(GameMaps.from_arguments(OS.get_cmdline_user_args()))
	# Lobby switches for each encounter. The church yard is haunted and raiders wait in the woods
	# unless the host opts out; raiders in the village are opt-in. In Terminal: --no-pve,
	# --no-forest-raiders, --village-raiders.
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	pve_toggle.button_pressed = not "--no-pve" in arguments
	forest_raiders_toggle.button_pressed = not "--no-forest-raiders" in arguments
	village_raiders_toggle.button_pressed = "--village-raiders" in arguments
	match_flow.name = "Match"
	match_flow.players = players
	add_child(match_flow)
	build_ui()
	apply_map_shading()
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
	# Spawns stay 6 m apart: the host's movement envelope must still accept the smoke client's hop.
	player.position = player_spawn(int(info[1]))
	player.set("sync_position", player.position)
	player.set("yaw", 0.0 if map_id != GameMaps.VILLAGE or int(info[1]) % 2 == 0 else PI)
	return player

func player_spawn(slot: int) -> Vector3:
	if map_id == GameMaps.CRYPT:
		return Vector3(-1.5 + float(slot % 2) * 3.0, 0.95, 17.0 + float(slot / 2) * 2.0)
	if map_id == GameMaps.WHITE_ROOM:
		return Vector3(-1.5 + float(slot % 2) * 3.0, 0.95, 10.0 + float(slot / 2) * 2.0)
	if map_id == GameMaps.LONG_GRASS:
		return (map_nodes[0] as LongGrass).player_spawn(slot)
	return Vector3(0, 0.95, 3.0 if slot % 2 == 0 else -3.0)

func host_started() -> void:
	menu.hide()
	if not NetworkManager.dedicated:
		spawner.spawn([1, 0])
	# The dungeons run their own encounter; the lobby's switches only shape the village.
	if map_id != GameMaps.VILLAGE:
		mobs.start()
		return
	mobs.villagers = pve_toggle.button_pressed or "--pve" in OS.get_cmdline_user_args()
	mobs.village_raiders = village_raiders_toggle.button_pressed
	mobs.forest_raiders = forest_raiders_toggle.button_pressed
	if mobs.villagers or mobs.village_raiders or mobs.forest_raiders:
		mobs.start()
	if match_toggle.button_pressed or "--match" in OS.get_cmdline_user_args():
		match_flow.start()

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
	Projectiles.clear()
	match_flow.state = MatchFlow.State.OFF
	match_flow.time_left = 0.0
	match_flow.scores.clear()
	match_flow.scores_text = "{}"
	match_flow.banner = ""
	for player: Node in players.get_children():
		player.queue_free()
	menu.show()
	controls_panel.hide()
	leave_button.hide()
	lobby_camera.make_current()

## Builds a map and its encounter in place of the current ones. The host loads its lobby choice
## before listening; a joiner loads the host's map during authentication, before anyone spawns.
func load_map(id: String) -> void:
	if not id in GameMaps.IDS:
		id = GameMaps.VILLAGE
	if map_select.item_count == GameMaps.IDS.size():
		map_select.select(GameMaps.IDS.find(id))
	if id == map_id:
		return
	map_id = id
	BuildSync.map_id = id
	# Out of the tree at once, so the replacements keep the replicated names (Mobs, ...).
	for node: Node in map_nodes:
		remove_child(node)
		node.queue_free()
	map_nodes.clear()
	if mobs != null:
		remove_child(mobs)
		mobs.queue_free()
	build_arena()
	mobs = GameMaps.create_mobs(id)
	mobs.name = "Mobs"
	mobs.players = players
	add_child(mobs)
	# Birds belong to the outdoor village only.
	if id == GameMaps.VILLAGE and not Wildlife.is_in_group("match_world"):
		Wildlife.add_to_group("match_world")
	elif id != GameMaps.VILLAGE and Wildlife.is_in_group("match_world"):
		Wildlife.remove_from_group("match_world")
	GameAudio.set_map(id)
	apply_map_shading()
	# Frame cap, render scale, sun shadows and ground cover follow Settings > Graphics.
	GraphicsSettings.register_world(self)
	print("MAP: %s (%s)" % [GameMaps.title(id), id])

func build_arena() -> void:
	if map_id == GameMaps.CRYPT:
		add_map_node(preload("res://gameplay/environment/crypt_dungeon.gd").new())
		return
	if map_id == GameMaps.WHITE_ROOM:
		add_map_node(preload("res://gameplay/environment/white_room.gd").new())
		return
	if map_id == GameMaps.LONG_GRASS:
		add_map_node(preload("res://gameplay/environment/long_grass.gd").new())
		return
	add_map_node(preload("res://gameplay/environment/village_arena.gd").new())
	# After the village, whose landscape heights they sample.
	add_map_node(preload("res://gameplay/environment/church_grounds.gd").new())
	add_map_node(preload("res://gameplay/environment/church_road.gd").new())
	add_map_node(preload("res://gameplay/environment/haunted_forest.gd").new())

# The shading layer is built after the first map (build_ui), so _ready applies this once more.
func apply_map_shading() -> void:
	for child: Node in get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path == "res://ui/shading.gd":
			child.call("set_map_theme", GameMaps.shading(map_id))

func add_map_node(node: Node) -> void:
	add_child(node)
	map_nodes.append(node)

func build_ui() -> void:
	add_child(preload("res://ui/fisheye.gd").new())
	add_child(preload("res://ui/shading.gd").new())
	add_child(preload("res://ui/datamosh.gd").new())
	add_child(preload("res://ui/game_ui.gd").new())

func _process(_delta: float) -> void:
	if not hud.visible:
		return
	hud.text = "SECHA · %s\n%s melee · %s bolt · %s block · %s dash · %s jump\n%s camera · %s turn · Esc release cursor" % [NetworkManager.status, InputSettings.key_label(&"melee"), InputSettings.key_label(&"bolt"), InputSettings.key_label(&"block"), InputSettings.key_label(&"dash"), InputSettings.key_label(&"jump"), InputSettings.key_label(&"camera_toggle"), InputSettings.key_label(&"quick_turn")]
	var local: Node = players.get_node_or_null(str(multiplayer.get_unique_id()))
	if local != null:
		var combat: CombatController = local.get("combat") as CombatController
		hud.text += "\nHealth %d · Stamina %d · Poise %d · %s · players %d / 4" % [combat.health, int(combat.stamina), int(combat.poise), CombatController.Phase.keys()[combat.phase], players.get_child_count()]
		if float(local.get("feedback_left")) > 0:
			hud.text += " · " + String(local.get("feedback"))
	if mobs.bodies.get_child_count() > 0 or (mobs.started and mobs.villagers):
		hud.text += "\nChurch yard · %d possessed villagers · they pounce if you come close" % mobs.living_count()
	if mobs.raiders.get_child_count() > 0:
		hud.text += "\nPvE · %d raiders" % mobs.living_count(mobs.raiders)

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
	check(host_combat.health == 75, "A multi-tick melee swing hits each target once (health %d, host %s, local %s, local yaw %.2f)" % [host_combat.health, host.get("position"), local.get("position"), float(local.get("yaw"))])
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
	var locations: Array[Vector3] = [Vector3(-9, 0, -9), Vector3(9, 0, 9), Vector3(-22, 0, 20), Vector3(22, 0, -20)]
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
	# Off the spawn axis (players start at z = +/-3 on x = 0) so nobody spawns against a hull.
	var placements: Array[Vector4] = [Vector4(-13, 0, -17, 90), Vector4(13, 0, 17, 75), Vector4(-23, 0, -6, 4), Vector4(23, 0, 6, 180)]
	for index: int in range(cars.size()):
		cars[index].position = Vector3(placements[index].x, placements[index].y, placements[index].z)
		cars[index].rotation_degrees.y = placements[index].w
		add_child(cars[index])
