extends Node

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")

# Run as a scene so NetworkManager and InputSettings autoloads exist.
func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("STAGGER_FAIL: " + message)
		get_tree().quit(1)

func run() -> void:
	# Offline peer: this process is peer 1 and the player belongs to a remote peer.
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = "2"
	player.set_multiplayer_authority(2)
	add_child(player)
	var combat: CombatController = player.get("combat") as CombatController
	await get_tree().physics_frame
	combat.stagger()
	await get_tree().physics_frame
	player.set("sync_position", Vector3(1.0, 0.0, 0.0))
	await get_tree().physics_frame
	check(player.get("sync_position") == Vector3(1.0, 0.0, 0.0), "Knockback-sized drift is allowed")
	player.set("sync_position", Vector3(6.0, 0.0, 0.0))
	await get_tree().physics_frame
	var corrected: Vector3 = player.get("sync_position") as Vector3
	check(corrected.x < 3.0 and corrected.x > 2.0, "Walking through stagger is clamped")
	combat.step(1.0)
	await get_tree().physics_frame
	player.set("sync_position", Vector3(6.0, 0.0, 0.0))
	await get_tree().physics_frame
	check(player.get("sync_position") == Vector3(6.0, 0.0, 0.0), "Movement is free after stagger")
	print("STAGGER_OK: drift allowance, clamp, release")
	get_tree().quit()
