extends SceneTree
## Render the real world through the MPEG datamosh effect (ui/datamosh.gd) on the GPU and save
## frames outside the repository: --capture-dir=/absolute/dir. Needs --host and a real window.
##   "$GODOT" --path . --resolution 1152x720 --script scripts/capture_datamosh.gd -- --host --port=7795 --capture-dir=/tmp/mosh
## Checks that the codec runs, that near-lossless settings reproduce the plain frame, then
## saves the default look, each debug view during a turn, and a dash/respawn mosh sequence.

var directory: String = ""
var world: Node3D
var player: Node3D
var mosh: CanvasLayer
var effect: DatamoshEffect

func _initialize() -> void:
	capture.call_deferred()

func fail(message: String) -> void:
	printerr("DATAMOSH_FAIL: ", message)
	quit(1)

func capture() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.get_slice("=", 1)
	if directory == "":
		fail("pass --capture-dir=/absolute/dir")
		return
	DirAccess.make_dir_recursive_absolute(directory)
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world # bisect halves and hit effects are added to the current scene
	for frame: int in range(120):
		await process_frame
	if world.get("players").get_child_count() == 0:
		fail("requires --host")
		return
	player = world.get("players").get_child(0) as Node3D
	for child: Node in world.get_children():
		if child.get_script() == preload("res://ui/datamosh.gd"):
			mosh = child as CanvasLayer
	if mosh == null:
		fail("match world has no datamosh node")
		return
	effect = mosh.get("effect") as DatamoshEffect
	mosh.call("reset_defaults")
	var values: Dictionary = mosh.get("values") as Dictionary
	var flags: Dictionary = mosh.get("flags") as Dictionary
	flags["enabled"] = false # the reference frame is the plain render
	(world.get_node("GameUI") as CanvasLayer).visible = false

	# A fixed camera for the still checks: the player's view drifts while idle.
	var still: Camera3D = Camera3D.new()
	world.add_child(still)
	still.fov = 75.0
	still.position = Vector3(-18, 2.3, 17)
	still.look_at(Vector3(-18, 2.6, -5))
	still.make_current()
	await frames(10)
	var plain: Image = await shot("00-off")
	flags["enabled"] = true
	values["internal_scale"] = 1.0
	values["quality"] = 100.0
	values["residual_gain"] = 1.0
	await frames(10)
	if effect.frames_coded < 5:
		fail("codec did not run (frames coded: %d)" % effect.frames_coded)
		return
	var lossless: Image = await shot("01-quality100")
	var difference: float = mean_difference(plain, lossless)
	print("DATAMOSH_RENDERER: colour format ", effect.last_color_format, " depth ", effect.last_has_depth, " frames ", effect.frames_coded)
	print("DATAMOSH_LOSSLESS: mean abs difference ", difference, " (0..1 per channel)")
	if difference > 0.03:
		fail("quality 100 at full scale should reproduce the frame")
		return

	values["internal_scale"] = 0.5
	values["quality"] = 20.0
	values["residual_gain"] = 0.92
	await frames(10)
	await shot("02-default")
	values["quality"] = 4.0
	await frames(4)
	await shot("03-quality4")
	values["quality"] = 20.0
	(player.get("camera") as Camera3D).make_current()
	still.queue_free()
	await frames(10)

	# Turn the player while showing each debug view.
	for view: int in range(1, DatamoshEffect.DEBUG_VIEWS.size()):
		effect.debug_view = view
		for frame: int in range(8):
			turn(0.03)
			await process_frame
		await shot("1%d-%s" % [view, DatamoshEffect.DEBUG_VIEWS[view].replace(" ", "-").replace("/", "")])
	effect.debug_view = 0

	# Manual burst while turning: I-frames off, starved residual.
	mosh.call("mosh_burst", 1200.0, 0.05)
	for frame: int in range(60):
		turn(0.025)
		await process_frame
		if frame % 15 == 14:
			await shot("2%d-burst" % (frame / 15))
	await frames(120)
	# Cut a raider in half in front of a fixed camera (needs --pve): the real bisect path spawns
	# the halves, and the effect must start moshing from that alone.
	var raider: HostileMob = null
	for node: Node in world.find_children("*", "CharacterBody3D", true, false):
		if node is HostileMob:
			raider = node as HostileMob
			break
	if raider != null:
		var watcher: Camera3D = Camera3D.new()
		world.add_child(watcher)
		watcher.global_position = raider.global_position + Vector3(0.0, 1.6, 3.5)
		watcher.look_at(raider.global_position + Vector3.UP)
		watcher.make_current()
		await frames(150)
		if bool(mosh.call("is_moshing")):
			fail("still moshing before the bisect")
			return
		raider.bisected(raider.global_position + Vector3.UP, Vector3(0.3, 1.0, 0.0).normalized(), Vector3(2.0, 2.0, 0.0), Vector3.RIGHT)
		await frames(2)
		if not bool(mosh.call("is_moshing")) or not effect.suppress_iframes:
			fail("bisect did not start a mosh")
			return
		print("DATAMOSH_BISECT_OK: raider halves started a mosh")
		for frame: int in range(48):
			watcher.global_position += Vector3(0.04, 0.0, 0.0)
			watcher.look_at(raider.global_position + Vector3.UP)
			await process_frame
			if frame % 12 == 11:
				await shot("4%d-bisect" % (frame / 12))
		(player.get("camera") as Camera3D).make_current()
		watcher.queue_free()
		await frames(150)
	else:
		print("DATAMOSH_BISECT_SKIPPED: run with --pve to check the bisect trigger")
	# Respawn-style teleport: the cut's I-frame is skipped.
	var start: Vector3 = player.global_position
	player.global_position = start + Vector3(12.0, 0.0, 6.0)
	for frame: int in range(40):
		turn(-0.02)
		await process_frame
		if frame % 10 == 9:
			await shot("3%d-respawn" % (frame / 10))
	print("DATAMOSH_OK: ", directory)
	quit()

func turn(amount: float) -> void:
	player.set("yaw", float(player.get("yaw")) + amount)

func frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame

func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = directory.path_join("mosh-%s.png" % name)
	image.save_png(path)
	print("DATAMOSH_CAPTURE: ", path)
	return image

func mean_difference(a: Image, b: Image) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(0, a.get_height(), 4):
		for x: int in range(0, a.get_width(), 4):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(count)
