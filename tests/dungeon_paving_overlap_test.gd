extends SceneTree
## A mitred edge crosses baked paving although its segment midpoint does not.

func _initialize() -> void:
	var geometry: RedDescentGeometry = RedDescentGeometry.new()
	geometry.rooms.clear()
	geometry.paths.assign([{"id": "nave", "width": 4.4, "points": PackedVector3Array([Vector3(7,0,21),Vector3(7,0,34)])}])
	geometry.stone_passages.assign([{"route": "nave", "segment": 0, "t0": 0.0, "t1": .504}])
	var triangle: PackedVector3Array = PackedVector3Array([Vector3(4,0,26),Vector3(10,0,28),Vector3(4,0,28)])
	geometry.ribbon_top(triangle[0],triangle[1],triangle[2],"floor")
	assert(geometry.collision_faces == triangle, "Clipping the render changed the walking triangle")
	var cover: PackedVector2Array = PackedVector2Array([Vector2(4.6,21),Vector2(9.4,21),Vector2(9.4,27.552),Vector2(4.6,27.552)])
	var visible_area: float = 0.0
	for vertices: PackedVector3Array in geometry.surfaces.values():
		for index: int in range(0,vertices.size(),3):
			var polygon: PackedVector2Array = PackedVector2Array()
			for corner: int in range(3):
				var point: Vector3 = vertices[index+corner]
				polygon.append(Vector2(point.x,point.z))
			visible_area += area(polygon)
			for overlap: PackedVector2Array in Geometry2D.intersect_polygons(polygon,cover):
				assert(area(overlap) < .0001, "Old flat floor still cuts through baked flags")
	assert(visible_area > .5, "Uncovered floor was deleted along with the overlap")
	# The root tunnel clears a shaft corner although its centre line crosses
	# only the adjacent wall. The other face must not block the camera/lane.
	geometry.paths.assign([{"id": "root_tunnel", "enclosed": true, "width": 5.0, "points": PackedVector3Array([Vector3(-30,-23,-8.5),Vector3(-23,-23,-16)])}])
	geometry.ribbon_edges.clear()
	var cuts: Array[Dictionary] = geometry.shaft_route_cuts(Vector2(-22,-1),Vector2(-26,-12),[])
	assert(not cuts.is_empty(), "The adjacent shaft face remains inside the root tunnel")
	for cut: Dictionary in cuts:
		assert(float(cut["t1"])-float(cut["t0"]) < .75, "Corner clearance removed most of the shaft wall")
	geometry.paths.assign([{"id": "ledge", "enclosed": false, "width": 2.0, "points": PackedVector3Array([Vector3(-2,0,0),Vector3(2,0,0)])}])
	geometry.ribbon_edges.clear()
	assert(geometry.shaft_route_cuts(Vector2(-2,.5),Vector2(2,.5),[]).is_empty(), "An open ledge carved the wall beside it")
	geometry.paths.assign([{"id": "crossing", "enclosed": false, "width": 2.0, "points": PackedVector3Array([Vector3(0,0,-3),Vector3(0,0,3)])}])
	geometry.ribbon_edges.clear()
	assert(not geometry.shaft_route_cuts(Vector2(-2,0),Vector2(2,0),[]).is_empty(), "An open crossing lost its doorway")
	var room_door: Array[Dictionary] = [{"t0":0.0,"t1":1.0,"band":Vector2(-1,5)}]
	assert(geometry.shaft_route_cuts(Vector2(-2,0),Vector2(2,0),room_door).is_empty(), "An open crossing duplicated the room's doorway")
	geometry.free()
	print("DUNGEON_PAVING_OVERLAP_OK: angled render overlap removed, uncovered floor and collision retained")
	quit()

func area(polygon: PackedVector2Array) -> float:
	var twice: float = 0.0
	for index: int in range(polygon.size()):
		twice += polygon[index].cross(polygon[(index+1)%polygon.size()])
	return absf(twice)*.5
