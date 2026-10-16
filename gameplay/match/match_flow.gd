class_name MatchFlow
extends Node
## Optional host-authoritative match: countdown, 90 s rounds, first to three round wins, result and
## automatic rematch. Peer 1 runs the clock from physics delta (never Engine.time_scale) and
## replicates state, time and scores; clients only display them. A round goes to whoever lands
## the kill. On timeout a sudden-death ring closes on the centre; if it closes fully, the
## healthiest player wins the round and a tie is a draw. Combat is frozen during countdowns.
## Off unless the host enables it (menu switch or --match).

enum State { OFF, WAITING, COUNTDOWN, ROUND, ROUND_OVER, MATCH_OVER, SUDDEN_DEATH }

const COUNTDOWN_SECONDS: float = 3.0
const ROUND_SECONDS: float = 90.0
const ROUND_OVER_SECONDS: float = 3.0
const REMATCH_SECONDS: float = 10.0
const WINS_NEEDED: int = 3

var players: Node = null
var state: int = State.OFF
var time_left: float = 0.0
var scores_text: String = "{}"
var banner: String = ""
var scores: Dictionary[int, int] = {}
var label: Label = null
var ring: SuddenDeathRing = SuddenDeathRing.new()

func _ready() -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "MatchSync"
	synchronizer.set_multiplayer_authority(1)
	synchronizer.replication_interval = 0.1
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property: NodePath in [^".:state", ^".:time_left", ^".:scores_text", ^".:banner"]:
		config.add_property(property)
		config.property_set_replication_mode(property, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = config
	add_child(synchronizer)
	ring.name = "SuddenDeathRing"
	add_child(ring)
	if DisplayServer.get_name() != "headless":
		var layer: CanvasLayer = CanvasLayer.new()
		add_child(layer)
		label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.position.y += 16
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		layer.add_child(label)
	if "--match-smoke" in OS.get_cmdline_user_args():
		smoke_client()

func start() -> void:
	if multiplayer.is_server():
		scores.clear()
		enter(State.WAITING, 0.0, "Match · waiting for a second player")

func fighters() -> Array[CharacterBody3D]:
	var found: Array[CharacterBody3D] = []
	if players != null:
		for child: Node in players.get_children():
			if child is CharacterBody3D and child.get("combat") is CombatController and not child.is_queued_for_deletion():
				found.append(child as CharacterBody3D)
	return found

func combat_of(body: CharacterBody3D) -> CombatController:
	return body.get("combat") as CombatController

func name_of(peer: int) -> String:
	return "Host" if peer == 1 else "Player %d" % peer

func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and state != State.OFF:
		step(delta)
	ring.display(state == State.SUDDEN_DEATH, SuddenDeathRing.radius_at(time_left), delta)
	if label != null:
		label.visible = state != State.OFF
		label.text = display_text()

func step(delta: float) -> void:
	watch_deaths()
	var count: int = fighters().size()
	if state in [State.COUNTDOWN, State.ROUND, State.SUDDEN_DEATH] and count < 2:
		enter(State.WAITING, 0.0, "Match · waiting for a second player")
		return
	time_left = maxf(0.0, time_left - delta)
	match state:
		State.WAITING:
			if count >= 2:
				begin_round()
		State.COUNTDOWN:
			if time_left <= 0.0:
				enter(State.ROUND, ROUND_SECONDS, "Fight!")
		State.ROUND:
			if time_left <= 0.0:
				ring.reset()
				enter(State.SUDDEN_DEATH, SuddenDeathRing.CLOSE_SECONDS, "Sudden death · get inside the ring")
		State.SUDDEN_DEATH:
			ring.burn(fighters(), SuddenDeathRing.radius_at(time_left), delta)
			# A ring death may already have ended the round.
			if state == State.SUDDEN_DEATH and time_left <= 0.0:
				end_round(healthiest())
		State.ROUND_OVER:
			if time_left <= 0.0:
				begin_round()
		State.MATCH_OVER:
			if time_left <= 0.0:
				start()

func enter(next: int, seconds: float, message: String) -> void:
	state = next
	time_left = seconds
	banner = message
	scores_text = JSON.stringify(scores)
	for body: CharacterBody3D in fighters():
		combat_of(body).frozen = next in [State.COUNTDOWN, State.ROUND_OVER, State.MATCH_OVER]
		combat_of(body).locked = next == State.COUNTDOWN

# Everyone restarts the round at full health from their spawn point.
func begin_round() -> void:
	enter(State.COUNTDOWN, COUNTDOWN_SECONDS, "Round %d" % (total_rounds() + 1))
	for body: CharacterBody3D in fighters():
		combat_of(body).frozen = false
		combat_of(body).respawn()
		combat_of(body).frozen = true

func total_rounds() -> int:
	var total: int = 0
	for wins: int in scores.values():
		total += wins
	return total

func watch_deaths() -> void:
	for body: CharacterBody3D in fighters():
		var combat: CombatController = combat_of(body)
		if not combat.died.is_connected(on_died):
			combat.died.connect(on_died.bind(body.get_multiplayer_authority()))

func on_died(killer: CombatController, victim: int) -> void:
	if state not in [State.ROUND, State.SUDDEN_DEATH]:
		return
	var winner: int = 0
	for body: CharacterBody3D in fighters():
		# Server-owned mobs also have authority 1; only an actual fighter can earn credit.
		if killer == combat_of(body):
			winner = body.get_multiplayer_authority()
			break
	if winner == victim or winner == 0:
		var others: Array[CharacterBody3D] = fighters().filter(func(body: CharacterBody3D) -> bool: return body.get_multiplayer_authority() != victim)
		winner = others[0].get_multiplayer_authority() if others.size() == 1 else 0
	end_round(winner)

func healthiest() -> int:
	var best: int = 0
	var best_health: int = -1
	var tied: bool = false
	for body: CharacterBody3D in fighters():
		var health: int = combat_of(body).health
		if health > best_health:
			best = body.get_multiplayer_authority()
			best_health = health
			tied = false
		elif health == best_health:
			tied = true
	return 0 if tied else best

func end_round(winner: int) -> void:
	if winner == 0:
		enter(State.ROUND_OVER, ROUND_OVER_SECONDS, "Draw")
		return
	scores[winner] = int(scores.get(winner, 0)) + 1
	if scores[winner] >= WINS_NEEDED:
		enter(State.MATCH_OVER, REMATCH_SECONDS, "%s wins the match!" % name_of(winner))
	else:
		enter(State.ROUND_OVER, ROUND_OVER_SECONDS, "%s wins the round" % name_of(winner))

func display_text() -> String:
	var parsed: Variant = JSON.parse_string(scores_text) if scores_text.begins_with("{") else null
	var parts: PackedStringArray = PackedStringArray()
	if parsed is Dictionary:
		for key: Variant in (parsed as Dictionary).keys():
			var peer: int = int(str(key))
			var tag: String = "You" if peer == multiplayer.get_unique_id() else name_of(peer)
			parts.append("%s %d" % [tag, int((parsed as Dictionary)[key])])
	var timer: String = ""
	if state in [State.COUNTDOWN, State.ROUND, State.SUDDEN_DEATH, State.MATCH_OVER]:
		timer = " · %d s" % ceili(time_left)
	if state == State.MATCH_OVER:
		timer = " · rematch in %d s" % ceili(time_left)
	return "%s%s\n%s" % [banner, timer, " · ".join(parts) if not parts.is_empty() else "first to %d" % WINS_NEEDED]

# Two-process check: a client sees the host's countdown and then the running round.
func smoke_client() -> void:
	await get_tree().create_timer(5.5).timeout
	if state == State.ROUND and banner == "Fight!" and time_left > 80.0 and time_left < ROUND_SECONDS:
		print("MATCH_SMOKE_OK: client sees round %s with %d s left" % [banner, ceili(time_left)])
		get_tree().quit()
		return
	printerr("MATCH_SMOKE_FAIL: state %d banner %s time %.1f" % [state, banner, time_left])
	get_tree().quit(1)
