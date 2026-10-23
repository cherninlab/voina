class_name RedDescentLayout
extends RefCounted
## Original fixed level coordinates. Physics, rendering and route probes share this source.

const ORIGIN: Vector3 = Vector3(50, 0, 50)
const FALL_LIMIT: float = -56.0
const MAIN_PATHS: int = 11

static func at(point: Vector3) -> Vector3:
	return point - ORIGIN

static func points(source: Array[Vector3]) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in source:
		result.append(at(point))
	return result

static func outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-16.0, -28.0), Vector2(-2.0, -30.0), Vector2(8.0, -26.0), Vector2(16.0, -28.0), Vector2(25.0, -21.0), Vector2(28.0, -7.0), Vector2(22.0, 0.0), Vector2(27.0, 10.0), Vector2(18.0, 24.0), Vector2(4.0, 28.0), Vector2(-7.0, 22.0), Vector2(-19.0, 24.0), Vector2(-25.0, 12.0), Vector2(-22.0, -1.0), Vector2(-26.0, -12.0), Vector2(-21.0, -22.0)])

static func spine() -> PackedVector2Array:
	return PackedVector2Array([Vector2(5.0, -11.0), Vector2(11.0, -9.0), Vector2(9.0, -4.0), Vector2(12.0, 0.0), Vector2(8.0, 5.0), Vector2(3.0, 2.0), Vector2(4.0, -3.0), Vector2(1.0, -6.0)])

static func routes() -> Array[Dictionary]:
	return [
		{"id": "entry", "points": points([Vector3(8.0, 0.0, 26.0), Vector3(25.0, 0.0, 27.0), Vector3(28.0, 0.0, 27.0), Vector3(28.0, 0.0, 34.0)]), "width": 5.0, "wood": false, "enclosed": true},
		{"id": "high_span", "points": points([Vector3(28.0, 0.0, 34.0), Vector3(38.0, -0.7, 36.0), Vector3(47.0, -1.4, 38.0), Vector3(53.0, -2.0, 35.0), Vector3(65.0, -3.0, 35.0), Vector3(74.0, -4.0, 40.0)]), "width": 3.2, "wood": true, "enclosed": false},
		{"id": "upper_hall", "points": points([Vector3(74.0, -4.0, 40.0), Vector3(84.0, -4.0, 41.5), Vector3(86.0, -4.0, 26.0), Vector3(86.0, -6.0, 21.0)]), "width": 4.4, "wood": false, "enclosed": true},
		{"id": "first_stair", "points": points([Vector3(86.0, -6.0, 21.0), Vector3(86.0, -6.0, 11.0), Vector3(82.0, -6.0, 11.0), Vector3(82.0, -10.0, 21.0)]), "width": 3.8, "wood": false, "enclosed": true},
		{"id": "chapel_approach", "points": points([Vector3(82.0, -10.0, 21.0), Vector3(72.0, -10.0, 20.0), Vector3(64.0, -10.0, 17.0), Vector3(50.0, -10.0, 18.0), Vector3(44.0, -10.0, 22.0)]), "width": 4.4, "wood": false, "enclosed": true},
		{"id": "central_ledge", "points": points([Vector3(44.0, -10.0, 22.0), Vector3(43.5, -10.0, 27.0), Vector3(43.0, -11.0, 31.0), Vector3(45.0, -12.0, 36.0), Vector3(49.0, -13.0, 41.0), Vector3(52.0, -14.0, 47.0), Vector3(51.0, -15.0, 51.5), Vector3(54.0, -16.0, 57.0), Vector3(60.0, -17.0, 63.0), Vector3(57.0, -18.0, 71.0)]), "width": 4.0, "wood": false, "enclosed": false},
		{"id": "nave", "points": points([Vector3(57.0, -18.0, 71.0), Vector3(57.0, -18.0, 84.0), Vector3(44.0, -18.0, 84.0), Vector3(44.0, -18.0, 80.0), Vector3(40.0, -18.0, 80.0), Vector3(40.0, -18.0, 77.0), Vector3(36.0, -19.0, 74.0), Vector3(20.0, -20.0, 74.0)]), "width": 4.4, "wood": false, "enclosed": true},
		{"id": "second_stair", "points": points([Vector3(20.0, -20.0, 74.0), Vector3(20.0, -20.0, 86.0), Vector3(16.0, -20.0, 86.0), Vector3(16.0, -23.0, 74.0)]), "width": 3.8, "wood": false, "enclosed": true},
		{"id": "root_tunnel", "points": points([Vector3(16.0, -23.0, 74.0), Vector3(9.0, -23.0, 74.0), Vector3(9.0, -23.0, 64.0), Vector3(19.0, -23.0, 56.0), Vector3(12.0, -23.0, 48.0), Vector3(20.0, -23.0, 41.5), Vector3(27.0, -23.0, 34.0)]), "width": 5.0, "wood": false, "enclosed": true},
		{"id": "low_span", "points": points([Vector3(27.0, -23.0, 34.0), Vector3(36.0, -24.0, 34.0), Vector3(41.0, -24.5, 42.0), Vector3(47.0, -25.0, 54.0), Vector3(55.0, -26.0, 59.0), Vector3(62.0, -27.0, 58.0), Vector3(66.0, -27.3, 53.0), Vector3(75.0, -28.0, 56.0)]), "width": 3.6, "wood": true, "enclosed": false},
		{"id": "choir", "points": points([Vector3(75.0, -28.0, 56.0), Vector3(83.0, -28.0, 55.0), Vector3(88.0, -28.0, 48.0)]), "width": 4.6, "wood": false, "enclosed": true},
		{"id": "return_stair", "points": points([Vector3(88.0, -28.0, 48.0), Vector3(88.0, -28.0, 60.0), Vector3(88.0, -25.0, 73.0), Vector3(84.0, -25.0, 73.0), Vector3(84.0, -22.0, 60.0), Vector3(88.0, -22.0, 60.0), Vector3(88.0, -19.0, 73.0), Vector3(84.0, -19.0, 73.0), Vector3(84.0, -16.0, 60.0), Vector3(88.0, -16.0, 60.0), Vector3(88.0, -13.0, 73.0), Vector3(84.0, -13.0, 73.0), Vector3(84.0, -10.0, 60.0)]), "width": 3.5, "wood": false, "enclosed": true},
		{"id": "return_gallery", "points": points([Vector3(84.0, -10.0, 60.0), Vector3(72.0, -10.0, 60.0), Vector3(76.0, -10.0, 49.0), Vector3(75.0, -10.0, 36.0), Vector3(72.0, -10.0, 26.0), Vector3(72.0, -10.0, 20.0), Vector3(82.0, -10.0, 21.0)]), "width": 4.0, "wood": false, "enclosed": true},
		{"id": "upper_cells", "points": points([Vector3(84.0, -4.0, 41.5), Vector3(84.0, -4.0, 54.0), Vector3(86.0, -4.0, 56.0), Vector3(96.0, -4.0, 56.0), Vector3(96.0, -4.0, 24.0), Vector3(86.0, -4.0, 26.0), Vector3(86.0, -6.0, 21.0)]), "width": 4.0, "wood": false, "enclosed": true},
		{"id": "ossuary_loop", "points": points([Vector3(40.0, -10.0, 20.0), Vector3(32.0, -10.0, 20.0), Vector3(32.0, -10.0, 44.0), Vector3(26.0, -10.0, 44.0), Vector3(26.0, -10.0, 36.0), Vector3(16.0, -10.0, 34.0), Vector3(16.0, -10.0, 25.0), Vector3(18.0, -10.0, 16.0), Vector3(38.0, -10.0, 16.0), Vector3(40.0, -10.0, 20.0)]), "width": 4.0, "wood": false, "enclosed": true},
		{"id": "bell_loop", "points": points([Vector3(50.0, -18.0, 84.0), Vector3(50.0, -18.0, 86.0), Vector3(66.0, -18.0, 86.0), Vector3(86.0, -18.0, 86.0), Vector3(86.0, -18.0, 94.0), Vector3(64.0, -18.0, 94.0), Vector3(64.0, -18.0, 92.0), Vector3(56.0, -18.0, 92.0), Vector3(56.0, -18.0, 84.0)]), "width": 4.0, "wood": false, "enclosed": true},
		{"id": "cave_bypass", "points": points([Vector3(9.0, -23.0, 64.0), Vector3(4.0, -23.0, 57.0), Vector3(7.0, -23.0, 44.0), Vector3(20.0, -23.0, 41.5)]), "width": 4.5, "wood": false, "enclosed": true},
	]

static func main_route() -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var paths: Array[Dictionary] = routes()
	for index: int in range(MAIN_PATHS):
		for point: Vector3 in paths[index]["points"] as PackedVector3Array:
			if result.is_empty() or point.distance_to(result[-1]) > 0.02:
				result.append(point)
	return result

static func return_route() -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for index: int in [11, 12]:
		result.append_array(routes()[index]["points"] as PackedVector3Array)
	return result

static func player_spawn(slot: int) -> Vector3:
	return at(Vector3(6 + (slot % 2) * 3.0, 0.95, 24 + (slot / 2) * 3.0))

static func finish_point() -> Vector3:
	return at(Vector3(88, -28, 48))

static func rooms() -> Array[Dictionary]:
	return [
		{"id": "entry", "floor": 0.0, "height": 5.0, "points": PackedVector2Array([Vector2(-48.0, -29.0), Vector2(-42.0, -32.0), Vector2(-34.0, -30.0), Vector2(-32.0, -25.0), Vector2(-34.0, -18.0), Vector2(-40.0, -15.0), Vector2(-46.0, -18.0), Vector2(-48.0, -22.0)])},
		{"id": "antechamber", "floor": 0.0, "height": 7.0, "points": PackedVector2Array([Vector2(-26.0, -31.0), Vector2(-18.0, -31.0), Vector2(-16.0, -29.0), Vector2(-16.0, -19.0), Vector2(-18.0, -17.0), Vector2(-26.0, -17.0), Vector2(-28.0, -19.0), Vector2(-28.0, -29.0)])},
		{"id": "restraint", "floor": -4.0, "height": 14.0, "points": PackedVector2Array([Vector2(29.0, -23.0), Vector2(39.0, -23.0), Vector2(42.0, -20.0), Vector2(42.0, -5.0), Vector2(39.0, -2.0), Vector2(29.0, -2.0), Vector2(26.0, -5.0), Vector2(26.0, -20.0)])},
		{"id": "cells", "floor": -4.0, "height": 5.0, "points": PackedVector2Array([Vector2(32.0, 0.0), Vector2(40.0, 0.0), Vector2(42.0, 2.0), Vector2(42.0, 10.0), Vector2(40.0, 12.0), Vector2(32.0, 12.0), Vector2(30.0, 10.0), Vector2(30.0, 2.0)])},
		{"id": "chapel", "floor": -10.0, "height": 16.0, "points": PackedVector2Array([Vector2(-9.0, -43.0), Vector2(15.0, -43.0), Vector2(18.0, -40.0), Vector2(18.0, -27.0), Vector2(15.0, -24.0), Vector2(-9.0, -24.0), Vector2(-12.0, -27.0), Vector2(-12.0, -40.0)])},
		{"id": "nave", "floor": -18.0, "height": 20.0, "points": PackedVector2Array([Vector2(-11.0, 28.0), Vector2(11.0, 28.0), Vector2(14.0, 31.0), Vector2(14.0, 46.0), Vector2(11.0, 49.0), Vector2(-11.0, 49.0), Vector2(-14.0, 46.0), Vector2(-14.0, 31.0)])},
		{"id": "ossuary", "floor": -10.0, "height": 7.0, "points": PackedVector2Array([Vector2(-39.0, -43.0), Vector2(-25.0, -43.0), Vector2(-22.0, -40.0), Vector2(-22.0, -28.0), Vector2(-25.0, -25.0), Vector2(-39.0, -25.0), Vector2(-42.0, -28.0), Vector2(-42.0, -40.0)])},
		{"id": "bones", "floor": -10.0, "height": 4.0, "points": PackedVector2Array([Vector2(-40.5, -20.0), Vector2(-23.5, -20.0), Vector2(-22.0, -18.5), Vector2(-22.0, -13.5), Vector2(-23.5, -12.0), Vector2(-40.5, -12.0), Vector2(-42.0, -13.5), Vector2(-42.0, -18.5)])},
		{"id": "window", "floor": -10.0, "height": 6.0, "points": PackedVector2Array([Vector2(-26.0, -10.0), Vector2(-16.0, -10.0), Vector2(-16.0, -2.0), Vector2(-26.0, -2.0)])},
		{"id": "bell", "floor": -18.0, "height": 12.0, "points": PackedVector2Array([Vector2(29.0, 29.0), Vector2(43.0, 29.0), Vector2(46.0, 32.0), Vector2(46.0, 46.0), Vector2(43.0, 49.0), Vector2(29.0, 49.0), Vector2(26.0, 46.0), Vector2(26.0, 32.0)])},
		{"id": "choir", "floor": -28.0, "height": 22.0, "points": PackedVector2Array([Vector2(29.0, -13.0), Vector2(43.0, -13.0), Vector2(46.0, -10.0), Vector2(46.0, 5.0), Vector2(43.0, 8.0), Vector2(29.0, 8.0), Vector2(26.0, 5.0), Vector2(26.0, -10.0)])},
	]
