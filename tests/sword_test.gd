extends Node

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
var failures: int = 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("SWORD_FAIL: " + message)

func run() -> void:
	if "--sword-network" in OS.get_cmdline_user_args():
		await network_checks()
		return
	var gesture: DragGesture = DragGesture.new()
	check(gesture.move(Vector2(100, 0)) == Vector2.ZERO, "Look without a press cannot attack")
	gesture.begin()
	check(gesture.move(Vector2(10, 0)) == Vector2.ZERO, "A short drag cannot attack")
	gesture.cancel()
	gesture.begin()
	check(gesture.move(Vector2(30, 0)) == Vector2.ZERO, "Release clears accumulated motion")
	check(gesture.move(Vector2(0, 30)).is_equal_approx(Vector2(1, 1).normalized()), "Drag crosses threshold with diagonal cut")
	check(gesture.move(Vector2(-100, 0)) == Vector2.ZERO, "One swing per hold")
	gesture.cancel()
	gesture.begin()
	check(gesture.move(Vector2(NAN, 0)) == Vector2.ZERO, "Nonfinite motion is ignored")
	check(gesture.move(Vector2(-40, 0)) == Vector2.LEFT, "A new press rearms")
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child(player)
	player.set_physics_process(false)
	var combat: CombatController = player.get("combat") as CombatController
	combat.set_physics_process(false)
	var body: CharacterVisual = player.get("body") as CharacterVisual
	if DisplayServer.get_name() != "headless":
		# Exercise the actual input route, including cursor recapture and camera suppression.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		player.call("_unhandled_input", click)
		var routed_gesture: DragGesture = player.get("drag_gesture") as DragGesture
		check(not routed_gesture.held and combat.stamina == 100.0, "Recapture click does not arm or attack")
		var press: InputEventAction = InputEventAction.new()
		press.action = &"melee"
		press.pressed = true
		player.call("_unhandled_input", press)
		check(routed_gesture.held and combat.stamina == 100.0, "Press only arms")
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.screen_relative = Vector2(15, 0)
		player.call("_unhandled_input", motion)
		check(combat.stamina == 100.0, "Jitter does not spend stamina")
		motion.screen_relative = Vector2(25, 0)
		player.call("_unhandled_input", motion)
		check(combat.stamina == 82.0 and float(player.get("yaw")) == 0.0, "Drag attacks while camera remains still")
		player.call("_unhandled_input", motion)
		check(combat.stamina == 82.0, "Further drag cannot repeat")
		press.pressed = false
		player.call("_unhandled_input", press)
		player.call("_unhandled_input", motion)
		check(not routed_gesture.held and float(player.get("yaw")) < 0.0, "Release restores camera look")
	combat.respawn()
	combat.clock += 1.0
	for invalid: Vector2 in [Vector2.ZERO, Vector2(NAN, 0), Vector2(INF, 1), Vector2(100, 0)]:
		player.call("request_attack", false, invalid)
	check(combat.stamina == 100.0 and combat.phase == CombatController.Phase.IDLE, "Invalid requests cannot spend stamina or begin a swing")
	player.call("request_attack", false, Vector2(-1.5, 0))
	check(body.swing_direction.is_equal_approx(Vector2.LEFT), "Host normalizes accepted direction")
	check(combat.stamina == 82.0 and combat.phase == CombatController.Phase.WINDUP, "Host charges one attack")
	player.call("request_attack", false, Vector2.RIGHT)
	check(combat.stamina == 82.0 and body.swing_direction == Vector2.LEFT, "Repeated requests cannot change an active swing")
	var input_gesture: DragGesture = player.get("drag_gesture") as DragGesture
	input_gesture.begin()
	player.call("release_input")
	check(not input_gesture.held, "Cursor release cancels gesture")
	input_gesture.begin()
	player.call("set_camera_mode", false)
	check(not input_gesture.held, "Camera change cancels gesture")
	body.start_swing(Vector2.UP)
	player.set("swing_pending", true)
	player.set("swing_time", 0.05)
	player.call("cancel_prediction")
	check(body.swing_elapsed < 0.0 and float(player.get("swing_time")) < 0.0, "Host rejection cancels predicted visual and movement")
	player.queue_free()
	await get_tree().process_frame
	for variant: String in ["male", "female"]:
		var scene: PackedScene = load("res://content/characters/quaternius/%s.tscn" % variant) as PackedScene
		var visual: CharacterVisual = scene.instantiate() as CharacterVisual
		add_child(visual)
		visual.playback.pause()
		visual.update_pose(0.0, Vector3.ZERO, false, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var tip: Vector3 = visual.to_local(visual.sword.to_global(CharacterVisual.BLADE_TIP))
		check(tip.z > 1.0 and absf(tip.y + 0.85) < 0.03, variant + " blade trails behind at ground level")
		check_grip(visual, false, variant + " idle")
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
			visual.start_swing(direction)
			for elapsed: float in [0.15, 0.21, 0.269]:
				visual.swing_elapsed = elapsed
				visual.update_pose(0.0, Vector3.ZERO, false, false)
				await get_tree().process_frame
				await get_tree().process_frame
				check_grip(visual, true, "%s cut %s at %.3f" % [variant, direction, elapsed])
		visual.update_pose(0.01, Vector3.ZERO, false, true)
		check(visual.swing_elapsed < 0.0, "Stagger cancels sword presentation")
		visual.set_first_person(true)
		for mesh: MeshInstance3D in visual.meshes:
			check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "First-person body keeps shadows")
		for mesh: MeshInstance3D in visual.sword_meshes:
			check(mesh.visible and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "First-person sword stays visible")
		visual.queue_free()
	if failures == 0:
		print("SWORD_OK: gesture rearm/cancel, request validation, cooldown, prediction cancellation, both hand IK rigs")
	get_tree().quit(0 if failures == 0 else 1)

func check_grip(visual: CharacterVisual, both: bool, label: String) -> void:
	var right_target: Vector3 = visual.sword.to_global(Vector3(0.065, 0, 0.06))
	var left_target: Vector3 = visual.sword.to_global(Vector3(-0.065, 0, 0.23))
	var right_error: float = visual.ik.last_right_hand.distance_to(right_target)
	var left_error: float = visual.ik.last_left_hand.distance_to(left_target)
	check(right_error < 0.06, "%s right grip error %.3f m" % [label, right_error])
	if both:
		check(left_error < 0.06, "%s left grip error %.3f m" % [label, left_error])

func network_checks() -> void:
	var scene: PackedScene = load("res://gameplay/match_world.tscn") as PackedScene
	var world: Node3D = scene.instantiate() as Node3D
	add_child(world)
	await get_tree().create_timer(2.0).timeout
	if multiplayer.is_server():
		return
	var players: Node = world.get_node("Players")
	check(players.get_child_count() == 2, "Network players replicate")
	var local: Node = players.get_node(str(multiplayer.get_unique_id()))
	var host: Node = players.get_node("1")
	var local_combat: CombatController = local.get_node("Combat") as CombatController
	var host_combat: CombatController = host.get_node("Combat") as CombatController
	var local_body: CharacterVisual = local.get("body") as CharacterVisual
	var host_body: CharacterVisual = host.get("body") as CharacterVisual
	host.rpc_id(1, "request_attack", false, Vector2.LEFT)
	local.rpc_id(1, "attack_effect", false, Vector2.LEFT)
	for invalid: Vector2 in [Vector2.ZERO, Vector2(NAN, 0), Vector2(INF, 1), Vector2(100, 0)]:
		local.rpc_id(1, "request_attack", false, invalid)
	await get_tree().create_timer(0.2).timeout
	check(local_combat.stamina == 100.0 and host_combat.stamina == 100.0, "Forged/invalid network attacks rejected")
	check(local_body.swing_elapsed < 0.0 and host_body.swing_elapsed < 0.0, "Forged effect cannot animate a swing")
	local.rpc_id(1, "request_attack", false, Vector2(-1.5, 0))
	local.rpc_id(1, "request_attack", false, Vector2.RIGHT)
	await get_tree().create_timer(0.12).timeout
	check(local_body.swing_direction == Vector2.LEFT, "Host-approved normalized direction broadcasts to owner")
	check(local_body.swing_elapsed >= 0.0, "Accepted sword animates")
	check(local_combat.stamina == 82.0, "Only one network attack spends stamina")
	if failures == 0:
		print("SWORD_NETWORK_OK: ownership, finite vectors, effect authentication, direction broadcast, cooldown")
	get_tree().quit(0 if failures == 0 else 1)
