extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	(world.get("mobs") as MobSystem).clear() # Keep this network ordering check free of PvE hits.
	if "--host" in OS.get_cmdline_user_args():
		await create_timer(40).timeout
		quit(1)
		return
	var players: Node3D = world.get("players") as Node3D
	var deadline: int = Time.get_ticks_msec() + 30000
	while players.get_child_count() < 2 and Time.get_ticks_msec() < deadline:
		await physics_frame
	if players.get_child_count() < 2:
		printerr("PREDICTION_LATENCY_FAIL: players did not replicate")
		quit(1)
		return
	await create_timer(1.0).timeout
	var player: CharacterBody3D = players.get_node(str(get_multiplayer().get_unique_id())) as CharacterBody3D
	player.call("dash")
	await create_timer(0.35).timeout
	deadline = Time.get_ticks_msec() + 3000
	while not bool(player.call("can_predict_action", 35.0)) and Time.get_ticks_msec() < deadline:
		await physics_frame
	if not bool(player.call("can_predict_action", 35.0)):
		printerr("PREDICTION_LATENCY_FAIL: second dash was not eligible")
		quit(1)
		return
	if "--delayed-approvals" in OS.get_cmdline_user_args() and not bool(player.get("dash_pending")):
		printerr("PREDICTION_LATENCY_FAIL: delayed case did not overlap outstanding approvals")
		quit(1)
		return
	player.call("dash")
	var dash_expired: bool = false
	var replayed: bool = false
	var end: int = Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < end:
		await physics_frame
		var left: float = float(player.get("dash_left"))
		if dash_expired and left > 0.0:
			replayed = true
		if left <= 0.0:
			dash_expired = true
	# A reply later than the whole predicted swing must not start another swing.
	if not bool(player.call("can_predict_action", 18.0)):
		printerr("PREDICTION_LATENCY_FAIL: melee was not eligible")
		quit(1)
		return
	player.call("attack", false, Vector2.LEFT)
	var swing_expired: bool = false
	end = Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < end:
		await physics_frame
		var elapsed: float = float(player.get("swing_time"))
		if swing_expired and elapsed >= 0.0:
			replayed = true
		if elapsed < 0.0:
			swing_expired = true
	var rtt: float = float(root.get_node("NetworkManager").call("round_trip_seconds", 1))
	root.get_node("NetworkManager").call("stop", "prediction latency check complete")
	if replayed or not dash_expired or not swing_expired:
		printerr("PREDICTION_LATENCY_FAIL: completed prediction replayed")
		quit(1)
		return
	print("PREDICTION_LATENCY_OK: two dashes and melee acknowledged once, RTT %.3f s" % rtt)
	quit()
