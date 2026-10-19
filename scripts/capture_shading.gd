extends SceneTree
## Render the real world through every shading theme (ui/shading.gd) and save frames outside the
## repository: --capture-dir=/absolute/dir. Needs --host --pve and a real window.
##   "$GODOT" --path . --resolution 1152x720 --script scripts/capture_shading.gd -- --host --pve --port=7796 --shading-ephemeral --capture-dir=/tmp/shading
## --shading-ephemeral keeps this machine's user://shading_tweaks.cfg out of the run (no load, no save).
## Cuts a raider in half in front of a fixed camera so there is blood on screen, then checks that
## Natural leaves the frame untouched, that every other theme changes it, that Night darkens it,
## that the grey Concrete theme still shows vibrant red where the blood is, that returning to
## Natural restores the baked lightmap, the sun and normal rendering, that the lantern survives
## its camera being freed, and that T advances the theme.

var directory: String = ""
var world: Node3D
var shading: CanvasLayer

func _initialize() -> void:
	capture.call_deferred()

func fail(message: String) -> void:
	printerr("SHADING_FAIL: ", message)
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
	await frames(120)
	for child: Node in world.get_children():
		# By path: preloading ui/shading.gd here would compile it before the autoloads exist.
		var path: String = (child.get_script() as Script).resource_path if child.get_script() != null else ""
		if path == "res://ui/shading.gd":
			shading = child as CanvasLayer
		elif path == "res://ui/datamosh.gd":
			(child.get("flags") as Dictionary)["enabled"] = false
	if shading == null:
		fail("match world has no shading node")
		return
	(world.get_node("GameUI") as CanvasLayer).visible = false
	(shading.get("overlay") as CanvasLayer).visible = false # status text and tweaks panel
	shading.set("overrides", {} as Dictionary[String, Dictionary]) # ignore this machine's tuning
	shading.call("set_theme", 0)

	var raider: HostileMob = null
	for node: Node in world.find_children("*", "CharacterBody3D", true, false):
		if node is HostileMob:
			raider = node as HostileMob
			break
	if raider == null:
		fail("requires --host --pve (no raider to bleed)")
		return
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 75.0
	camera.global_position = raider.global_position + Vector3(0.0, 1.5, 3.0)
	camera.look_at(raider.global_position + Vector3(0.0, 0.7, 0.0))
	camera.make_current()
	await frames(30)
	raider.bisected(raider.global_position + Vector3.UP, Vector3(0.3, 1.0, 0.0).normalized(), Vector3(1.0, 1.5, 0.0), Vector3.RIGHT)
	await frames(45)
	raider.set_process(false)
	raider.set_physics_process(false)
	# Freeze the scene so every theme sees the same frame.
	paused = true
	await frames(2)

	var plain: Image = await shot("00-Natural")
	var names: PackedStringArray = shading.call("theme_names") as PackedStringArray
	for index: int in range(1, names.size()):
		shading.call("set_theme", index)
		await frames(4)
		var image: Image = await shot("%02d-%s" % [index, names[index].replace(" ", "-")])
		var difference: float = mean_difference(plain, image)
		print("SHADING_THEME: %s mean abs difference %.3f" % [names[index], difference])
		if difference < 0.01:
			fail("theme %s does not change the frame" % names[index])
			return
		if names[index] == "Night" and mean_luma(image) > mean_luma(plain) * 0.6:
			fail("Night is not darker than Natural (%.3f vs %.3f)" % [mean_luma(image), mean_luma(plain)])
			return
		if names[index] == "Concrete":
			var red: int = vivid_red(image)
			print("SHADING_BLOOD: Concrete vivid red pixels ", red, " (plain frame ", vivid_red(plain), ")")
			if red < 50:
				fail("Concrete lost the blood")
				return

	paused = false
	# The lantern must outlive the camera it follows: players (and their cameras) are freed on
	# leave or rejoin. Free this camera, switch to a new one, and the lantern must follow it.
	shading.call("set_theme", names.find("Night"))
	await frames(3)
	var lantern: OmniLight3D = (shading.get("lighting") as Node).get("lantern") as OmniLight3D
	camera.queue_free()
	var replacement: Camera3D = Camera3D.new()
	world.add_child(replacement)
	replacement.global_position = Vector3(4.0, 2.0, 6.0)
	replacement.make_current()
	await frames(3)
	if not is_instance_valid(lantern) or not lantern.visible or lantern.light_energy < 0.1 \
			or lantern.global_position.distance_to(replacement.global_position) > 1.0:
		fail("lantern did not survive its camera being freed")
		return
	print("SHADING_LANTERN_OK: lantern follows the new camera after the old one was freed")
	shading.call("set_theme", 0)
	# Natural must hand the village back its baked light.
	var lighting: Node = shading.get("lighting") as Node
	var lightmap: LightmapGI = lighting.get("lightmap") as LightmapGI
	var sun: DirectionalLight3D = lighting.get("sun") as DirectionalLight3D
	var original: Dictionary = lighting.get("original") as Dictionary
	if lightmap == null or lightmap.light_data == null or sun == null or sun.light_bake_mode != original["sun_bake"] \
			or not is_equal_approx(sun.light_energy, original["sun_energy"] as float):
		fail("Natural did not restore the baked lightmap and the sun")
		return
	if root.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		fail("Natural left the unshaded render mode on")
		return
	print("SHADING_RESTORE_OK: lightmap and sun back")
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_T
	press.keycode = KEY_T
	press.pressed = true
	root.push_input(press)
	await frames(2)
	if int(shading.get("theme_index")) != 1:
		fail("T did not advance the theme (index %d)" % int(shading.get("theme_index")))
		return
	print("SHADING_KEY_OK: T -> ", shading.call("theme_name"))
	shading.call("set_theme", 0)
	print("SHADING_OK: ", directory)
	quit()

func frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame

func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = directory.path_join("shading-%s.png" % name)
	image.save_png(path)
	print("SHADING_CAPTURE: ", path)
	return image

func mean_luma(image: Image) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	return total / float(count)

func vivid_red(image: Image) -> int:
	var count: int = 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var c: Color = image.get_pixel(x, y)
			if c.r > 0.8 and c.g < 0.25 and c.b < 0.25:
				count += 1
	return count

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
