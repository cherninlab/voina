extends SceneTree
## H-035: the build fingerprint must follow content/ as well as scripts, and equal bytes must
## give an equal fingerprint whether committed, staged or unstaged. Git mutations happen only in
## a throwaway repo under the system temp folder; the real checkout is read, never written.

var identity_script: GDScript
const ODD_NAMES: Array[String] = ["sp ace.json", "quo\"te.json", "tab\tname.json", "line\nname.json", "карта.json"]

var fixture: String = ""
var failed: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("BUILD_CONTENT_FAIL: " + message)

func git(arguments: Array[String]) -> void:
	var command: Array[String] = ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "core.autocrlf=false"]
	command.append_array(arguments)
	var output: Array[String] = []
	check(identity_script.git_lines(fixture, command, output), "fixture git %s failed: %s" % [" ".join(PackedStringArray(arguments)), str(output)])

func write(path: String, bytes: PackedByteArray) -> void:
	var full: String = fixture.path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file: FileAccess = FileAccess.open(full, FileAccess.WRITE)
	check(file != null, "Could not write fixture file " + path)
	if file != null:
		file.store_buffer(bytes)
		file.close()

func text(path: String, content: String) -> void:
	write(path, content.to_utf8_buffer())

func identity() -> Dictionary:
	var result: Dictionary = identity_script.content_identity(fixture)
	check(bool(result["ok"]), "Fixture identity failed: " + str(result["error"]))
	return result

func fingerprint() -> String:
	return str(identity()["fingerprint"])

# The working change must alter the fingerprint, and staging then committing it must not.
func through_commit(what: String, paths: Array[String], before: String) -> String:
	var unstaged: String = fingerprint()
	check(not unstaged.is_empty() and unstaged != before, what + ": an unstaged change must change the fingerprint")
	var add: Array[String] = ["add", "--"]
	add.append_array(paths)
	git(add)
	check(fingerprint() == unstaged, what + ": staging must not change the fingerprint")
	git(["commit", "-q", "-m", what])
	check(fingerprint() == unstaged, what + ": committing must not change the fingerprint")
	return unstaged

func remove_tree(path: String) -> void:
	var access: DirAccess = DirAccess.open(path)
	if access == null:
		return
	access.include_hidden = true
	for file: String in access.get_files():
		access.remove(file)
	for child: String in access.get_directories():
		remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)

func run() -> void:
	identity_script = root.get_node("BuildSync").get_script() as GDScript
	check(identity_script.unquote_git_path("content/plain.gd") == "content/plain.gd", "A plain path must pass through")
	check(identity_script.unquote_git_path("\"a\\tb\\\"c\\\\d\"") == "a\tb\"c\\d", "C escapes must decode")
	check(identity_script.unquote_git_path("\"content/\\320\\272.json\"") == "content/к.json", "Octal UTF-8 bytes must decode")

	var project: String = ProjectSettings.globalize_path("res://")
	fixture = OS.get_temp_dir().path_join("secha_build_content_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if fixture.begins_with(project) or DirAccess.dir_exists_absolute(fixture):
		check(false, "Refusing to build the fixture at " + fixture)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(fixture)
	git(["init", "-q"])
	if failed or not DirAccess.dir_exists_absolute(fixture.path_join(".git")):
		check(false, "The fixture repo was not created; no git mutation attempted")
		remove_tree(fixture)
		quit(1)
		return

	text(".gitignore", "*.tmp\n")
	text(".gitattributes", "*.bin filter=lfs diff=lfs merge=lfs -text\n")
	text("project.godot", "config_version=5\n")
	text("core/rules.gd", "extends Node\nconst DAMAGE: int = 10\n")
	text("content/rules.gd", "extends Node\nconst HEIGHT: int = 1\n")
	text("content/maps/level.json", "{\"rooms\": 3}\n")
	write("content/maps/collision.bin", PackedByteArray([0, 255, 1, 2, 0, 13, 10, 128]))
	text("content/maps/old_room.tscn", "[gd_scene format=3]\n")
	text("docs/notes.md", "outside the build\n")
	for name: String in ODD_NAMES:
		text("content/odd/" + name, "{}\n")
	git(["add", "--", "."])
	git(["commit", "-q", "-m", "base"])

	var base: Dictionary = identity()
	var entries: Dictionary = base["entries"] as Dictionary
	var current: String = str(base["fingerprint"])
	check(current.length() == 12, "The fingerprint must be 12 hex characters")
	check(fingerprint() == current, "The fingerprint must be stable between runs")
	for path: String in ["project.godot", "core/rules.gd", "content/maps/level.json", "content/maps/collision.bin"]:
		check(entries.has(path), "Identity must cover " + path)
	for name: String in ODD_NAMES:
		check(entries.has("content/odd/" + name), "Identity must decode the file name " + name.c_escape())
	check(not entries.has("docs/notes.md"), "Files outside the build paths must stay out")

	text("content/maps/level.json", "{\"rooms\": 4}\n")
	current = through_commit("json map change", ["content/maps/level.json"], current)
	write("content/maps/collision.bin", PackedByteArray([0, 255, 1, 3, 0, 13, 10, 128]))
	current = through_commit("binary collision change", ["content/maps/collision.bin"], current)
	text("core/rules.gd", "extends Node\nconst DAMAGE: int = 12\n")
	current = through_commit("script change", ["core/rules.gd"], current)
	text("content/rules.gd", "extends Node\nconst HEIGHT: int = 2\n")
	current = through_commit("content script change", ["content/rules.gd"], current)

	var odd_paths: Array[String] = []
	for name: String in ODD_NAMES:
		odd_paths.append("content/odd/" + name)
		text("content/odd/" + name, "{\"edited\": true}\n")
	current = through_commit("odd file names change", odd_paths, current)

	text("content/maps/new_room.tscn", "[gd_scene format=3]\n")
	check(fingerprint() != current, "An untracked content file must change the fingerprint")
	DirAccess.remove_absolute(fixture.path_join("content/maps/new_room.tscn"))
	check(fingerprint() == current, "Removing the untracked file must restore the fingerprint")
	text("content/maps/new_room.tscn", "[gd_scene format=3]\n")
	current = through_commit("untracked content file", ["content/maps/new_room.tscn"], current)

	DirAccess.remove_absolute(fixture.path_join("content/maps/old_room.tscn"))
	current = through_commit("deleted content file", ["content/maps/old_room.tscn"], current)
	check(not (identity()["entries"] as Dictionary).has("content/maps/old_room.tscn"), "A deleted file must leave the identity")

	text("docs/notes.md", "still outside the build\n")
	text("tests/extra_test.gd", "extends Node\n")
	text("content/maps/cache.tmp", "ignored\n")
	check(fingerprint() == current, "Docs, tests and ignored files must not change the fingerprint")

	var missing: Dictionary = identity_script.content_identity(fixture.path_join("missing"))
	check(not bool(missing["ok"]) and str(missing["fingerprint"]).is_empty() and not str(missing["error"]).is_empty(), "A git failure must give an empty fingerprint and an error")
	remove_tree(fixture)

	# Read-only pass over the real checkout: it must resolve and cover content without hashing it all.
	var started: int = Time.get_ticks_msec()
	var real: Dictionary = identity_script.content_identity(project)
	var elapsed: int = Time.get_ticks_msec() - started
	var real_entries: Dictionary = real["entries"] as Dictionary
	var content_files: int = 0
	for path: String in real_entries:
		if path.begins_with("content/"):
			content_files += 1
	check(bool(real["ok"]), "The real checkout identity failed: " + str(real["error"]))
	check(real_entries.has("project.godot") and content_files > 0, "The real identity must cover project.godot and content/")
	if failed:
		quit(1)
		return
	print("BUILD_CONTENT_OK: staging-independent identity; real checkout %d files (%d content) in %d ms" % [real_entries.size(), content_files, elapsed])
	quit()
