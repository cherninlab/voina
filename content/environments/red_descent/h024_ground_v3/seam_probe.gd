extends "res://scripts/capture_dungeon.gd"
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
		if view[0] != "root_tunnel_3-forward":continue
		camera.fov=float(view[3]);camera.position=view[1] as Vector3;camera.look_at(view[2] as Vector3)
		for pixel: Vector2 in [Vector2(130,500),Vector2(145,420),Vector2(144,180),Vector2(485,440),Vector2(1400,180),Vector2(600,180)]:
			var a: Vector3=camera.project_ray_origin(pixel)
			var hit: Dictionary=inspector.call("visual_ray",a,a+camera.project_ray_normal(pixel)*30) as Dictionary
			print("SEAM_PIXEL ",pixel," ",hit)
			if hit.is_empty() or not String(hit.get("path","")).contains("Stone-rock"):
				push_error("Finished cavity is missing or structural backing still paints through")
				quit(1)
				return
	inspector.free()
	print("CAVE_RENDER_BACKING_SEAMS_OK: six targeted rays meet finished rock")
	quit(0)
