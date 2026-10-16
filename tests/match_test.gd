extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")

var failed: bool = false

# Run as a scene so autoloads exist. Offline peer: this process is the host.
func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("MATCH_FAIL: " + message)
		get_tree().quit(1)

func add_player(peer: int, location: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = location
	player.set("sync_position", location)
	return player

func combat(player: CharacterBody3D) -> CombatController:
	return player.get("combat") as CombatController

func place(body: CharacterBody3D, location: Vector3) -> void:
	body.position = location
	body.set("sync_position", location)

func kill(victim: CharacterBody3D, killer: CharacterBody3D) -> void:
	combat(victim).take_hit(500, false, false, combat(killer) if killer != null else null)

func run() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var players: Node3D = Node3D.new()
	players.name = "Players"
	add_child(players)
	var host: CharacterBody3D = add_player(1, Vector3(0, 0.9, 3))
	players.add_child(host)
	var flow: MatchFlow = MatchFlow.new()
	flow.players = players
	add_child(flow)
	flow.set_physics_process(false)
	await get_tree().physics_frame

	flow.start()
	flow.step(0.1)
	check(flow.state == MatchFlow.State.WAITING, "A lone host waits for a second player")
	var guest: CharacterBody3D = add_player(2, Vector3(0, 0.95, -3))
	players.add_child(guest)
	await get_tree().physics_frame
	flow.step(0.1)
	check(flow.state == MatchFlow.State.COUNTDOWN and combat(guest).frozen, "A second player starts a frozen countdown")
	check(combat(guest).take_hit(25, false, false, combat(host)) == CombatController.HitResult.EVADE and not combat(host).begin_attack(false), "Countdown blocks damage and attacks")
	check(combat(host).locked and combat(guest).locked, "The countdown locks movement")
	Input.action_press(&"move_forward")
	check(host.call(&"movement_direction") == Vector3.ZERO, "A locked owner ignores movement input")
	var spawn: Vector3 = guest.get("spawn_position")
	place(guest, spawn + Vector3(3, 0, 0))
	for frame: int in 30:
		await get_tree().physics_frame
	var held: Vector3 = guest.get("sync_position")
	check(Vector2(held.x - spawn.x, held.z - spawn.z).length() < 0.8, "The host snaps a drifting locked player back to its spawn point")
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	check(flow.state == MatchFlow.State.ROUND and not combat(host).frozen and not combat(host).locked, "The round starts after the countdown and unlocks movement")
	check(host.call(&"movement_direction") != Vector3.ZERO, "Movement input works again once the round starts")
	Input.action_release(&"move_forward")

	kill(guest, host)
	check(flow.state == MatchFlow.State.ROUND_OVER and flow.scores.get(1, 0) == 1 and combat(guest).health == CombatController.MAX_HEALTH, "A kill wins the round and the victim respawns")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	combat(guest).take_hit(30, false, false, combat(host))
	flow.step(MatchFlow.ROUND_SECONDS + 0.1)
	check(flow.state == MatchFlow.State.SUDDEN_DEATH and not combat(host).frozen and flow.display_text().contains("ring"), "Timeout starts sudden death")
	place(host, Vector3(0.5, 0.9, 0))
	place(guest, Vector3(-0.5, 0.95, 0))
	flow.step(SuddenDeathRing.CLOSE_SECONDS + 0.1)
	check(flow.scores.get(1, 0) == 2 and flow.banner == "Host wins the round" and combat(guest).health == 70, "A fully closed ring gives the round to the healthiest player and spares players inside it")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	check(combat(guest).health == CombatController.MAX_HEALTH, "Every round starts at full health")
	flow.step(MatchFlow.ROUND_SECONDS + 0.1)
	place(host, Vector3(0.5, 0.9, 0))
	place(guest, Vector3(-0.5, 0.95, 0))
	flow.step(SuddenDeathRing.CLOSE_SECONDS + 0.1)
	check(flow.banner == "Draw" and flow.total_rounds() == 2, "Equal health when the ring closes is a draw")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	kill(host, null)
	check(flow.scores.get(2, 0) == 1, "An unattributed death gives the round to the only opponent")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	flow.step(MatchFlow.ROUND_SECONDS + 0.1)
	place(host, Vector3(10, 0.9, 0))
	place(guest, Vector3(0.5, 0.95, 0))
	var elapsed: float = 0.0
	while elapsed < 5.0:
		flow.step(SuddenDeathRing.BURN_INTERVAL)
		elapsed += SuddenDeathRing.BURN_INTERVAL
	check(combat(host).health == CombatController.MAX_HEALTH, "The ring starts at the arena edge, so a player 10 m out is safe at first")
	while flow.state == MatchFlow.State.SUDDEN_DEATH and elapsed < SuddenDeathRing.CLOSE_SECONDS:
		flow.step(SuddenDeathRing.BURN_INTERVAL)
		elapsed += SuddenDeathRing.BURN_INTERVAL
	check(flow.scores.get(2, 0) == 2 and elapsed < SuddenDeathRing.CLOSE_SECONDS and combat(guest).health == CombatController.MAX_HEALTH, "The closing ring burns the player outside it to death and the opponent inside wins")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	kill(guest, host)
	check(flow.state == MatchFlow.State.MATCH_OVER and flow.banner == "Host wins the match!", "Three round wins take the match")
	check(combat(host).frozen and not combat(host).begin_attack(false), "Combat stays frozen on the result screen")
	kill(host, guest)
	check(flow.scores.get(2, 0) == 2, "Deaths after the match do not score")
	flow.step(MatchFlow.REMATCH_SECONDS + 0.1)
	flow.step(0.1)
	check(flow.state == MatchFlow.State.COUNTDOWN and flow.scores.is_empty(), "A rematch starts with fresh scores")
	guest.queue_free()
	await get_tree().physics_frame
	flow.step(0.1)
	check(flow.state == MatchFlow.State.WAITING and not combat(host).frozen, "A leaving opponent returns the match to waiting")
	check(flow.display_text().contains("waiting"), "The banner explains the state")
	var second: CharacterBody3D = add_player(2, Vector3(0, 0.95, -3))
	var third: CharacterBody3D = add_player(3, Vector3(3, 0.95, 0))
	players.add_child(second)
	players.add_child(third)
	flow.start()
	flow.step(0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	var npc: CharacterBody3D = CharacterBody3D.new()
	add_child(npc)
	var npc_combat: CombatController = CombatController.new()
	npc.add_child(npc_combat)
	combat(second).take_hit(500, false, false, npc_combat)
	check(flow.scores.is_empty() and flow.banner == "Draw", "An NPC sharing peer 1 cannot earn the host a round in a three-player match")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	kill(third, second)
	check(flow.scores.get(2, 0) == 1, "Actual fighter identity still credits a three-player kill")
	if failed:
		return
	print("MATCH_OK: waiting, frozen and movement-locked countdown, kill rounds, sudden-death ring burn and closed-ring healthiest/draw, first to three, result freeze, rematch, leaver")
	get_tree().quit()
