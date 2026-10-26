extends Node3D
## Offline inspection has map knowledge; enemy scenarios retain their production perception.

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const STEP: float = 0.5
const DT: float = 1.0 / 60.0
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var output: String = "/tmp/dungeon-explorer"
var full: bool = false
var seed_value: int = 186
var tick_limit: int = 3600
var world: Node3D
var dungeon: RedDescentDungeon
var mobs: MobSystem
var space: PhysicsDirectSpaceState3D
var exclude: Array[RID] = []
var workers: Array[CharacterBody3D] = []
var jobs: Array[Dictionary] = []
var cells: Array[Dictionary] = []
var columns: Dictionary[Vector2i, Array] = {}
var links: Array[PackedInt32Array] = []
var issues: Array[Dictionary] = []
var issue_keys: Dictionary[String, int] = {}
var report: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var rooms: Array[Dictionary] = RedDescentLayout.rooms()
var routes: Array[Dictionary] = RedDescentLayout.routes()
var geometry: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var suppressed: int = 0
var enemy_runs: Array[Dictionary] = []
var detector_failures: int = 0
var mesh_records: Array[Dictionary] = []
var triangle_cache: Dictionary[int, TriangleMesh] = {}
var overlap_points: Array[Dictionary] = []
var inspection_views: Array[Dictionary] = []

func register_mesh(node: MeshInstance3D, count_geometry: bool = true) -> void:
	if node.mesh == null:
		return
	var triangles: int = 0
	for surface: int in range(node.mesh.get_surface_count()):
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	var path: String = String(node.get_path())
	if count_geometry:
		geometry.append({"path": path, "asset": node.mesh.resource_path, "triangles": triangles,
			"surfaces": node.mesh.get_surface_count(), "instances": 1, "lod_begin_m": node.visibility_range_begin,
			"lod_end_m": node.visibility_range_end, "color": object_color(path).to_html(false)})
	# Other explicit LODs overlap intentionally and must not be tested as simultaneous surfaces.
	if node.visibility_range_begin > 0.0 or not node.is_visible_in_tree():
		return
	var planes: PackedVector3Array = PackedVector3Array()
	var material: ShaderMaterial = node.material_override as ShaderMaterial
	if material != null and material.shader.resource_path.ends_with("flagstone_clipped.gdshader"):
		planes = material.get_shader_parameter("clip_planes") as PackedVector3Array
	mesh_records.append({"path": path, "mesh": node.mesh, "transform": node.global_transform,
		"inverse": node.global_transform.affine_inverse(), "bounds": node.get_aabb(), "clip": planes})

func object_color(path: String) -> Color:
	return Color.from_hsv(float(posmod(path.hash(), 65521)) / 65521.0, 0.72, 0.95)

func inventory() -> void:
	for node: Node in dungeon.find_children("*", "MeshInstance3D", true, false):
		register_mesh(node as MeshInstance3D)
	for node: Node in dungeon.find_children("*", "MultiMeshInstance3D", true, false):
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if multi.multimesh == null:
			continue
		geometry.append({"path": String(node.get_path()), "asset": multi.multimesh.mesh.resource_path,
			"instances": multi.multimesh.instance_count, "triangles": multi.multimesh.mesh.get_faces().size() / 3 * multi.multimesh.instance_count,
			"surfaces": multi.multimesh.mesh.get_surface_count(), "color": object_color(String(node.get_path())).to_html(false), "multimesh": true})
	report["capabilities"]["geometry_counts"] = "per render object, explicit LOD range, material surfaces, MultiMesh instances; not GPU cost"
	print("EXPLORER_MESHES: ", geometry.size())

func survives_clip(record: Dictionary, position_value: Vector3) -> bool:
	for plane: Vector3 in record["clip"] as PackedVector3Array:
		if Vector2(position_value.x, position_value.z).dot(Vector2(plane.x, plane.y)) > plane.z + 0.0001:
			return false
	return true

func mesh_hit(record: Dictionary, a: Vector3, b: Vector3) -> Dictionary:
	var inverse: Transform3D = record["inverse"] as Transform3D
	var local_a: Vector3 = inverse * a
	var local_b: Vector3 = inverse * b
	if not (record["bounds"] as AABB).grow(0.001).intersects_segment(local_a, local_b):
		return {}
	var mesh: Mesh = record["mesh"] as Mesh
	var key: int = mesh.get_instance_id()
	if not triangle_cache.has(key):
		triangle_cache[key] = mesh.generate_triangle_mesh()
	var hit: Dictionary = triangle_cache[key].intersect_segment(local_a, local_b)
	if hit.is_empty():
		return {}
	var transform: Transform3D = record["transform"] as Transform3D
	var location: Vector3 = transform * (hit["position"] as Vector3)
	if not survives_clip(record, location):
		return {}
	return {"position": location, "normal": (inverse.basis.transposed() * (hit["normal"] as Vector3)).normalized(), "path": record["path"]}

func visual_ray(a: Vector3, b: Vector3) -> Dictionary:
	var closest: Dictionary = {}
	var distance: float = a.distance_to(b) + 0.01
	for record: Dictionary in mesh_records:
		var hit: Dictionary = mesh_hit(record, a, b)
		if not hit.is_empty() and a.distance_to(hit["position"] as Vector3) < distance:
			closest = hit
			distance = a.distance_to(hit["position"] as Vector3)
	return closest

func visual_controls() -> void:
	var root: Node3D = Node3D.new()
	root.name = "VisualControls"
	add_child(root)
	var base: Vector3 = Vector3(180, 0, 200)
	fixture_box(root, "SolidCollision", Vector3(4, 0.2, 4), base + Vector3.DOWN * 0.1)
	var size_before: int = mesh_records.size()
	for side: float in [-1.0, 1.0]:
		var visual: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(1.96, 4.0)
		visual.mesh = plane
		visual.position = base + Vector3(side * 1.02, 0, 0)
		root.add_child(visual)
		register_mesh(visual, false)
	await frames(2)
	verify("visual detector sees a gap above solid collision", not ray(base + Vector3.UP, base + Vector3.DOWN).is_empty() and visual_ray(base + Vector3.UP, base + Vector3.DOWN).is_empty())
	var solid_hit: Dictionary = visual_ray(base + Vector3(1, 1, 0), base + Vector3(1, -1, 0))
	verify("visual detector accepts solid floor control", not solid_hit.is_empty())
	verify("normal diagnostic faces the viewer on a floor", not solid_hit.is_empty() and (solid_hit["normal"] as Vector3).y > 0.0)
	mesh_records.resize(size_before)
	root.queue_free()
	await frames(2)

func visual_audit() -> void:
	var sampled: int = 0
	for room: Dictionary in rooms:
		var polygon: PackedVector2Array = room["points"] as PackedVector2Array
		var low: Vector2 = polygon[0]
		var high: Vector2 = low
		for corner: Vector2 in polygon:
			low = low.min(corner)
			high = high.max(corner)
		var stride: float = 1.0 if full else 3.0
		var x: float = low.x + 0.35
		while x < high.x:
			var z: float = low.y + 0.35
			while z < high.y:
				var at: Vector2 = Vector2(x, z)
				if Geometry2D.is_point_in_polygon(at, polygon):
					var eye: Vector3 = Vector3(x, float(room["floor"]) + 1.6, z)
					var below: Vector3 = Vector3(x, float(room["floor"]) - 1.0, z)
					var floor_hit: Dictionary = visual_ray(eye, below)
					var physics: Dictionary = ray(eye, below)
					sampled += 1
					if floor_hit.is_empty() and not physics.is_empty():
						issue("visible_floor_gap", point(vector(physics["position"] as Vector3)), "room:" + String(room["id"]),
							{"expected": "visible floor over collision", "observed": "no render triangle on floor ray", "collider": collider_path(physics), "camera": vector(eye), "direction": [0, -1, 0], "limits": "mesh ray; shader displacement and alpha masks not evaluated"}, 1)
					var roof_end: Vector3 = eye + Vector3.UP * (float(room["height"]) + 5.0)
					var roof_hit: Dictionary = visual_ray(eye, roof_end)
					if roof_hit.is_empty():
						issue("visible_ceiling_gap", eye, "room:" + String(room["id"]), {"expected": "ceiling/backing over enclosed room", "observed": "no render triangle above", "camera": vector(eye), "direction": [0, 1, 0], "limits": "intentional openings require review"}, 2)
				z += stride
			x += stride
		print("EXPLORER_VISUAL: ", room["id"], " probes=", sampled)
		await get_tree().process_frame
	report["visual_audit"] = {"room_probe_count": sampled, "stride_m": 1.0 if full else 3.0, "limits": "sampled triangles, explicit near LOD; shader displacement/peeling and MultiMesh not evaluated; narrow gaps may be missed"}
	report["capabilities"]["visual_holes"] = "sampled floor/ceiling mesh rays with known gap and solid controls; rendered captures are separate"

func intersection_audit() -> void:
	# ponytail: bounded surface samples find candidates, not an exhaustive mesh boolean.
	for index: int in range(mesh_records.size()):
		var record: Dictionary = mesh_records[index]
		var mesh: Mesh = record["mesh"] as Mesh
		var faces: PackedVector3Array = mesh.get_faces()
		if faces.size() < 3:
			continue
		var transform: Transform3D = record["transform"] as Transform3D
		var count: int = mini(6 if full else 2, faces.size() / 3)
		for sample_index: int in range(count):
			var face: int = (posmod(String(record["path"]).hash(), faces.size() / 3) + sample_index * 113) % (faces.size() / 3) * 3
			var a: Vector3 = transform * faces[face]
			var b: Vector3 = transform * faces[face + 1]
			for other_index: int in range(index + 1, mesh_records.size()):
				var other: Dictionary = mesh_records[other_index]
				var hit: Dictionary = mesh_hit(other, a, b)
				if hit.is_empty():
					continue
				var location: Vector3 = hit["position"] as Vector3
				if location.distance_to(a) < 0.003 or location.distance_to(b) < 0.003 or not survives_clip(record, location):
					continue
				if overlap_points.size() < 300:
					overlap_points.append({"position": vector(location), "a": record["path"], "b": other["path"]})
				break
		if index % 200 == 0:
			await get_tree().process_frame
	report["intersections"] = {"samples": overlap_points, "limit": 300, "method": "sampled triangle edges crossing another render object's triangles", "limits": "intentional mortar/stone contacts included; no self-intersections inside a merged mesh; not a defect verdict"}
	report["capabilities"]["intersections"] = "bounded geometric surface crossings between distinct objects; candidates only"

func verify(name_value: String, condition: bool, details: Dictionary = {}) -> void:
	checks.append({"name": name_value, "passed": condition, "details": details})
	if not condition:
		detector_failures += 1
		printerr("EXPLORER_CHECK_FAIL: ", name_value)

func false_arrival(claimed: bool, actual: Vector3, goal: Vector3) -> bool:
	return claimed and (flat_distance(actual, goal) > 0.6 or absf(actual.y - goal.y) > 0.6)

func fixture_box(parent: Node3D, name_value: String, size: Vector3, location: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_value
	body.position = location
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func enemy_trace(mob: HostileMob, tick: int, goal: Vector3) -> Dictionary:
	var path: Array[Array] = []
	for location: Vector3 in mob.route:
		path.append(vector(location))
	var contacts: Array[String] = []
	for index: int in range(mob.get_slide_collision_count()):
		var body: Node = mob.get_slide_collision(index).get_collider() as Node
		contacts.append(String(body.get_path()) if body != null else "")
	return {"tick": tick, "position": vector(mob.position), "state": mob.state, "goal": vector(goal),
		"last_seen": vector(mob.last_seen), "memory_left": mob.memory_left, "target_present": mob.has_target(),
		"visible": mob.can_see(mob.target) if mob.has_target() else false, "path": path, "path_refresh_left": mob.path_left,
		"velocity": vector(mob.velocity), "floor": mob.is_on_floor(), "colliders": contacts}

func enemy_walk(mob: HostileMob, goal: Vector3, name_value: String, limit: int = 720) -> Dictionary:
	var trace: Array[Dictionary] = []
	var travelled: float = 0.0
	var stationary: int = 0
	var longest_stuck: int = 0
	var claimed: bool = false
	var start: Vector3 = mob.position
	var ticks: int = 0
	mob.route.clear()
	mob.path_left = 0.0
	for tick: int in range(limit):
		await get_tree().physics_frame
		var before: Vector3 = mob.position
		claimed = mob.walk(goal, RaiderMob.RUN_SPEED, HostileMob.State.MOVE, DT)
		mob.velocity.y = -0.6 if mob.is_on_floor() else mob.velocity.y - HostileMob.GRAVITY * DT
		mob.move_and_slide()
		travelled += flat_distance(before, mob.position)
		stationary = stationary + 1 if flat_distance(before, mob.position) < 0.003 else 0
		longest_stuck = maxi(longest_stuck, stationary)
		ticks = tick + 1
		if tick % 12 == 0 or claimed:
			trace.append(enemy_trace(mob, tick, goal))
		if claimed or stationary >= 120:
			break
	var bad_arrival: bool = false_arrival(claimed, mob.position, goal)
	var result: Dictionary = {"scenario": name_value, "profile": "production RaiderMob.walk + move_and_slide", "start": vector(start),
		"goal": vector(goal), "end": vector(mob.position), "claimed_arrival": claimed, "false_arrival": bad_arrival,
		"arrived": not bad_arrival and claimed, "distance_m": travelled, "direct_distance_m": start.distance_to(goal),
		"seconds": ticks * DT, "max_stuck_seconds": longest_stuck * DT, "trace": trace}
	enemy_runs.append(result)
	if bad_arrival or longest_stuck >= 120:
		issue("enemy_false_arrival" if bad_arrival else "enemy_stuck", mob.position, "fixture:" + name_value,
			{"expected": "arrive at the requested 3D goal or report no route", "observed": result,
			"source": "gameplay/mobs/hostile_mob.gd:walk; gameplay/mobs/mob_navigation.gd:path"}, 1, "observed")
	return result

func enemy_scenarios() -> void:
	verify("arrival detector accepts valid arrival", not false_arrival(true, Vector3.ZERO, Vector3(0.1, 0.1, 0)))
	verify("arrival detector catches empty-route success", false_arrival(true, Vector3.ZERO, Vector3(4, 0, 0)))
	verify("arrival detector catches wrong floor", false_arrival(true, Vector3.ZERO, Vector3(0, 6, 0)))
	verify("arrival detector accepts honest no-route", not false_arrival(false, Vector3.ZERO, Vector3(4, 0, 0)))
	var arena: Node3D = Node3D.new()
	arena.name = "EnemyControls"
	add_child(arena)
	var base: Vector3 = Vector3(200, 0, 200)
	fixture_box(arena, "Floor", Vector3(42, 1, 42), base + Vector3.DOWN * 0.5)
	var players: Node3D = Node3D.new()
	players.name = "Players"
	arena.add_child(players)
	var system: MobSystem = MobSystem.new()
	system.name = "Mobs"
	system.players = players
	arena.add_child(system)
	system.set_process(false)
	var actor: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	actor.name = "ControlPlayer"
	players.add_child(actor)
	actor.position = base + Vector3(0, 0.95, 8)
	actor.set_physics_process(false)
	actor.set_process(false)
	var mob: RaiderMob = system.create_raider([1186, base + Vector3(-6, 0.95, 0), 0.0, MobSystem.Zone.VILLAGE]) as RaiderMob
	system.raiders.add_child(mob)
	mob.set_physics_process(false)
	mob.set_process(false)
	await frames(3)
	system.raider_grids[0].build(space, system.actor_rids(), Vector2(base.x, base.z))
	var clear_run: Dictionary = await enemy_walk(mob, base + Vector3(6, 0.95, 0), "clear-floor")
	verify("real enemy crosses clear floor", bool(clear_run["arrived"]), clear_run)
	# The upper floor is real; reaching its x/z on the lower floor is not arrival.
	fixture_box(arena, "UpperFloor", Vector3(4, 0.3, 4), base + Vector3(6, 5.85, 0))
	await frames(2)
	await enemy_walk(mob, base + Vector3(6, 6.95, 0), "stacked-floor", 90)
	var wall: StaticBody3D = fixture_box(arena, "ChangedObstacle", Vector3(1, 3, 10), base + Vector3(0, 1.5, 0))
	await frames(2)
	# The existing navigation snapshot predates this obstacle, as it can during play.
	var changed: Dictionary = await enemy_walk(mob, base + Vector3(-6, 0.95, 0), "changed-obstacle")
	verify("stuck detector sees changed obstacle", float(changed["max_stuck_seconds"]) >= 2.0 or bool(changed["arrived"]), changed)
	# Refresh only via the production build method, then verify a real detour.
	system.raider_grids[0].build(space, system.actor_rids(), Vector2(base.x, base.z))
	var detour: Dictionary = await enemy_walk(mob, base + Vector3(-6, 0.95, 0), "static-detour", 1200)
	verify("real enemy routes around static cover", bool(detour["arrived"]), detour)
	wall.queue_free()
	await frames(2)
	fixture_box(arena, "UnreachableDivider", Vector3(1, 3, 44), base + Vector3(0, 1.5, 0))
	await frames(2)
	system.raider_grids[0].build(space, system.actor_rids(), Vector2(base.x, base.z))
	await enemy_walk(mob, base + Vector3(6, 0.95, 0), "unreachable-goal", 900)
	# Perception and action now run through the actual physics callback.
	mob.position = base + Vector3(-6, 0.95, 0)
	mob.home = mob.position
	mob.sync_position = mob.position
	mob.velocity = Vector3.ZERO
	mob.route.clear()
	mob.state = HostileMob.State.IDLE
	mob.target = null
	actor.position = base + Vector3(-2.5, 0.95, 0)
	await frames(2)
	mob.sense()
	verify("real enemy sees unobstructed target", mob.target == actor)
	var seen: Vector3 = mob.last_seen
	actor.position = base + Vector3(6, 0.95, 0)
	system.started = true
	mob.set_physics_process(true)
	var perception_trace: Array[Dictionary] = []
	var remembered_hidden: bool = false
	for tick: int in range(240):
		await get_tree().physics_frame
		remembered_hidden = remembered_hidden or mob.last_seen.distance_to(seen) > 0.01
		if tick % 12 == 0:
			perception_trace.append(enemy_trace(mob, tick, actor.position))
	verify("cover prevents hidden-position updates", not remembered_hidden)
	verify("production target memory expires behind cover", not mob.has_target())
	actor.position = base + Vector3(-3, 0.95, 0)
	await frames(18)
	verify("real enemy reacquires target", mob.has_target())
	actor.position = base + Vector3(40, 0.95, 0)
	await frames(300)
	verify("enemy gives up outside its zone and returns home", not mob.has_target() and flat_distance(mob.position, mob.home) < 0.6)
	enemy_runs.append({"scenario": "cover-memory-reacquire-return", "profile": "production RaiderMob physics/perception/actions", "trace": perception_trace})
	mob.set_physics_process(false)
	system.started = false
	arena.queue_free()
	await frames(5)
	report["capabilities"]["enemy_scenarios"] = "production enemy locomotion, blocked/changed paths, stacked floors, cover, memory, reacquisition, return home"
	print("EXPLORER_ENEMIES: ", enemy_runs.size(), " scenarios; detector failures=", detector_failures)

func _ready() -> void:
	run.call_deferred()

func argument(key: String, fallback: String) -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with(key + "="):
			return value.substr(key.length() + 1)
	return fallback

func vector(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]

func point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func ray(a: Vector3, b: Vector3, mask: int = 1, back_faces: bool = true) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b, mask, exclude)
	query.hit_back_faces = back_faces
	return space.intersect_ray(query)

func collider_path(hit: Dictionary) -> String:
	var collider: Node = hit.get("collider") as Node
	return String(collider.get_path()) if collider != null else ""

func issue(kind: String, position_value: Vector3, area: String, evidence: Dictionary, severity: int = 2, confidence: String = "candidate") -> void:
	var key: String = "%s:%s:%d:%d:%d" % [kind, area, roundi(position_value.x), roundi(position_value.y), roundi(position_value.z)]
	if issue_keys.has(key):
		issues[issue_keys[key]]["occurrences"] = int(issues[issue_keys[key]]["occurrences"]) + 1
		return
	if issues.size() >= 1000:
		suppressed += 1
		return
	var id: String = "E%04d" % (issues.size() + 1)
	issue_keys[key] = issues.size()
	issues.append({"id": id, "kind": kind, "severity": severity, "confidence": confidence,
		"area": area, "position": vector(position_value), "evidence": evidence, "occurrences": 1,
		"replay": {"seed": seed_value, "mode": "full" if full else "fast", "ticks": tick_limit}})

func expected_levels(at: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in rooms:
		if Geometry2D.is_point_in_polygon(at, room["points"] as PackedVector2Array):
			result.append({"y": float(room["floor"]), "area": "room:" + String(room["id"])})
	for route: Dictionary in routes:
		var points: PackedVector3Array = route["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector2 = Vector2(points[index].x, points[index].z)
			var b: Vector2 = Vector2(points[index + 1].x, points[index + 1].z)
			var t: float = clampf((at - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
			if at.distance_to(a.lerp(b, t)) <= float(route["width"]) * 0.5:
				result.append({"y": lerpf(points[index].y, points[index + 1].y, t), "area": "route:" + String(route["id"])})
	return result

func sample() -> void:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = exclude
	var raw_surfaces: int = 0
	for x: int in range(-102, 99):
		for z: int in range(-92, 104):
			var at: Vector2 = Vector2(x, z) * STEP
			var expected: Array[Dictionary] = expected_levels(at)
			if expected.is_empty():
				continue
			var top: float = 16.0
			var found: Array[float] = []
			for layer: int in range(32):
				var hit: Dictionary = ray(Vector3(at.x, top, at.y), Vector3(at.x, -55.0, at.y))
				if hit.is_empty():
					break
				var location: Vector3 = hit["position"] as Vector3
				top = location.y - 0.03
				raw_surfaces += 1
				# Collision sheets include reversed triangles; retain their reported normal.
				# Actual capsule visits, rather than winding alone, establish traversability.
				if absf((hit["normal"] as Vector3).y) < cos(PI * 0.25):
					continue
				var area: String = ""
				var difference: float = 0.65
				for candidate: Dictionary in expected:
					if absf(location.y - float(candidate["y"])) < difference:
						difference = absf(location.y - float(candidate["y"]))
						area = String(candidate["area"])
				if area.is_empty():
					continue
				var repeated: bool = false
				for previous: float in found:
					repeated = repeated or absf(previous - location.y) < 0.15
				if repeated:
					continue
				found.append(location.y)
				var roof: Dictionary = ray(location + Vector3.UP * 0.06, location + Vector3.UP * 8.0, 1, true)
				var headroom: float = (roof["position"] as Vector3).y - location.y if not roof.is_empty() else 8.0
				query.transform = Transform3D(Basis.IDENTITY, location + Vector3.UP * 1.0)
				var contacts: Array[Dictionary] = space.intersect_shape(query, 4)
				var index: int = cells.size()
				var free: bool = contacts.is_empty() and headroom >= 2.0
				cells.append({"id": index, "position": vector(location), "normal": vector(hit["normal"] as Vector3),
					"area": area, "collider": collider_path(hit), "headroom_m": headroom,
					"walkable": free, "reached": false, "component": -1, "x": x, "z": z})
				var key: Vector2i = Vector2i(x, z)
				if not columns.has(key):
					columns[key] = []
				columns[key].append(index)
			if full:
				for candidate: Dictionary in expected:
					var present: bool = false
					for y: float in found:
						present = present or absf(y - float(candidate["y"])) < 0.65
					if not present:
						issue("missing_floor_candidate", Vector3(at.x, float(candidate["y"]), at.y), String(candidate["area"]),
							{"expected": "walkable surface near layout floor", "observed": "no upward surface within 0.65 m", "probe": "collision ray; intended openings require review"})
		if x % 20 == 0:
			print("EXPLORER_SAMPLE: x=", x, " cells=", cells.size())
			await get_tree().process_frame
	report["survey"] = {"cell_m": STEP, "surface_hits": raw_surfaces, "columns": columns.size(),
		"bounds": [-51, -46, 49, 51.5], "scope": "layout room polygons and route widths; all matching height layers", "max_surfaces_per_column": 32}

func connect_cells() -> void:
	links.resize(cells.size())
	for cell: Dictionary in cells:
		var id: int = int(cell["id"])
		if not bool(cell["walkable"]):
			continue
		var origin: Vector3 = point(cell["position"] as Array)
		for direction: Vector2i in DIRECTIONS:
			var key: Vector2i = Vector2i(int(cell["x"]), int(cell["z"])) + direction
			for neighbour: int in columns.get(key, []) as Array:
				if bool(cells[neighbour]["walkable"]) and absf(point(cells[neighbour]["position"] as Array).y - origin.y) <= 0.42:
					links[id].append(neighbour)
	var component: int = 0
	for cell: Dictionary in cells:
		if not bool(cell["walkable"]) or int(cell["component"]) >= 0:
			continue
		var queue: Array[int] = [int(cell["id"])]
		cell["component"] = component
		var cursor: int = 0
		while cursor < queue.size():
			var id: int = queue[cursor]
			cursor += 1
			for neighbour: int in links[id]:
				if int(cells[neighbour]["component"]) < 0:
					cells[neighbour]["component"] = component
					queue.append(neighbour)
		component += 1
	report["survey"]["sampled_components"] = component

func nearest_cell(location: Vector3, only_unreached: bool = false) -> int:
	var best: int = -1
	var distance: float = INF
	for cell: Dictionary in cells:
		if not bool(cell["walkable"]) or (only_unreached and bool(cell["reached"])):
			continue
		var current: float = location.distance_squared_to(point(cell["position"] as Array) + Vector3.UP * 0.91)
		if current < distance:
			distance = current
			best = int(cell["id"])
	return best

func frontier_path(start: int) -> Array[int]:
	var queue: Array[int] = [start]
	var parent: Dictionary[int, int] = {start: -1}
	var cursor: int = 0
	while cursor < queue.size():
		var id: int = queue[cursor]
		cursor += 1
		if not bool(cells[id]["reached"]):
			var result: Array[int] = [id]
			while parent[id] >= 0:
				id = parent[id]
				result.push_front(id)
			return result
		var offset: int = rng.randi_range(0, maxi(0, links[id].size() - 1))
		for j: int in range(links[id].size()):
			var next: int = links[id][(j + offset) % links[id].size()]
			if not parent.has(next):
				parent[next] = id
				queue.append(next)
	return []

func restart(worker: CharacterBody3D, job: Dictionary, cell_id: int, reason: String) -> void:
	worker.position = point(cells[cell_id]["position"] as Array) + Vector3.UP * 0.95
	worker.velocity = Vector3.ZERO
	job["current"] = cell_id
	job["path"] = []
	job["settle"] = 8
	job["stuck_ticks"] = 0
	job["restarts"].append({"tick": int(job["tick"]), "cell": cell_id, "reason": reason, "position": vector(worker.position)})

func explore() -> void:
	var start: int = nearest_cell(RedDescentLayout.player_spawn(0))
	if start < 0:
		push_error("Explorer found no walkable cells")
		get_tree().quit(1)
		return
	report["survey"]["entry_component"] = int(cells[start]["component"])
	for worker: CharacterBody3D in workers:
		var job: Dictionary = {"tick": 0, "current": start, "path": [], "settle": 0, "stuck_ticks": 0,
			"distance_m": 0.0, "restarts": [], "trace": [], "visited": 0, "idle": false}
		restart(worker, job, start, "initial spawn")
		jobs.append(job)
	for tick: int in range(tick_limit):
		await get_tree().physics_frame
		var active: bool = false
		for index: int in range(workers.size()):
			var worker: CharacterBody3D = workers[index]
			var job: Dictionary = jobs[index]
			job["tick"] = tick
			if bool(job["idle"]):
				continue
			active = true
			var path: Array = job["path"] as Array
			if path.is_empty():
				path.assign(frontier_path(int(job["current"])))
				if path.is_empty():
					var next: int = nearest_cell(worker.position, true)
					if next < 0:
						job["idle"] = true
						continue
					restart(worker, job, next, "restart after exhausting or blocking current connected frontier")
					path = job["path"] as Array
					path.append(next)
			var target_id: int = int(path[0])
			var target: Vector3 = point(cells[target_id]["position"] as Array) + Vector3.UP * 0.91
			var before: Vector3 = worker.position
			var delta: Vector3 = target - before
			delta.y = 0.0
			var horizontal: Vector3 = delta.normalized() * minf(6.5, delta.length() / DT)
			worker.velocity = Vector3(horizontal.x, -0.6 if worker.is_on_floor() else worker.velocity.y - 18.0 * DT, horizontal.z)
			worker.move_and_slide()
			worker.apply_floor_snap()
			job["distance_m"] = float(job["distance_m"]) + before.distance_to(worker.position)
			if tick % 12 == 0:
				var trace: Array = job["trace"] as Array
				trace.append({"tick": tick, "position": vector(worker.position), "goal": target_id, "velocity": vector(worker.velocity), "floor": worker.is_on_floor()})
				if trace.size() > 25:
					trace.pop_front()
			if flat_distance(worker.position, target) < 0.18 and absf(worker.position.y - target.y) < 0.6 and worker.is_on_floor():
				if not bool(cells[target_id]["reached"]):
					cells[target_id]["reached"] = true
					cells[target_id]["reached_by"] = index
					cells[target_id]["reached_tick"] = tick
					job["visited"] = int(job["visited"]) + 1
				job["current"] = target_id
				job["stuck_ticks"] = 0
				path.pop_front()
			elif worker.position.y < target.y - 2.5:
				issue("unplanned_fall", before, String(cells[target_id]["area"]), {"expected": "reach sampled neighbour without a drop", "observed": vector(worker.position), "target": target_id, "trace": (job["trace"] as Array).duplicate(true)}, 1, "observed")
				links[int(job["current"])].erase(target_id)
				restart(worker, job, int(job["current"]), "fall recovery")
			else:
				job["stuck_ticks"] = int(job["stuck_ticks"]) + (1 if flat_distance(before, worker.position) < 0.003 else -mini(2, int(job["stuck_ticks"])))
				if int(job["stuck_ticks"]) > 90:
					var contacts: Array[Dictionary] = []
					for c: int in range(worker.get_slide_collision_count()):
						var collision: KinematicCollision3D = worker.get_slide_collision(c)
						var body: Node = collision.get_collider() as Node
						contacts.append({"collider": String(body.get_path()) if body != null else "", "position": vector(collision.get_position()), "normal": vector(collision.get_normal())})
					issue("stuck", worker.position, String(cells[target_id]["area"]), {"expected": "progress toward neighbour", "observed": "no progress for 1.5 simulated seconds", "target": target_id, "contacts": contacts, "trace": (job["trace"] as Array).duplicate(true)}, 1, "observed")
					links[int(job["current"])].erase(target_id)
					restart(worker, job, int(job["current"]), "stuck recovery; failed edge removed")
		if tick % 600 == 0:
			print("EXPLORER_WALK: tick=", tick, " visited=", reached_count(), " issues=", issues.size())
		if not active:
			break

func reached_count() -> int:
	var result: int = 0
	for cell: Dictionary in cells:
		result += 1 if bool(cell["reached"]) else 0
	return result

func save_report() -> void:
	var walkable: int = 0
	var entry_connected: int = 0
	for cell: Dictionary in cells:
		walkable += 1 if bool(cell["walkable"]) else 0
		entry_connected += 1 if bool(cell["walkable"]) and int(cell["component"]) == int(report["survey"].get("entry_component", -2)) else 0
	report["coverage"] = {"sampled": cells.size(), "walkable": walkable, "reached": reached_count(), "entry_component_cells": entry_connected,
		"budget_ticks": tick_limit, "simulated_seconds_limit": tick_limit * DT, "workers": jobs, "suppressed_issue_locations": suppressed}
	report["cells"] = cells
	report["issues"] = issues
	report["geometry"] = geometry
	report["checks"] = checks
	report["enemy_runs"] = enemy_runs
	var file: FileAccess = FileAccess.open(output.path_join("telemetry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("EXPLORER_OK: reached=%d/%d issues=%d report=%s" % [reached_count(), walkable, issues.size(), output])

func diagnostic_shader() -> Shader:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 explorer_color : source_color = vec4(1.0);
uniform int mode = 0;
uniform int clip_count = 0;
uniform vec3 clip_planes[12];
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    for (int i = 0; i < clip_count; i++) {
        if (dot(world_position.xz, clip_planes[i].xy) > clip_planes[i].z) { discard; }
    }
    if (mode == 0) { ALBEDO = explorer_color.rgb; }
    else if (mode == 1) { ALBEDO = vec3(clamp(-VERTEX.z / 30.0, 0.0, 1.0)); }
    else if (mode == 2) { ALBEDO = normalize(world_normal) * 0.5 + 0.5; }
    else { ALBEDO = vec3(0.012); }
}"""
	return shader

func capture_views() -> void:
	var telemetry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("telemetry.json"))) as Dictionary
	get_viewport().size = Vector2i(1152, 720)
	get_viewport().disable_3d = false
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 80.0
	var debug_environment: Environment = Environment.new()
	debug_environment.background_mode = Environment.BG_COLOR
	debug_environment.background_color = Color.BLACK
	debug_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var views: Array[Dictionary] = []
	var worker_count: int = mini(int(argument("--explorer-capture-workers", "1")), (telemetry["coverage"]["workers"] as Array).size())
	var lenses: Dictionary[String, Vector3] = {"forward": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT, "up": Vector3.UP, "down": Vector3.DOWN}
	for index: int in range(worker_count):
		var trace: Array = telemetry["coverage"]["workers"][index]["trace"] as Array
		if trace.is_empty():
			continue
		var last: Dictionary = trace[-1] as Dictionary
		for lens: String in argument("--explorer-lenses", "forward,back,left,right,up,down").split(","):
			if lenses.has(lens):
				views.append({"name": "crawler%d-%s" % [index, lens], "eye": last["position"], "direction": vector(lenses[lens]), "tick": last["tick"], "head_offset_m": 0.65})
	var issue_views: int = 0
	for finding: Dictionary in telemetry["issues"] as Array:
		if String(finding["area"]).begins_with("fixture:"):
			continue
		var evidence: Dictionary = finding["evidence"] as Dictionary
		if evidence.has("camera") and issue_views < 3:
			views.append({"name": String(finding["id"]), "eye": evidence["camera"], "direction": evidence["direction"], "head_offset_m": 0.0})
			issue_views += 1
	var visuals: Array[GeometryInstance3D] = []
	var originals: Array[Material] = []
	var materials: Array[ShaderMaterial] = []
	var shader: Shader = diagnostic_shader()
	for node: Node in dungeon.find_children("*", "GeometryInstance3D", true, false):
		if not node is MeshInstance3D and not node is MultiMeshInstance3D:
			continue
		var visual: GeometryInstance3D = node as GeometryInstance3D
		visuals.append(visual)
		originals.append(visual.material_override)
		var diagnostic: ShaderMaterial = ShaderMaterial.new()
		diagnostic.shader = shader
		diagnostic.set_shader_parameter("explorer_color", object_color(String(node.get_path())))
		var old: ShaderMaterial = visual.material_override as ShaderMaterial
		if old != null and old.shader.resource_path.ends_with("flagstone_clipped.gdshader"):
			diagnostic.set_shader_parameter("clip_count", old.get_shader_parameter("clip_count"))
			diagnostic.set_shader_parameter("clip_planes", old.get_shader_parameter("clip_planes"))
		materials.append(diagnostic)
	var crossings: Node3D = Node3D.new()
	world.add_child(crossings)
	var green: StandardMaterial3D = StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color = Color(0, 1, 0.1)
	green.no_depth_test = true
	var ball: SphereMesh = SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	ball.radial_segments = 8
	ball.rings = 4
	for crossing: Dictionary in telemetry["intersections"]["samples"] as Array:
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.mesh = ball
		marker.material_override = green
		marker.position = point(crossing["position"] as Array)
		crossings.add_child(marker)
	var collision_overlay: Node3D = Node3D.new()
	world.add_child(collision_overlay)
	for node: Node in dungeon.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = node as CollisionShape3D
		if shape.shape == null or shape.disabled:
			continue
		var wire: MeshInstance3D = MeshInstance3D.new()
		wire.mesh = shape.shape.get_debug_mesh()
		wire.material_override = green
		collision_overlay.add_child(wire)
		wire.global_transform = shape.global_transform
	var clearance: Node3D = Node3D.new()
	world.add_child(clearance)
	var tile: BoxMesh = BoxMesh.new()
	tile.size = Vector3(0.42, 0.02, 0.42)
	var results: Array[Dictionary] = []
	for view: Dictionary in views:
		camera.position = point(view["eye"] as Array) + Vector3.UP * float(view["head_offset_m"])
		var direction: Vector3 = point(view["direction"] as Array)
		camera.look_at(camera.position + direction, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)
		camera.make_current()
		for child: Node in clearance.get_children():
			child.free()
		for cell: Dictionary in telemetry["cells"] as Array:
			var location: Vector3 = point(cell["position"] as Array)
			if camera.position.distance_to(location) > 6.0:
				continue
			var marker: MeshInstance3D = MeshInstance3D.new()
			marker.mesh = tile
			var color: StandardMaterial3D = StandardMaterial3D.new()
			color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			color.albedo_color = Color(0, 0.8, 0.2) if bool(cell["walkable"]) else Color(1, 0.15, 0.03)
			marker.material_override = color
			marker.position = location + Vector3.UP * 0.04
			clearance.add_child(marker)
		for pass_name: String in ["color", "objects", "depth", "normals", "intersections", "collision", "clearance"]:
			var mode: int = {"objects": 0, "depth": 1, "normals": 2}.get(pass_name, 3)
			camera.environment = null if pass_name == "color" else debug_environment
			crossings.visible = pass_name == "intersections"
			collision_overlay.visible = pass_name == "collision"
			clearance.visible = pass_name == "clearance"
			for index: int in range(visuals.size()):
				visuals[index].material_override = originals[index] if pass_name == "color" else materials[index]
				materials[index].set_shader_parameter("mode", mode)
			for frame: int in range(4):
				await get_tree().process_frame
			RenderingServer.force_draw()
			var filename: String = "%s-%s.png" % [String(view["name"]), pass_name]
			var frame_image: Image = get_viewport().get_texture().get_image()
			if frame_image.save_png(output.path_join(filename)) != OK:
				push_error("Cannot save capture " + filename)
			results.append({"view": view, "pass": pass_name, "camera": vector(camera.position), "frame": filename,
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			print("EXPLORER_CAPTURE: ", filename)
	for index: int in range(visuals.size()):
		visuals[index].material_override = originals[index]
	crossings.queue_free()
	collision_overlay.queue_free()
	clearance.queue_free()
	var file: FileAccess = FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"views": results, "legends": {"depth": "linear camera depth, black=0 m white=30 m; background black", "normals": "world normal XYZ mapped to RGB", "objects": "stable per-object colors; see objects.json; each MultiMesh is one object", "intersections": "green markers at sampled triangle crossings, shown through occluders; intentional contacts included", "collision": "green collision wire meshes shown through occluders", "clearance": "green=sampled capsule/headroom clear, red=blocked; not proof of reachability", "limits": "debug materials preserve flagstone clipping but not shader peeling/displacement/transparency; paired color view is authoritative"}}, "\t"))
	var objects: FileAccess = FileAccess.open(output.path_join("objects.json"), FileAccess.WRITE)
	objects.store_string(JSON.stringify(telemetry["geometry"], "\t"))

func run() -> void:
	output = argument("--explorer-output", output)
	full = argument("--explorer-mode", "fast") == "full"
	seed_value = int(argument("--explorer-seed", "186"))
	tick_limit = int(argument("--explorer-ticks", "36000" if full else "3600"))
	rng.seed = seed_value
	DirAccess.make_dir_recursive_absolute(output)
	report = {"schema": 1, "seed": seed_value, "mode": "full" if full else "fast", "engine": Engine.get_version_info()["string"],
		"build": argument("--explorer-build", "unknown"), "actor": {"profile": "production player scene, scripted movement", "radius_m": 0.4, "height_m": 1.8, "speed_m_s": 6.5, "step_seconds": DT},
		"capabilities": {"collision_survey": "implemented", "capsule_exploration": "implemented", "enemy_scenarios": "unchecked", "visual_holes": "unchecked", "geometry_counts": "unchecked", "performance": "unchecked", "crowd": "unchecked"}}
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	await frames(20)
	dungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	mobs = world.get("mobs") as MobSystem
	for mob: Node in mobs.raiders.get_children():
		mob.set_physics_process(false)
	var players: Node3D = world.get("players") as Node3D
	for node: Node in players.get_children():
		node.set_physics_process(false)
		node.set_process(false)
	space = get_world_3d().direct_space_state
	exclude = mobs.actor_rids()
	if "--explorer-capture" in OS.get_cmdline_user_args():
		await capture_views()
	else:
		await enemy_scenarios()
		inventory()
		await visual_controls()
		await visual_audit()
		await intersection_audit()
		for index: int in range(3):
			var worker: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
			worker.name = "Explorer%d" % index
			add_child(worker)
			worker.set_physics_process(false)
			worker.set_process(false)
			worker.floor_snap_length = 0.35
			worker.collision_layer = 0
			for actor: Node in players.get_children() + mobs.raiders.get_children():
				worker.add_collision_exception_with(actor as PhysicsBody3D)
			workers.append(worker)
			exclude.append(worker.get_rid())
		await sample()
		connect_cells()
		await explore()
		save_report()
	NetworkManager.stop("explorer finished")
	Audio.set_process(false)
	for node: Node in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node: Node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	world.queue_free()
	for worker: CharacterBody3D in workers:
		worker.queue_free()
	await frames(15)
	FlagstoneFloor.meshes.clear()
	FlagstoneFloor.surfaces.clear()
	triangle_cache.clear()
	mesh_records.clear()
	get_tree().quit(1 if detector_failures > 0 else 0)
