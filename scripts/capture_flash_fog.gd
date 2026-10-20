extends SceneTree
## Night Flash fog light and flash-photo flames (ui/flash_fog.gdshader, ui/shading_lighting.gd).
## Run WITHOUT --headless, through scripts/godot_bg.sh; frames are saved outside the repository:
## scripts/godot_bg.sh --path . --script scripts/capture_flash_fog.gd -- --host --port=7796 --shading-ephemeral --capture-dir=/absolute/folder
## For each view it saves Night Flash with the fog light and flame grade off ("plain") and on
## ("lit"), and checks that the fog pass brightens the frame near the torches and that the grade
## makes the brightest flame pixels less red.

func _initialize() -> void:
	capture.call_deferred()

func fail(message: String) -> void:
	printerr("FLASH_FOG_FAIL: ", message)
	quit(1)

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.scaling_3d_scale = 1.0
	var directory: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.get_slice("=", 1)
	if directory.is_empty() or directory.is_relative_path():
		fail("pass --capture-dir=/absolute/folder")
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(150):
		await process_frame
	var road: Node3D = world.get_node_or_null("ChurchRoad") as Node3D
	var shading: Node = null
	for child: Node in world.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path == "res://ui/shading.gd":
			shading = child
	if road == null or shading == null:
		fail("ChurchRoad or shading missing")
		return
	var presentation: CanvasLayer = world.get_node_or_null("GameUI") as CanvasLayer
	if presentation != null:
		presentation.visible = false
	shading.call("set_theme", (shading.call("theme_names") as PackedStringArray).find("Night Flash"))
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.far = 600.0
	camera.fov = 75.0
	var torches: Array = road.get("torches") as Array
	var torch: Node3D = torches[2] as Node3D
	var across: Vector3 = Vector3(ChurchSite.road_x(torch.position.z) - torch.position.x, 0.0, 0.0).normalized()
	var views: Dictionary[String, Array] = {
		"torch": [torch.position + across * 2.2 + Vector3(0.0, 1.6, 2.4), torch.position + Vector3(0.0, 1.3, 0.0)],
		"road": [torch.position + across * 1.0 + Vector3(0.0, 1.7, 9.0), torch.position + Vector3(0.0, 1.2, -14.0)],
	}
	var lit: Dictionary[String, float] = {"fog_flash": 0.12, "fog_fire": 1.2, "flame_grade": 1.0}
	for label: String in views:
		camera.position = views[label][0] as Vector3
		camera.look_at(views[label][1] as Vector3)
		camera.make_current()
		for name: String in lit:
			shading.call("set_value", name, 0.0)
		var plain: Image = await shoot(directory, label + "-plain")
		for name: String in lit:
			shading.call("set_value", name, lit[name])
		var graded: Image = await shoot(directory, label + "-lit")
		if plain == null or graded == null:
			return
		var before: float = mean_luminance(plain)
		var after: float = mean_luminance(graded)
		print("FLASH_FOG_LUMA: ", label, " plain ", snappedf(before, 0.001), " lit ", snappedf(after, 0.001))
		if after <= before:
			fail("%s: fog light did not brighten the frame" % label)
			return
		if label == "torch":
			var red_before: float = hottest_red_share(plain)
			var red_after: float = hottest_red_share(graded)
			print("FLASH_FOG_FLAME_RED: plain ", snappedf(red_before, 0.001), " graded ", snappedf(red_after, 0.001))
			if red_after >= red_before:
				fail("flame grade did not make the flame less red")
				return
	shading.call("set_theme", 0)
	print("FLASH_FOG_OK")
	quit(0)

func shoot(directory: String, label: String) -> Image:
	for frame: int in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = directory.path_join("flash-fog-%s.png" % label)
	if image.save_png(path) != OK:
		fail("screenshot save failed: " + path)
		return null
	print("FLASH_FOG_CAPTURE: ", path)
	return image

func mean_luminance(image: Image) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(0, image.get_height(), 8):
		for x: int in range(0, image.get_width(), 8):
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	return total / float(count)

## Mean red share r / (r + g + b) over the bright warm pixels (flame, halo, fire-lit haze); lower
## is less red.
func hottest_red_share(image: Image) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > pixel.b + 0.15 and pixel.get_luminance() > 0.3:
				total += pixel.r / maxf(pixel.r + pixel.g + pixel.b, 0.001)
				count += 1
	return total / float(count) if count > 0 else 1.0
