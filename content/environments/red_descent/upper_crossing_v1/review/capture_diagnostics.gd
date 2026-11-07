extends "res://tests/dungeon_explorer.gd"
## Matched diagnostic cameras for this asset iteration.
const CaptureViews: GDScript = preload("res://scripts/capture_bridges.gd")

func intersection_audit() -> void:
	var walls: Array[Dictionary] = []
	var stone: Array[Dictionary] = []
	for record: Dictionary in mesh_records:
		var path: String = record["path"]
		if record.has("instance") and "/Architecture/wall_" in path:
			walls.append(record)
		elif "/StoneRoom_" in path or "/StonePassage_" in path:
			stone.append(record)
	var found: Dictionary[Vector3, bool] = {}
	for wall: Dictionary in walls:
		var transform: Transform3D = wall["transform"]
		var bounds: AABB = transform * (wall["bounds"] as AABB)
		var faces: PackedVector3Array = (wall["mesh"] as Mesh).get_faces()
		for other: Dictionary in stone:
			if not bounds.intersects((other["transform"] as Transform3D) * (other["bounds"] as AABB)):
				continue
			for i: int in range(faces.size()):
				var j: int = i - (i % 3) + (i + 1) % 3
				var a: Vector3 = transform * faces[i]
				var b: Vector3 = transform * faces[j]
				var hit: Dictionary = mesh_hit(other, a, b)
				if hit.is_empty():
					continue
				var location: Vector3 = hit["position"]
				var key: Vector3 = location.snapped(Vector3.ONE * 0.04)
				if found.has(key):
					continue
				found[key] = true
				overlap_points.append({"position": vector(location), "a": wall["path"], "b": other["path"]})
				if found.size() == 100:
					break
			if found.size() == 100:
				break
		if found.size() == 100:
			break
	await get_tree().process_frame
	report["intersections"] = {"samples": overlap_points, "limit": 300, "method": "Edges of runtime shaft wall boxes intersecting baked room or passage triangles, up to 100 unique locations per region.", "limits": "Contacts include intentional masonry connections. This is an edge sample, so it does not prove the absence of intersections."}


func diagnostic_shader() -> Shader:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 explorer_color : source_color = vec4(1.0);
uniform int mode = 0;
uniform float depth_m = 30.0;
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
	else if (mode == 1) { ALBEDO = vec3(clamp(-VERTEX.z / depth_m, 0.0, 1.0)); }
	else if (mode == 2) { ALBEDO = normalize(world_normal) * 0.5 + 0.5; }
	else { ALBEDO = vec3(0.012); }
}"""
	return shader


func capture_views() -> void:
	world.get_node("GameUI").set_process(false)
	inventory()
	var regions: Array[AABB] = [
		AABB(Vector3(14, -32, -18), Vector3(20, 35, 33)),
		AABB(Vector3(-32, -28, -23), Vector3(17, 34, 16)),
		AABB(Vector3(0, -23, 17), Vector3(20, 14, 19)),
	]
	var indexed: Array[Dictionary] = mesh_records.duplicate()
	for region: AABB in regions:
		mesh_records.assign(indexed.filter(func(record: Dictionary) -> bool:
			return region.intersects((record["transform"] as Transform3D) * (record["bounds"] as AABB))
		))
		await intersection_audit()
	var telemetry: Dictionary = {"cells": [], "intersections": report["intersections"], "geometry": geometry}
	var samples: FileAccess = FileAccess.open(output.path_join("intersection-samples.json"), FileAccess.WRITE)
	samples.store_string(JSON.stringify(telemetry["intersections"], "\t"))
	# These passes inspect static architecture; actors would otherwise keep their original
	# shaders in a depth/normal image and contaminate its meaning.
	(world.get("players") as Node3D).visible = false
	mobs.visible = false
	get_viewport().size = Vector2i(1440, 900)
	get_viewport().disable_3d = false
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 90.0
	var debug_environment: Environment = Environment.new()
	debug_environment.background_mode = Environment.BG_COLOR
	debug_environment.background_color = Color.BLACK
	debug_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var views: Array[Dictionary] = []
	var selected: PackedStringArray = PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-views="):
			selected = argument.trim_prefix("--capture-views=").split(",")
	for entry: Array in CaptureViews.UPPER_CROSSING_VIEWS:
		if not selected.is_empty() and not selected.has(String(entry[0])):
			continue
		var eye: Vector3 = entry[1] as Vector3
		var target: Vector3 = entry[2] as Vector3
		views.append({"name": entry[0], "eye": vector(eye), "direction": vector(target - eye), "head_offset_m": 0.0, "fov": float(entry[3])})

	dungeon.get_node("DeepWater").hide()
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
		camera.fov = float(view["fov"])
		camera.position = point(view["eye"] as Array) + Vector3.UP * float(view["head_offset_m"])
		var direction: Vector3 = point(view["direction"] as Array)
		camera.look_at(camera.position + direction, Vector3.FORWARD if absf(direction.normalized().y) > 0.99 else Vector3.UP)
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
		for pass_name: String in ["color", "albedo", "objects", "depth", "depth-far", "normals", "intersections", "collision"]:
			var mode: int = {"objects": 0, "depth": 1, "depth-far": 1, "normals": 2}.get(pass_name, 3)
			var material_view: bool = pass_name in ["color", "albedo", "intersections"]
			dungeon.get_node("DeepWater").visible = material_view
			camera.environment = null if material_view else debug_environment
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_UNSHADED if pass_name in ["albedo", "intersections"] else Viewport.DEBUG_DRAW_DISABLED
			crossings.visible = pass_name == "intersections"
			collision_overlay.visible = pass_name == "collision"
			clearance.visible = pass_name == "clearance"
			for index: int in range(visuals.size()):
				visuals[index].material_override = originals[index] if material_view else materials[index]
				materials[index].set_shader_parameter("mode", mode)
				materials[index].set_shader_parameter("depth_m", 65.0 if pass_name == "depth-far" else 30.0)
			for frame: int in range(8 if material_view else 4):
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

