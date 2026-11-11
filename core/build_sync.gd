extends Node
## Debug builds only play against the same build. The fingerprint covers every file Git sees
## under core/, gameplay/, ui/ and content/ plus project.godot (scripts, scenes, maps, collision,
## assets), so uncommitted agent edits count as a different build. Unchanged files reuse the
## object IDs in the Git index; only modified and untracked files are hashed at startup.
## Peers compare it during SceneMultiplayer authentication, before peer_connected, so a
## mismatched joiner never spawns. Release builds and --allow-version-mismatch skip source checks.
## The host's answer also names its map, which the joiner loads before completing authentication.
## See docs/playtest.md.

const SOURCES: Array[String] = ["res://core", "res://gameplay", "res://ui"]
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
const IDENTITY_PATHS: Array[String] = ["core", "gameplay", "ui", "content", "project.godot"]
const HASH_BATCH: int = 128
const ESCAPES: Dictionary[int, int] = {0x61: 7, 0x62: 8, 0x66: 12, 0x6E: 10, 0x72: 13, 0x74: 9, 0x76: 11}

var fingerprint: String = "" # empty when the identity could not be read; never matches a peer
var identity_error: String = ""
var commit: String = "unknown"
var enforced: bool = false
var expecting_refusal: bool = false
var map_id: String = GameMaps.VILLAGE # set by MatchWorld.load_map

func _ready() -> void:
	commit = describe_commit()
	fingerprint = compute_fingerprint()
	if fingerprint.is_empty():
		printerr("BUILD_IDENTITY_FAIL: %s. Build checks refuse this copy; fix Git or launch with -- --allow-version-mismatch." % identity_error)
	var override: String = user_arg("--fake-build=")
	if OS.is_debug_build() and not override.is_empty():
		fingerprint = override
	print("BUILD: " + label())
	enforced = OS.is_debug_build() and not ("--allow-version-mismatch" in OS.get_cmdline_user_args())
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	scene_multiplayer.auth_callback = receive_auth
	# Room for a joiner to build the host's map (the village takes a few seconds) inside the check.
	scene_multiplayer.auth_timeout = 30.0
	scene_multiplayer.peer_authenticating.connect(authenticating)
	scene_multiplayer.peer_authentication_failed.connect(authentication_failed)
	expecting_refusal = "--expect-version-mismatch" in OS.get_cmdline_user_args()
	if expecting_refusal:
		multiplayer.connected_to_server.connect(func() -> void: refusal_check_failed("Joined a host running another build"))
		get_tree().create_timer(8.0).timeout.connect(func() -> void: refusal_check_failed("No build refusal within 8 s"))

func label() -> String:
	return "%s [%s]" % [commit, "unverified" if fingerprint.is_empty() else fingerprint]

func user_arg(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func describe_commit() -> String:
	if not OS.is_debug_build():
		return str(ProjectSettings.get_setting("application/config/version", "release"))
	var root: String = ProjectSettings.globalize_path("res://")
	var output: Array[String] = []
	if not git_lines(root, ["rev-parse", "--short", "HEAD"], output) or output.is_empty():
		return "unknown"
	var short: String = str(output[0]).strip_edges()
	output.clear()
	var status: Array[String] = ["status", "--porcelain", "--"]
	status.append_array(IDENTITY_PATHS)
	git_lines(root, status, output)
	var dirty: bool = not output.is_empty() and not str(output[0]).strip_edges().is_empty()
	return short + ("+dirty" if dirty else "")

# Source checkouts (editor binary) must prove their content through Git; a failure leaves the
# fingerprint empty, which no peer accepts. Exported games have no checkout and keep the file hash.
func compute_fingerprint() -> String:
	if not OS.has_feature("editor"):
		return compute_packed_fingerprint()
	var identity: Dictionary = content_identity(ProjectSettings.globalize_path("res://"))
	identity_error = str(identity["error"])
	return str(identity["fingerprint"])

static func identity_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "fingerprint": "", "entries": {}}

# Native argv avoids OS.execute's shell quoting; Git prints C-quoted paths for line parsing.
static func git_lines(root: String, arguments: Array[String], lines: Array[String]) -> bool:
	var command: PackedStringArray = PackedStringArray(["--no-optional-locks", "-C", root, "-c", "core.quotePath=true"])
	command.append_array(PackedStringArray(arguments))
	lines.clear()
	var process: Dictionary = OS.execute_with_pipe("git", command, false)
	if process.is_empty():
		return false
	var output: FileAccess = process["stdio"] as FileAccess
	var errors: FileAccess = process["stderr"] as FileAccess
	var bytes: PackedByteArray = PackedByteArray()
	var pid: int = int(process["pid"])
	var deadline: int = Time.get_ticks_msec() + 30000
	while true:
		var chunk: PackedByteArray = output.get_buffer(65536)
		var error_chunk: PackedByteArray = errors.get_buffer(65536)
		bytes.append_array(chunk)
		var running: bool = OS.is_process_running(pid)
		if not running and chunk.is_empty() and error_chunk.is_empty():
			break
		if Time.get_ticks_msec() >= deadline:
			if running:
				OS.kill(pid)
			output.close()
			errors.close()
			return false
		OS.delay_usec(1000)
	output.close()
	errors.close()
	if OS.get_process_exit_code(pid) != 0:
		return false
	for line: String in bytes.get_string_from_utf8().split("\n", false):
		lines.append(line.trim_suffix("\r"))
	return true

# Decodes a path as git prints it: plain, or in double quotes with C escapes and octal bytes.
static func unquote_git_path(text: String) -> String:
	if text.length() < 2 or not text.begins_with("\"") or not text.ends_with("\""):
		return text
	var source: PackedByteArray = text.substr(1, text.length() - 2).to_utf8_buffer()
	var bytes: PackedByteArray = PackedByteArray()
	var index: int = 0
	while index < source.size():
		var byte: int = source[index]
		index += 1
		if byte != 0x5C or index >= source.size():
			bytes.append(byte)
			continue
		var escape: int = source[index]
		index += 1
		if escape >= 0x30 and escape <= 0x37:
			var value: int = escape - 0x30
			var digits: int = 1
			while digits < 3 and index < source.size() and source[index] >= 0x30 and source[index] <= 0x37:
				value = value * 8 + source[index] - 0x30
				index += 1
				digits += 1
			bytes.append(value & 0xFF)
			continue
		bytes.append(int(ESCAPES.get(escape, escape)))
	return bytes.get_string_from_utf8()

static func is_object_id(text: String) -> bool:
	return (text.length() == 40 or text.length() == 64) and text.is_valid_hex_number()

# Maps every build path to the Git object ID of its current bytes, then hashes the sorted map.
# The index supplies unchanged files; modified and untracked files are hashed through the same
# clean filters (line endings, LFS pointers) and deleted files drop out, so equal bytes give an
# equal fingerprint whether they are committed, staged or unstaged. Any git failure fails the lot.
static func content_identity(root: String, scope: Array[String] = IDENTITY_PATHS) -> Dictionary:
	var entries: Dictionary[String, String] = {}
	var changed: Dictionary[String, bool] = {}
	var lines: Array[String] = []
	var listing: Array[String] = ["ls-files", "--stage", "--"]
	listing.append_array(scope)
	if not git_lines(root, listing, lines):
		return identity_failure("git could not list the tracked build files in " + root)
	for line: String in lines:
		var tab: int = line.find("\t")
		var fields: PackedStringArray = line.left(maxi(tab, 0)).split(" ")
		if fields.size() != 3 or not is_object_id(fields[1]):
			return identity_failure("unreadable git index line: " + line)
		var path: String = unquote_git_path(line.substr(tab + 1))
		entries[path] = fields[1]
		if fields[2] != "0":
			changed[path] = true # unmerged: take the working file
	var dirty: Array[String] = ["ls-files", "--modified", "--deleted", "--others", "--exclude-standard", "--"]
	dirty.append_array(scope)
	if not git_lines(root, dirty, lines):
		return identity_failure("git could not list the changed build files in " + root)
	for line: String in lines:
		changed[unquote_git_path(line)] = true
	var present: Array[String] = []
	for path: String in changed:
		if FileAccess.file_exists(root.path_join(path)):
			present.append(path)
		else:
			entries.erase(path)
	for start: int in range(0, present.size(), HASH_BATCH):
		var batch: Array[String] = present.slice(start, start + HASH_BATCH)
		var hashing: Array[String] = ["hash-object", "--"]
		hashing.append_array(batch)
		if not git_lines(root, hashing, lines) or lines.size() != batch.size():
			return identity_failure("git could not hash the changed build files, first of them " + batch[0])
		for index: int in range(batch.size()):
			if not is_object_id(lines[index]):
				return identity_failure("unreadable git object id for " + batch[index])
			entries[batch[index]] = lines[index]
	if entries.is_empty():
		return identity_failure("git tracks no build files in " + root)
	var paths: Array[String] = []
	paths.assign(entries.keys())
	paths.sort()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		context.update(("%s\t%s\n" % [path.c_escape(), entries[path]]).to_utf8_buffer())
	return {"ok": true, "error": "", "fingerprint": context.finish().hex_encode().left(12), "entries": entries}

func compute_packed_fingerprint() -> String:
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
		var matches: bool = not enforced or (not remote_fingerprint.is_empty() and remote_fingerprint == fingerprint)
		scene_multiplayer.send_auth(peer, encode({"fingerprint": fingerprint, "commit": commit, "map": map_id, "accepted": matches}))
		if matches:
			scene_multiplayer.complete_auth(peer)
		else:
			print("BUILD_REFUSED: peer %d runs %s [%s]; host runs %s" % [peer, remote_commit, remote_fingerprint, label()])
			NetworkManager.report("Refused a player on build %s; you run %s" % [remote_commit, label()])
		return
	if bool(info.get("accepted", false)):
		if remote_map != map_id:
			if not remote_map in GameMaps.IDS:
				NetworkManager.stop("The host plays map '%s', which this build does not have." % remote_map)
				return
			print("MAP_ADOPTED: %s" % remote_map)
			for world: Node in get_tree().get_nodes_in_group("match_world"):
				if world.has_method("load_map"):
					world.call("load_map", remote_map)
		scene_multiplayer.complete_auth(peer)
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
