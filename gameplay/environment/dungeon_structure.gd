class_name DungeonStructure
extends RefCounted
## Construction is fitted to real route joints and masonry, never to world axes.

const ROOT: String = "res://content/environments/dungeon_structure_v1/"
const BRIDGE_ROOT: String = "res://content/environments/procedural_bridge_v1/"
const FOUNDATION_Y: float = -60.0
## Transom centre below the deck: procedural timber vs the baked bridge's
## 6 cm boards on 40 cm stringers.
const SEAT_DEPTH: float = 0.97
const BAKED_SEAT_DEPTH: float = 0.68
const BAKED_STRINGER_BOTTOM: float = 0.46
var g: RedDescentGeometry
var meshes: Dictionary[String, Mesh] = {}
var bearings: Array[Dictionary] = []
var members: Array[Dictionary] = []
var cloth_pins: Array[Vector3] = []
var bridges: Array[Node3D] = []
var bridge_material: ShaderMaterial

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
	var embed: float = 0.55
	var plan: Vector2 = Vector2(point.x, point.z)
	for polygon: PackedVector2Array in [RedDescentLayout.outline(), RedDescentLayout.spine()]:
		for index: int in range(polygon.size()):
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(plan, polygon[index], polygon[(index + 1) % polygon.size()])
			# The shaft wall stops where a room stands in it (RedDescentGeometry.room_cuts).
			if near.distance_to(plan) < distance and not in_room_band(near, point.y):
				distance = near.distance_to(plan)
				best = near
				embed = 0.55
	# Room walls stand on their outline (centred), from the floor up: a bracket
	# a few metres below the deck anchors in any room wall at that height.
	for room: Dictionary in g.rooms:
		# The bracket's foot, about 3.2 m under the deck, must meet the wall where it stands.
		var foot: float = point.y - 3.2
		if foot < float(room["floor"]) - 0.2 or foot > float(room["floor"]) + float(room["height"]):
			continue
		var outline: PackedVector2Array = room["points"] as PackedVector2Array
		for index: int in range(outline.size()):
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(plan, outline[index], outline[(index + 1) % outline.size()])
			if near.distance_to(plan) < distance:
				distance = near.distance_to(plan)
				best = near
				embed = 0.0
	# Embed at least half a metre beyond the visible outline, including when
	# a route lands exactly on it. Core walls lie behind their facing.
	var toward: Vector2 = best - plan
	if toward.length() < 0.1:
		toward = best.normalized()
	return Vector3(best.x + toward.normalized().x * embed, point.y, best.y + toward.normalized().y * embed)

func in_room_band(at: Vector2, y: float) -> bool:
	for room: Dictionary in g.rooms:
		if y >= float(room["floor"]) - 0.6 and y <= float(room["floor"]) + float(room["height"]) + 0.6:
			var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(room["points"] as PackedVector2Array, 0.45, Geometry2D.JOIN_MITER)
			if not grown.is_empty() and Geometry2D.is_point_in_polygon(at, grown[0]):
				return true
	return false

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

func support(point: Vector3, side: Vector3, width: float, route: String, baked: bool = false) -> void:
	var wall: Vector3 = nearest_wall(point)
	var seat: Vector3 = point - Vector3.UP * (BAKED_SEAT_DEPTH if baked else SEAT_DEPTH)
	var type: String = "wall bracket"
	var base: Vector3
	if wall.distance_to(point) < 8.5:
		var drop: float = maxf(3.2, wall.distance_to(point) * 0.65 + 0.6)
		base = wall - Vector3.UP * drop
		# Each brace finds its own masonry face, so neither leg of a pair
		# lands in air where the outline turns a corner.
		for lateral: float in [-0.42, 0.42]:
			var face: Vector3 = nearest_wall(point + side * lateral)
			var anchor: Vector3 = Vector3(face.x, base.y, face.z)
			timber(anchor - Vector3.UP * 0.25, face - Vector3.UP * 0.9, 0.30, 0.30, "wall plate")
			timber(anchor, seat + side * lateral, 0.26, 0.28, "wall brace")
			timber(face - Vector3.UP, seat + side * lateral, 0.30, 0.38, "wall bearer")
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
		# The bearing cap and pier cap stack 1.08 m from pier top to transom centre.
		var top: float = seat.y - 1.08
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
	bearings.append({"route": route, "type": type, "deck": point, "base": base, "seat": seat})
	if baked:
		# The baked bridge carries its own straps where its stringers cross.
		return
	for sign_value: float in [-1.0, 1.0]:
		var joint: Vector3 = point + side * sign_value * width * 0.39 - Vector3.UP * 0.75
		var along: Vector3 = side.cross(Vector3.UP)
		# Visible straps and through-pins bind the crossbeam to its stringers.
		g.piece(Vector3(0.35, 0.045, 0.5), joint - Vector3.UP * 0.04, "iron", Basis(side, Vector3.UP, along))
		g.beam(joint - along * 0.27, joint + along * 0.27, 0.06, "iron")

## Fingerprint of a route's walking ribbon. The Blender bake stores the value it
## was built from; a mismatch means the route moved and the bake is stale.
static func layout_hash(path: Dictionary, edges: PackedVector3Array) -> String:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var text: String = "%s|%.3f" % [String(path["id"]), float(path["width"])]
	for index: int in range(points.size()):
		text += "|%.3f,%.3f,%.3f,%.3f,%.3f" % [points[index].x, points[index].y, points[index].z, edges[index].x, edges[index].z]
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()

## Places the Blender-baked deck, rails and straps for a wooden route when a
## bake exists for its current layout. Returns false to keep procedural timber.
func baked_bridge(path: Dictionary, edges: PackedVector3Array) -> bool:
	var file: String = BRIDGE_ROOT + String(path["id"]) + ".glb"
	# --no-baked-bridges renders the procedural fallback for same-camera A/B frames.
	if not ResourceLoader.exists(file) or "--no-baked-bridges" in OS.get_cmdline_user_args():
		return false
	var bridge: Node3D = (load(file) as PackedScene).instantiate() as Node3D
	var expected: String = layout_hash(path, edges)
	var found: String = ""
	for node: Node in bridge.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta("extras", {}) as Dictionary
		found = String(extras.get("layout_hash", found))
	if found != expected:
		push_warning("Stale bridge bake for %s (%s, layout %s); rerun scripts/art/build_procedural_bridge.py" % [path["id"], found, expected])
		bridge.free()
		return false
	if bridge_material == null:
		bridge_material = ShaderMaterial.new()
		bridge_material.shader = load(BRIDGE_ROOT + "bridge_surface.gdshader") as Shader
		var wood: ShaderMaterial = g.materials["wood"] as ShaderMaterial
		for parameter: String in ["albedo_map", "normal_map", "roughness_map", "ao_map", "wet_map"]:
			bridge_material.set_shader_parameter(parameter, wood.get_shader_parameter(parameter))
		# Soaked decks that catch the torches, as in the paintovers (T-181 grade).
		bridge_material.set_shader_parameter("wetness", 1.6)
	for node: Node in bridge.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		visual.material_override = g.materials["iron"] if visual.name.begins_with("Iron") else bridge_material
		if visual.name.begins_with("Rope"):
			visual.set_instance_shader_parameter("rope", 1.0)
	bridge.name = "Bridge_" + String(path["id"])
	g.add_child(bridge)
	bridges.append(bridge)
	return true

func route(path: Dictionary, edges: PackedVector3Array) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var baked: bool = bool(path["wood"]) and baked_bridge(path, edges)
	for node: int in range(points.size()):
		var side: Vector3 = edges[node].normalized()
		if not g.in_room(points[node]):
			support(points[node], side, width, String(path["id"]), baked)
		if baked:
			continue
		for sign_value: float in [-1.0, 1.0]:
			# Guard posts land on the transom/stringer joint, never beside empty air.
			var at: Vector3 = points[node] + edges[node] * sign_value
			timber(at - Vector3.UP * 1.16, at + Vector3.UP * 1.14, 0.18, 0.18, "guard post")
	if baked:
		# Ragged cloth hangs from a bearer fixed to the baked stringers' undersides.
		var center: Vector3 = points[1].lerp(points[2], 0.45) - Vector3.UP * (BAKED_STRINGER_BOTTOM + 0.125)
		var side: Vector3 = edges[1].lerp(edges[2], 0.45).normalized()
		timber(center - side * 1.35, center + side * 1.35, 0.25, 0.25, "cloth bearer")
		instance("cloth_drape", Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), center), "cloth")
		cloth_pins.append(center - side * 1.2 - Vector3.UP * 0.035)
		cloth_pins.append(center + side * 1.2 - Vector3.UP * 0.035)
		return
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

## Under a stone vault only the tie beams stay: set into the walls, they take
## the vault's thrust and carry the banners. Otherwise each tie is a truss.
func roof(room: Dictionary, vaulted: bool = false) -> void:
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
	for edge_x: float in ([] if vaulted else [bounds.position.x, bounds.end.x]):
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
		if vaulted:
			continue
		timber(left, crown, 0.32, 0.40, "rafter")
		timber(right, crown, 0.32, 0.40, "rafter")
		timber((left + right) * 0.5, crown, 0.26, 0.26, "king post")
		for at: Vector3 in [left, right]:
			# Sockets are cut into real room walls, with a masonry bearing below.
			g.piece(Vector3(1.0, 0.5, 1.0), at - Vector3.UP * 0.5, "trim")
			g.piece(Vector3(0.70, 1.2, 0.72), at - Vector3.UP * 1.3, "stone")
