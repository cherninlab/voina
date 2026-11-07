extends "res://content/environments/red_descent/upper_crossing_v1/review/capture_diagnostics.gd"
## Actual game inputs for the parallel local Krea style review. No game edits.

func review_passes() -> PackedStringArray:
	if "--near-depth-only" in OS.get_cmdline_user_args():
		return PackedStringArray(["depth-near"])
	return PackedStringArray(["color", "depth", "depth-near", "normals"])

func review_views() -> Array[Array]:
	var views: Array[Array] = []
	for room: Dictionary in rooms:
		if String(room["id"]) == "entry":
			continue
		var polygon: PackedVector2Array = room["points"] as PackedVector2Array
		var centre: Vector2 = Vector2.ZERO
		for point: Vector2 in polygon:
			centre += point / float(polygon.size())
		var eye: Vector3 = Vector3(centre.x, float(room["floor"]) + 1.8, centre.y)
		var valid: bool = false
		for corner: Vector2 in polygon:
			var candidate: Vector2 = centre.lerp(corner, 0.55)
			var position: Vector3 = Vector3(candidate.x, float(room["floor"]) + 1.8, candidate.y)
			if valid_inspection_eye(position):
				eye = position
				valid = true
				break
		if not valid:
			valid = valid_inspection_eye(eye)
		print("PACK_CAMERA: ", room["id"], " collision_clear=", valid, " eye=", eye)
		if String(room["id"]) == "first_stair_hall":
			# The automatic corner is under the upper flight. Stand at the
			# lower landing so the actual ascending stair is visible.
			eye = Vector3(31, -8.2, -30)
			views.append(["room-first_stair_hall", eye, Vector3(29.5, -7.0, -39.5), 90.0])
		else:
			views.append(["room-" + String(room["id"]), eye, Vector3(centre.x, eye.y + 0.3, centre.y), 90.0])
	views.append(CaptureViews.UPPER_CROSSING_VIEWS[0])
	views.append(CaptureViews.UPPER_CROSSING_VIEWS[2])
	for id: String in ["low_span", "root_tunnel"]:
		var route: Dictionary = routes.filter(func(path: Dictionary) -> bool: return path["id"] == id)[0]
		var points: PackedVector3Array = route["points"] as PackedVector3Array
		var segment: int = (points.size() - 2) / 2 if id == "low_span" else 0
		var eye: Vector3 = points[segment].lerp(points[segment + 1], 0.22) + Vector3.UP * 1.8
		views.append(["route-" + id, eye, points[segment + 1] + Vector3.UP * 1.3, 90.0])
	return views
