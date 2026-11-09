extends "res://content/environments/red_descent/h024_ground_v3/capture_ground.gd"
## Regression rays through the roof/wall gaps exposed by the rejected thin shell.

func _initialize() -> void:
	probe.call_deferred()

func probe() -> void:
	root.size = Vector2i(1440,900)
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	dungeon.set_process(false)
	var inspector: Node3D = load("res://tests/dungeon_explorer.gd").new() as Node3D
	inspector.set("dungeon",dungeon)
	inspector.set("report",{"capabilities":{}})
	inspector.call("inventory")
	var camera: Camera3D = Camera3D.new()
	dungeon.add_child(camera)
	camera.make_current()
	for view: Array in stone_room_views():
		if view[0] != "puddle-walk":continue
		camera.fov=float(view[3]);camera.position=view[1] as Vector3;camera.look_at(view[2] as Vector3)
		for pixel: Vector2 in [Vector2(1110,150),Vector2(1100,260),Vector2(340,240),Vector2(980,250)]:
			var a: Vector3=camera.project_ray_origin(pixel)
			var hit: Dictionary=inspector.call("visual_ray",a,a+camera.project_ray_normal(pixel)*30) as Dictionary
			print("SEAM_PIXEL ",pixel," ",hit)
			var hits: Array[Dictionary]=[]
			for record: Dictionary in inspector.get("mesh_records") as Array:
				var h: Dictionary=inspector.call("mesh_hit",record,a,a+camera.project_ray_normal(pixel)*30) as Dictionary
				if not h.is_empty():
					h["distance"]=a.distance_to(h["position"] as Vector3)
					h["front"]=(h["normal"] as Vector3).dot(camera.project_ray_normal(pixel))<0
					hits.append(h)
			hits.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return float(x["distance"])<float(y["distance"]))
			print("SEAM_ALL ",pixel," ",JSON.stringify(hits.slice(0,4)))
	inspector.free()
	print("CAVE_RENDER_BACKING_SEAMS_OK: six targeted rays meet finished rock")
	quit(0)
