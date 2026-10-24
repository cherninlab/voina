class_name DungeonStructure
extends RefCounted
## Construction is fitted to real route joints and masonry, never to world axes.

const ROOT: String = "res://content/environments/dungeon_structure_v1/"
const FOUNDATION_Y: float = -60.0
var g: RedDescentGeometry
var meshes: Dictionary[String, Mesh] = {}
var bearings: Array[Dictionary] = []
var members: Array[Dictionary] = []
var cloth_pins: Array[Vector3] = []

func _init(geometry: RedDescentGeometry) -> void:
	g = geometry

func mesh(id: String) -> Mesh:
	if not meshes.has(id):
		var scene: Node3D = (load(ROOT + id + ".glb") as PackedScene).instantiate() as Node3D
		var source: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		meshes[id] = source.mesh
		scene.free()
	return meshes[id]

func instance(id: String, transform: Transform3D, material: String, color: Color = Color.WHITE) -> void:
	var at: Vector3 = transform.origin
	var key: String = "structure:%s:%d:%d:%d" % [id, floori(at.x / 15.0), floori(at.y / 12.0), floori(at.z / 15.0)]
	if not g.batches.has(key):
		g.batches[key] = []
		g.batch_colors[key] = []
		g.batch_materials[key] = material
		g.batch_meshes[key] = mesh(id)
	g.batches[key].append(transform)
	g.batch_colors[key].append(color)

func timber(a: Vector3, b: Vector3, width: float, depth: float, role: String = "framing", up_hint: Vector3 = Vector3.UP) -> void:
	var up: Vector3 = Vector3.FORWARD if absf((b - a).normalized().y) > 0.98 else up_hint
	var basis: Basis = Basis.looking_at(b - a, up) * Basis.from_scale(Vector3(width, depth, a.distance_to(b)))
	var variant: int = posmod(members.size(), 3)
	instance("hewn_timber_%d" % variant, Transform3D(basis, (a + b) * 0.5), "wood", Color(0.65, 0.61, 0.55))
	members.append({"from": a, "to": b, "width": width, "depth": depth, "role": role})

func nearest_wall(point: Vector3) -> Vector3:
	var best: Vector2 = Vector2(INF, INF)
	var distance: float = INF
	for polygon: PackedVector2Array in [RedDescentLayout.outline(), RedDescentLayout.spine()]:
		for index: int in range(polygon.size()):
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), polygon[index], polygon[(index + 1) % polygon.size()])
			if near.distance_to(Vector2(point.x, point.z)) < distance:
				distance = near.distance_to(Vector2(point.x, point.z))
				best = near
	# Embed at least half a metre beyond the visible outline, including when
	# a route lands exactly on it. Core walls lie behind their facing.
	var toward: Vector2 = best - Vector2(point.x, point.z)
	if toward.length() < 0.1:
		toward = best.normalized()
	return Vector3(best.x + toward.normalized().x * 0.55, point.y, best.y + toward.normalized().y * 0.55)

func foundation_clear(at: Vector3, top: float) -> bool:
	# A support may not grow through a lower playable crossing or side passage.
	for path: Dictionary in g.paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)
			var y: float = lerpf(a.y, b.y, t)
			if y + 2.6 > FOUNDATION_Y and y < top + 0.2 and near.distance_to(Vector2(at.x, at.z)) < float(path["width"]) * 0.5 + 1.25:
				return false
	return true

func support(point: Vector3, side: Vector3, width: float, route: String) -> void:
	var wall: Vector3 = nearest_wall(point)
	var seat: Vector3 = point - Vector3.UP * 0.97
	var type: String = "wall bracket"
	var base: Vector3
	if wall.distance_to(point) < 8.5:
		var drop: float = maxf(3.2, wall.distance_to(point) * 0.65 + 0.6)
		base = wall - Vector3.UP * drop
		# Full-depth wall plate and two braces embed into the same masonry face.
		for lateral: float in [-0.42, 0.42]:
			var anchor: Vector3 = base + side * lateral
			timber(anchor - Vector3.UP * 0.25, wall + side * lateral - Vector3.UP * 0.9, 0.30, 0.30, "wall plate")
			timber(anchor, seat + side * lateral, 0.26, 0.28, "wall brace")
			timber(wall + side * lateral - Vector3.UP, seat + side * lateral, 0.30, 0.38, "wall bearer")
	else:
		type = "foundation pier"
		base = point
		var found: bool = false
		for offset: float in [0.0, width * 0.65, -width * 0.65, width, -width, width * 1.6, -width * 1.6, width * 2.2, -width * 2.2]:
			var candidate: Vector3 = point + side * offset
			if foundation_clear(candidate, point.y - 2.1):
				base = candidate
				found = true
				break
		assert(found, "No clear foundation for " + route + " " + str(point))
		var top: float = point.y - 2.05
		var column: CylinderMesh = CylinderMesh.new()
		column.top_radius = 0.68
		column.bottom_radius = 0.98
		column.height = top - FOUNDATION_Y
		column.radial_segments = 8
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "GroundedPier"
		visual.mesh = column
		visual.material_override = g.materials["stone"]
		visual.position = Vector3(base.x, (top + FOUNDATION_Y) * 0.5, base.z)
		g.add_child(visual)
		for vertex: Vector3 in column.get_faces():
			g.collision_faces.append(vertex + visual.position)
		var cap_mesh: Mesh = mesh("meshes/bearing_cap_lod1")
		var bounds: AABB = cap_mesh.get_aabb()
		var cap_basis: Basis = Basis(side, Vector3.UP, side.cross(Vector3.UP)) * Basis.from_scale(Vector3(2.1, 0.86, 1.35) / bounds.size)
		var cap: Vector3 = Vector3(base.x, top - 0.04, base.z) - cap_basis * Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		instance("meshes/bearing_cap_lod1", Transform3D(cap_basis, cap), "trim")
		# Bearing saddle reaches the underside of the transverse beam.
		var reach: float = width * 0.5 + 0.25
		var offset: float = (base - point).dot(side)
		timber(seat + side * minf(-reach, offset - 0.6), seat + side * maxf(reach, offset + 0.6), 0.46, 0.54, "pier cap")
		for sign_value: float in [-1.0, 1.0]:
			timber(Vector3(base.x, top - 1.25, base.z) + side * sign_value * 0.45, seat + side * sign_value * (width * 0.42), 0.28, 0.30, "knee brace")
		base.y = FOUNDATION_Y
	# All spans meet this transverse bearer at the route's actual miter joint.
	timber(seat - side * (width * 0.5 + 0.25), seat + side * (width * 0.5 + 0.25), 0.40, 0.44, "transom")
	for sign_value: float in [-1.0, 1.0]:
		var joint: Vector3 = point + side * sign_value * width * 0.39 - Vector3.UP * 0.75
		var along: Vector3 = side.cross(Vector3.UP)
		# Visible straps and through-pins bind the crossbeam to its stringers.
		g.piece(Vector3(0.35, 0.045, 0.5), joint - Vector3.UP * 0.04, "iron", Basis(side, Vector3.UP, along))
		g.beam(joint - along * 0.27, joint + along * 0.27, 0.06, "iron")
	bearings.append({"route": route, "type": type, "deck": point, "base": base, "seat": seat})

func route(path: Dictionary, edges: PackedVector3Array) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	for node: int in range(points.size()):
		var side: Vector3 = edges[node].normalized()
		if not g.in_room(points[node]):
			support(points[node], side, width, String(path["id"]))
		for sign_value: float in [-1.0, 1.0]:
			# Guard posts land on the transom/stringer joint, never beside empty air.
			var at: Vector3 = points[node] + edges[node] * sign_value
			timber(at - Vector3.UP * 1.16, at + Vector3.UP * 1.14, 0.18, 0.18, "guard post")
	for index: int in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		for sign_value: float in [-1.0, 1.0]:
			var start: Vector3 = a + edges[index] * sign_value * 0.78 - Vector3.UP * 0.45
			var end: Vector3 = b + edges[index + 1] * sign_value * 0.78 - Vector3.UP * 0.45
			timber(start, end, 0.30, 0.60, "stringer")
			var previous: Vector3 = a + edges[index] * sign_value + Vector3.UP
			for part: int in range(1, 17):
				var t: float = float(part) / 16.0
				var next: Vector3 = a.lerp(b, t) + edges[index].lerp(edges[index + 1], t) * sign_value + Vector3.UP * (1.0 - 0.20 * sin(PI * t))
				g.beam(previous, next, 0.035, "iron")
				previous = next
		if not bool(path["wood"]):
			continue
		# Every board spans across both stringers. The mitered ribbon is the
		# unchanged collision surface, while actual board gaps reveal framing.
		var count: int = ceili(a.distance_to(b) / 0.29)
		for plank: int in range(count):
			var t: float = (float(plank) + 0.5) / float(count)
			var center: Vector3 = a.lerp(b, t) - Vector3.UP * 0.075
			var side: Vector3 = edges[index].lerp(edges[index + 1], t)
			var normal: Vector3 = side.cross(b - a).normalized()
			timber(center - side * 1.025, center + side * 1.025, a.distance_to(b) / float(count) - 0.016, 0.15, "deck board", normal)
		# Ragged cloth pins meet a real underside crossbeam at both corners.
		if index == 1 and bool(path["wood"]):
			var center: Vector3 = a.lerp(b, 0.45) - Vector3.UP * 1.05
			var side: Vector3 = edges[index].lerp(edges[index + 1], 0.45).normalized()
			var frame: Basis = Basis(side, Vector3.UP, side.cross(Vector3.UP))
			timber(center - side * 1.35, center + side * 1.35, 0.25, 0.25, "cloth bearer")
			instance("cloth_drape", Transform3D(frame, center), "cloth")
			cloth_pins.append(center - side * 1.2 - Vector3.UP * 0.035)
			cloth_pins.append(center + side * 1.2 - Vector3.UP * 0.035)

func roof(room: Dictionary) -> void:
	# Wall-to-wall trusses: tie, two rafters and king post share exact nodes.
	var polygon: PackedVector2Array = room["points"] as PackedVector2Array
	var y: float = float(room["floor"]) + float(room["height"]) - 2.3
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	var center_x: float = bounds.get_center().x
	var front: float = bounds.position.y
	var back: float = bounds.end.y
	# Timber roof planes bear directly on the rafters, replacing the flat
	# brick-textured ceiling that had no masonry vault or plausible support.
	for edge_x: float in [bounds.position.x, bounds.end.x]:
		var ridge_a: Vector3 = Vector3(center_x, y + 2.14, front)
		var ridge_b: Vector3 = Vector3(center_x, y + 2.14, back)
		var eave_a: Vector3 = Vector3(edge_x, y + 0.24, front)
		var eave_b: Vector3 = Vector3(edge_x, y + 0.24, back)
		g.quad(ridge_a, ridge_b, eave_b, eave_a, Vector3.DOWN, "wood")
	for ratio: float in [0.25, 0.5, 0.75]:
		var z: float = bounds.position.y + bounds.size.y * ratio
		var hits: Array[float] = []
		for index: int in range(polygon.size()):
			var a: Vector2 = polygon[index]
			var b: Vector2 = polygon[(index + 1) % polygon.size()]
			if (a.y <= z and b.y > z) or (b.y <= z and a.y > z):
				hits.append(lerpf(a.x, b.x, (z - a.y) / (b.y - a.y)))
		hits.sort()
		if hits.size() < 2:
			continue
		var left: Vector3 = Vector3(hits[0] - 0.3, y, z)
		var right: Vector3 = Vector3(hits[-1] + 0.3, y, z)
		var crown: Vector3 = (left + right) * 0.5 + Vector3.UP * 1.9
		timber(left, right, 0.42, 0.55, "roof tie")
		timber(left, crown, 0.32, 0.40, "rafter")
		timber(right, crown, 0.32, 0.40, "rafter")
		timber((left + right) * 0.5, crown, 0.26, 0.26, "king post")
		for at: Vector3 in [left, right]:
			# Sockets are cut into real room walls, with a masonry bearing below.
			g.piece(Vector3(1.0, 0.5, 1.0), at - Vector3.UP * 0.5, "trim")
			g.piece(Vector3(0.70, 1.2, 0.72), at - Vector3.UP * 1.3, "stone")
