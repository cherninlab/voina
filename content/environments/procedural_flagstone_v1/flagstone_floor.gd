class_name FlagstoneFloor
extends RefCounted
## Seamless flagstone floor modules baked by scripts/art/build_flagstones.py (T-165).
## A module spans +X and +Z from its corner (4 x 4 m; border strips 4 x 0.5 m) with the
## walking plane at y = 0. Every vertex stays within 2.1 cm of it, so flat collision stays.
## Variants of one family share every stone that crosses a border, so any variant tiles
## with any other: pick one per cell to hide repetition. Visual only, no collision.

const ROOT: String = "res://content/environments/procedural_flagstone_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
const SIZE: float = 4.0
const BORDER_WIDTH: float = 0.5
const FAMILIES: Dictionary[String, Array] = {
	"laid": ["laid_a", "laid_b", "laid_c"],
	"coursed": ["coursed_a", "coursed_b", "coursed_c"],
	"border": ["border_a", "border_b"],
}
const PARTS: PackedStringArray = ["stones", "dirt"]
## Visibility range (begin, end) in metres for LOD 0, 1 and 2.
const LOD_RANGES: Array[Vector2] = [Vector2(0.0, 14.0), Vector2(14.0, 32.0), Vector2(32.0, 90.0)]
static var meshes: Dictionary[String, Mesh] = {}
static var surfaces: Dictionary[String, ShaderMaterial] = {}

static func mesh(id: String, part: String, level: int = 0) -> Mesh:
	var key: String = "%s_%s_lod%d" % [id, part, level]
	if not meshes.has(key):
		var scene: Node3D = (load(ROOT + "flagstone_%s.glb" % id) as PackedScene).instantiate() as Node3D
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			meshes[String(node.name)] = (node as MeshInstance3D).mesh
		scene.free()
	return meshes[key]

static func material(part: String) -> ShaderMaterial:
	if not surfaces.has(part):
		surfaces[part] = textured(preload("res://content/environments/procedural_flagstone_v1/flagstone.gdshader"), part)
	return surfaces[part]

## A material that discards fragments outside convex clip planes, see clip_planes().
static func clipped(part: String, planes: PackedVector3Array) -> ShaderMaterial:
	var result: ShaderMaterial = textured(preload("res://content/environments/procedural_flagstone_v1/flagstone_clipped.gdshader"), part)
	result.set_shader_parameter("clip_count", mini(planes.size(), 12))
	result.set_shader_parameter("clip_planes", planes)
	return result

static func textured(shader: Shader, part: String) -> ShaderMaterial:
	var folder: String = PBR + ("Rocks025/" if part == "dirt" else "Concrete012/")
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("albedo_map", load(folder + "albedo.png"))
	result.set_shader_parameter("normal_map", load(folder + "normal_gl.png"))
	result.set_shader_parameter("roughness_map", load(folder + "roughness.png"))
	result.set_shader_parameter("dirt", part == "dirt")
	return result

## One module with both parts and all LODs switched by visibility range.
static func module(id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = id
	for part: String in PARTS:
		for level: int in range(LOD_RANGES.size()):
			var visual: MeshInstance3D = MeshInstance3D.new()
			visual.name = "%s_lod%d" % [part, level]
			visual.mesh = mesh(id, part, level)
			visual.material_override = material(part)
			visual.visibility_range_begin = LOD_RANGES[level].x
			visual.visibility_range_end = LOD_RANGES[level].y
			if part == "dirt":
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(visual)
	return root

## Deterministic variant for a grid cell.
static func pick(family: String, cell: Vector2i, seed: int = 0) -> String:
	var ids: Array = FAMILIES[family]
	return String(ids[posmod(hash([cell.x, cell.y, seed]), ids.size())])

## Lays `cells` modules of one family from `origin` (a module corner) along +X and +Z.
static func tile(parent: Node3D, family: String, origin: Vector3, cells: Vector2i, seed: int = 0) -> void:
	var depth: float = BORDER_WIDTH if family == "border" else SIZE
	for x: int in range(cells.x):
		for z: int in range(cells.y):
			var piece: Node3D = module(pick(family, Vector2i(x, z), seed))
			piece.position = origin + Vector3(x * SIZE, 0.0, z * depth)
			parent.add_child(piece)

## Floors a convex room outline (world x/z, as in RedDescentLayout.rooms()) at height y:
## a kerb course (border strips, mitred at corners) along every edge and field modules on
## the world-aligned 4 m grid inside it, so the pattern continues from room to room.
## Only modules that cross an edge use the clipped (discarding) shader. Returns the modules
## added. The old flat floor must become collision-only: these stones sit within 2 cm of y.
static func cover(parent: Node3D, outline: PackedVector2Array, y: float, family: String = "coursed", seed: int = 0, kerb: bool = true) -> int:
	var polygon: PackedVector2Array = counter_clockwise(outline)
	var inset: float = BORDER_WIDTH if kerb else 0.0
	var field: PackedVector2Array = offset(polygon, inset)
	var field_planes: PackedVector3Array = clip_planes(field)
	var field_materials: Dictionary[String, ShaderMaterial] = {}
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for point: Vector2 in field:
		low = low.min(point)
		high = high.max(point)
	var count: int = 0
	for x: int in range(floori(low.x / SIZE), ceili(high.x / SIZE)):
		for z: int in range(floori(low.y / SIZE), ceili(high.y / SIZE)):
			var square: PackedVector2Array = PackedVector2Array([Vector2(x, z) * SIZE, Vector2(x + 1, z) * SIZE, Vector2(x + 1, z + 1) * SIZE, Vector2(x, z + 1) * SIZE])
			var inside: int = 0
			for corner: Vector2 in square:
				inside += 1 if Geometry2D.is_point_in_polygon(corner, field) else 0
			if inside < 4 and Geometry2D.intersect_polygons(square, field).is_empty():
				continue
			var piece: Node3D = module(pick(family, Vector2i(x, z), seed))
			piece.position = Vector3(x * SIZE, y, z * SIZE)
			if inside < 4:
				for part: String in PARTS:
					if not field_materials.has(part):
						field_materials[part] = clipped(part, field_planes)
				use_materials(piece, field_materials)
			parent.add_child(piece)
			count += 1
	if not kerb:
		return count
	var room_planes: PackedVector3Array = clip_planes(polygon)
	var size: int = polygon.size()
	for index: int in range(size):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % size]
		var along: Vector2 = (b - a).normalized()
		var inward: Vector2 = Vector2(-along.y, along.x)
		var before: Vector2 = inward_normal(polygon[index - 1], a)
		var after: Vector2 = inward_normal(b, polygon[(index + 2) % size])
		# Mitres: each kerb owns the points nearer to its own wall than to the neighbouring one.
		var planes: PackedVector3Array = room_planes.duplicate()
		planes.append(Vector3(inward.x - before.x, inward.y - before.y, (inward - before).dot(a)))
		planes.append(Vector3(inward.x - after.x, inward.y - after.y, (inward - after).dot(b)))
		var materials: Dictionary[String, ShaderMaterial] = {}
		for part: String in PARTS:
			materials[part] = clipped(part, planes)
		var basis: Basis = Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(inward.x, 0.0, inward.y))
		for step: int in range(ceili(a.distance_to(b) / SIZE)):
			var strip: Node3D = module(pick("border", Vector2i(index, step), seed))
			var start: Vector2 = a + along * (step * SIZE)
			strip.transform = Transform3D(basis, Vector3(start.x, y, start.y))
			use_materials(strip, materials)
			parent.add_child(strip)
			count += 1
	return count

static func use_materials(piece: Node3D, materials: Dictionary[String, ShaderMaterial]) -> void:
	for child: Node in piece.get_children():
		var visual: MeshInstance3D = child as MeshInstance3D
		visual.material_override = materials[String(child.name).get_slice("_", 0)]

static func counter_clockwise(outline: PackedVector2Array) -> PackedVector2Array:
	var area: float = 0.0
	for index: int in range(outline.size()):
		area += outline[index].cross(outline[(index + 1) % outline.size()])
	var result: PackedVector2Array = outline.duplicate()
	if area < 0.0:
		result.reverse()
	return result

static func inward_normal(a: Vector2, b: Vector2) -> Vector2:
	var along: Vector2 = (b - a).normalized()
	return Vector2(-along.y, along.x)

## Half-planes (n.x, n.y, d) of a counter-clockwise convex outline: inside when n.p <= d.
static func clip_planes(polygon: PackedVector2Array) -> PackedVector3Array:
	var planes: PackedVector3Array = PackedVector3Array()
	for index: int in range(polygon.size()):
		var outward: Vector2 = -inward_normal(polygon[index], polygon[(index + 1) % polygon.size()])
		planes.append(Vector3(outward.x, outward.y, outward.dot(polygon[index])))
	return planes

## Convex outline moved inwards by `distance` (edges shifted, corners re-intersected).
static func offset(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	if distance <= 0.0:
		return polygon
	var result: PackedVector2Array = PackedVector2Array()
	var size: int = polygon.size()
	for index: int in range(size):
		var a0: Vector2 = polygon[index - 1] + inward_normal(polygon[index - 1], polygon[index]) * distance
		var a1: Vector2 = polygon[index] + inward_normal(polygon[index - 1], polygon[index]) * distance
		var b0: Vector2 = polygon[index] + inward_normal(polygon[index], polygon[(index + 1) % size]) * distance
		var b1: Vector2 = polygon[(index + 1) % size] + inward_normal(polygon[index], polygon[(index + 1) % size]) * distance
		var hit: Variant = Geometry2D.line_intersects_line(a0, a1 - a0, b0, b1 - b0)
		result.append(hit as Vector2 if hit != null else a1)
	return result
