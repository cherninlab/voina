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
	(world.get_node("CinderCrypt") as RedDescentDungeon).set_process(false) # Freeze the six-nearest shadow updater during controls.
	root.disable_3d = false
	for node: Node in root.find_children("*","CanvasLayer",true,false):
		(node as CanvasLayer).visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var target: String = "root_tunnel_1-back"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):target=argument.trim_prefix("--view=")
	for view: Array in stone_room_views():
		if view[0] == target:
			camera.fov = float(view[3])
			camera.position = view[1] as Vector3
			camera.look_at(view[2] as Vector3)
	camera.make_current()
	(world.get_node("CinderCrypt") as RedDescentDungeon).update_fire_lights(camera)
	var inspector: Node3D = load("res://tests/dungeon_explorer.gd").new() as Node3D
	inspector.set("dungeon",world.get_node("CinderCrypt"))
	inspector.set("report",{"capabilities":{}})
	inspector.call("inventory")
	for pixel: Vector2 in [Vector2(1100,450),Vector2(1220,650),Vector2(1250,300),Vector2(700,100),Vector2(650,250),Vector2(400,700),Vector2(400,650),Vector2(650,680),Vector2(650,740),Vector2(200,800)]:
		var start: Vector3 = camera.project_ray_origin(pixel)
		var hit: Dictionary = inspector.call("visual_ray",start,start+camera.project_ray_normal(pixel)*30) as Dictionary
		print("FLOOR_SURFACE_RAY: ",pixel," ",hit)
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
		lights.append({"node":node,"shadow":(node as Light3D).shadow_enabled,"visible":(node as Light3D).visible,"energy":(node as Light3D).light_energy})
	var rocks: Array[Dictionary] = []
	for node: Node in world.find_children("Stone-flag*","MeshInstance3D",true,false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var original: ShaderMaterial = visual.material_override as ShaderMaterial
		var plain: ShaderMaterial = original.duplicate() as ShaderMaterial
		plain.shader = original.shader.duplicate() as Shader
		assert(plain.shader.code.contains("color *= COLOR.rgb *"))
		plain.shader.code = plain.shader.code.replace("color *= COLOR.rgb *","color *= ")
		rocks.append({"node":visual,"original":original,"plain":plain,"cast_shadow":visual.cast_shadow})
	var directory: String = "/tmp/h024-floor-controls"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):directory=argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var temporary: Array[MeshInstance3D] = []
	var modes: Array[String] = ["unbounded","baseline"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--floor-modes="):modes.assign(argument.trim_prefix("--floor-modes=").split(","))
	for mode: String in modes:
		for visual: MeshInstance3D in temporary:visual.free()
		temporary.clear()
		for record: Dictionary in rocks:(record["node"] as MeshInstance3D).visible=true
		for record: Dictionary in lights:
			(record["node"] as Light3D).light_energy = float(record["energy"])
			(record["node"] as Light3D).visible = bool(record["visible"]) and (mode != "camera-only" or record["node"] == lamp)
			(record["node"] as Light3D).shadow_enabled = bool(record["shadow"]) and mode not in ["no-live-shadows","neither"]
		for record: Dictionary in rocks:
			(record["node"] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode == "no-floor-shadows" else int(record["cast_shadow"])
			(record["node"] as MeshInstance3D).material_override = record["plain"] if mode in ["no-baked-colour","neither"] else record["original"]
		if mode == "unbounded":
			for light: OmniLight3D in (world.get_node("CinderCrypt") as RedDescentDungeon).fires:
				light.visible=true
				light.light_energy=8.0
		if mode == "limited-lights":
			var fires: Array[OmniLight3D] = (world.get_node("CinderCrypt") as RedDescentDungeon).fires.duplicate()
			fires.sort_custom(func(a: OmniLight3D,b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(camera.global_position)<b.global_position.distance_squared_to(camera.global_position))
			for i: int in range(fires.size()):fires[i].visible=i<6
		if mode in ["no-specular","flat-normal","flat-diffuse"]:
			for record: Dictionary in rocks:
				var material: ShaderMaterial = (record["original"] as ShaderMaterial).duplicate() as ShaderMaterial
				var shader: Shader = material.shader.duplicate() as Shader
				var code: String = shader.code
				if mode in ["flat-normal","flat-diffuse"]:code=code.replace("NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);","NORMAL = normalize((VIEW_MATRIX * vec4(vec3(0,1,0),0)).xyz);")
				if mode in ["no-specular","flat-diffuse"]:
					var begin: int = code.find("ROUGHNESS =")
					var end: int = code.find(";",begin)
					code=code.substr(0,begin)+"ROUGHNESS = 1.0"+code.substr(end)
					code=code.replace("SPECULAR = mix(0.35, 0.42, wet);","SPECULAR = 0.0;")
				if mode == "flat-diffuse":
					var begin: int = code.find("ALBEDO =")
					var end: int = code.find(";",begin)
					code=code.substr(0,begin)+"ALBEDO = vec3(.3)"+code.substr(end)
				shader.code=code
				material.shader=shader
				(record["node"] as MeshInstance3D).material_override=material
		if mode in ["fresh-mesh","local-light-batches"]:
			for record: Dictionary in rocks:
				var visual: MeshInstance3D = record["node"] as MeshInstance3D
				temporary.append_array(local_batches(visual,100000.0 if mode == "fresh-mesh" else 3.0))
				visual.visible=false
		if mode == "flat-geometry":
			var flat: StandardMaterial3D = StandardMaterial3D.new()
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flat.albedo_color = Color(.1,.4,.8)
			for record: Dictionary in rocks:(record["node"] as MeshInstance3D).material_override=flat
			for node: Node in world.find_children("*","MeshInstance3D",true,false):
				if not node.name.begins_with("Stone-flag"):(node as MeshInstance3D).visible=false
		for frame: int in range(18): await process_frame
		RenderingServer.force_draw()
		assert(root.get_texture().get_image().save_png(directory.path_join(mode+".png")) == OK)
		print("FLOOR_CONTROL: ",mode)
	rocks.clear()
	lights.clear()
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*","AudioStreamPlayer",true,false): (node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*","AudioStreamPlayer3D",true,false): (node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for frame: int in range(10): await process_frame
	quit()

func local_batches(visual: MeshInstance3D, span: float) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for surface: int in range(visual.mesh.get_surface_count()):
		var source: MeshDataTool = MeshDataTool.new()
		assert(source.create_from_surface(visual.mesh as ArrayMesh,surface) == OK)
		var builders: Dictionary[Vector2i,SurfaceTool] = {}
		for face: int in range(source.get_face_count()):
			var centre: Vector3 = Vector3.ZERO
			for corner: int in range(3):centre += source.get_vertex(source.get_face_vertex(face,corner))/3.0
			var cell: Vector2i = Vector2i(floori(centre.x/span),floori(centre.z/span)) if span < 10000 else Vector2i.ZERO
			if not builders.has(cell):
				builders[cell]=SurfaceTool.new()
				builders[cell].begin(Mesh.PRIMITIVE_TRIANGLES)
			var builder: SurfaceTool = builders[cell]
			for corner: int in range(3):
				var index: int = source.get_face_vertex(face,corner)
				builder.set_normal(source.get_vertex_normal(index))
				builder.set_tangent(source.get_vertex_tangent(index))
				builder.set_color(source.get_vertex_color(index))
				builder.set_uv(source.get_vertex_uv(index))
				builder.set_uv2(source.get_vertex_uv2(index))
				builder.add_vertex(source.get_vertex(index))
		for cell: Vector2i in builders:
			var part: MeshInstance3D = MeshInstance3D.new()
			part.name="Stone-flag_control"
			part.mesh=builders[cell].commit()
			part.material_override=visual.material_override
			part.cast_shadow=visual.cast_shadow
			visual.get_parent().add_child(part)
			part.transform=visual.transform
			result.append(part)
	return result
