extends Node
## Debug builds only play against the same build. The fingerprint hashes every gameplay script,
## scene, resource and project setting, so uncommitted agent edits count as a different build.
## Peers compare it during SceneMultiplayer authentication, before peer_connected, so a
## mismatched joiner never spawns. Release builds and --allow-version-mismatch skip source checks;
## map agreement is always required.
## See docs/playtest.md.

const SOURCES: Array[String] = ["res://core", "res://gameplay", "res://ui"]
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]

var fingerprint: String = ""
var commit: String = "unknown"
var enforced: bool = false
var expecting_refusal: bool = false
var map_id: String = "crypt" if "--dungeon" in OS.get_cmdline_user_args() else "village"

func _ready() -> void:
	commit = describe_commit()
	fingerprint = compute_fingerprint()
	var override: String = user_arg("--fake-build=")
	if OS.is_debug_build() and not override.is_empty():
		fingerprint = override
	print("BUILD: " + label())
	enforced = OS.is_debug_build() and not ("--allow-version-mismatch" in OS.get_cmdline_user_args())
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	# Map agreement remains mandatory in exports and with --allow-version-mismatch.
	if scene_multiplayer == null:
		return
	scene_multiplayer.auth_callback = receive_auth
	scene_multiplayer.auth_timeout = 5.0
	scene_multiplayer.peer_authenticating.connect(authenticating)
	scene_multiplayer.peer_authentication_failed.connect(authentication_failed)
	expecting_refusal = "--expect-version-mismatch" in OS.get_cmdline_user_args()
	if expecting_refusal:
		multiplayer.connected_to_server.connect(func() -> void: refusal_check_failed("Joined a host running another build"))
		get_tree().create_timer(8.0).timeout.connect(func() -> void: refusal_check_failed("No build refusal within 8 s"))

func label() -> String:
	return "%s [%s]" % [commit, fingerprint]

func user_arg(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func describe_commit() -> String:
	if not OS.is_debug_build():
		return str(ProjectSettings.get_setting("application/config/version", "release"))
	var root: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	if OS.execute("git", ["-C", root, "rev-parse", "--short", "HEAD"], output) != 0 or output.is_empty():
		return "unknown"
	var short: String = str(output[0]).strip_edges()
	output.clear()
	OS.execute("git", ["-C", root, "status", "--porcelain", "--", "core", "gameplay", "ui", "project.godot"], output)
	var dirty: bool = not output.is_empty() and not str(output[0]).strip_edges().is_empty()
	return short + ("+dirty" if dirty else "")

func compute_fingerprint() -> String:
	var files: Array[String] = []
	for source: String in SOURCES:
		collect(source, files)
	files.append("res://project.godot")
	files.sort()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in files:
		context.update(path.to_utf8_buffer())
		# Exported games keep only compiled scripts, so a source file may read back empty.
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			context.update(bytes)
	return context.finish().hex_encode().left(12)

func collect(directory: String, files: Array[String]) -> void:
	var access: DirAccess = DirAccess.open(directory)
	if access == null:
		return
	for file: String in access.get_files():
		if file.get_extension() in EXTENSIONS:
			files.append(directory.path_join(file))
	for child: String in access.get_directories():
		collect(directory.path_join(child), files)

static func encode(info: Dictionary) -> PackedByteArray:
	return var_to_bytes(info)

# Only payloads headed as a dictionary reach the variant decoder, so garbage is ignored quietly.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 8 or (data.decode_u32(0) & 0xFF) != TYPE_DICTIONARY:
		return {}
	var value: Variant = bytes_to_var(data)
	return value as Dictionary if value is Dictionary else {}

# The joining side speaks first; the host answers after comparing.
func authenticating(peer: int) -> void:
	if not multiplayer.is_server():
		(multiplayer as SceneMultiplayer).send_auth(peer, encode({"fingerprint": fingerprint, "commit": commit, "map": map_id}))

func receive_auth(peer: int, data: PackedByteArray) -> void:
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	var info: Dictionary = decode(data)
	var remote_fingerprint: String = str(info.get("fingerprint", ""))
	var remote_commit: String = str(info.get("commit", "unknown"))
	var remote_map: String = str(info.get("map", "village"))
	if multiplayer.is_server():
		var matches: bool = remote_map == map_id and (not enforced or (not remote_fingerprint.is_empty() and remote_fingerprint == fingerprint))
		scene_multiplayer.send_auth(peer, encode({"fingerprint": fingerprint, "commit": commit, "map": map_id, "accepted": matches}))
		if matches:
			scene_multiplayer.complete_auth(peer)
		else:
			print("BUILD_REFUSED: peer %d runs %s [%s]; host runs %s" % [peer, remote_commit, remote_fingerprint, label()])
			NetworkManager.report("Refused a player on build %s; you run %s" % [remote_commit, label()])
		return
	if bool(info.get("accepted", false)):
		scene_multiplayer.complete_auth(peer)
		return
	if remote_map != map_id:
		var map_message: String = "Host map is %s; your map is %s. Restart %s --dungeon on both host and joiner." % [remote_map, map_id, "with" if remote_map == "crypt" else "without"]
		print("MAP_MISMATCH: " + map_message)
		NetworkManager.stop(map_message)
		if expecting_refusal:
			print("VERSION_MISMATCH_OK: map refused before spawn")
			get_tree().quit()
		return
	var message: String = "Host runs %s [%s], you run %s. Run: python3 scripts/playtest.py sync --commit %s" % [remote_commit, remote_fingerprint, label(), remote_commit.trim_suffix("+dirty")]
	print("VERSION_MISMATCH: " + message)
	NetworkManager.stop(message)
	if expecting_refusal:
		print("VERSION_MISMATCH_OK: refused before spawn by host build " + remote_commit)
		get_tree().quit()

func authentication_failed(peer: int) -> void:
	if multiplayer.is_server():
		print("BUILD_REFUSED: peer %d left before proving a matching build" % peer)
	elif NetworkManager.status.begins_with("Connecting"):
		NetworkManager.stop("The host did not answer the build check (older build?). Sync both copies: python3 scripts/playtest.py sync")

func refusal_check_failed(message: String) -> void:
	printerr("VERSION_MISMATCH_FAIL: " + message)
	get_tree().quit(1)
