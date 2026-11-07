extends "res://tests/dungeon_explorer.gd"

func capture_views() -> void:
	inventory()
	var cases: Array[Dictionary] = [
		{"name": "choir", "eye": Vector3(32.15, -26.2, -4.3375), "target": Vector3(36, -25.9, 6.25), "pixels": [[405,443],[411,360],[396,333],[329,393],[398,346],[406,469],[412,389],[422,340]]},
		{"name": "first-stair", "eye": Vector3(31,-8.2,-30), "target": Vector3(29.5,-7,-39.5), "pixels": [[1210,480],[1230,510],[1200,540],[1150,540],[1300,500]]},
		{"name": "stair-wedge", "eye": Vector3(39,-4.8,-33), "target": Vector3(37.6,-6,-36), "fov": 65.0, "pixels": [[1330,490],[1290,515],[1200,480],[1340,530]]},
	]
	get_viewport().size = Vector2i(1440,900)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.fov = 90
	for entry: Dictionary in cases:
		camera.fov = float(entry.get("fov", 90.0))
		camera.position = entry["eye"] as Vector3
		camera.look_at(entry["target"] as Vector3)
		for pixel: Array in entry["pixels"] as Array:
			var direction: Vector3 = camera.project_ray_normal(Vector2(float(pixel[0]),float(pixel[1])))
			var origin: Vector3 = camera.global_position
			var hits: Array[Dictionary] = []
			for record: Dictionary in mesh_records:
				var hit: Dictionary = mesh_hit(record, origin, origin + direction * 40)
				if hit.is_empty():
					continue
				hit["distance"] = (hit["position"] as Vector3).distance_to(origin)
				hit["normal_dot_ray"] = (hit["normal"] as Vector3).dot(direction)
				hits.append(hit)
			hits.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return float(a["distance"]) < float(b["distance"]))
			print("SEAM_RAY ",entry["name"]," ",pixel," ",JSON.stringify(hits.slice(0,8)))
	for node: Node in dungeon.find_children("Mortar*", "MeshInstance3D", true, false):
		if "choir" in String(node.name) or "stair_hall" in String(node.name):
			var visual: MeshInstance3D = node as MeshInstance3D
			var material: Material = visual.material_override
			print("CORE_MATERIAL ",node.get_path()," type=",material.get_class()," name=",material.resource_name)
