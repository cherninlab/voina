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
	var checks: Array[Dictionary] = []
	var failed: bool = false
	for view: Array in stone_room_views():
		if view[0] not in ["cave_bypass_0-forward","root_tunnel_4-forward"]:continue
		camera.fov = float(view[3])
		camera.position = view[1] as Vector3
		camera.look_at(view[2] as Vector3)
		for pixel: Vector2 in [Vector2(600,180),Vector2(600,400),Vector2(800,100)]:
			var start: Vector3 = camera.project_ray_origin(pixel)
			var hit: Dictionary = inspector.call("visual_ray",start,start+camera.project_ray_normal(pixel)*30) as Dictionary
			var distance: float = INF if hit.is_empty() else start.distance_to(hit["position"] as Vector3)
			checks.append({"view":view[0],"pixel":str(pixel),"distance_m":distance,"path":hit.get("path","")})
			# The centre ray looks down the corridor to the new end arch;
			# the other five rays target nearby wall/roof patches.
			if view[0] == "root_tunnel_4-forward" and pixel == Vector2(600,400):
				if distance > 20 or not String(hit.get("path","")).contains("Stone-arch_node_-23_-23_-16"):failed = true
			elif distance > 10:failed = true
	print("CAVITY_COVERAGE_RAYS: ",JSON.stringify(checks))
	inspector.free()
	if failed:
		push_error("Excavated cavity has a missing nearby wall or roof face")
		quit(1)
		return
	print("CAVITY_COVERAGE_OK: five nearby wall/roof rays and one end-arch control meet render geometry")
	quit(0)
