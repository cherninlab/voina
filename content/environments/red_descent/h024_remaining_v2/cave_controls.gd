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
	root.disable_3d = false
	for node: Node in root.find_children("*","CanvasLayer",true,false):
		(node as CanvasLayer).visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	for view: Array in stone_room_views():
		if view[0] == "cave_bypass_2-back":
			camera.fov = float(view[3])
			camera.position = view[1] as Vector3
			camera.look_at(view[2] as Vector3)
	camera.make_current()
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
	DirAccess.make_dir_recursive_absolute(directory)
	for mode: String in ["baseline","no-live-shadows","no-baked-colour","neither"]:
		for record: Dictionary in lights:
			(record["node"] as Light3D).shadow_enabled = bool(record["shadow"]) and mode not in ["no-live-shadows","neither"]
		for record: Dictionary in rocks:
			(record["node"] as MeshInstance3D).material_override = record["plain"] if mode in ["no-baked-colour","neither"] else record["original"]
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
