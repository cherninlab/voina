extends "res://scripts/capture_dungeon.gd"
## Exact rays through Theo's three marked points; flat colors isolate layers.

func _initialize() -> void:
	run_probe.call_deferred()

func run_probe() -> void:
	root.size = Vector2i(1440, 900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(90):
		await process_frame
	for canvas: Node in root.find_children("*", "CanvasLayer", true, false):
		(canvas as CanvasLayer).visible = false
	root.disable_3d = false
	var dungeon: Node3D = world.get_node("CinderCrypt") as Node3D
	var inspector: Node3D = load("res://tests/dungeon_explorer.gd").new() as Node3D
	inspector.set("dungeon", dungeon)
	inspector.set("report", {"capabilities": {}})
	inspector.call("inventory")
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var marks: Dictionary[String, Array] = {
		"chapel_approach_0-forward": [Vector2(720,450),Vector2(900,450),Vector2(1200,500)],
		"cave_bypass_0-back": [Vector2(703, 55), Vector2(559, 329), Vector2(276, 821), Vector2(780,270), Vector2(1000,90)],
		"nave_6-back": [Vector2(749, 134), Vector2(789, 729)],
		"nave_5-forward": [Vector2(1160,450),Vector2(1320,550),Vector2(110,550),Vector2(1280,400)],
		"nave_0-forward": [Vector2(668, 662), Vector2(700,790), Vector2(400,790), Vector2(1000,790), Vector2(700,750)],
		"chapel_approach_1-back": [Vector2(1135, 253), Vector2(167, 456), Vector2(714, 293)],
		"cave_bypass_2-back": [Vector2(582, 122),Vector2(520,280),Vector2(570,300),Vector2(450,117),Vector2(420,140),Vector2(390,165),Vector2(400,210)],
		"root_tunnel_0-back": [Vector2(835,757)],
		"root_tunnel_1-forward": [Vector2(346,333)],
		"root_tunnel_2-back": [Vector2(789,702)],
		"root_tunnel_2-forward": [Vector2(662,337)],
		"root_tunnel_3-back": [Vector2(818,309)],
		"root_tunnel_3-forward": [Vector2(363,352)],
		"root_tunnel_5-back": [Vector2(530,348)],
		"root_tunnel_5-forward": [Vector2(507,416),Vector2(639,341),Vector2(824,745),Vector2(789,344)],
	}
	var findings: Array[Dictionary] = []
	for view: Array in stone_room_views():
		if not marks.has(String(view[0])):
			continue
		camera.fov = float(view[3])
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		camera.make_current()
		for pixel: Vector2 in marks[String(view[0])]:
			var eye: Vector3 = camera.project_ray_origin(pixel)
			var direction: Vector3 = camera.project_ray_normal(pixel)
			var hits: Array[Dictionary] = []
			for record: Dictionary in inspector.get("mesh_records") as Array:
				var hit: Dictionary = inspector.call("mesh_hit", record, eye, eye + direction * 80) as Dictionary
				if not hit.is_empty():
					var position: Vector3 = hit["position"] as Vector3
					var source: MeshInstance3D = world.get_node_or_null(NodePath(String(hit["path"]))) as MeshInstance3D
					var material: Material = source.get_active_material(0) if source != null else null
					var texture: Texture2D = (material as ShaderMaterial).get_shader_parameter("albedo_map") as Texture2D if material is ShaderMaterial else null
					hits.append({"path": hit["path"], "position": [position.x, position.y, position.z], "distance": eye.distance_to(position),
						"mesh": source.mesh.resource_path if source != null else "", "albedo": texture.resource_path if texture != null else "",
						"camera": [eye.x,eye.y,eye.z], "direction": [direction.x,direction.y,direction.z]})
			hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
			var finding: Dictionary = {"view": view[0], "pixel": [pixel.x, pixel.y], "camera": [eye.x,eye.y,eye.z], "direction": [direction.x,direction.y,direction.z], "hits": hits}
			if not hits.is_empty() and String(hits[0]["path"]).contains("Stone-flag"):
				var value: Array = hits[0]["position"] as Array
				var at: Vector3 = Vector3(float(value[0]),float(value[1]),float(value[2]))
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at+Vector3.UP*.1,at-Vector3.UP*.6)
				var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
				finding["floor_gap_m"] = at.y-(floor_hit["position"] as Vector3).y if not floor_hit.is_empty() else "no floor within .6m"
			findings.append(finding)
	# Isolate the dark nave threshold from geometry overlap and real shadows.
	for view: Array in stone_room_views():
		if view[0] == "nave_0-forward":
			camera.fov = float(view[3])
			camera.position = view[1] as Vector3
			camera.look_at(view[2] as Vector3)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(.88,.93,1)
	lamp.light_energy = 3
	lamp.omni_range = 12
	lamp.shadow_enabled = true
	lamp.position = Vector3(.3,.4,0)
	camera.add_child(lamp)
	DirAccess.make_dir_recursive_absolute("/tmp/h024-nave-floor-controls")
	dungeon.set_process(false)
	for mode: String in ["inspection", "without-shadows"]:
		if mode == "without-shadows":
			for node: Node in world.find_children("*", "Light3D", true, false):
				(node as Light3D).shadow_enabled = false
		for frame: int in range(12):
			await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/h024-nave-floor-controls/"+mode+".png")
	lamp.queue_free()
	for node: Node in dungeon.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.65, 0.65, 0.65)
		if visual.name.begins_with("Mortar"):
			material.albedo_color = Color(0.8, 0.12, 0.08)
		elif visual.name.begins_with("Stone-rock"):
			material.albedo_color = Color(0.08, 0.4, 0.8)
		elif visual.name.begins_with("Stone-wood"):
			material.albedo_color = Color(0.25, 0.65, 0.1)
		visual.material_override = material
	var directory: String = "/tmp/h024-marked-wall-probe"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	for view: Array in stone_room_views():
		if not marks.has(String(view[0])):
			continue
		camera.fov = float(view[3])
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		for frame: int in range(12):
			await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(directory.path_join(String(view[0])+"-layers.png"))
	var file: FileAccess = FileAccess.open(directory.path_join("rays.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(findings, "\t"))
	file.close()
	print("MARKED_WALL_PROBE_OK: ", directory)
	inspector.free()
	world.queue_free()
	await process_frame
	quit()
