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
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	check(flow.state == MatchFlow.State.ROUND and not combat(host).frozen, "The round starts after the countdown")

	kill(guest, host)
	check(flow.state == MatchFlow.State.ROUND_OVER and flow.scores.get(1, 0) == 1 and combat(guest).health == CombatController.MAX_HEALTH, "A kill wins the round and the victim respawns")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	combat(guest).take_hit(30, false, false, combat(host))
	flow.step(MatchFlow.ROUND_SECONDS + 0.1)
	check(flow.scores.get(1, 0) == 2 and flow.banner == "Host wins the round", "On timeout the healthiest player wins the round")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	check(combat(guest).health == CombatController.MAX_HEALTH, "Every round starts at full health")
	flow.step(MatchFlow.ROUND_SECONDS + 0.1)
	check(flow.banner == "Draw" and flow.total_rounds() == 2, "Equal health at timeout is a draw")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	kill(host, null)
	check(flow.scores.get(2, 0) == 1, "An unattributed death gives the round to the only opponent")
	flow.step(MatchFlow.ROUND_OVER_SECONDS + 0.1)
	flow.step(MatchFlow.COUNTDOWN_SECONDS + 0.1)
	kill(guest, host)
	check(flow.state == MatchFlow.State.MATCH_OVER and flow.banner == "Host wins the match!", "Three round wins take the match")
	check(combat(host).frozen and not combat(host).begin_attack(false), "Combat stays frozen on the result screen")
	kill(host, guest)
	check(flow.scores.get(2, 0) == 1, "Deaths after the match do not score")
	flow.step(MatchFlow.REMATCH_SECONDS + 0.1)
	flow.step(0.1)
	check(flow.state == MatchFlow.State.COUNTDOWN and flow.scores.is_empty(), "A rematch starts with fresh scores")
	guest.queue_free()
	await get_tree().physics_frame
	flow.step(0.1)
	check(flow.state == MatchFlow.State.WAITING and not combat(host).frozen, "A leaving opponent returns the match to waiting")
	check(flow.display_text().contains("waiting"), "The banner explains the state")
	if failed:
		return
	print("MATCH_OK: waiting, frozen countdown, kill and timeout rounds, draw, first to three, result freeze, rematch, leaver")
	get_tree().quit()
