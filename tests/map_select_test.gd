extends Node3D
## Host side: picks each map from the lobby and hosts it in one process (white room, crypt,
## village), checking the world, encounter and endless white-room raiders. Joiner side (--join):
## starts on its own map and must arrive on the host's (--expect-map=ID).

var world: Node3D
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func check(condition: bool, message: String) -> void:
	if not condition and not failed:
		failed = true
		printerr("MAP_SELECT_FAIL: " + message)
		get_tree().quit(1)

func wait_for(condition: Callable, limit: int = 900) -> bool:
	for frame: int in range(limit):
		if condition.call():
			return true
		await get_tree().physics_frame
	return false

func mobs() -> MobSystem:
	return world.get("mobs") as MobSystem

func players() -> Node3D:
	return world.get("players") as Node3D

func run() -> void:
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	await frames(10)
	if not BuildSync.user_arg("--join=").is_empty():
		await joiner()
		return
	check(str(world.get("map_id")) == GameMaps.VILLAGE and world.has_node("WoodlandVillage") and Wildlife.is_in_group("match_world"), "The lobby starts on the village")
	await host_map(GameMaps.WHITE_ROOM)
	check(world.has_node("WhiteRoom") and not world.has_node("WoodlandVillage") and not world.has_node("CinderCrypt"), "Only the white room is built")
	check(not Wildlife.is_in_group("match_world") and not Wildlife.active, "No birds indoors")
	check(mobs().name == "Mobs" and mobs().get("felled") != null, "The replacement encounter keeps the replicated name")
	check(mobs().raiders.get_child_count() == WaveMobs.OPENING, "The white room opens with %d raiders" % WaveMobs.OPENING)
	for node: Node in mobs().raiders.get_children():
		check(not (node as RaiderMob).visual.get("cultist"), "White room raiders are the classic, unhooded kind")
	print("MAP_SELECT_HOST_READY: white room")
	check(await wait_for(func() -> bool: return players().get_child_count() == 2, 1200), "A joiner on another map spawns in the white room")
	check(await wait_for(func() -> bool: return players().get_child_count() == 1, 1200), "The joiner leaves")
	# One more arrives every SPAWN_INTERVAL; then fell every one of them at once.
	check(await wait_for(func() -> bool: return mobs().raiders.get_child_count() > WaveMobs.OPENING, 600), "Raiders keep arriving")
	var killed: int = mobs().raiders.get_child_count()
	check(killed <= WaveMobs.MAX_ALIVE, "Raiders stop at the cap (%d)" % killed)
	for node: Node in mobs().raiders.get_children():
		(node as HostileMob).receive_hit(999, Vector3.FORWARD)
	await frames(10)
	check(int(mobs().get("felled")) >= killed and int(mobs().get("alive")) == 0, "Felled raiders are counted (%d felled, %d alive)" % [int(mobs().get("felled")), int(mobs().get("alive"))])
	check(await wait_for(func() -> bool: return int(mobs().get("alive")) >= 2, 900), "Raiders keep coming after the room is cleared")
	await host_map(GameMaps.CRYPT)
	check(world.has_node("CinderCrypt") and not world.has_node("WhiteRoom") and mobs().name == "Mobs", "The crypt replaces the white room")
	check(mobs().raiders.get_child_count() == 5 and int(mobs().get("remaining")) == 5, "The crypt starts its five cultists")
	await host_map(GameMaps.VILLAGE)
	check(world.has_node("WoodlandVillage") and not world.has_node("CinderCrypt") and Wildlife.is_in_group("match_world"), "The village comes back, birds included")
	# Birds start only when the world is the main scene (Wildlife.host_started); here it is not.
	check(await wait_for(func() -> bool: return mobs().bodies.get_child_count() == MobSystem.COUNT, 600), "The village encounter starts")
	if not failed:
		print("MAP_SELECT_OK: lobby picks white room, crypt and village; endless raiders; joiner adopts the host map")
		get_tree().quit()

# Leave any running game, pick the map in the lobby as a player would and press Start game.
func host_map(id: String) -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		NetworkManager.stop("Left game")
		await frames(3)
	var select: OptionButton = world.get("map_select") as OptionButton
	select.select(GameMaps.IDS.find(id))
	select.item_selected.emit(select.selected)
	(world.get("host_button") as Button).pressed.emit()
	await frames(20)
	check(str(world.get("map_id")) == id and BuildSync.map_id == id, "Hosting %s loads it" % id)
	check(players().get_child_count() == 1, "The host spawns on %s" % id)

func joiner() -> void:
	var expected: String = BuildSync.user_arg("--expect-map=")
	check(await wait_for(func() -> bool: return players().get_child_count() == 2, 1800), "The joiner spawns")
	await frames(30)
	check(str(world.get("map_id")) == expected and BuildSync.map_id == expected, "The joiner plays the host's map %s (has %s)" % [expected, world.get("map_id")])
	if expected == GameMaps.WHITE_ROOM:
		check(world.has_node("WhiteRoom") and not world.has_node("WoodlandVillage") and not world.has_node("CinderCrypt"), "The joiner built the white room only")
		check(mobs().raiders.get_child_count() >= WaveMobs.OPENING, "The joiner sees the host's raiders")
	elif expected == GameMaps.VILLAGE:
		check(world.has_node("WoodlandVillage") and not world.has_node("CinderCrypt"), "The joiner rebuilt the village")
	if not failed:
		print("MAP_SELECT_CLIENT_OK: adopted %s" % expected)
		get_tree().quit()
