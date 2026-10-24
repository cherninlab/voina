extends SceneTree
## Standalone review/audit only. Does not place props in Red Descent.

const SOURCE_ROOT: String = "res://content/environments/procedural_props_aged_v1/"
const REVIEW_ROOT: String = "res://content/environments/red_descent/review/props_aged_v1/"
var _stage: Node3D
var _camera: Camera3D
var _floor: MeshInstance3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audit_only: bool = "--audit-only" in OS.get_cmdline_user_args()
	_stage = Node3D.new()
	root.add_child(_stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.19, 0.20)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72, 0.74, 0.78)
	environment.environment.ambient_light_energy = 0.65
	_stage.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	_stage.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 100.0
	_stage.add_child(_camera)
	_camera.make_current()
	_floor = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(100.0, 100.0)
	_floor.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.31, 0.32, 0.33)
	floor_material.roughness = 0.9
	_floor.material_override = floor_material
	_stage.add_child(_floor)
	var sources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_ROOT + "sources.json")) as Dictionary
	var report: Dictionary = {"engine": Engine.get_version_info(), "sources": [], "sets": [], "audit_only": audit_only}
	var source_ids: Array = sources.keys()
	source_ids.sort()
	for asset_id: String in source_ids:
		var entry: Dictionary = sources[asset_id] as Dictionary
		var levels: Array = entry["lods"] as Array
		for level: int in range(levels.size()):
			var item: Dictionary = levels[level] as Dictionary
			var result: Dictionary = await _inspect("res://" + str(item["path"]), -1,
				"cl3d_v1/godot/" + asset_id + ".png" if level == 0 and not audit_only else "")
			if not bool(result.get("ok", false)):
				quit(1)
				return
			(report["sources"] as Array).append(result)
	var set_file: String = SOURCE_ROOT + "sets.json"
	if FileAccess.file_exists(set_file):
		var sets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(set_file)) as Dictionary
		var set_ids: Array = sets.keys()
		set_ids.sort()
		for set_id: String in set_ids:
			var entry: Dictionary = sets[set_id] as Dictionary
			var result: Dictionary = await _inspect("res://" + str(entry["glb"]), int(entry["collision_hulls"]),
				"physics_v1/godot/" + set_id + ".png" if not audit_only else "")
			if not bool(result.get("ok", false)):
				quit(1)
				return
			(report["sets"] as Array).append(result)
	var report_path: String = REVIEW_ROOT + "cl3d_v1/checks/godot-audit.json"
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("PROP_IMPORT_OK: ", (report["sources"] as Array).size(), " source LODs, ", (report["sets"] as Array).size(), " sets")
	quit(0)


func _inspect(path: String, expected_hulls: int, capture: String) -> Dictionary:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("Cannot import prop scene: " + path)
		return {"ok": false, "path": path}
	var instance: Node3D = scene.instantiate() as Node3D
	_stage.add_child(instance)
	await process_frame
	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		meshes.append(instance)
	var box: AABB = AABB()
	var has_bounds: bool = false
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		var transformed: AABB = mesh.global_transform * mesh.get_aabb()
		box = box.merge(transformed) if has_bounds else transformed
		has_bounds = true
	var bodies: Array[Node] = instance.find_children("*", "PhysicsBody3D", true, false)
	var shapes: Array[Node] = instance.find_children("*", "CollisionShape3D", true, false)
	var valid: bool = has_bounds and box.size.is_finite() and box.size.length() > 0.01
	for node: Node in bodies:
		valid = valid and (node as Node3D).scale.is_equal_approx(Vector3.ONE)
	for node: Node in shapes:
		var collision: CollisionShape3D = node as CollisionShape3D
		valid = valid and collision.scale.is_equal_approx(Vector3.ONE)
		valid = valid and collision.shape is ConvexPolygonShape3D
	if expected_hulls >= 0:
		valid = valid and shapes.size() == expected_hulls
	if not valid:
		push_error("Prop import audit failed: " + path)
	if valid and not capture.is_empty():
		var span: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var target: Vector3 = box.get_center()
		_camera.size = span * 1.8
		_camera.position = target + Vector3(1.4, 1.1, 2.0).normalized() * span * 3.0
		_camera.look_at(target)
		_floor.position.y = box.position.y - 0.004
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var destination: String = ProjectSettings.globalize_path(REVIEW_ROOT + capture)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var saved: Error = root.get_texture().get_image().save_png(destination)
		valid = valid and saved == OK
	var result: Dictionary = {"ok": valid, "path": path, "meshes": meshes.size(), "bodies": bodies.size(),
		"convex_shapes": shapes.size(), "bounds_position": [box.position.x, box.position.y, box.position.z],
		"bounds_size": [box.size.x, box.size.y, box.size.z], "capture": capture}
	instance.queue_free()
	await process_frame
	return result
