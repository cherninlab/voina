extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")

var failed: bool = false

# Run as a scene so the BuildSync, NetworkManager and InputSettings autoloads exist.
func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("NET_FAIL: " + message)
		get_tree().quit(1)

func run() -> void:
	check(BuildSync.fingerprint.length() == 12 and BuildSync.fingerprint.is_valid_hex_number(), "The build fingerprint is 12 hex digits")
	check(BuildSync.compute_fingerprint() == BuildSync.fingerprint, "The build fingerprint is stable")
	check(BuildSync.decode(PackedByteArray([1, 2, 3])).is_empty() and BuildSync.decode(PackedByteArray()).is_empty(), "Malformed auth data is ignored")
	check(str(BuildSync.decode(BuildSync.encode({"fingerprint": "abc"})).get("fingerprint")) == "abc", "Auth data round-trips")

	var hosted: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	hosted.position = Vector3(0, 5, 0)
	add_child(hosted)
	var movement: MultiplayerSynchronizer = hosted.get_node("MovementSync") as MultiplayerSynchronizer
	check(movement.replication_interval == 0.0, "Movement replicates every network frame")
	await get_tree().physics_frame
	var here: Vector3 = hosted.position
	# What a host holds for a client one snapshot and a round trip behind.
	hosted.set("sync_position", here + Vector3(3, 0, 0))
	hosted.call("receive_hit", 25, Vector3.FORWARD, false, null)
	check(hosted.position == here, "A hit does not teleport its owner back to a stale snapshot")
	check(hosted.velocity.is_equal_approx(Vector3.FORWARD * 5.0 + Vector3.UP * 2.0), "A hit pushes its owner")
	hosted.set_physics_process(false)
	var host_combat: CombatController = hosted.get("combat") as CombatController
	host_combat.set_physics_process(false)
	for phase: int in [CombatController.Phase.ACTIVE, CombatController.Phase.DASHING]:
		host_combat.respawn()
		host_combat.phase = phase
		hosted.set("swing_time", 0.2 if phase == CombatController.Phase.ACTIVE else -1.0)
		hosted.set("dash_left", 0.2 if phase == CombatController.Phase.DASHING else 0.0)
		hosted.call("receive_hit", 10, Vector3.FORWARD)
		check(host_combat.phase == phase, "A non-staggering hit preserves the authoritative action")
		check(float(hosted.get("swing_time")) == (0.2 if phase == CombatController.Phase.ACTIVE else -1.0), "Non-staggering knockback preserves the owner's swing")
		check(is_equal_approx(float(hosted.get("dash_left")), 0.2 if phase == CombatController.Phase.DASHING else 0.0), "Non-staggering knockback preserves the owner's dash")
	host_combat.respawn()
	host_combat.phase = CombatController.Phase.WINDUP
	hosted.set("swing_time", 0.1)
	hosted.call("receive_hit", 10, Vector3.FORWARD)
	check(host_combat.phase == CombatController.Phase.STAGGERED and float(hosted.get("swing_time")) < 0.0, "A real windup stagger interrupts the owner")
	host_combat.respawn()
	host_combat.frozen = true
	check(not bool(hosted.call("can_predict_action", 0.0)), "Frozen match phases prevent local prediction")
	var combat_sync: MultiplayerSynchronizer = hosted.get_node("CombatSync") as MultiplayerSynchronizer
	check(combat_sync.replication_config.has_property(^"Combat:frozen"), "Clients receive the host's frozen flag")
	host_combat.frozen = false
	# Owner action identity: a reply settles only the action that carries its number.
	var owner_body: CharacterVisual = hosted.get("body") as CharacterVisual
	hosted.set("dash_action", 2)
	hosted.set("dash_pending", true)
	hosted.set("dash_left", 0.1)
	hosted.call("dash_effect", Vector3.RIGHT, 1)
	hosted.call("action_rejected", 1)
	check(bool(hosted.get("dash_pending")) and is_equal_approx(float(hosted.get("dash_left")), 0.1), "Late replies to an older dash neither acknowledge nor cancel the current one")
	hosted.call("dash_effect", Vector3.RIGHT, 2)
	check(not bool(hosted.get("dash_pending")) and is_equal_approx(float(hosted.get("dash_left")), 0.1), "A matching approval settles the predicted dash without restarting it")
	hosted.set("dash_left", 0.0)
	hosted.call("dash_effect", Vector3.RIGHT, 2)
	check(float(hosted.get("dash_left")) == 0.0, "An approval arriving after the dash ran out does not replay it")
	hosted.set("dash_action", 3)
	hosted.set("dash_pending", true)
	hosted.set("dash_left", 0.1)
	hosted.call("action_rejected", 3)
	check(not bool(hosted.get("dash_pending")) and float(hosted.get("dash_left")) == 0.0, "A matching rejection cancels the predicted dash")
	hosted.set("dash_action", 4)
	hosted.set("dash_pending", true)
	hosted.set("dash_left", 0.1)
	hosted.call("correct_position", hosted.position, Vector3.ZERO)
	hosted.call("dash_effect", Vector3.RIGHT, 4)
	check(not bool(hosted.get("dash_pending")) and float(hosted.get("dash_left")) == 0.0, "An approval arriving after a correction does not replay the dash")
	owner_body.start_swing(Vector2.LEFT)
	hosted.set("swing_action", 6)
	hosted.set("swing_pending", true)
	hosted.set("swing_time", 0.1)
	hosted.set("dash_action", 7)
	hosted.set("dash_pending", true)
	hosted.set("dash_left", 0.1)
	hosted.call("attack_effect", false, Vector2.RIGHT, 5)
	hosted.call("action_rejected", 5)
	check(bool(hosted.get("swing_pending")) and bool(hosted.get("dash_pending")) and is_equal_approx(float(hosted.get("swing_time")), 0.1) and owner_body.swing_direction.is_equal_approx(Vector2.LEFT), "Late replies to an older swing neither acknowledge nor cancel current actions")
	hosted.call("attack_effect", false, Vector2.RIGHT, 6)
	check(not bool(hosted.get("swing_pending")) and bool(hosted.get("dash_pending")) and is_equal_approx(float(hosted.get("swing_time")), 0.1) and owner_body.swing_direction.is_equal_approx(Vector2.LEFT), "A matching approval settles only its own swing and does not restart it")
	hosted.set("swing_time", -1.0)
	owner_body.cancel_swing()
	hosted.call("attack_effect", false, Vector2.RIGHT, 6)
	check(float(hosted.get("swing_time")) < 0.0 and owner_body.swing_elapsed < 0.0, "An approval arriving after the swing finished does not replay it")
	owner_body.start_swing(Vector2.UP)
	hosted.set("swing_action", 8)
	hosted.set("swing_pending", true)
	hosted.set("swing_time", 0.05)
	hosted.call("action_rejected", 8)
	check(not bool(hosted.get("swing_pending")) and float(hosted.get("swing_time")) < 0.0 and owner_body.swing_elapsed < 0.0 and bool(hosted.get("dash_pending")) and is_equal_approx(float(hosted.get("dash_left")), 0.1), "A matching rejection cancels its swing and leaves the other pending action alone")
	owner_body.start_swing(Vector2.LEFT)
	hosted.set("swing_action", 9)
	hosted.set("swing_pending", true)
	hosted.set("swing_time", 0.1)
	hosted.call("respawn")
	hosted.call("attack_effect", false, Vector2.LEFT, 9)
	check(float(hosted.get("swing_time")) < 0.0 and owner_body.swing_elapsed < 0.0 and float(hosted.get("dash_left")) == 0.0, "An approval arriving after a respawn does not replay the swing")
	hosted.call("dash_effect", Vector3.RIGHT)
	check(is_equal_approx(float(hosted.get("dash_left")), CombatController.DASH_DURATION), "An unnumbered host dash still starts")
	hosted.call("attack_effect", false, Vector2.LEFT)
	check(owner_body.swing_elapsed >= 0.0 and float(hosted.get("swing_time")) == 0.0, "An unnumbered host swing still starts")
	hosted.call("interrupt")
	host_combat.respawn()
	host_combat.clock += 1.0
	hosted.set("dash_action", 10)
	hosted.set("dash_pending", true)
	hosted.call("request_dash", Vector3.RIGHT, 10)
	check(host_combat.phase == CombatController.Phase.DASHING and not bool(hosted.get("dash_pending")) and float(hosted.get("dash_left")) == 0.0, "The host echoes the dash number with its approval")
	host_combat.respawn()
	host_combat.clock += 1.0
	hosted.set("swing_action", 11)
	hosted.set("swing_pending", true)
	hosted.call("request_attack", false, Vector2.LEFT, 11)
	check(host_combat.phase == CombatController.Phase.WINDUP and int(hosted.get("approved_action")) == 11 and not bool(hosted.get("swing_pending")) and owner_body.swing_elapsed < 0.0, "The host echoes the swing number with its approval")
	host_combat.respawn()
	hosted.call("interrupt")

	var remote: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	remote.set_multiplayer_authority(2)
	remote.position = Vector3(4, 5, 0)
	remote.set("sync_position", remote.position)
	add_child(remote)
	await get_tree().physics_frame
	check(remote.position.is_equal_approx(Vector3(4, 5, 0)), "A remote body starts where it spawned")
	remote.set("sync_position", Vector3(4.5, 5, 0))
	for frame: int in range(40):
		await get_tree().physics_frame
	check(remote.position.distance_to(Vector3(4.5, 5, 0)) < 0.01, "A host-side position write eases the remote body there")
	# Numbered effects belong to the owner's prediction; every other peer still shows them.
	remote.call("dash_effect", Vector3.RIGHT, 12)
	remote.call("attack_effect", false, Vector2.LEFT, 12)
	var remote_body: CharacterVisual = remote.get("body") as CharacterVisual
	check(is_equal_approx(float(remote.get("dash_left")), CombatController.DASH_DURATION) and remote_body.swing_elapsed >= 0.0 and remote_body.swing_direction.is_equal_approx(Vector2.LEFT), "A remote body still shows another owner's numbered dash and swing")
	check(int(hosted.get("corrections_sent")) == 0, "No movement corrections were needed")
	var lines: PackedStringArray = NetMonitor.report()
	check(lines[0] == "offline · build " + BuildSync.label() and lines[lines.size() - 1].begins_with("bolts in flight"), "The net monitor reports role, build and bolts")
	check(InputMap.has_action(&"net_overlay"), "The net overlay has a remappable key")
	if failed:
		return
	print("NET_OK: fingerprint, auth payloads, 60 Hz movement, push knockback, action identity, remote easing")
	get_tree().quit()
