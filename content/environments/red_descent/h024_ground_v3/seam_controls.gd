extends "res://scripts/capture_dungeon.gd"
## Same-camera controls distinguish baked colour, live shadow and real overlap.

func _initialize() -> void:
	controls.call_deferred()

func controls() -> void:
	root.size = Vector2i(1440,900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	for frame: int in range(90): await process_frame
	world.get_node("CinderCrypt").set_process(false)
	root.disable_3d = false
	for node: Node in root.find_children("*","CanvasLayer",true,false):
		(node as CanvasLayer).visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var target: String = "cave_bypass_2-back"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):target=argument.trim_prefix("--view=")
	for view: Array in stone_room_views():
		if view[0] == target:
			camera.fov = float(view[3])
			camera.position = view[1] as Vector3
			camera.look_at(view[2] as Vector3)
	camera.make_current()
	var inspector: Node3D = load("res://tests/dungeon_explorer.gd").new() as Node3D
	inspector.set("dungeon",world.get_node("CinderCrypt"))
	inspector.set("report",{"capabilities":{}})
	inspector.call("inventory")
	for pixel: Vector2 in [Vector2(1100,450),Vector2(1220,650),Vector2(1250,300),Vector2(700,100),Vector2(650,250)]:
		var start: Vector3 = camera.project_ray_origin(pixel)
		var hit: Dictionary = inspector.call("visual_ray",start,start+camera.project_ray_normal(pixel)*30) as Dictionary
		print("CAVE_SURFACE_RAY: ",pixel," ",hit)
	inspector.free()
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(.88,.93,1)
	lamp.light_energy = 3
	lamp.omni_range = 12
	lamp.shadow_enabled = true
	camera.add_child(lamp)
	lamp.position = Vector3(.3,.4,0)
	var lights: Array[Dictionary] = []
	for node: Node in world.find_children("*","Light3D",true,false):
		lights.append({"node":node,"shadow":(node as Light3D).shadow_enabled})
	var rocks: Array[Dictionary] = []
	for node: Node in world.find_children("Stone-rock*","MeshInstance3D",true,false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var original: ShaderMaterial = visual.material_override as ShaderMaterial
		var plain: ShaderMaterial = original.duplicate() as ShaderMaterial
		plain.shader = original.shader.duplicate() as Shader
		assert(plain.shader.code.contains("color *= COLOR.rgb *"))
		plain.shader.code = plain.shader.code.replace("color *= COLOR.rgb *","color *= ")
		rocks.append({"node":visual,"original":original,"plain":plain})
	var directory: String = "/tmp/h024-cave-controls-v2"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):directory=argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	for mode: String in ["baseline","no-live-shadows","no-baked-colour","neither","flat-geometry"]:
		for record: Dictionary in lights:
			(record["node"] as Light3D).shadow_enabled = bool(record["shadow"]) and mode not in ["no-live-shadows","neither"]
		for record: Dictionary in rocks:
			(record["node"] as MeshInstance3D).material_override = record["plain"] if mode in ["no-baked-colour","neither"] else record["original"]
		if mode == "flat-geometry":
			var flat: StandardMaterial3D = StandardMaterial3D.new()
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flat.albedo_color = Color(.1,.4,.8)
			for record: Dictionary in rocks:(record["node"] as MeshInstance3D).material_override=flat
			for node: Node in world.find_children("*","MeshInstance3D",true,false):
				if not node.name.begins_with("Stone-rock"):(node as MeshInstance3D).visible=false
		for frame: int in range(18): await process_frame
		RenderingServer.force_draw()
		assert(root.get_texture().get_image().save_png(directory.path_join(mode+".png")) == OK)
		print("CAVE_CONTROL: ",mode)
	rocks.clear()
	lights.clear()
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*","AudioStreamPlayer",true,false): (node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*","AudioStreamPlayer3D",true,false): (node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10): await process_frame
	quit()
