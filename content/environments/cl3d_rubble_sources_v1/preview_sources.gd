extends SceneTree
## Standalone T-167 closure/import/material review. No dungeon placement.

const SOURCE_ROOT: String = "res://content/environments/cl3d_rubble_sources_v1/"
const REVIEW_ROOT: String = "res://content/environments/cl3d_rubble_sources_v1/"
var _stage: Node3D
var _camera: Camera3D
var _floor: MeshInstance3D
var _label: Label


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
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_label)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_ROOT + "manifest.json")) as Dictionary
	var assets: Array = manifest["assets"] as Array
	var report: Dictionary = {"engine": Engine.get_version_info(), "sources": [], "textured_previews": [], "normal_disabled_control": "--flat-normal" in OS.get_cmdline_user_args()}
	for entry: Dictionary in assets:
		var asset_id: String = str(entry["id"])
		var levels: Array = entry["lods"] as Array
		for level: int in range(levels.size()):
			var item: Dictionary = levels[level] as Dictionary
			var result: Dictionary = await _inspect(SOURCE_ROOT + str(item["path"]), 0,
				"review/godot/" + asset_id + ".png" if level == 0 and not audit_only else "", "", int(item["triangles"]))
			if not bool(result.get("ok", false)):
				quit(1)
				return
			(report["sources"] as Array).append(result)
		if not audit_only:
			var first: Dictionary = levels[0] as Dictionary
			var preview: Dictionary = await _inspect(SOURCE_ROOT + str(first["path"]), 0,
				"review/godot_textured/" + asset_id + ".png", str(entry["material_hint"]), int(first["triangles"]))
			if not bool(preview.get("ok", false)):
				quit(1)
				return
			(report["textured_previews"] as Array).append(preview)
	var file: FileAccess = FileAccess.open(SOURCE_ROOT + "review/godot-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("RUBBLE_IMPORT_OK: ", (report["sources"] as Array).size(), " LODs, ", (report["textured_previews"] as Array).size(), " material previews")
	quit(0)


func _inspect(path: String, expected_hulls: int, capture: String, material_path: String = "", expected_triangles: int = -1) -> Dictionary:
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
	var triangles: int = 0
	var finish: ShaderMaterial = load(material_path) as ShaderMaterial if not material_path.is_empty() else null
	var has_mapping: bool = true
	if finish != null:
		finish = finish.duplicate() as ShaderMaterial
		finish.set_shader_parameter("mapped", true)
		finish.set_shader_parameter("relief_m", 0.0)
		finish.set_shader_parameter("scale", 4.0 if "terracotta" in material_path else 2.0)
		if "--flat-normal" in OS.get_cmdline_user_args():
			finish.set_shader_parameter("normal_strength", 0.0)
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		triangles += int(mesh.mesh.get_faces().size() / 3.0)
		if finish != null:
			mesh.material_override = finish
			for surface_index: int in range(mesh.mesh.get_surface_count()):
				var arrays: Array = mesh.mesh.surface_get_arrays(surface_index)
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				has_mapping = has_mapping and not tangents.is_empty() and not uvs.is_empty()
		var transformed: AABB = mesh.global_transform * mesh.get_aabb()
		box = box.merge(transformed) if has_bounds else transformed
		has_bounds = true
	var bodies: Array[Node] = instance.find_children("*", "PhysicsBody3D", true, false)
	var shapes: Array[Node] = instance.find_children("*", "CollisionShape3D", true, false)
	var valid: bool = has_bounds and has_mapping and box.size.is_finite() and box.size.length() > 0.01
	for node: Node in bodies:
		valid = valid and (node as Node3D).scale.is_equal_approx(Vector3.ONE)
	for node: Node in shapes:
		var collision: CollisionShape3D = node as CollisionShape3D
		valid = valid and collision.scale.is_equal_approx(Vector3.ONE)
		valid = valid and collision.shape is ConvexPolygonShape3D
	if expected_hulls >= 0:
		valid = valid and shapes.size() == expected_hulls
	valid = valid and box.get_center().length() < 0.00001 and (expected_triangles < 0 or triangles == expected_triangles)
	if not material_path.is_empty():
		valid = valid and finish != null
	if not valid:
		push_error("Prop import audit failed: " + path)
	if valid and not capture.is_empty():
		_label.text = path.get_file().get_basename() + (" | neutral clay" if material_path.is_empty() else " | paired material preview")
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
	var result: Dictionary = {"ok": valid, "path": path, "meshes": meshes.size(), "bodies": bodies.size(), "triangles": triangles, "material": material_path, "mapped_uv_tangents_ok": has_mapping,
		"convex_shapes": shapes.size(), "bounds_position": [box.position.x, box.position.y, box.position.z],
		"bounds_size": [box.size.x, box.size.y, box.size.z], "capture": capture}
	instance.queue_free()
	await process_frame
	return result
