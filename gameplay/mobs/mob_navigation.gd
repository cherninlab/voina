class_name MobNavigation
extends RefCounted

# One grid over the church yard, shared by the encounter. Dynamic actors are steered by physics.
# The yard lies on a slope, so every cell keeps the height of the ground under it.
const CELL: float = 0.5
const CELLS: int = 89 # 44 m around the yard centre at 0.5 m
const STAND: float = 0.95 # capsule centre above the ground
const MAX_STEP: float = 0.3 # height change between neighbouring cells that still counts as walkable
const SEARCH: int = 12 # nearest() looks this many cells out for a free one
var grid: AStarGrid2D = AStarGrid2D.new()
var origin: Vector2 = Vector2.ZERO
var heights: PackedFloat32Array = PackedFloat32Array()

func build(space: PhysicsDirectSpaceState3D, exclude: Array[RID], center: Vector2 = ChurchSite.YARD_CENTER) -> void:
	origin = center - Vector2.ONE * CELL * (CELLS - 1) * 0.5
	grid.region = Rect2i(0, 0, CELLS, CELLS)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = origin
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	heights.resize(CELLS * CELLS)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	ray.exclude = exclude
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = exclude
	for x: int in range(CELLS):
		for z: int in range(CELLS):
			var point: Vector2 = origin + Vector2(x, z) * CELL
			var ground: float = lowest_ground(space, ray, point)
			heights[x * CELLS + z] = ground
			var blocked: bool = is_nan(ground)
			if not blocked:
				# Clearance starts a little above the ground so the slope itself never blocks.
				query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, ground + 0.35 + capsule.height * 0.5, point.y))
				blocked = not space.intersect_shape(query, 1).is_empty()
			grid.set_point_solid(Vector2i(x, z), blocked)
	# Ledges, tomb tops and roofs are cut off from the ground around them.
	for x: int in range(CELLS):
		for z: int in range(CELLS):
			var cell: Vector2i = Vector2i(x, z)
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var other: Vector2i = cell + step
				if other.x < CELLS and other.y < CELLS and absf(height(cell) - height(other)) > MAX_STEP:
					grid.set_point_solid(cell, true)
					grid.set_point_solid(other, true)

# The lowest open surface under a point: a ray stopped by a roof, branch or gravestone top keeps
# going down from just below it, so the ground itself decides the cell's height. A surface with
# less than a body's height of room under the one above it is buried (the old landscape 1.5 m under
# the village floor) and does not count. NAN where nothing is.
const HEADROOM: float = 1.9
func lowest_ground(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, point: Vector2) -> float:
	var ground: float = NAN
	var above: float = INF
	var top: float = 60.0
	for attempt: int in range(6):
		ray.from = Vector3(point.x, top, point.y)
		ray.to = Vector3(point.x, -40.0, point.y)
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			break
		var surface: float = (hit["position"] as Vector3).y
		if is_nan(ground) or above - surface >= HEADROOM:
			ground = surface
		above = surface
		top = surface - 0.02
	return ground

func height(cell: Vector2i) -> float:
	var value: float = heights[cell.x * CELLS + cell.y]
	return value if not is_nan(value) else -1000.0

func cell_of(location: Vector3) -> Vector2i:
	return Vector2i(roundi((location.x - origin.x) / CELL), roundi((location.z - origin.y) / CELL))

func covers(location: Vector3) -> bool:
	var cell: Vector2i = cell_of(location)
	return cell.x >= 0 and cell.y >= 0 and cell.x < CELLS and cell.y < CELLS

func walkable(location: Vector3) -> bool:
	return not heights.is_empty() and covers(location) and not grid.is_point_solid(cell_of(location))

# Rings outward from the cell under the location, so open ground costs a single lookup.
func nearest(location: Vector3) -> Vector2i:
	var center: Vector2i = cell_of(location).clamp(Vector2i.ZERO, Vector2i(CELLS - 1, CELLS - 1))
	for radius: int in range(SEARCH + 1):
		var best: Vector2i = -Vector2i.ONE
		var distance: int = 1 << 30
		for x: int in range(maxi(0, center.x - radius), mini(CELLS - 1, center.x + radius) + 1):
			for z: int in range(maxi(0, center.y - radius), mini(CELLS - 1, center.y + radius) + 1):
				var candidate: Vector2i = Vector2i(x, z)
				if maxi(absi(x - center.x), absi(z - center.y)) != radius or grid.is_point_solid(candidate):
					continue
				var squared: int = (candidate - center).length_squared()
				if squared < distance:
					best = candidate
					distance = squared
		if best.x >= 0:
			return best
	return center

# A standing point (capsule centre) over the nearest free cell.
func stand_point(location: Vector3) -> Vector3:
	return point_of(nearest(location))

func point_of(cell: Vector2i) -> Vector3:
	var flat: Vector2 = origin + Vector2(cell) * CELL
	return Vector3(flat.x, height(cell) + STAND, flat.y)

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if heights.is_empty():
		result.append(to) # not built (no encounter started): straight at it
		return result
	for cell: Vector2i in grid.get_id_path(nearest(from), nearest(to), true):
		result.append(point_of(cell))
	return result
