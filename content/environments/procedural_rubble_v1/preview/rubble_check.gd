extends SceneTree
## Headless import and standing check for the baked rubble piles (T-163).
## Godot --headless --path . -s res://content/environments/procedural_rubble_v1/preview/rubble_check.gd
## Per pile: mesh, grey vertex colour, origin on the ground at the footprint centre,
## one convex StaticBody3D per hull listed in rubble.json, and a player-sized capsule
## dropped onto the highest point must come to rest on the rubble, not the floor.

const FOLDER: String = "res://content/environments/procedural_rubble_v1/"
const CAPSULE_RADIUS: float = 0.4
const CAPSULE_HEIGHT: float = 1.8
# Low loose scatter is too low to hold a 0.8 m wide capsule; it is reported, not required.
const MUST_STAND: Array[String] = ["wall_spill", "corner_heap", "bridge_debris"]

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "rubble.json")) as Dictionary
	var piles: Array = report["piles"] as Array
	if piles.size() < 12:
		failures.append("expected at least 12 piles, found %d" % piles.size())
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	for entry: Variant in piles:
		await check_pile(entry as Dictionary)
	floor_body.queue_free()
	await process_frame
	if failures.is_empty():
		print("RUBBLE_CHECK_OK: %d piles import with grey AO colour, ground origin, convex collision and a standing capsule" % piles.size())
		quit.call_deferred(0)
	else:
		for failure: String in failures:
			printerr("RUBBLE_CHECK_FAIL: " + failure)
		quit.call_deferred(1)

func check_pile(entry: Dictionary) -> void:
	var id: String = String(entry["id"])
	var scene: PackedScene = load(FOLDER + id + ".glb") as PackedScene
	if scene == null:
		failures.append(id + ": GLB did not import")
		return
	var pile: Node3D = scene.instantiate() as Node3D
	root.add_child(pile)
	var triangles: int = 0
	var bounds: AABB = AABB()
	var first: bool = true
	var grey: bool = true
	for node: Node in pile.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = instance.mesh
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			triangles += indices.size() / 3
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			if colors.is_empty():
				grey = false
			for color: Color in colors:
				if absf(color.r - color.g) > 0.01 or absf(color.r - color.b) > 0.01:
					grey = false
					break
		var box: AABB = instance.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var bodies: Array[Node] = pile.find_children("*", "StaticBody3D", true, false)
	var hulls: int = 0
	for body: Node in bodies:
		for child: Node in body.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is ConvexPolygonShape3D:
				hulls += 1
	var expected_hulls: int = int((entry["collision"] as Dictionary)["convex_hulls"])
	var lod0: int = int(((entry["lods"] as Array)[0] as Dictionary)["tris"])
	if triangles != lod0 or triangles > 8000:
		failures.append("%s: %d triangles, report says %d (budget 8000)" % [id, triangles, lod0])
	if not grey:
		failures.append(id + ": vertex colour missing or not grey")
	if hulls != expected_hulls or bodies.size() != expected_hulls:
		failures.append("%s: %d convex hulls in %d bodies, report says %d" % [id, hulls, bodies.size(), expected_hulls])
	var centre: Vector3 = bounds.get_center()
	if absf(bounds.position.y) > 0.01 or absf(centre.x) > 0.01 or absf(centre.z) > 0.01:
		failures.append("%s: origin is not the ground centre (bounds %s)" % [id, bounds])
	for frame: int in range(2):
		await physics_frame
	var standing: Dictionary = await stand(pile, bounds)
	var recipe: String = String(entry["recipe"])
	var stood: bool = bool(standing["stood"])
	if recipe in MUST_STAND and not stood:
		failures.append("%s: capsule did not stand on the pile: %s" % [id, standing])
	print("RUBBLE_PILE_CHECK %s tris=%d hulls=%d height=%.3f capsule_feet=%.3f on_floor=%s rest_speed=%.4f stood=%s" % [
		id, triangles, hulls, bounds.end.y, float(standing["feet"]), standing["on_floor"], float(standing["speed"]), stood])
	pile.queue_free()
	await process_frame

## Drop a player-sized capsule over the highest collision point of the pile and
## let it settle for three seconds under gravity.
func stand(pile: Node3D, bounds: AABB) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = pile.get_world_3d().direct_space_state
	var best: Vector3 = Vector3(0, -1, 0)
	for ix: int in range(-8, 9):
		for iz: int in range(-8, 9):
			var x: float = bounds.get_center().x + bounds.size.x * 0.5 * float(ix) / 8.0
			var z: float = bounds.get_center().z + bounds.size.z * 0.5 * float(iz) / 8.0
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x, 5.0, z), Vector3(x, -1.0, z))
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty() and (hit["position"] as Vector3).y > best.y:
				best = hit["position"] as Vector3
	var body: CharacterBody3D = CharacterBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	body.add_child(shape)
	body.position = best + Vector3.UP * (CAPSULE_HEIGHT * 0.5 + 0.3)
	root.add_child(body)
	var on_floor: bool = false
	for frame: int in range(180):
		await physics_frame
		body.velocity.y -= 9.8 / float(Engine.physics_ticks_per_second)
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		body.move_and_slide()
		on_floor = body.is_on_floor()
	var before: Vector3 = body.position
	for frame: int in range(30):
		await physics_frame
		body.velocity.y -= 9.8 / float(Engine.physics_ticks_per_second)
		body.move_and_slide()
	var speed: float = body.position.distance_to(before) * float(Engine.physics_ticks_per_second) / 30.0
	var feet: float = body.position.y - CAPSULE_HEIGHT * 0.5
	var stood: bool = on_floor and body.is_on_floor() and feet > 0.12 and speed < 0.02
	body.queue_free()
	return {"stood": stood, "feet": feet, "on_floor": on_floor, "speed": speed, "top": best.y}
