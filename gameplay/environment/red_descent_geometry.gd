class_name RedDescentGeometry
extends Node3D
## Fixed architecture. Batched visual blocks, one immutable concave collision mesh.

var materials: Dictionary[String, Material] = {}
var torch_posts: Array[Vector3] = []
var rooms: Array[Dictionary] = RedDescentLayout.rooms()
var paths: Array[Dictionary] = RedDescentLayout.routes()
var batches: Dictionary[String, Array] = {}
var batch_colors: Dictionary[String, Array] = {}
var batch_materials: Dictionary[String, String] = {}
var surfaces: Dictionary[String, PackedVector3Array] = {}
var collision_faces: PackedVector3Array = PackedVector3Array()
var cube_faces: PackedVector3Array = BoxMesh.new().get_faces()

func build() -> void:
	name = "Architecture"
	for room: Dictionary in rooms:
		build_room(room)
	for index: int in range(paths.size()):
		build_path(paths[index], index < RedDescentLayout.MAIN_PATHS)
	build_vault(RedDescentLayout.outline(), false)
	build_vault(RedDescentLayout.spine(), true)
	# The void's base stops physics falls; the player recovery threshold is above it.
	piece(Vector3(150, 1, 150), Vector3(0, -60, 0), "dark", Basis.IDENTITY, true)
	flush()
	print("RED_DESCENT_GEOMETRY_READY: %d routes, %d rooms, %d lit landmarks, sloping crossings" % [paths.size(), rooms.size(), torch_posts.size()])

func piece(size: Vector3, at: Vector3, material: String, basis: Basis = Basis.IDENTITY, solid: bool = false, color: Color = Color.WHITE) -> void:
	if material == "collision":
		for vertex: Vector3 in cube_faces:
			collision_faces.append(at + basis * (vertex * size))
		return
	var key: String = "%s:%d:%d:%d" % [material, floori(at.x / 18.0), floori(at.y / 12.0), floori(at.z / 18.0)]
	if not batches.has(key):
		batches[key] = []
		batch_colors[key] = []
		batch_materials[key] = material
	batches[key].append(Transform3D(basis * Basis.from_scale(size), at))
	batch_colors[key].append(color)
	if solid:
		for vertex: Vector3 in cube_faces:
			collision_faces.append(at + basis * (vertex * size))

func face(a: Vector3, b: Vector3, c: Vector3, material: String, solid: bool = true) -> void:
	var data: PackedVector3Array = surfaces.get(material, PackedVector3Array())
	# Godot renders clockwise front faces; callers supply an outward cross product.
	data.append_array(PackedVector3Array([a, c, b]))
	surfaces[material] = data
	if solid:
		collision_faces.append_array(PackedVector3Array([a, b, c]))

func polygon_surface(polygon: PackedVector2Array, y: float, material: String, upward: bool = true) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for index: int in range(0, indices.size(), 3):
		var a: Vector2 = polygon[indices[index]]
		var b: Vector2 = polygon[indices[index + 1]]
		var c: Vector2 = polygon[indices[index + 2]]
		var va: Vector3 = Vector3(a.x, y, a.y)
		var vb: Vector3 = Vector3(b.x, y, b.y)
		var vc: Vector3 = Vector3(c.x, y, c.y)
		if ((vb - va).cross(vc - va).y > 0.0) != upward:
			face(va, vc, vb, material)
		else:
			face(va, vb, vc, material)

func in_room(point: Vector3, tolerance: float = 0.3) -> bool:
	for room: Dictionary in rooms:
		if absf(point.y - float(room["floor"])) <= tolerance and Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), room["points"] as PackedVector2Array):
			return true
	return false

func opening(point: Vector2, floor_y: float) -> bool:
	for path: Dictionary in paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
			var length: float = Vector2(b.x - a.x, b.z - a.z).length()
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(length, 0.001)
			if near.distance_to(point) < float(path["width"]) * 0.5 + 0.6 and absf(lerpf(a.y, b.y, t) - floor_y) < 1.0:
				return true
	return false

func junction(point: Vector3, own_path: String, own_segment: int) -> bool:
	# Side walls must stop at a joining passage, including skewed T intersections.
	for path: Dictionary in paths:
		var route: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(route.size() - 1):
			if String(path["id"]) == own_path and index == own_segment:
				continue
			var a: Vector3 = route[index]
			var b: Vector3 = route[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)
			if near.distance_to(Vector2(point.x, point.z)) < float(path["width"]) * 0.5 + 0.7 and absf(lerpf(a.y, b.y, t) - point.y) < 2.5:
				return true
	return false

func build_room(room: Dictionary) -> void:
	var polygon: PackedVector2Array = room["points"] as PackedVector2Array
	var y: float = float(room["floor"])
	var height: float = float(room["height"])
	polygon_surface(polygon, y, "floor")
	polygon_surface(polygon, y - 0.5, "stone", false)
	polygon_surface(polygon, y + height, "stone", false)
	for index: int in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var delta: Vector2 = b - a
		var count: int = ceili(delta.length() / 1.5)
		var basis: Basis = Basis(Vector3.UP, -atan2(delta.y, delta.x))
		var door_start: int = -1
		for step: int in range(count):
			var mid: Vector2 = a.lerp(b, (float(step) + 0.5) / float(count))
			var door: bool = opening(mid, y)
			var spans: Array[Vector2] = [Vector2(y, y + height)]
			for level: float in portal_levels(mid, 0.1):
				var next: Array[Vector2] = []
				for span: Vector2 in spans:
					if level + 4.2 <= span.x or level - 0.2 >= span.y:
						next.append(span)
					else:
						if level - 0.2 > span.x:
							next.append(Vector2(span.x, level - 0.2))
						if level + 4.2 < span.y:
							next.append(Vector2(level + 4.2, span.y))
				spans = next
			for span: Vector2 in spans:
				piece(Vector3(delta.length() / float(count) + 0.04, span.y - span.x, 0.9), Vector3(mid.x, (span.x + span.y) * 0.5, mid.y), "stone", basis, true)
			if door and door_start < 0:
				door_start = step
			if door_start >= 0 and (not door or step == count - 1):
				var end: int = step if not door else step + 1
				var center: Vector2 = a.lerp(b, float(door_start + end) * 0.5 / float(count))
				arch(Vector3(center.x, y, center.y), delta.normalized(), float(end - door_start) * delta.length() / float(count) * 0.5)
				door_start = -1
		# Tall worn pilasters give the side halls scale without a flat wall of tiny bricks.
		if delta.length() > 5.0:
			for t: float in [0.18, 0.82]:
				var at: Vector2 = a.lerp(b, t)
				piece(Vector3(0.65, height, 1.25), Vector3(at.x, y + height * 0.5, at.y), "trim", basis)
			# Sealed burial recesses and their worn arch borders break up the side halls.
			var inward: Vector2 = Vector2(-delta.y, delta.x).normalized()
			for t: float in [0.35, 0.65]:
				var at: Vector2 = a.lerp(b, t)
				if opening(at, y):
					continue
				var niche: Vector3 = Vector3(at.x + inward.x * 0.48, y, at.y + inward.y * 0.48)
				piece(Vector3(1.4, 2.4, 0.06), niche + Vector3.UP * 1.6, "dark", basis)
				for side: float in [-1.0, 1.0]:
					piece(Vector3(0.2, 2.2, 0.24), niche + Vector3(delta.normalized().x, 0, delta.normalized().y) * side * 0.8 + Vector3.UP * 1.5, "trim", basis)
				arch(niche, delta.normalized(), 0.85)
	var centroid: Vector2 = Vector2.ZERO
	for point: Vector2 in polygon:
		centroid += point
	centroid /= float(polygon.size())
	for index: int in [0, polygon.size() / 2]:
		var at: Vector2 = centroid.lerp(polygon[index], 0.78)
		torch_posts.append(Vector3(at.x, y, at.y))
	# Fallen chips remain beside the wall and clear of all route centers.
	for index: int in range(polygon.size()):
		var at: Vector2 = polygon[index].lerp(centroid, 0.12)
		if not opening(at, y):
			for chip: int in range(3):
				var n: float = float(posmod(index * 17 + chip * 31, 19)) / 19.0
				piece(Vector3(0.25 + n * 0.4, 0.18 + n * 0.18, 0.35 + n * 0.25), Vector3(at.x + n, y + 0.1, at.y - float(chip) * 0.25), "trim", Basis.from_euler(Vector3(n * 0.2, n * 5, -n * 0.15)), false, Color(0.65 + n * 0.25, 0.65 + n * 0.25, 0.65 + n * 0.25))
	if String(room["id"]) in ["chapel", "nave", "choir", "restraint"]:
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = Vector3(centroid.x + side * 5.0, y, centroid.y + 5.0)
			piece(Vector3(1.1, minf(height - 1.0, 14.0), 1.1), at + Vector3.UP * minf(height - 1.0, 14.0) * 0.5, "trim", Basis.IDENTITY, true)
			piece(Vector3(1.8, 0.35, 1.8), at + Vector3.UP * 0.175, "stone", Basis.IDENTITY, true)

func build_path(path: Dictionary, light_route: bool) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var material: String = "wood" if bool(path["wood"]) else "floor"
	var enclosed: bool = bool(path["enclosed"])
	var edges: PackedVector3Array = PackedVector3Array()
	for node: int in range(points.size()):
		var before: Vector3 = points[node] - points[maxi(0, node - 1)]
		var after: Vector3 = points[mini(points.size() - 1, node + 1)] - points[node]
		for neighbor: Dictionary in paths:
			if String(neighbor["id"]) == String(path["id"]):
				continue
			var other: PackedVector3Array = neighbor["points"] as PackedVector3Array
			if node == 0 and points[node].distance_to(other[-1]) < 0.02:
				before = other[-1] - other[-2]
			if node == points.size() - 1 and points[node].distance_to(other[0]) < 0.02:
				after = other[1] - other[0]
		before.y = 0.0
		after.y = 0.0
		if before.is_zero_approx():
			before = after
		if after.is_zero_approx():
			after = before
		var incoming: Vector3 = before.normalized()
		var outgoing: Vector3 = after.normalized()
		var tangent: Vector3 = (incoming + outgoing).normalized()
		var side: Vector3 = Vector3(-tangent.z, 0, tangent.x)
		edges.append(side * width * 0.5 / maxf(0.65, tangent.dot(incoming)))
	var since_light: float = 15.0
	for index: int in range(points.size() - 1):
		var from: Vector3 = points[index]
		var to: Vector3 = points[index + 1]
		var direction: Vector3 = (to - from).normalized()
		var basis: Basis = Basis.looking_at(direction, Vector3.UP)
		var side: Vector3 = basis.x
		var steps: int = maxi(1, ceili(from.distance_to(to) / 1.4))
		for step: int in range(steps):
			var a: Vector3 = from.lerp(to, float(step) / float(steps))
			var b: Vector3 = from.lerp(to, float(step + 1) / float(steps))
			var at: Vector3 = (a + b) * 0.5
			var length: float = a.distance_to(b)
			var room_floor: bool = in_room(a) and in_room(b)
			if not room_floor:
				# One shared ribbon across each turn: no horizontal landing lips on ramps.
				var edge_a: Vector3 = edges[index].lerp(edges[index + 1], float(step) / float(steps))
				var edge_b: Vector3 = edges[index].lerp(edges[index + 1], float(step + 1) / float(steps))
				face(a - edge_a, a + edge_a, b - edge_b, material)
				face(a + edge_a, b + edge_b, b - edge_b, material)
				face(a - edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, a + edge_a - Vector3.UP * 0.32, "wood" if bool(path["wood"]) else "stone")
				face(a + edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, b + edge_b - Vector3.UP * 0.32, "wood" if bool(path["wood"]) else "stone")
				if enclosed:
					var roof: float = 3.7 if String(path["id"]) in ["root_tunnel", "cave_bypass"] else 4.2
					for sign_value: float in [-1.0, 1.0]:
						var edge: Vector3 = at + side * sign_value * (width * 0.5 + 0.3)
						if not junction(edge, String(path["id"]), index):
							piece(Vector3(0.65, roof + absf(a.y - b.y), length + 0.12), edge + Vector3.UP * roof * 0.5, "stone", Basis(Vector3.UP, atan2(-direction.x, -direction.z)), true)
					piece(Vector3(width + 1.0, 0.55, length + 0.1), at + Vector3.UP * (roof + 0.25), "stone", basis, true)
				else:
					for sign_value: float in [-1.0, 1.0]:
						var edge: Vector3 = at + side * sign_value * (width * 0.5 - 0.08)
						if junction(edge, String(path["id"]), index):
							continue
						if Geometry2D.is_point_in_polygon(Vector2(edge.x, edge.z), RedDescentLayout.spine()):
							continue
						piece(Vector3(0.12, 0.86, length + 0.1), edge + Vector3.UP * 0.55, "collision", basis, true)
						for link: int in range(4):
							var t0: float = float(link) * 0.25
							var t1: float = float(link + 1) * 0.25
							var p0: Vector3 = edge + direction * length * (t0 - 0.5) + Vector3.UP * (0.98 - 0.18 * sin(PI * (float(step % 2) + t0) * 0.5))
							var p1: Vector3 = edge + direction * length * (t1 - 0.5) + Vector3.UP * (0.98 - 0.18 * sin(PI * (float(step % 2) + t1) * 0.5))
							beam(p0, p1, 0.035, "iron")
						if step % 2 == 0:
							piece(Vector3(0.15, 1.12, 0.15), edge - direction * length * 0.5 + Vector3.UP * 0.56, "wood")
						piece(Vector3(0.24, 0.4, length + 0.1), edge - Vector3.UP * 0.4, "wood", basis)
					if bool(path["wood"]):
						for plank: int in range(4):
							var offset: float = (float(plank) - 1.5) * length * 0.25
							var shade: float = 0.78 + float(posmod(index * 37 + step * 11 + plank * 13, 17)) * 0.023
							piece(Vector3(width + 0.16, 0.09, length * 0.25 - 0.035), at + direction * offset - basis.y * 0.035, "wood", basis, false, Color(shade, shade, shade))
				since_light += length
				if light_route and since_light >= 13.0:
					torch_posts.append(at + side * (width * 0.5 - 0.35))
					since_light = 0.0
	# Supports stay below the shared walking ribbon.
	for point: Vector3 in points:
		if in_room(point):
			continue
		if not enclosed:
			# Masonry corbels and timber braces are below the walking surface.
			piece(Vector3(width * 0.9, 0.7, width * 0.9), point - Vector3.UP * 0.7, "stone")
			for sign_value: float in [-1.0, 1.0]:
				beam(point + Vector3(sign_value * width * 0.4, -0.6, 0), point + Vector3(sign_value * width * 1.4, -4.0, 0), 0.3, "wood")

func beam(from: Vector3, to: Vector3, width: float, material: String) -> void:
	var up: Vector3 = Vector3.FORWARD if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	piece(Vector3(width, width, from.distance_to(to)), (from + to) * 0.5, material, Basis.looking_at(to - from, up))

func arch(at: Vector3, tangent: Vector2, radius: float) -> void:
	var r: float = clampf(radius, 0.65, 3.0)
	var direction: Vector3 = Vector3(tangent.x, 0, tangent.y)
	var basis: Basis = Basis(Vector3.UP, -atan2(tangent.y, tangent.x))
	for segment: int in range(9):
		var angle: float = PI * float(segment) / 8.0
		var point: Vector3 = at + direction * cos(angle) * r + Vector3.UP * (2.5 + sin(angle) * r * 0.65)
		piece(Vector3(r * 0.42, 0.45, 1.08), point, "trim", basis * Basis(Vector3.BACK, atan2(0.65 * cos(angle), -sin(angle))))

func portal_levels(point: Vector2, radius: float) -> Array[float]:
	var result: Array[float] = []
	for path: Dictionary in paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
			if near.distance_to(point) > radius + float(path["width"]) * 0.5 + 0.35:
				continue
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(0.001, Vector2(b.x - a.x, b.z - a.z).length())
			var y: float = lerpf(a.y, b.y, t)
			var unique: bool = true
			for existing: float in result:
				if absf(existing - y) < 2.0:
					unique = false
			if unique:
				result.append(y)
	return result

func build_vault(polygon: PackedVector2Array, central: bool) -> void:
	for index: int in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var delta: Vector2 = b - a
		var tangent: Vector2 = delta.normalized()
		var normal: Vector2 = Vector2(tangent.y, -tangent.x) * (-1.0 if central else 1.0)
		var middle: Vector2 = (a + b) * 0.5
		var basis: Basis = Basis(Vector3.UP, -atan2(tangent.y, tangent.x))
		# Collision stays at the actual wall outline; recesses are cut into a separate facing.
		
		var count: int = maxi(1, roundi(delta.length() / 4.8))
		for column: int in range(count):
			var center: Vector2 = a.lerp(b, (float(column) + 0.5) / float(count))
			var width: float = delta.length() / float(count)
			var doors: Array[float] = []
			if not central:
				doors = portal_levels(center, width * 0.5)
			var spans: Array[Vector2] = [Vector2(-48, 14)]
			for floor_y: float in doors:
				var next: Array[Vector2] = []
				for span: Vector2 in spans:
					if floor_y + 4.8 <= span.x or floor_y - 0.25 >= span.y:
						next.append(span)
					else:
						if floor_y - 0.25 > span.x:
							next.append(Vector2(span.x, floor_y - 0.25))
						if floor_y + 4.8 < span.y:
							next.append(Vector2(floor_y + 4.8, span.y))
				spans = next
			for span: Vector2 in spans:
				piece(Vector3(width + 0.05, span.y - span.x, 0.8), Vector3(center.x + normal.x * 0.45, (span.x + span.y) * 0.5, center.y + normal.y * 0.45), "dark", basis, true)
			for door_y: float in doors:
				arch(Vector3(center.x, door_y, center.y), tangent, width * 0.48)
			for row: int in range(10):
				var y: float = -46.0 + float(row) * 6.0
				var at: Vector3 = Vector3(center.x, y, center.y)
				var doorway: bool = false
				for floor_y: float in doors:
					if y < floor_y + 4.8 and y + 6.0 > floor_y - 0.25:
						doorway = true
				if doorway:
					continue
				var opening_width: float = minf(1.8, width * 0.48)
				for side: float in [-1.0, 1.0]:
					piece(Vector3((width - opening_width) * 0.5, 6, 1.0), at + Vector3(tangent.x, 0, tangent.y) * side * (width + opening_width) * 0.25 + Vector3.UP * 3, "stone", basis)
				piece(Vector3(opening_width, 1.0, 1.0), at + Vector3.UP * 0.5, "stone", basis)
				piece(Vector3(opening_width, 2.5, 1.0), at + Vector3.UP * 4.75, "stone", basis)
				for side: float in [-1.0, 1.0]:
					piece(Vector3(0.22, 2.0, 1.08), at + Vector3(tangent.x, 0, tangent.y) * side * (opening_width * 0.5 + 0.02) + Vector3.UP * 2.0, "trim", basis)
				arch(at + Vector3.UP * 0.4, tangent, opening_width * 0.5)
				if not central and row in [3, 6] and posmod(index * 3 + column, 4) == 0:
					torch_posts.append(at - Vector3(normal.x, 0, normal.y) * 1.1 + Vector3.UP * 0.8)
	polygon_surface(polygon, 14, "stone", central)
	if central:
		polygon_surface(polygon, -48, "dark", false)

func flush() -> void:
	var worn_block: ArrayMesh = bevelled_block()
	for key: String in batches:
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = worn_block if batch_materials[key] in ["trim", "wood"] else BoxMesh.new()
		multi.instance_count = batches[key].size()
		for index: int in range(multi.instance_count):
			multi.set_instance_transform(index, batches[key][index] as Transform3D)
			multi.set_instance_color(index, batch_colors[key][index] as Color)
		var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
		visual.multimesh = multi
		visual.material_override = materials[batch_materials[key]]
		add_child(visual)
	for material: String in surfaces:
		var vertices: PackedVector3Array = surfaces[material]
		var normals: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		for index: int in range(0, vertices.size(), 3):
			var normal: Vector3 = -(vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).normalized()
			for corner: int in range(3):
				normals.append(normal)
				colors.append(Color.WHITE)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = materials[material]
		add_child(visual)
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(collision_faces)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

	batches.clear()
	batch_colors.clear()
	batch_materials.clear()
	surfaces.clear()
	collision_faces.clear()

func bevelled_block() -> ArrayMesh:
	# Shared chamfered cube: a small silhouette break on masonry, boards and old posts.
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for axis: int in range(3):
		for sign_value: float in [-1.0, 1.0]:
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = sign_value
			var quad: PackedVector3Array = PackedVector3Array()
			for pair: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point: Vector3 = normal * 0.5
				point[(axis + 1) % 3] = pair.x * 0.48
				point[(axis + 2) % 3] = pair.y * 0.48
				quad.append(point)
			bevel_face(quad, normal, vertices, normals)
	for axis: int in range(3):
		for s: float in [-1.0, 1.0]:
			for t: float in [-1.0, 1.0]:
				var quad: PackedVector3Array = PackedVector3Array()
				for pair: Vector2 in [Vector2(0.5, -0.48), Vector2(0.48, -0.48), Vector2(0.48, 0.48), Vector2(0.5, 0.48)]:
					var point: Vector3 = Vector3.ZERO
					point[axis] = pair.x * s
					point[(axis + 1) % 3] = (0.98 - pair.x) * t
					point[(axis + 2) % 3] = pair.y
					quad.append(point)
				var normal: Vector3 = Vector3.ZERO
				normal[axis] = s
				normal[(axis + 1) % 3] = t
				bevel_face(quad, normal.normalized(), vertices, normals)
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				bevel_face(PackedVector3Array([Vector3(x * 0.5, y * 0.48, z * 0.48), Vector3(x * 0.48, y * 0.5, z * 0.48), Vector3(x * 0.48, y * 0.48, z * 0.5)]), Vector3(x, y, z).normalized(), vertices, normals)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func bevel_face(polygon: PackedVector3Array, normal: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	for index: int in range(1, polygon.size() - 1):
		var a: Vector3 = polygon[0]
		var b: Vector3 = polygon[index]
		var c: Vector3 = polygon[index + 1]
		vertices.append_array(PackedVector3Array([a, b, c] if (b - a).cross(c - a).dot(normal) < 0 else [a, c, b]))
		normals.append_array(PackedVector3Array([normal, normal, normal]))
