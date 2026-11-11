extends Node3D

var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("SPAWN_SLOT_FAIL: " + message)

func run() -> void:
	var world: Node3D = preload("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	var original_map: String = str(world.get("map_id"))
	world.set("map_id", GameMaps.VILLAGE)
	var starts: Array[Vector3] = []
	for slot: int in range(4):
		var start: Vector3 = world.call("player_spawn", slot) as Vector3
		for previous: Vector3 in starts:
			check(start.distance_to(previous) >= 2.0, "Four village spawn slots must be distinct")
		starts.append(start)
	world.set("map_id", original_map)
	if failed:
		get_tree().quit(1)
		return
	var players: Node3D = world.get("players") as Node3D
	var flow: MatchFlow = world.get("match_flow") as MatchFlow
	var peers: Array[int] = [1, 2, 3, 4]
	for peer: int in peers:
		var slot: int = int(world.call("next_spawn_slot"))
		check(slot == peer - 1, "Opening players receive vacant consecutive slots")
		var player: CharacterBody3D = world.call("create_player", [peer, slot]) as CharacterBody3D
		players.add_child(player)
		player.set_physics_process(false)
		(player.get("combat") as CombatController).set_physics_process(false)
	check(int(world.call("next_spawn_slot")) == -1, "A full session has no spare slot")
	players.get_node("2").queue_free()
	check(int(world.call("next_spawn_slot")) == 1, "A departing middle peer releases its own slot")
	await get_tree().process_frame
	var replacement: CharacterBody3D = world.call("create_player", [5, int(world.call("next_spawn_slot"))]) as CharacterBody3D
	players.add_child(replacement)
	replacement.set_physics_process(false)
	(replacement.get("combat") as CombatController).set_physics_process(false)
	check(int(replacement.get_meta("spawn_slot")) == 1, "Replacement uses the vacant slot, not the occupied last slot")
	for player: Node in players.get_children():
		player.free()
	for phase: int in [MatchFlow.State.COUNTDOWN, MatchFlow.State.ROUND_OVER, MatchFlow.State.MATCH_OVER, MatchFlow.State.ROUND]:
		flow.enter(phase, 3.0, "Spawn regression")
		var joining: CharacterBody3D = world.call("create_player", [6, 0]) as CharacterBody3D
		var combat: CombatController = joining.get("combat") as CombatController
		check(combat.frozen == (phase != MatchFlow.State.ROUND), "Spawn inherits combat freeze before entering the tree")
		check(combat.locked == (phase == MatchFlow.State.COUNTDOWN), "Spawn inherits countdown lock before entering the tree")
		players.add_child(joining)
		joining.free()
	world.queue_free()
	await get_tree().process_frame
	if not failed:
		print("SPAWN_SLOT_OK: four starts, vacant slot reuse, full capacity and immediate match rules")
	get_tree().quit(1 if failed else 0)
