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
var batch_models: Dictionary[String, String] = {}
var module_counts: Dictionary[String, int] = {}
var surfaces: Dictionary[String, PackedVector3Array] = {}
var surface_materials: Dictionary[String, String] = {}
var collision_faces: PackedVector3Array = PackedVector3Array()
var cube_faces: PackedVector3Array = BoxMesh.new().get_faces()
var fort_source: Node3D

func build() -> void:
	name = "Architecture"
	fort_source = load("res://content/environments/dungeon_geometry_v2/modular_fort_01/modular_fort_01_2k.gltf").instantiate() as Node3D
	for room: Dictionary in rooms:
		build_room(room)
	for index: int in range(paths.size()):
		build_path(paths[index], index < RedDescentLayout.MAIN_PATHS)
	build_vault(RedDescentLayout.outline(), false)
	build_vault(RedDescentLayout.spine(), true)
	# The void's base stops physics falls; the player recovery threshold is above it.
	piece(Vector3(150, 1, 150), Vector3(0, -60, 0), "dark", Basis.IDENTITY, true)
	flush()
	fort_source.free()
	fort_source = null
	print("GENERATED_KIT_PLACED: ", JSON.stringify(module_counts))
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

func module(id: String, at: Vector3, basis: Basis = Basis.IDENTITY, scale: Vector3 = Vector3.ONE, color: Color = Color.WHITE) -> void:
	var key: String = "@%s:%d:%d:%d" % [id, floori(at.x / 12.0), floori(at.y / 10.0), floori(at.z / 12.0)]
	if not batches.has(key):
		batches[key] = []
		batch_colors[key] = []
		batch_models[key] = id
	batches[key].append(Transform3D(basis * Basis.from_scale(scale), at))
	batch_colors[key].append(color)
	module_counts[id] = module_counts.get(id, 0) + 1
	if id in ["wall_panel", "curved_wall", "broken_wall", "window_bay", "rock_outcrop"]:
		# Baked mesh faces keep bodies unscaled and include the projecting stone relief.
		var transform: Transform3D = Transform3D(basis * Basis.from_scale(scale), at)
		for vertex: Vector3 in GeneratedDungeonKit.mesh(id, 2).get_faces():
			collision_faces.append(transform * vertex)

func fitted_module(id: String, at: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var bounds: AABB = GeneratedDungeonKit.mesh(id).get_aabb()
	module(id, at, basis, size / bounds.size)

func stacked_pier(at: Vector3, basis: Basis, size: Vector3, variant: int) -> void:
	var count: int = ceili(size.y / 5.0)
	var rise: float = size.y / float(count)
	for level: int in range(count):
		var id: String = "column" if level == count - 1 and variant % 2 == 0 else "buttress"
		fitted_module(id, at + Vector3.UP * rise * float(level), Vector3(size.x, rise + 0.04, size.z), basis)

func face(a: Vector3, b: Vector3, c: Vector3, material: String, solid: bool = true) -> void:
	if material == "collision":
		collision_faces.append_array(PackedVector3Array([a, b, c]))
		return
	# Local surface bounds let Mobile select nearby practical lights for each span.
	var center: Vector3 = (a + b + c) / 3.0
	var key: String = "%s:%d:%d:%d" % [material, floori(center.x / 12.0), floori(center.y / 10.0), floori(center.z / 12.0)]
	var data: PackedVector3Array = surfaces.get(key, PackedVector3Array())
	# Godot renders clockwise front faces; callers supply an outward cross product.
	data.append_array(PackedVector3Array([a, c, b]))
	surfaces[key] = data
	surface_materials[key] = material
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
	var wall_material: String = "red_plaster" if String(room["id"]) == "nave" else "plaster"
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
			var door_height: float = 6.4 if String(room["id"]) == "nave" and mid.x > 3.0 and mid.y < 29.0 else 4.2
			var door: bool = opening(mid, y)
			var spans: Array[Vector2] = [Vector2(y, y + height)]
			for level: float in portal_levels(mid, 0.1):
				var next: Array[Vector2] = []
				for span: Vector2 in spans:
					if level + door_height <= span.x or level - 0.2 >= span.y:
						next.append(span)
					else:
						if level - 0.2 > span.x:
							next.append(Vector2(span.x, level - 0.2))
						if level + door_height < span.y:
							next.append(Vector2(level + door_height, span.y))
				spans = next
			for span: Vector2 in spans:
				piece(Vector3(delta.length() / float(count) + 0.04, span.y - span.x, 0.9), Vector3(mid.x, (span.x + span.y) * 0.5, mid.y), wall_material, basis, true)
			if door and door_start < 0:
				door_start = step
			if door_start >= 0 and (not door or step == count - 1):
				var end: int = step if not door else step + 1
				var center: Vector2 = a.lerp(b, float(door_start + end) * 0.5 / float(count))
				if String(room["id"]) == "nave" and center.x > 3.0 and center.y < 29.0:
					fort_gate(Vector3(center.x, y, center.y), delta.normalized())
				else:
					arch(Vector3(center.x, y, center.y), delta.normalized(), float(end - door_start) * delta.length() / float(count) * 0.5)
				door_start = -1
		# Tall worn pilasters give the side halls scale without a flat wall of tiny bricks.
		if delta.length() > 5.0:
			for t: float in [0.18, 0.82]:
				var at: Vector2 = a.lerp(b, t)
				if not opening(at, y):
					stacked_pier(Vector3(at.x, y, at.y) + basis.z * 0.55, basis, Vector3(0.95, height, 1.25), index + int(t * 10.0))
			# Sealed burial recesses and their worn arch borders break up the side halls.
			var inward: Vector2 = Vector2(-delta.y, delta.x).normalized()
			for t: float in [0.35, 0.65]:
				var at: Vector2 = a.lerp(b, t)
				if opening(at, y):
					continue
				var niche: Vector3 = Vector3(at.x + inward.x * 0.48, y, at.y + inward.y * 0.48)
				var id: String = "slit_window" if (index + int(t * 10.0)) % 2 == 0 else "gothic_window"
				var window_width: float = 1.15 if id == "slit_window" else 2.1
				piece(Vector3(window_width * 0.7, 2.1, 0.06), niche + basis.z * 0.2 + Vector3.UP * 1.6, "dark", basis)
				fitted_module(id, niche + basis.z * 0.4 + Vector3.UP * 0.3, Vector3(window_width, 2.9, 0.55), basis)
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
			var rubble_basis: Basis = Basis(Vector3.UP, float(index) * 1.73)
			module("rubble", Vector3(at.x, y - 0.15, at.y), rubble_basis, Vector3.ONE * (0.55 + float(index % 3) * 0.15))
	if String(room["id"]) in ["chapel", "nave", "choir", "restraint"]:
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = Vector3(centroid.x + side * 5.0, y, centroid.y + 5.0)
			var column_height: float = height - 0.2
			piece(Vector3(1.1, column_height, 1.1), at + Vector3.UP * column_height * 0.5, "collision")
			stacked_pier(at, Basis.IDENTITY, Vector3(1.5, column_height, 1.5), 0 if side < 0.0 else 1)
			piece(Vector3(1.8, 0.35, 1.8), at + Vector3.UP * 0.175, "stone", Basis.IDENTITY, true)

func build_path(path: Dictionary, light_route: bool) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var material: String = "wood" if bool(path["wood"]) else "floor"
	var enclosed: bool = bool(path["enclosed"])
	var lining: String = "rock" if String(path["id"]) in ["root_tunnel", "cave_bypass"] else "stone"
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
		var sculpted_deck: bool = bool(path["wood"]) and not enclosed and index % 2 == (0 if String(path["id"]) == "high_span" else 1)
		if sculpted_deck:
			var mesh_size: Vector3 = GeneratedDungeonKit.mesh("timber_bridge").get_aabb().size
			var deck_basis: Basis = basis * Basis(Vector3.UP, PI * 0.5) if mesh_size.x > mesh_size.z else basis
			var deck_count: int = maxi(1, roundi(from.distance_to(to) / 4.5))
			var deck_size: Vector3 = Vector3(from.distance_to(to) / float(deck_count) + 0.08, 0.32, width + 0.14) if mesh_size.x > mesh_size.z else Vector3(width + 0.14, 0.32, from.distance_to(to) / float(deck_count) + 0.08)
			for deck: int in range(deck_count):
				var at: Vector3 = from.lerp(to, (float(deck) + 0.5) / float(deck_count))
				fitted_module("timber_bridge", at - basis.y * 0.30, deck_size, deck_basis)
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
				face(a - edge_a, a + edge_a, b - edge_b, "collision" if sculpted_deck else material)
				face(a + edge_a, b + edge_b, b - edge_b, "collision" if sculpted_deck else material)
				face(a - edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, a + edge_a - Vector3.UP * 0.32, "wood" if bool(path["wood"]) else "stone")
				face(a + edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, b + edge_b - Vector3.UP * 0.32, "wood" if bool(path["wood"]) else "stone")
				# Close the walking ribbon's open sides; slopes and corners need real fascia.
				quad(a - edge_a, a - edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, b - edge_b, -side, "wood" if bool(path["wood"]) else "stone")
				quad(a + edge_a, b + edge_b, b + edge_b - Vector3.UP * 0.32, a + edge_a - Vector3.UP * 0.32, side, "wood" if bool(path["wood"]) else "stone")
				if enclosed:
					var roof: float = 3.7 if String(path["id"]) in ["root_tunnel", "cave_bypass"] else 4.2
					for sign_value: float in [-1.0, 1.0]:
						var edge: Vector3 = at + side * sign_value * (width * 0.5 + 0.3)
						if not junction(edge, String(path["id"]), index):
							piece(Vector3(0.65, roof + absf(a.y - b.y), length + 0.12), edge + Vector3.UP * roof * 0.5, lining, Basis(Vector3.UP, atan2(-direction.x, -direction.z)), true)
					piece(Vector3(width + 1.0, 0.55, length + 0.1), at + Vector3.UP * (roof + 0.25), lining, basis, true)
					if lining == "rock" and step % 3 == 0:
						var wall_side: float = -1.0 if (step + index) % 2 == 0 else 1.0
						var rock_at: Vector3 = at + side * wall_side * (width * 0.5 + 0.65)
						if not junction(rock_at, String(path["id"]), index):
							fitted_module("rock_outcrop", rock_at - Vector3.UP * 0.2, Vector3(1.4, 3.9, 3.6), basis)
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
					if bool(path["wood"]) and not sculpted_deck:
						for plank: int in range(4):
							var offset: float = (float(plank) - 1.5) * length * 0.25
							var shade: float = 0.78 + float(posmod(index * 37 + step * 11 + plank * 13, 17)) * 0.023
							var wear: float = float(posmod(index * 13 + step * 7 + plank * 31, 11)) / 10.0 - 0.5
							piece(Vector3(width + 0.16 + wear * 0.08, 0.12, length * 0.25 - 0.035), at + direction * offset - basis.y * (0.05 + wear * 0.012), "wood", basis * Basis(Vector3.FORWARD, wear * 0.006), false, Color(shade, shade * 0.97, shade * 0.91))
				since_light += length
				if light_route and since_light >= 13.0:
					torch_posts.append(at + side * (width * 0.5 - 0.35))
					since_light = 0.0
	# Supports stay below the shared walking ribbon.
	for node: int in range(points.size()):
		var point: Vector3 = points[node]
		var direction: Vector3 = points[mini(node + 1, points.size() - 1)] - points[maxi(0, node - 1)]
		var support_basis: Basis = Basis.looking_at(direction.normalized(), Vector3.UP)
		if in_room(point):
			continue
		if not enclosed:
			# Masonry corbels and timber braces are below the walking surface.
			if bool(path["wood"]):
				module("timber_anchor", point + support_basis.x * width * 0.5 - support_basis.y * 3.3, support_basis)
			else:
				fitted_module("stone_bridge", point - support_basis.y * 1.9, Vector3(4.0, 1.6, width * 0.95), support_basis * Basis(Vector3.UP, PI * 0.5))
			module("corbel", point + support_basis.x * width * 0.35 - support_basis.y * 1.8, support_basis, Vector3.ONE * 0.65)
			for sign_value: float in [-1.0, 1.0]:
				beam(point + Vector3(sign_value * width * 0.4, -0.6, 0), point + Vector3(sign_value * width * 1.4, -4.0, 0), 0.3, "wood")

func beam(from: Vector3, to: Vector3, width: float, material: String) -> void:
	var up: Vector3 = Vector3.FORWARD if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	if material == "iron" and is_equal_approx(width, 0.035):
		var count: int = maxi(1, roundi(from.distance_to(to) / 0.13))
		var basis: Basis = Basis.looking_at(to - from, up)
		for link: int in range(count):
			piece(Vector3(1, 1, 1.5), from.lerp(to, (float(link) + 0.5) / float(count)), "chain", basis * Basis(Vector3.BACK, float(link % 2) * PI * 0.5))
		return
	piece(Vector3(width, width, from.distance_to(to)), (from + to) * 0.5, material, Basis.looking_at(to - from, up))

func fort_gate(at: Vector3, tangent: Vector2) -> void:
	var source: MeshInstance3D = fort_source.find_child("*thin_gate_01*", true, false) as MeshInstance3D
	var gate: MeshInstance3D = source.duplicate() as MeshInstance3D
	var basis: Basis = Basis(Vector3(tangent.y, 0, -tangent.x), Vector3.UP, Vector3(tangent.x, 0, tangent.y))
	# Native mesh units are metres. Recenter the module around its clear opening.
	gate.transform = Transform3D(basis, at - basis * Vector3(1.2, 0.35, 3.7046))
	add_child(gate)
	for vertex: Vector3 in gate.mesh.get_faces():
		collision_faces.append(gate.transform * vertex)

func arch(at: Vector3, tangent: Vector2, radius: float) -> void:
	var id: String = "arch" if posmod(roundi(at.x * 0.5 + at.z), 3) == 0 else "round_arch"
	# Keep the opening wider than the collision passage; decorative frames never block it.
	fitted_module(id, at - Vector3.UP * 0.1, Vector3(clampf(radius * 2.0 + 1.3, 2.8, 7.0), 4.5, 1.05), Basis(Vector3.UP, -atan2(tangent.y, tangent.x)))

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
				piece(Vector3(width + 0.05, span.y - span.x, 0.8), Vector3(center.x + normal.x * (1.3 if central else 0.45), (span.x + span.y) * 0.5, center.y + normal.y * (1.3 if central else 0.45)), "core_stone" if central else "dark", basis, true)
			for door_y: float in doors:
				arch(Vector3(center.x, door_y, center.y), tangent, width * 0.48)
				arch_spandrel(Vector3(center.x, door_y, center.y), basis, width * 0.48, "plaster" if central else "wall")
			for row: int in range(10):
				var y: float = -46.0 + float(row) * 6.0
				var at: Vector3 = Vector3(center.x, y, center.y)
				var doorway: bool = false
				for floor_y: float in doors:
					if y < floor_y + 4.8 and y + 6.0 > floor_y - 0.25:
						doorway = true
				var wall_material: String = "plaster" if central else "wall"
				if doorway:
					# A portal removes only its own height, never the entire six-metre row.
					var remains: Array[Vector2] = [Vector2(y, y + 6.0)]
					for floor_y: float in doors:
						var next: Array[Vector2] = []
						for span: Vector2 in remains:
							if floor_y + 4.8 <= span.x or floor_y - 0.25 >= span.y:
								next.append(span)
							else:
								if floor_y - 0.25 > span.x:
									next.append(Vector2(span.x, floor_y - 0.25))
								if floor_y + 4.8 < span.y:
									next.append(Vector2(floor_y + 4.8, span.y))
						remains = next
					for span: Vector2 in remains:
						piece(Vector3(width + 0.04, span.y - span.x, 1.0), Vector3(at.x, (span.x + span.y) * 0.5, at.z), wall_material, basis)
					continue
				# Most of the shaft is structural masonry. Sparse, staggered recesses replace
				# the identical ten-storey grid of windows on every bay.
				var seed_value: int = posmod(index * 17 + column * 11 + row * 7, 23)
				if seed_value > (5 if central else 4):
					if not central:
						piece(Vector3(width + 0.04, 6.0, 1.0), at + Vector3.UP * 3.0, wall_material, basis)
					if central or seed_value % 3 == 0:
						var id: String = "wall_panel" if seed_value % 3 == 0 else ("curved_wall" if seed_value % 3 == 1 else "broken_wall")
						var facing: Basis = basis * Basis(Vector3.UP, PI) if central else basis
						fitted_module(id, at + Vector3(normal.x, 0, normal.y) * (0.65 if central else -0.5), Vector3(width + 0.25, 6.3 + float(seed_value % 3) * 0.2, 1.4), facing)
					continue
				if central and seed_value in [0, 3]:
					fitted_module("window_bay", at + Vector3(normal.x, 0, normal.y) * 0.55, Vector3(width + 0.18, 6.15, 1.3), basis * Basis(Vector3.UP, PI))
					continue
				if central:
					at += Vector3(normal.x, 0, normal.y) * 0.5
				var opening_width: float = minf(1.3 + float(seed_value) * 0.2, width * 0.48)
				for side: float in [-1.0, 1.0]:
					piece(Vector3((width - opening_width) * 0.5, 6, 1.0), at + Vector3(tangent.x, 0, tangent.y) * side * (width + opening_width) * 0.25 + Vector3.UP * 3, wall_material, basis)
				piece(Vector3(opening_width, 1.0, 1.0), at + Vector3.UP * 0.5, wall_material, basis)
				arch_spandrel(at, basis, opening_width * 0.5, wall_material)
				var frame: String = "slit_window" if seed_value % 2 == 0 else "gothic_window"
				var facing: Basis = basis * Basis(Vector3.UP, PI) if central else basis
				fitted_module(frame, at - Vector3(normal.x, 0, normal.y) * (0.3 if central else 0.55) + Vector3.UP * 0.85, Vector3(opening_width + 0.6, 3.1, 0.7), facing)
				if not central and row in [3, 6] and posmod(index * 3 + column, 4) == 0:
					torch_posts.append(at - Vector3(normal.x, 0, normal.y) * 1.1 + Vector3.UP * 0.8)
	polygon_surface(polygon, 14, "stone", central)
	if central:
		polygon_surface(polygon, -48, "dark", false)

func arch_spandrel(at: Vector3, basis: Basis, radius: float, material: String) -> void:
	# Solid masonry above the curved opening, with a real, one-metre-deep soffit.
	for segment: int in range(8):
		var angle_a: float = PI * float(segment) / 8.0
		var angle_b: float = PI * float(segment + 1) / 8.0
		var a: Vector3 = Vector3(cos(angle_a) * radius, 2.9 + sin(angle_a) * radius * 0.65, 0)
		var b: Vector3 = Vector3(cos(angle_b) * radius, 2.9 + sin(angle_b) * radius * 0.65, 0)
		for side: float in [-1.0, 1.0]:
			var near_a: Vector3 = at + basis * (a + Vector3.BACK * 0.5 * side)
			var near_b: Vector3 = at + basis * (b + Vector3.BACK * 0.5 * side)
			var top_a: Vector3 = at + basis * Vector3(a.x, 6.0, 0.5 * side)
			var top_b: Vector3 = at + basis * Vector3(b.x, 6.0, 0.5 * side)
			quad(near_a, near_b, top_b, top_a, basis.z * side, material)
		quad(at + basis * (a + Vector3.FORWARD * 0.5), at + basis * (b + Vector3.FORWARD * 0.5), at + basis * (b + Vector3.BACK * 0.5), at + basis * (a + Vector3.BACK * 0.5), -basis.y, "trim")

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, material: String) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		face(a, b, c, material, false)
		face(a, c, d, material, false)
	else:
		face(a, c, b, material, false)
		face(a, d, c, material, false)

func flush() -> void:
	var worn_block: ArrayMesh = bevelled_block()
	var chain: TorusMesh = TorusMesh.new()
	chain.inner_radius = 0.045
	chain.outer_radius = 0.06
	chain.rings = 8
	chain.ring_segments = 4
	for key: String in batches:
		var generated: bool = batch_models.has(key)
		for level: int in range(3 if generated else 1):
			var multi: MultiMesh = MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = GeneratedDungeonKit.mesh(batch_models[key], level) if generated else (chain if batch_materials[key] == "chain" else (worn_block if batch_materials[key] in ["trim", "wood"] else BoxMesh.new()))
			multi.instance_count = batches[key].size()
			for index: int in range(multi.instance_count):
				multi.set_instance_transform(index, batches[key][index] as Transform3D)
				multi.set_instance_color(index, batch_colors[key][index] as Color)
			var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
			visual.name = key.validate_node_name() + "_lod%d" % level
			visual.multimesh = multi
			visual.material_override = GeneratedDungeonKit.material(batch_models[key]) if generated else materials["iron" if batch_materials[key] == "chain" else batch_materials[key]]
			if generated:
				visual.visibility_range_begin = [0.0, 20.0, 50.0][level]
				visual.visibility_range_end = [20.0, 50.0, 140.0][level]
			add_child(visual)
	for key: String in surfaces:
		var material: String = surface_materials[key]
		var vertices: PackedVector3Array = surfaces[key]
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
	batch_models.clear()
	surfaces.clear()
	surface_materials.clear()
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
