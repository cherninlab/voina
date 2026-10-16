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
	check(is_equal_approx(movement.replication_interval, 1.0 / 60.0), "Movement replicates at 60 Hz")
	await get_tree().physics_frame
	var here: Vector3 = hosted.position
	# What a host holds for a client one snapshot and a round trip behind.
	hosted.set("sync_position", here + Vector3(3, 0, 0))
	hosted.call("receive_hit", 25, Vector3.FORWARD, false, null)
	check(hosted.position == here, "A hit does not teleport its hosted back to a stale snapshot")
	check(hosted.velocity.is_equal_approx(Vector3.FORWARD * 5.0 + Vector3.UP * 2.0), "A hit pushes its hosted")

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
	check(int(hosted.get("corrections_sent")) == 0, "No movement corrections were needed")
	if failed:
		return
	print("NET_OK: fingerprint, auth payloads, 60 Hz movement, push knockback, remote easing")
	get_tree().quit()
