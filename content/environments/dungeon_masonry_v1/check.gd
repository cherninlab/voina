extends SceneTree
## Focused construction proof; no rendering, networking or player-input claim.

func _initialize() -> void:
	var geometry: RedDescentGeometry = RedDescentGeometry.new()
	geometry.paths = []
	geometry.build_room({"id": "masonry_probe", "floor": 0.0, "height": 8.0, "points": PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(6, 8), Vector2(-6, 8)])})
	var wall_hit: float = first_hit(geometry.collision_faces, Vector3(0, 2, 2), Vector3(0, 2, -1))
	var reveal_hit: float = first_hit(geometry.collision_faces, Vector3(-1.8, 2, 2), Vector3(-1.8, 2, -1))
	assert(is_equal_approx(wall_hit, 1.55), "Wall face moved from the existing outline")
	assert(is_equal_approx(reveal_hit, 2.37), "Recess must have 0.82 m of real depth and a closed back")
	for id: String in ["window_bay", "slit_window", "gothic_window", "column", "buttress"]:
		assert(not geometry.module_counts.has(id), "A complete facade/column module was pasted onto the construction")
	geometry.free()
	var pier: RedDescentGeometry = RedDescentGeometry.new()
	pier.stacked_pier(Vector3.ZERO, Basis.IDENTITY, Vector3(0.95, 20, 1.25), 0)
	var blocks: int = 0
	var continuous_shaft: bool = false
	for key: String in pier.batches:
		for transform: Transform3D in pier.batches[key]:
			blocks += 1
			if is_equal_approx(transform.basis.y.length(), 20.0):
				continuous_shaft = is_equal_approx(transform.origin.y, 10.0)
	assert(continuous_shaft and blocks == 3, "Pilaster requires one continuous shaft and only one base/capital")
	assert(pier.batch_meshes.size() == 1, "Shaft must use the shaped batched masonry mesh")
	for key: String in pier.batch_meshes:
		var mesh: Mesh = pier.batch_meshes[key]
		assert(mesh.get_aabb().size.is_equal_approx(Vector3.ONE), "Shaped shaft lost its fitting bounds")
		var lower_width: float = 0.0
		var upper_width: float = 0.0
		var rebate: bool = false
		for vertex: Vector3 in mesh.get_faces():
			if vertex.y < -0.43:
				lower_width = maxf(lower_width, absf(vertex.x))
			if vertex.y > 0.2:
				upper_width = maxf(upper_width, absf(vertex.x))
			if is_equal_approx(vertex.z, 0.4) and absf(vertex.x) < 0.2:
				rebate = true
		assert(upper_width < lower_width * 0.97 and rebate, "Shaft lost its taper or real front rebate")
	pier.free()
	print("MASONRY_OK: 0.82 m blind reveals, continuous wall footprint, shaped 20 m unbroken pier shaft")
	quit()

func first_hit(faces: PackedVector3Array, from: Vector3, to: Vector3) -> float:
	var distance: float = INF
	for index: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1], faces[index + 2])
		if hit is Vector3:
			distance = minf(distance, from.distance_to(hit as Vector3))
	return distance
