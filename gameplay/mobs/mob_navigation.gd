class_name MobNavigation
extends RefCounted

# One ground-plane grid, shared by the encounter. Dynamic actors are steered by physics.
const CELL: float = 0.5
var grid: AStarGrid2D = AStarGrid2D.new()

func build(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	grid.region = Rect2i(0, 0, 43, 43)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = Vector2(-10.5, -10.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 1.8
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = exclude
	for x: int in range(43):
		for z: int in range(43):
			var point: Vector2 = grid.get_point_position(Vector2i(x, z))
			query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, 1.0, point.y))
			grid.set_point_solid(Vector2i(x, z), not space.intersect_shape(query, 1).is_empty())

func nearest(location: Vector3) -> Vector2i:
	# ponytail: scan this tiny fixed grid; use a local search if the arena grows.
	var point: Vector2i = Vector2i(roundi((location.x + 10.5) / CELL), roundi((location.z + 10.5) / CELL))
	point = point.clamp(Vector2i.ZERO, Vector2i(42, 42))
	var best: Vector2i = point
	var distance: float = INF
	for x: int in range(43):
		for z: int in range(43):
			var candidate: Vector2i = Vector2i(x, z)
			if not grid.is_point_solid(candidate) and Vector2(candidate).distance_squared_to(Vector2(point)) < distance:
				best = candidate
				distance = Vector2(candidate).distance_squared_to(Vector2(point))
	return best

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in grid.get_point_path(nearest(from), nearest(to), true):
		result.append(Vector3(point.x, 0.95, point.y))
	return result
