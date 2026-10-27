extends SceneTree
## Focused before/after observations in the actual map; no level repairs happen here.

var directory: String = "/tmp/dungeon-issue-probe"
var world: Node3D
var inspector: Node3D
var baseline: Dictionary
var doorway_rays: int = 0

func _initialize() -> void:
	run.call_deferred()

func argument(key: String, fallback: String) -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with(key + "="):
			return value.substr(key.length() + 1)
	return fallback

func point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func frames(count: int) -> void:
	for frame: int in range(count):
		await physics_frame

func navigation_checks(mobs: MobSystem, players: Node3D) -> void:
	var results: Array[Dictionary] = []
	var excluded: Array[RID] = []
	for actor: Node in players.get_children() + mobs.raiders.get_children():
		if actor is CollisionObject3D:
			excluded.append((actor as CollisionObject3D).get_rid())
	for index: int in [0, 2]:
		var mob: RaiderMob = mobs.raiders.get_child(index) as RaiderMob
		var navigation: MobNavigation = mob.grid()
		var saved_grid: AStarGrid2D = navigation.grid
		var saved_heights: PackedByteArray = navigation.heights.to_byte_array()
		var saved_origin: Vector2 = navigation.origin
		var goal: Vector3 = navigation.stand_point(mob.home + Vector3.RIGHT * 5.0)
		var before: PackedVector3Array = navigation.path(mob.position, goal)
		var fresh: PackedVector3Array = navigation.fresh_path(world.get_world_3d().direct_space_state, excluded, mob.position, goal)
		var restored: bool = navigation.grid == saved_grid and navigation.origin == saved_origin and navigation.heights.to_byte_array() == saved_heights and navigation.path(mob.position, goal) == before
		var correct_floor: bool = not fresh.is_empty()
		for at: Vector3 in fresh:
			correct_floor = correct_floor and absf(at.y - mob.home.y) < 0.6
		results.append({"hall_mob": index, "home": vector(mob.home), "goal": vector(goal), "fresh_points": fresh.size(), "shared_grid_restored": restored, "correct_floor": correct_floor})
		if not restored or not correct_floor:
			push_error("Navigation scratch query changed the shared grid or selected another floor")
	var file: FileAccess = FileAccess.open(directory.path_join("navigation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("NAVIGATION_PROBE: ", JSON.stringify(results))

func doorway_ray(eye: Vector3, end: Vector3, area: String, height: float, seen: Dictionary[String, bool], results: Array[Dictionary]) -> void:
	doorway_rays += 1
	var hit: Dictionary = inspector.call("visual_ray", eye, end) as Dictionary
	if hit.is_empty() or not String(hit["path"]).get_file().begins_with("Stone"):
		return
	var location: Vector3 = hit["position"] as Vector3
	var key: String = "%s:%d:%d:%d" % [hit["path"], roundi(location.x * 2), roundi(location.y * 2), roundi(location.z * 2)]
	if seen.has(key):
		return
	seen[key] = true
	results.append({"id": "DOOR%03d" % (results.size() + 1), "area": area, "position": vector(location), "evidence": {"camera": vector(eye), "direction": vector((end - eye).normalized()), "mesh": hit["path"], "normal": vector(hit["normal"] as Vector3), "height_above_route": height}})

func doorway_findings() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary[String, bool] = {}
	for room: Dictionary in RedDescentLayout.rooms():
		var outline: PackedVector2Array = room["points"] as PackedVector2Array
		for route: Dictionary in RedDescentLayout.routes():
			var points: PackedVector3Array = route["points"] as PackedVector3Array
			for segment: int in range(points.size() - 1):
				var a: Vector3 = points[segment]
				var b: Vector3 = points[segment + 1]
				var a2: Vector2 = Vector2(a.x, a.z)
				var b2: Vector2 = Vector2(b.x, b.z)
				var along: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var side: Vector3 = Vector3.UP.cross(along)
				for edge: int in range(outline.size()):
					var crossing: Variant = Geometry2D.segment_intersects_segment(a2, b2, outline[edge], outline[(edge + 1) % outline.size()])
					if crossing == null:
						continue
					var at: Vector2 = crossing as Vector2
					var t: float = at.distance_to(a2) / maxf(0.001, a2.distance_to(b2))
					var level: float = lerpf(a.y, b.y, t)
					if level < float(room["floor"]) - 0.6 or level + 2.0 > float(room["floor"]) + float(room["height"]):
						continue
					for lateral: float in [-0.55, 0.0, 0.55]:
						for height: float in [0.45, 0.75, 1.05, 1.35, 1.65, 1.95, 2.25, 2.55, 2.85, 3.15, 3.45]:
							var centre: Vector3 = Vector3(at.x, level + height, at.y) + side * lateral
							doorway_ray(centre - along * 1.1, centre + along * 1.1, "room:" + String(room["id"]), height, seen, results)
	var architecture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/environments/procedural_architecture_v1/index.json")) as Dictionary
	for node: Dictionary in architecture["nodes"] as Array:
		var centre: Vector3 = point(node["at"] as Array)
		var radius: float = float(node["radius"])
		for route: Dictionary in RedDescentLayout.routes():
			var points: PackedVector3Array = route["points"] as PackedVector3Array
			for segment: int in range(points.size() - 1):
				if minf(centre.distance_to(points[segment]), centre.distance_to(points[segment + 1])) > 0.1:
					continue
				var along: Vector3 = points[segment + 1] - points[segment]
				along.y = 0.0
				along = along.normalized()
				var side: Vector3 = Vector3.UP.cross(along)
				for lateral: float in [-0.55, 0.0, 0.55]:
					for height: float in [0.45, 1.05, 1.65, 2.25, 2.85, 3.45]:
						var at: Vector3 = centre + Vector3.UP * height + side * lateral
						doorway_ray(at - along * (radius + 0.25), at + along * (radius + 0.25), "node:" + String(node["kind"]), height, seen, results)
	var file: FileAccess = FileAccess.open(directory.path_join("doorways.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("DOORWAY_CANDIDATES: ", results.size(), " across ", doorway_rays, " rays; upper arch contacts require inspection")
	return results

func motion(finding: Dictionary, player: CharacterBody3D) -> Dictionary:
	var evidence: Dictionary = finding["evidence"] as Dictionary
	if not evidence.has("target") or not evidence.has("trace"):
		return {"status": "no motion trace"}
	var trace: Array = evidence["trace"] as Array
	# A bounded incident trace can span a logged restart. Replay only its final
	# continuous segment, rather than walking between unrelated floors.
	var segment: int = 0
	for index: int in range(1, trace.size()):
		if point(trace[index]["position"] as Array).distance_to(point(trace[index - 1]["position"] as Array)) > 3.0:
			segment = index
	trace = trace.slice(segment)
	var goals: Array[int] = []
	for row: Dictionary in trace:
		var goal: int = int(row["goal"])
		if goals.is_empty() or goals[-1] != goal:
			goals.append(goal)
	if goals.is_empty() or goals[-1] != int(evidence["target"]):
		goals.append(int(evidence["target"]))
	player.position = point(trace[0]["position"] as Array)
	player.velocity = Vector3.ZERO
	player.floor_snap_length = 0.35
	var visited: int = 0
	var total_ticks: int = 0
	for id: int in goals:
		var target: Vector3 = point(baseline["cells"][id]["position"] as Array) + Vector3.UP * 0.91
		var arrived: bool = false
		for tick: int in range(240):
			await physics_frame
			var offset: Vector3 = target - player.position
			var horizontal: Vector3 = Vector3(offset.x, 0, offset.z)
			var vertical_speed: float = -0.6 if player.is_on_floor() else player.velocity.y - 18.0 / 60.0
			player.velocity = horizontal.normalized() * minf(6.5, horizontal.length() * 60.0)
			player.velocity.y = vertical_speed
			player.move_and_slide()
			player.apply_floor_snap()
			total_ticks += 1
			if Vector2(offset.x, offset.z).length() < 0.18 and absf(player.position.y - target.y) < 0.6 and player.is_on_floor():
				arrived = true
				break
		if not arrived:
			var contacts: Array[Dictionary] = []
			for index: int in range(player.get_slide_collision_count()):
				var hit: KinematicCollision3D = player.get_slide_collision(index)
				var body: Node = hit.get_collider() as Node
				contacts.append({"path": String(body.get_path()) if body != null else "", "position": vector(hit.get_position()), "normal": vector(hit.get_normal())})
			return {"arrived": false, "reached_goals": visited, "goals": goals.size(), "failed_goal": id, "position": vector(player.position), "ticks": total_ticks, "contacts": contacts}
		visited += 1
	return {"arrived": true, "reached_goals": visited, "goals": goals.size(), "ticks": total_ticks, "position": vector(player.position)}

func stair_routes(player: CharacterBody3D, camera: Camera3D) -> void:
	var results: Array[Dictionary] = []
	for route: Dictionary in RedDescentLayout.routes():
		if not String(route["id"]).contains("stair"):
			continue
		for reverse: bool in [false, true]:
			var points: PackedVector3Array = (route["points"] as PackedVector3Array).duplicate()
			if reverse:
				points.reverse()
			player.position = points[0] + Vector3.UP * 0.95
			player.velocity = Vector3.ZERO
			player.floor_snap_length = 0.35
			var reached: int = 0
			var contacts: Array[Dictionary] = []
			for goal: Vector3 in points:
				var arrived: bool = false
				for tick: int in range(900):
					await physics_frame
					var offset: Vector3 = goal + Vector3.UP * 0.91 - player.position
					var horizontal: Vector3 = Vector3(offset.x, 0, offset.z)
					var vertical_speed: float = -0.6 if player.is_on_floor() else player.velocity.y - 18.0 / 60.0
					player.velocity = horizontal.normalized() * minf(6.5, horizontal.length() * 60.0)
					player.velocity.y = vertical_speed
					player.move_and_slide()
					player.apply_floor_snap()
					if horizontal.length() < 0.18 and absf(offset.y) < 0.6 and player.is_on_floor():
						arrived = true
						break
				if not arrived:
					for index: int in range(player.get_slide_collision_count()):
						var hit: KinematicCollision3D = player.get_slide_collision(index)
						var body: Node = hit.get_collider() as Node
						contacts.append({"path": String(body.get_path()) if body != null else "", "position": vector(hit.get_position()), "normal": vector(hit.get_normal())})
					break
				reached += 1
			var row: Dictionary = {"route": route["id"], "reverse": reverse, "arrived": reached == points.size(), "reached": reached, "goals": points.size(), "position": vector(player.position), "contacts": contacts}
			results.append(row)
			print("STAIR_ROUTE: ", JSON.stringify(row))
			if reached < points.size() and DisplayServer.get_name() != "headless":
				camera.position = player.position + Vector3.UP * 0.65
				camera.look_at(points[reached] + Vector3.UP * 0.8)
				camera.make_current()
				for frame: int in range(6):
					await process_frame
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(directory.path_join("stair-%s-%s.png" % [route["id"], "reverse" if reverse else "forward"]))
	var file: FileAccess = FileAccess.open(directory.path_join("stairs.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()

func run() -> void:
	directory = argument("--probe-output", directory)
	DirAccess.make_dir_recursive_absolute(directory)
	baseline = JSON.parse_string(FileAccess.get_file_as_string("res://content/environments/red_descent/review/explorer_v1/20261027-full-v2/telemetry.json")) as Dictionary
	root.size = Vector2i(1152, 720)
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	await frames(25)
	var dungeon: RedDescentDungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	var players: Node3D = world.get("players") as Node3D
	var mobs: MobSystem = world.get("mobs") as MobSystem
	for actor: Node in players.get_children() + mobs.raiders.get_children():
		actor.set_physics_process(false)
		actor.set_process(false)
	players.visible = false
	mobs.visible = false
	if "--probe-navigation" in OS.get_cmdline_user_args():
		navigation_checks(mobs, players)
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	root.disable_3d = false
	inspector = load("res://tests/dungeon_explorer.gd").new() as Node3D
	inspector.set("dungeon", dungeon)
	inspector.set("report", {"capabilities": {}})
	inspector.call("inventory")
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 80
	if "--probe-stairs" in OS.get_cmdline_user_args():
		await stair_routes(players.get_child(0) as CharacterBody3D, camera)
	var requested: PackedStringArray = argument("--probe-ids", "E0438,E0437,E0439").split(",")
	var findings: Array[Dictionary] = []
	for finding: Dictionary in baseline["issues"] as Array:
		if requested.has(String(finding["id"])):
			findings.append(finding)
	if "--probe-doorways" in OS.get_cmdline_user_args():
		findings = doorway_findings().slice(0, 6)
	var view_file: String = argument("--probe-views", "")
	if not view_file.is_empty():
		findings.clear()
		for finding: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(view_file)) as Array:
			findings.append(finding)
	var results: Array[Dictionary] = []
	var materials: Dictionary[MeshInstance3D, Material] = {}
	for node: Node in dungeon.find_children("Mortar*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		materials[visual] = visual.material_override
	for finding: Dictionary in findings:
		var evidence: Dictionary = finding["evidence"] as Dictionary
		var eye: Vector3 = point(evidence["camera"] as Array) if evidence.has("camera") else point(finding["position"] as Array) + Vector3.UP * 0.65
		var direction: Vector3 = point(evidence["direction"] as Array) if evidence.has("direction") else (point(baseline["cells"][int(evidence["target"])]["position"] as Array) + Vector3.UP * 0.95 - eye).normalized()
		camera.position = eye
		camera.look_at(eye + direction, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)
		camera.make_current()
		var hits: Array[Dictionary] = []
		for record: Dictionary in inspector.get("mesh_records") as Array:
			var hit: Dictionary = inspector.call("mesh_hit", record, eye, eye + direction * 4.0) as Dictionary
			if hit.is_empty():
				continue
			hits.append({"path": hit["path"], "position": vector(hit["position"] as Vector3), "normal": vector(hit["normal"] as Vector3), "distance": eye.distance_to(hit["position"] as Vector3), "front": (hit["normal"] as Vector3).dot(direction) < 0.0})
		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
		for mode: String in argument("--probe-modes", "game,mortar-two-sided,mortar-solid-debug").split(","):
			for visual: MeshInstance3D in materials:
				if mode == "game":
					visual.material_override = materials[visual]
				elif mode == "mortar-two-sided":
					var original: ShaderMaterial = materials[visual] as ShaderMaterial
					var replacement: ShaderMaterial = original.duplicate() as ShaderMaterial
					var shader: Shader = Shader.new()
					shader.code = original.shader.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;")
					replacement.shader = shader
					visual.material_override = replacement
				else:
					var solid: StandardMaterial3D = StandardMaterial3D.new()
					solid.albedo_color = Color(1, 0, 1)
					solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					solid.cull_mode = BaseMaterial3D.CULL_DISABLED
					visual.material_override = solid
			if DisplayServer.get_name() != "headless":
				for frame: int in range(6):
					await process_frame
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(directory.path_join(String(finding["id"]) + "-" + mode + ".png"))
		for visual: MeshInstance3D in materials:
			visual.material_override = materials[visual]
		var motion_result: Dictionary = await motion(finding, players.get_child(0) as CharacterBody3D)
		results.append({"id": finding["id"], "area": finding["area"], "eye": vector(eye), "direction": vector(direction), "hits": hits.slice(0, 12), "motion": motion_result})
		print("ISSUE_PROBE: ", finding["id"], " ", JSON.stringify(motion_result))
	var file: FileAccess = FileAccess.open(directory.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	materials.clear()
	(inspector.get("triangle_cache") as Dictionary).clear()
	(inspector.get("triangle_faces") as Dictionary).clear()
	(inspector.get("mesh_records") as Array).clear()
	inspector.free()
	root.get_node("NetworkManager").call("stop", "issue probe finished")
	root.get_node("Audio").set_process(false)
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	await frames(15)
	FlagstoneFloor.meshes.clear()
	FlagstoneFloor.surfaces.clear()
	print("ISSUE_PROBE_OK")
	quit()
