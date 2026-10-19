extends SceneTree
## Terrain audit (T-097). Loads the real match world (baked village snapshot unless --village-source)
## and checks what a player sees and stands on:
## - collision versus the visible ground triangles over dense grids (village, gate apron, trail,
##   church yard, landscape out to 176 m), collision holes, invisible ground, overlapping ground
##   meshes (poke-through, coplanar z-fight risk) and visible steps/edges in the ground,
## - each ground collider's faces against the visible mesh it should copy,
## - steep or spiky landscape near the playable routes, inverted or faceted ground normals,
## - scatter, trees and props floating above or buried below the visible ground,
## - player capsules (radius 0.4, height 1.8, default floor settings, 6.5 m/s, gravity 20) dropped on
##   thousands of points and walked along routes (village to church, palisade inside and outside,
##   lookout ramp, a 50 m foothill loop); the real host player is also dropped at a few points.
## Numeric checks run headless:
##   "$GODOT" --headless --fixed-fps 60 --path . --script scripts/terrain_audit.gd -- --host --no-pve --port=7795
## With the real renderer (no --headless), --capture-dir=/abs/dir also saves ground-level views.
## --json=/abs/file.json writes the summary; --strict exits 1 when a check fails; --quick skips walks.

const RADIUS: float = 0.4
const HEIGHT: float = 1.8
const TOLERANCE: float = 0.03
const LAYER: int = 1 << 19
const GROUND_LAYER: int = 1 << 20 # added to ground colliders in this audit world only

class Surface:
	var label: String
	var node: MeshInstance3D
	var tris: PackedVector3Array = PackedVector3Array()
	var origin: Vector2
	var cell: float = 1.0
	var columns: int = 1
	var rows: int = 1
	var bins: Array[PackedInt32Array] = []
	var bounds: Rect2

	func _init(name: String, visual: MeshInstance3D) -> void:
		label = name
		node = visual
		var faces: PackedVector3Array = visual.mesh.get_faces()
		var xform: Transform3D = visual.global_transform
		tris.resize(faces.size())
		var extent: float = 0.0
		for index: int in range(faces.size()):
			tris[index] = xform * faces[index]
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		for index: int in range(0, tris.size(), 3):
			for corner: int in range(3):
				var point: Vector3 = tris[index + corner]
				low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
				high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
			if index < 300:
				extent = maxf(extent, absf(tris[index].x - tris[index + 1].x) + absf(tris[index].z - tris[index + 1].z))
		bounds = Rect2(low, high - low)
		cell = clampf(extent, 0.25, 6.0)
		origin = low
		columns = int(ceilf((high.x - low.x) / cell)) + 1
		rows = int(ceilf((high.y - low.y) / cell)) + 1
		bins.resize(columns * rows)
		for index: int in range(bins.size()):
			bins[index] = PackedInt32Array()
		for index: int in range(0, tris.size(), 3):
			var a: Vector3 = tris[index]
			var b: Vector3 = tris[index + 1]
			var c: Vector3 = tris[index + 2]
			var x0: int = int(floorf((minf(a.x, minf(b.x, c.x)) - origin.x) / cell))
			var x1: int = int(floorf((maxf(a.x, maxf(b.x, c.x)) - origin.x) / cell))
			var z0: int = int(floorf((minf(a.z, minf(b.z, c.z)) - origin.y) / cell))
			var z1: int = int(floorf((maxf(a.z, maxf(b.z, c.z)) - origin.y) / cell))
			for z: int in range(maxi(z0, 0), mini(z1, rows - 1) + 1):
				for x: int in range(maxi(x0, 0), mini(x1, columns - 1) + 1):
					bins[z * columns + x].append(index)

	## Highest point of this mesh above (x, z), or NAN where it has no triangle.
	func height_at(x: float, z: float) -> float:
		var column: int = int(floorf((x - origin.x) / cell))
		var row: int = int(floorf((z - origin.y) / cell))
		if column < 0 or row < 0 or column >= columns or row >= rows:
			return NAN
		var best: float = -INF
		for index: int in bins[row * columns + column]:
			var a: Vector3 = tris[index]
			var b: Vector3 = tris[index + 1]
			var c: Vector3 = tris[index + 2]
			var det: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(det) < 1e-9:
				continue
			var l1: float = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / det
			var l2: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / det
			var l3: float = 1.0 - l1 - l2
			if l1 < -1e-5 or l2 < -1e-5 or l3 < -1e-5:
				continue
			best = maxf(best, l1 * a.y + l2 * b.y + l3 * c.y)
		return best if best > -INF else NAN

class Walker extends CharacterBody3D:
	var route: Array[Vector3] = []
	var next: int = 0
	var frames: int = 0
	var air: int = 0
	var longest_air: int = 0
	var walls: Array[Vector3] = []
	var lowest_margin: float = INF
	var history: PackedVector3Array = PackedVector3Array()
	var done_frame: int = -1

	func _init(terrain_only: bool = false) -> void:
		collision_layer = LAYER
		collision_mask = GROUND_LAYER if terrain_only else 1
		var shape: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = RADIUS
		capsule.height = HEIGHT
		shape.shape = capsule
		add_child(shape)

	func _physics_process(delta: float) -> void:
		frames += 1
		var direction: Vector3 = Vector3.ZERO
		if next < route.size():
			var toward: Vector3 = route[next] - global_position
			toward.y = 0.0
			if toward.length() < 0.7:
				next += 1
				if next == route.size():
					done_frame = frames
			else:
				direction = toward.normalized()
		velocity.x = move_toward(velocity.x, direction.x * 6.5, delta * 24.0)
		velocity.z = move_toward(velocity.z, direction.z * 6.5, delta * 24.0)
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		move_and_slide()
		if is_on_floor():
			air = 0
		else:
			air += 1
			longest_air = maxi(longest_air, air)
		if done_frame >= 0:
			return
		if is_on_wall() and not route.is_empty() and (walls.is_empty() or walls[-1].distance_to(global_position) > 1.0):
			walls.append(global_position)
		if frames % 6 == 0:
			history.append(global_position)

var world: Node3D
var village: Node3D
var space: PhysicsDirectSpaceState3D
var surfaces: Array[Surface] = []
var ground_bodies: Dictionary[RID, String] = {}
var summary: Dictionary = {}
var failures: Array[String] = []
var started: int = 0

func _initialize() -> void:
	run.call_deferred()

func arg(name: String, fallback: String = "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(name + "="):
			return argument.trim_prefix(name + "=")
	return fallback

func flag(name: String) -> bool:
	return name in OS.get_cmdline_user_args()

func note(line: String) -> void:
	print("TERRAIN_AUDIT ", line)

func fail(check: String, detail: String) -> void:
	failures.append(check)
	print("TERRAIN_AUDIT_FAIL ", check, ": ", detail)

func run() -> void:
	started = Time.get_ticks_msec()
	root.size = Vector2i(1600, 1000)
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	for frame: int in range(90):
		await process_frame
	for frame: int in range(4):
		await physics_frame
	village = world.get_node("WoodlandVillage") as Node3D
	space = world.get_world_3d().direct_space_state
	collect_surfaces()
	collect_ground_bodies()
	check_collider_faces()
	check_normals()
	scan_regions()
	scan_border()
	scan_landscape_shape()
	check_scatter()
	check_props()
	check_invisible_colliders()
	check_palisade()
	check_overlays()
	if not flag("--quick"):
		await drop_capsules()
		await walk_routes()
		await drop_real_player()
	if DisplayServer.get_name() != "headless" and not arg("--capture-dir").is_empty():
		await capture_views(arg("--capture-dir"))
	summary["failures"] = failures
	summary["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	var json_path: String = arg("--json")
	if not json_path.is_empty():
		var file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(summary, "  ", false))
		file.close()
	if failures.is_empty():
		print("TERRAIN_AUDIT_OK: every check passed in ", summary["seconds"], " s")
	else:
		print("TERRAIN_AUDIT_DONE: ", failures.size(), " failing checks: ", ", ".join(failures))
	quit(1 if flag("--strict") and not failures.is_empty() else 0)

# --- Visible ground ---------------------------------------------------------------------------

func collect_surfaces() -> void:
	var labels: Dictionary[String, int] = {}
	for node: Node in village.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree():
			continue
		var material: ShaderMaterial = visual.material_override as ShaderMaterial
		if material == null:
			continue
		var label: String = ""
		var size: Vector3 = (visual.global_transform * visual.mesh.get_aabb()).size
		if material.get_shader_parameter("dirt_color") != null and material.get_shader_parameter("soil") == null:
			label = "village" if size.x > 40.0 else "apron"
			if String(visual.name).begins_with("VillageSkirt"):
				label = "skirt"
		elif material.get_shader_parameter("soil") != null and material.get_shader_parameter("rock") != null:
			var has_body: bool = false
			for child: Node in visual.get_children():
				has_body = has_body or child is StaticBody3D
			label = "landscape" if has_body else ""
		if label.is_empty():
			continue
		labels[label] = labels.get(label, 0) + 1
		surfaces.append(Surface.new(label, visual))
	note("surfaces %s" % [labels])
	summary["surfaces"] = labels
	for label: String in ["village", "landscape"]:
		if not labels.has(label):
			fail("surfaces", "no visible %s ground mesh" % label)

func collect_ground_bodies() -> void:
	for node: Node in world.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = node as CollisionShape3D
		var concave: ConcavePolygonShape3D = shape.shape as ConcavePolygonShape3D
		var body: CollisionObject3D = shape.get_parent() as CollisionObject3D
		if concave == null or body == null or shape.disabled:
			continue
		var faces: int = concave.get_faces().size()
		for surface: Surface in surfaces:
			if surface.tris.size() == faces:
				ground_bodies[body.get_rid()] = surface.label
				body.collision_layer |= GROUND_LAYER
	note("ground colliders %d %s" % [ground_bodies.size(), ground_bodies.values()])

## Top visible ground above (x, z): [height, label, second height, second label].
func visible_ground(x: float, z: float) -> Array:
	var top: float = NAN
	var label: String = ""
	var second: float = NAN
	var second_label: String = ""
	for surface: Surface in surfaces:
		if not surface.bounds.grow(0.01).has_point(Vector2(x, z)):
			continue
		var height: float = surface.height_at(x, z)
		if is_nan(height):
			continue
		if is_nan(top) or height > top:
			second = top
			second_label = label
			top = height
			label = surface.label
		elif is_nan(second) or height > second:
			second = height
			second_label = surface.label
	return [top, label, second, second_label]

## First ground-collider hit straight down: [height, normal_y, label, top static hit height, top label].
func physical_ground(x: float, z: float) -> Array:
	var exclude: Array[RID] = []
	var top_height: float = NAN
	var top_label: String = ""
	for attempt: int in range(10):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x, 250.0, z), Vector3(x, -60.0, z))
		query.exclude = exclude
		query.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return [NAN, 0.0, "", top_height, top_label]
		var rid: RID = hit["rid"] as RID
		var collider: Object = hit["collider"]
		var point: Vector3 = hit["position"] as Vector3
		if is_nan(top_height) and collider is StaticBody3D:
			top_height = point.y
			top_label = ground_bodies.get(rid, describe(collider as Node))
		if ground_bodies.has(rid):
			return [point.y, (hit["normal"] as Vector3).y, ground_bodies[rid], top_height, top_label]
		exclude.append(rid)
	return [NAN, 0.0, "", top_height, top_label]

func describe(node: Node) -> String:
	var path: String = str(world.get_path_to(node))
	var parts: PackedStringArray = path.split("/")
	return parts[0] + "/" + String(node.name) if parts.size() > 1 else path

func check_collider_faces() -> void:
	# Each ground collider must copy its visible mesh: sample every collision triangle's centroid.
	var report: Dictionary = {}
	for node: Node in world.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = node as CollisionShape3D
		var concave: ConcavePolygonShape3D = shape.shape as ConcavePolygonShape3D
		var body: CollisionObject3D = shape.get_parent() as CollisionObject3D
		if concave == null or body == null or not ground_bodies.has(body.get_rid()):
			continue
		var label: String = ground_bodies[body.get_rid()]
		var faces: PackedVector3Array = concave.get_faces()
		var xform: Transform3D = shape.global_transform
		var worst: float = 0.0
		var where: Vector3 = Vector3.ZERO
		var source: Surface
		for surface: Surface in surfaces:
			if surface.label == label and surface.tris.size() == faces.size():
				source = surface
		for index: int in range(0, faces.size(), 3):
			var centroid: Vector3 = xform * ((faces[index] + faces[index + 1] + faces[index + 2]) / 3.0)
			var height: float = source.height_at(centroid.x, centroid.z)
			var error: float = absf(height - centroid.y) if not is_nan(height) else 99.0
			if error > worst:
				worst = error
				where = centroid
		report[label] = snappedf(worst, 0.0001)
		if worst > TOLERANCE:
			fail("collider_faces", "%s collider differs from its visible mesh by %.3f m at %s" % [label, worst, where])
	note("collider vs own mesh max error %s" % [report])
	summary["collider_faces"] = report

func check_normals() -> void:
	var report: Dictionary = {}
	for surface: Surface in surfaces:
		var mesh: Mesh = surface.node.mesh
		var inverted: int = 0
		var total: int = 0
		var flat: int = 0
		for index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(index)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			total += normals.size()
			for normal: Vector3 in normals:
				if normal.y < 0.0:
					inverted += 1
		# Faceting: the stored normal of a triangle's first vertex equals its face normal everywhere.
		var arrays0: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays0[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals0: PackedVector3Array = arrays0[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays0[Mesh.ARRAY_INDEX] != null:
			indices = arrays0[Mesh.ARRAY_INDEX] as PackedInt32Array
		else:
			indices.resize(vertices.size())
			for index: int in range(vertices.size()):
				indices[index] = index
		var samples: int = 0
		for tri: int in range(0, mini(indices.size(), 6000), 3):
			var a: Vector3 = vertices[indices[tri]]
			var face: Vector3 = (vertices[indices[tri + 2]] - a).cross(vertices[indices[tri + 1]] - a).normalized()
			if face.y < 0.0:
				face = -face
			samples += 1
			if normals0[indices[tri]].dot(face) > 0.99999 and absf(face.y) < 0.995:
				flat += 1
		report[surface.label] = {"vertices": total, "inverted": inverted, "faceted_share": snappedf(float(flat) / maxf(samples, 1.0), 0.001)}
		if inverted > 0:
			fail("normals", "%s has %d downward vertex normals" % [surface.label, inverted])
	note("normals %s" % [report])
	summary["normals"] = report

# --- Dense grids ------------------------------------------------------------------------------

func scan_regions() -> void:
	var regions: Array[Array] = [
		["village", Rect2(-30, -30, 60, 60), 0.25],
		["gate_apron", Rect2(-6, -40, 12, 16), 0.1],
		["trail", Rect2(-18, -112, 36, 72), 0.5],
		["church_yard", Rect2(-22, -132, 36, 48), 0.25],
		["landscape", Rect2(-176, -176, 352, 352), 1.5],
	]
	var results: Dictionary = {}
	for region: Array in regions:
		var name: String = region[0]
		var rect: Rect2 = region[1]
		var step: float = region[2]
		var stats: Dictionary = {"points": 0, "mismatch": 0, "max_mismatch": 0.0, "max_mismatch_at": "", "collision_holes": 0, "invisible_ground": 0, "pokes": 0, "max_poke": 0.0, "max_poke_at": "", "coplanar": 0, "coplanar_at": "", "steps": 0, "max_step": 0.0, "max_step_at": "", "steep": 0, "steep_at": "", "obstructed": 0}
		# A small offset keeps samples off exact mesh seams, where a ray can pass between two
		# colliders that share an edge (a zero-width leak no capsule can use).
		var z: float = rect.position.y + 0.0137
		while z <= rect.end.y + 0.0001:
			var x: float = rect.position.x + 0.0137
			while x <= rect.end.x + 0.0001:
				if name == "trail" and absf(x - float(village.call("north_trail_center", z))) > 12.0:
					x += step
					continue
				if name == "landscape" and absf(x) <= 30.0 and absf(z) <= 30.0:
					x += step
					continue
				sample_point(x, z, step, name, stats)
				x += step
			z += step
		results[name] = stats
		note("grid %s %s" % [name, stats])
		if int(stats["mismatch"]) > 0:
			fail("grid_mismatch_" + name, "%d points where collision differs from the visible ground by > %.2f m (max %.3f at %s)" % [stats["mismatch"], TOLERANCE, stats["max_mismatch"], stats["max_mismatch_at"]])
		if int(stats["collision_holes"]) > 0 or int(stats["invisible_ground"]) > 0:
			fail("grid_holes_" + name, "%d collision holes, %d invisible ground points" % [stats["collision_holes"], stats["invisible_ground"]])
		if int(stats["pokes"]) > 0:
			fail("grid_pokes_" + name, "%d points where a lower ground mesh shows through (max %.3f m at %s)" % [stats["pokes"], stats["max_poke"], stats["max_poke_at"]])
		if int(stats["coplanar"]) > 0:
			fail("grid_coplanar_" + name, "%d points with two ground meshes within 2 cm (z-fight risk), e.g. %s" % [stats["coplanar"], stats["coplanar_at"]])
		if int(stats["steps"]) > 0 and name != "landscape":
			fail("grid_steps_" + name, "%d visible ground steps over 8 cm (max %.3f m at %s)" % [stats["steps"], stats["max_step"], stats["max_step_at"]])
	summary["grids"] = results

func sample_point(x: float, z: float, step: float, region: String, stats: Dictionary) -> void:
	stats["points"] = int(stats["points"]) + 1
	var seen: Array = visible_ground(x, z)
	var physical: Array = physical_ground(x, z)
	var top: float = seen[0]
	var hit: float = physical[0]
	var where: String = "(%.2f, %.2f)" % [x, z]
	if not is_nan(top) and is_nan(hit):
		stats["collision_holes"] = int(stats["collision_holes"]) + 1
	elif is_nan(top) and not is_nan(hit):
		stats["invisible_ground"] = int(stats["invisible_ground"]) + 1
	elif not is_nan(top):
		var error: float = absf(hit - top)
		if error > TOLERANCE:
			stats["mismatch"] = int(stats["mismatch"]) + 1
		if error > float(stats["max_mismatch"]):
			stats["max_mismatch"] = snappedf(error, 0.001)
			stats["max_mismatch_at"] = "%s visible %s %.3f collision %s %.3f" % [where, seen[1], top, physical[2], hit]
		if float(physical[1]) < 0.707:
			stats["steep"] = int(stats["steep"]) + 1
			stats["steep_at"] = "%s normal_y %.2f" % [where, physical[1]]
	if not is_nan(top) and str(physical[4]) != str(physical[2]) and not is_nan(float(physical[3])) and float(physical[3]) > hit + 0.05:
		stats["obstructed"] = int(stats["obstructed"]) + 1
	if not is_nan(float(seen[2])):
		var gap: float = top - float(seen[2])
		# The landscape (or any outer mesh) rising through village/apron/skirt ground is the wrong surface.
		if seen[1] == "landscape" and seen[3] != "landscape" and gap > 0.003:
			stats["pokes"] = int(stats["pokes"]) + 1
			if gap > float(stats["max_poke"]):
				stats["max_poke"] = snappedf(gap, 0.001)
				stats["max_poke_at"] = "%s %s over %s" % [where, seen[1], seen[3]]
		elif gap < 0.02 and sustained_overlap(x, z):
			stats["coplanar"] = int(stats["coplanar"]) + 1
			stats["coplanar_at"] = "%s %s %.3f over %s %.3f" % [where, seen[1], top, seen[3], seen[2]]
	if region != "landscape" and not is_nan(top):
		var offset: float = 0.05
		for direction: Vector2 in [Vector2(offset, 0), Vector2(0, offset)]:
			var other: float = float(visible_ground(x + direction.x, z + direction.y)[0])
			if is_nan(other):
				continue
			var jump: float = absf(other - top)
			if jump > 0.08:
				stats["steps"] = int(stats["steps"]) + 1
				if jump > float(stats["max_step"]):
					stats["max_step"] = snappedf(jump, 0.001)
					stats["max_step_at"] = where

## Two ground meshes within 2 cm over an area (z-fight risk), not just along the line where one
## mesh meets another at an angle: every neighbour 0.3 m away that both cover is as close.
func sustained_overlap(x: float, z: float) -> bool:
	var both: int = 0
	for offset: Vector2 in [Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]:
		var other: Array = visible_ground(x + offset.x, z + offset.y)
		if is_nan(float(other[2])):
			continue
		both += 1
		if float(other[0]) - float(other[2]) >= 0.02:
			return false
	return both >= 3

func scan_border() -> void:
	# The village mesh edge against whatever ground continues outside it.
	var worst: float = 0.0
	var where: String = ""
	var over: int = 0
	var count: int = 0
	var t: float = -28.0
	while t <= 28.0:
		for edge: Vector4 in [Vector4(t, -28, 0, -1), Vector4(t, 28, 0, 1), Vector4(-28, t, -1, 0), Vector4(28, t, 1, 0)]:
			var inside: float = float(visible_ground(edge.x - edge.z * 0.02, edge.y - edge.w * 0.02)[0])
			var outside: float = float(visible_ground(edge.x + edge.z * 0.02, edge.y + edge.w * 0.02)[0])
			count += 1
			if is_nan(inside) or is_nan(outside):
				continue
			var step: float = absf(inside - outside)
			if step > 0.05:
				over += 1
			if step > worst:
				worst = step
				where = "(%.2f, %.2f) inside %.3f outside %.3f" % [edge.x, edge.y, inside, outside]
		t += 0.25
	summary["village_border"] = {"samples": count, "over_5cm": over, "max_step": snappedf(worst, 0.001), "at": where}
	note("village border step: %d of %d samples over 5 cm, max %.3f m at %s" % [over, count, worst, where])
	if over > 0:
		fail("village_border", "visible step at the village ground edge up to %.3f m" % worst)

func scan_landscape_shape() -> void:
	var landscape: Surface
	for surface: Surface in surfaces:
		if surface.label == "landscape":
			landscape = surface
	if landscape == null:
		return
	var bands: Dictionary = {"route_15m": 0, "within_60m": 0, "within_176m": 0}
	var worst_route: String = ""
	var worst_route_y: float = 1.0
	var tallest_spike: float = 0.0
	var spike_at: String = ""
	var heights: Dictionary[Vector2i, float] = {}
	for index: int in range(0, landscape.tris.size(), 3):
		var a: Vector3 = landscape.tris[index]
		var b: Vector3 = landscape.tris[index + 1]
		var c: Vector3 = landscape.tris[index + 2]
		for point: Vector3 in [a, b, c]:
			heights[Vector2i(roundi(point.x), roundi(point.z))] = point.y
		var center: Vector3 = (a + b + c) / 3.0
		var distance: float = maxf(absf(center.x), absf(center.z))
		if distance > 176.0:
			continue
		var normal: Vector3 = (c - a).cross(b - a).normalized()
		if normal.y < 0.0:
			normal = -normal
		if normal.y >= 0.707:
			continue
		if distance < 30.0:
			continue # hidden under the village ground
		bands["within_176m"] = int(bands["within_176m"]) + 1
		if distance < 60.0:
			bands["within_60m"] = int(bands["within_60m"]) + 1
		if near_route(center.x, center.z, 15.0):
			bands["route_15m"] = int(bands["route_15m"]) + 1
			if normal.y < worst_route_y:
				worst_route_y = normal.y
				worst_route = "(%.1f, %.1f) normal_y %.2f" % [center.x, center.z, normal.y]
	for key: Vector2i in heights:
		if maxi(absi(key.x), absi(key.y)) > 176 or maxi(absi(key.x), absi(key.y)) < 31:
			continue
		var height: float = heights[key]
		var highest_neighbour: float = -INF
		for offset: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(3, -3), Vector2i(-3, 3)]:
			highest_neighbour = maxf(highest_neighbour, heights.get(key + offset, height))
		if height - highest_neighbour > tallest_spike:
			tallest_spike = height - highest_neighbour
			spike_at = str(key)
	summary["landscape_shape"] = {"steep_triangles": bands, "steepest_near_route": worst_route, "tallest_spike": snappedf(tallest_spike, 0.01), "spike_at": spike_at}
	note("landscape steep (>45 deg) triangles %s; steepest near routes %s; tallest single-vertex spike %.2f m at %s" % [bands, worst_route, tallest_spike, spike_at])
	if int(bands["route_15m"]) > 0:
		fail("landscape_steep_near_route", "%d unwalkable landscape triangles within 15 m of the village, trail or church yard" % bands["route_15m"])
	if tallest_spike > 2.0:
		fail("landscape_spike", "single-vertex spike %.2f m at %s" % [tallest_spike, spike_at])

func near_route(x: float, z: float, margin: float) -> bool:
	if absf(x) < 28.0 + margin and absf(z) < 28.0 + margin:
		return true
	if z < -26.0 and z > -112.0 and absf(x - float(village.call("north_trail_center", z))) < margin:
		return true
	return Vector2(x, z).distance_to(ChurchSite.YARD_CENTER) < ChurchSite.YARD_RADIUS + margin

# --- Scatter and props ------------------------------------------------------------------------

func scatter_label(visual: GeometryInstance3D) -> String:
	var owner_name: String = str(world.get_path_to(visual)).split("/")[0]
	var material: Material = visual.material_override
	if material is ShaderMaterial:
		var code: String = (material as ShaderMaterial).shader.code
		for signature: Array in [["0.045,0.085,0.018", "grass"], ["0.08,0.14,0.025", "clover"], ["0.045,0.075,0.015", "ferns"]]:
			if signature[0] in code:
				return owner_name + ":" + str(signature[1])
	if material is StandardMaterial3D:
		var texture: Texture2D = (material as StandardMaterial3D).albedo_texture
		if texture != null:
			return owner_name + ":" + texture.resource_path.get_file().get_basename()
	return owner_name + ":" + String(visual.name)

func check_scatter() -> void:
	var results: Dictionary = {}
	if DisplayServer.get_name() == "headless":
		# The dummy renderer keeps no MultiMesh instance buffers: every transform reads back empty.
		note("scatter skipped: needs the real renderer (run without --headless)")
		summary["scatter"] = "skipped (headless)"
		return
	for node: Node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var visual: MultiMeshInstance3D = node as MultiMeshInstance3D
		if visual.multimesh == null or not visual.is_visible_in_tree() or visual.multimesh.instance_count == 0:
			continue
		var label: String = scatter_label(visual)
		var tree: bool = "oak_bough" in label or "tree" in label
		var stats: Dictionary = results.get(label, {"instances": 0, "checked": 0, "floating": 0, "max_float": 0.0, "max_float_at": "", "buried": 0, "max_bury": 0.0, "max_bury_at": ""})
		var xform: Transform3D = visual.global_transform
		var multi: MultiMesh = visual.multimesh
		var bury_limit: float = 0.5 if tree else 0.15
		var count: int = multi.visible_instance_count if multi.visible_instance_count >= 0 else multi.instance_count
		for index: int in range(count):
			var instance: Transform3D = xform * multi.get_instance_transform(index)
			if instance.basis.get_scale().length() < 0.01:
				continue # collapsed (hidden) instance
			stats["instances"] = int(stats["instances"]) + 1
			var point: Vector3 = instance.origin
			if maxf(absf(point.x), absf(point.z)) > 176.0:
				continue
			var ground: float = float(visible_ground(point.x, point.z)[0])
			if is_nan(ground):
				continue
			stats["checked"] = int(stats["checked"]) + 1
			var gap: float = point.y - ground
			if gap > 0.04:
				stats["floating"] = int(stats["floating"]) + 1
			if gap > float(stats["max_float"]):
				stats["max_float"] = snappedf(gap, 0.001)
				stats["max_float_at"] = "(%.1f, %.1f)" % [point.x, point.z]
			if gap < -bury_limit:
				stats["buried"] = int(stats["buried"]) + 1
			if -gap > float(stats["max_bury"]):
				stats["max_bury"] = snappedf(-gap, 0.001)
				stats["max_bury_at"] = "(%.1f, %.1f)" % [point.x, point.z]
		results[label] = stats
	for label: String in results:
		var stats: Dictionary = results[label]
		note("scatter %s %s" % [label, stats])
		if label.begins_with("WoodlandVillage") and (int(stats["floating"]) > 0 or int(stats["buried"]) > 0):
			fail("scatter", "%s: %d floating (max %.2f m at %s), %d buried (max %.2f m at %s)" % [label, stats["floating"], stats["max_float"], stats["max_float_at"], stats["buried"], stats["max_bury"], stats["max_bury_at"]])
	summary["scatter"] = results

func check_props() -> void:
	# Trees, bushes, rocks and kit props: compare each mesh's lowest point with the ground under it.
	var results: Dictionary = {}
	for node: Node in village.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree():
			continue
		var bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		if bounds.size.x > 30.0 or bounds.size.z > 30.0:
			continue
		var center: Vector3 = bounds.get_center()
		if maxf(absf(center.x), absf(center.z)) > 176.0:
			continue
		var label: String = prop_label(visual)
		if label.is_empty():
			continue
		var ground: float = float(visible_ground(center.x, center.z)[0])
		if is_nan(ground):
			continue
		# The lowest ground under the footprint: a base above it is visibly floating on that side.
		var lowest: float = ground
		var radius: float = minf(minf(bounds.size.x, bounds.size.z) * 0.25, 0.6)
		if label == "tree_pack_tree" or label == "woodland_tree":
			radius = minf(minf(bounds.size.x, bounds.size.z) * 0.06, 0.3) # trunk, not crown
		for offset: Vector2 in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
			var other: float = float(visible_ground(center.x + offset.x, center.z + offset.y)[0])
			if not is_nan(other):
				lowest = minf(lowest, other)
		var gap: float = bounds.position.y - lowest
		var stats: Dictionary = results.get(label, {"count": 0, "floating": 0, "max_float": 0.0, "max_float_at": "", "buried": 0, "max_bury": 0.0, "max_bury_at": ""})
		stats["count"] = int(stats["count"]) + 1
		if gap > 0.05:
			stats["floating"] = int(stats["floating"]) + 1
		if gap > float(stats["max_float"]):
			stats["max_float"] = snappedf(gap, 0.001)
			stats["max_float_at"] = "(%.1f, %.1f, %.1f)" % [center.x, bounds.position.y, center.z]
		# Buried: more than 40 % (rocks 60 %) of its height under the ground at its centre.
		var depth: float = ground - bounds.position.y
		if depth > bounds.size.y * (0.6 if label == "rock" else 0.4) and depth > 0.3:
			stats["buried"] = int(stats["buried"]) + 1
			if depth > float(stats["max_bury"]):
				stats["max_bury"] = snappedf(depth, 0.001)
				stats["max_bury_at"] = "(%.1f, %.1f) height %.2f" % [center.x, center.z, bounds.size.y]
		results[label] = stats
	for label: String in results:
		var stats: Dictionary = results[label]
		note("props %s %s" % [label, stats])
		if int(stats["floating"]) > 0 or int(stats["buried"]) > 0:
			fail("props_" + label, "%d floating (max %.2f m at %s), %d buried (max %.2f m at %s)" % [stats["floating"], stats["max_float"], stats["max_float_at"], stats["buried"], stats["max_bury"], stats["max_bury_at"]])
	summary["props"] = results

func prop_label(visual: MeshInstance3D) -> String:
	if visual.get_parent() != null and visual.get_parent().get_script() == preload("res://gameplay/environment/woodland_tree.gd"):
		return "woodland_tree" if visual.get_index() == 0 else ""
	var material: Material = visual.material_override if visual.material_override != null else visual.get_active_material(0)
	if material is ShaderMaterial and ((material as ShaderMaterial).get_shader_parameter("grain") != null or (material as ShaderMaterial).get_shader_parameter("basecolor") != null):
		var bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		if bounds.size.y > 2.2 and bounds.size.y < 2.8 and maxf(bounds.size.x, bounds.size.z) < 0.4:
			return "palisade_post"
	if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null:
		var path: String = (material as StandardMaterial3D).albedo_texture.resource_path
		if "/tree_pack/" in path:
			return "tree_pack_bush" if "bush" in path.get_file() else "tree_pack_tree"
		if "StoneGeneric" in path or "Rock" in path or "rock" in path.get_file():
			return "rock"
	return ""

func check_palisade() -> void:
	# Daylight under a palisade wall: its visible bottom (box, plus any child plinth) against the
	# lower of the two ground heights beside it, every 0.25 m along every wall.
	var walls: int = 0
	var gaps: int = 0
	var worst: float = 0.0
	var where: String = ""
	var box_worst: float = 0.0
	var box_gaps: int = 0
	for node: Node in world.find_children("*", "CollisionShape3D", true, false):
		var collider: CollisionShape3D = node as CollisionShape3D
		var box: BoxShape3D = collider.shape as BoxShape3D
		if collider.disabled or box == null or not is_equal_approx(box.size.y, 2.2) or not is_equal_approx(box.size.z, 0.35):
			continue
		var wall: MeshInstance3D = collider.get_parent().get_parent() as MeshInstance3D
		if wall == null or not wall.is_visible_in_tree():
			continue
		walls += 1
		var columns: Dictionary[float, float] = {}
		for child: Node in wall.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).is_visible_in_tree():
				var plinth: MeshInstance3D = child as MeshInstance3D
				for vertex: Vector3 in plinth.mesh.get_faces():
					var local: Vector3 = plinth.transform * vertex
					var key: float = snappedf(local.x, 0.01)
					columns[key] = minf(columns.get(key, INF), local.y)
		var keys: Array[float] = columns.keys()
		keys.sort()
		var half: float = box.size.x * 0.5
		var along: float = -half + 0.05
		while along <= half - 0.05:
			var bottom: float = -1.1
			for index: int in range(keys.size() - 1):
				if keys[index] <= along and along <= keys[index + 1]:
					var t: float = (along - keys[index]) / maxf(keys[index + 1] - keys[index], 0.001)
					bottom = minf(bottom, lerpf(columns[keys[index]], columns[keys[index + 1]], t))
			var low: float = INF
			for side: float in [-0.18, 0.18]:
				var point: Vector3 = wall.global_transform * Vector3(along, 0.0, side)
				low = minf(low, float(visible_ground(point.x, point.z)[0]))
			var world_bottom: float = (wall.global_transform * Vector3(along, bottom, 0.0)).y
			var gap: float = world_bottom - low
			# The same wall without any plinth: the gap the flat box alone leaves.
			var box_gap: float = (wall.global_transform * Vector3(along, -1.1, 0.0)).y - low
			box_worst = maxf(box_worst, box_gap)
			if box_gap > 0.02:
				box_gaps += 1
			if gap > 0.02:
				gaps += 1
			if gap > worst:
				worst = gap
				where = str((wall.global_transform * Vector3(along, bottom, 0.0)).snappedf(0.1))
			along += 0.25
	summary["palisade"] = {"walls": walls, "gap_samples": gaps, "max_gap": snappedf(worst, 0.001), "at": where, "box_only_gap_samples": box_gaps, "box_only_max_gap": snappedf(box_worst, 0.001)}
	note("palisade walls %d: %d samples with daylight under the wall, max gap %.3f m at %s (flat boxes alone: %d samples, max %.3f m)" % [walls, gaps, worst, where, box_gaps, box_worst])
	if gaps > 0:
		fail("palisade_gaps", "%d samples with a gap under a wall (max %.3f m at %s)" % [gaps, worst, where])

func check_overlays() -> void:
	# Ground-hugging meshes other scenery lays on the terrain (torch road mud strip): their vertices
	# against the visible ground under them. Reported, not failed: they belong to other tasks.
	var results: Dictionary = {}
	for node: Node in world.find_children("MudChunk*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var faces: PackedVector3Array = visual.mesh.get_faces()
		var highest: float = -INF
		var lowest: float = INF
		var high_at: Vector3 = Vector3.ZERO
		var low_at: Vector3 = Vector3.ZERO
		for index: int in range(faces.size()):
			var point: Vector3 = visual.global_transform * faces[index]
			var ground: float = float(visible_ground(point.x, point.z)[0])
			if is_nan(ground):
				continue
			var gap: float = point.y - ground
			if gap > highest:
				highest = gap
				high_at = point
			if gap < lowest:
				lowest = gap
				low_at = point
		results[String(visual.name)] = {"max_above": snappedf(highest, 0.001), "at": str(high_at.snappedf(0.1)), "min_above": snappedf(lowest, 0.001), "min_at": str(low_at.snappedf(0.1))}
	summary["overlays"] = results
	note("road mud strip height above visible ground %s" % [results])

func check_invisible_colliders() -> void:
	var listed: Array[String] = []
	for node: Node in world.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = node as CollisionShape3D
		var body: Node = shape.get_parent()
		if shape.disabled or not body is StaticBody3D:
			continue
		var visual: Node3D = body.get_parent() as Node3D
		if visual is MeshInstance3D and not visual.is_visible_in_tree():
			var bounds: AABB = (visual as MeshInstance3D).global_transform * (visual as MeshInstance3D).mesh.get_aabb()
			listed.append("%s at %s size %s" % [describe(visual), bounds.get_center().snappedf(0.1), bounds.size.snappedf(0.1)])
	summary["invisible_colliders"] = listed
	note("invisible static colliders (%d): %s" % [listed.size(), listed])

# --- Capsules ---------------------------------------------------------------------------------

func drop_capsules() -> void:
	var points: Array[Vector2] = []
	for z: int in range(-29, 30, 2):
		for x: int in range(-29, 30, 2):
			points.append(Vector2(x + 0.5, z + 0.5))
	for z: int in range(-40, -24):
		for x: float in [-3.0, -1.5, 0.0, 1.5, 3.0]:
			points.append(Vector2(x, z))
	for z: int in range(-112, -36, 2):
		var center: float = float(village.call("north_trail_center", float(z)))
		for offset: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			points.append(Vector2(center + offset, z))
	for z: int in range(-128, -86, 2):
		for x: int in range(-20, 13, 2):
			points.append(Vector2(x, z))
	for z: int in range(-60, 61, 3):
		for x: int in range(-60, 61, 3):
			if maxi(absi(x), absi(z)) >= 27:
				points.append(Vector2(x, z))
	var results: Dictionary = {"dropped": 0, "failed": 0, "examples": []}
	var batch: Array[Walker] = []
	var expected: Array[float] = []
	for index: int in range(points.size()):
		var point: Vector2 = points[index]
		var physical: Array = physical_ground(point.x, point.y)
		if is_nan(float(physical[0])) or float(physical[1]) < 0.72:
			results["skipped_steep"] = int(results.get("skipped_steep", 0)) + 1
			continue
		var walker: Walker = Walker.new(true)
		world.add_child(walker)
		ignore_players(walker)
		walker.global_position = Vector3(point.x, float(physical[0]) + HEIGHT * 0.5 + 0.35, point.y)
		batch.append(walker)
		expected.append(float(physical[0]) + RADIUS * (1.0 / float(physical[1]) - 1.0))
		if batch.size() == 500 or index == points.size() - 1:
			for frame: int in range(45):
				await physics_frame
			for slot: int in range(batch.size()):
				var body: Walker = batch[slot]
				var feet: float = body.global_position.y - HEIGHT * 0.5
				results["dropped"] = int(results["dropped"]) + 1
				if not body.is_on_floor() or absf(feet - expected[slot]) > 0.08:
					results["failed"] = int(results["failed"]) + 1
					if (results["examples"] as Array).size() < 12:
						(results["examples"] as Array).append("(%.1f, %.1f) feet %.3f expected %.3f floor %s" % [body.global_position.x, body.global_position.z, feet, expected[slot], body.is_on_floor()])
				body.queue_free()
			batch.clear()
			expected.clear()
	summary["capsule_drops"] = results
	note("capsule drops %s" % [results])
	if int(results["failed"]) > 0:
		fail("capsule_drops", "%d of %d capsules did not settle on the ground: %s" % [results["failed"], results["dropped"], results["examples"]])

func ignore_players(walker: Walker) -> void:
	var players: Node = world.get("players") as Node
	if players != null:
		for player: Node in players.get_children():
			walker.add_collision_exception_with(player)

func walk_routes() -> void:
	# [points, terrain_only]: terrain-only capsules collide with ground colliders alone, so props
	# cannot hide a ground snag, step or slip-under; full capsules meet everything a player meets.
	var routes: Dictionary = {}
	var church: Array[Vector2] = [Vector2(0, 0), Vector2(2, -12), Vector2(2, -22), Vector2(0.4, -26.5), Vector2(0.3, -31)]
	for z: int in range(-37, -98, -4):
		church.append(Vector2(float(village.call("north_trail_center", float(z))), z))
	church.append_array([Vector2(-4, -100), Vector2(-4, -106), Vector2(-4, -110), Vector2(-4, -113)])
	routes["village_to_church_terrace"] = [church, false]
	var outline: PackedVector2Array = PackedVector2Array([Vector2(-28,-10), Vector2(-24,-23), Vector2(-9,-28), Vector2(8,-25), Vector2(22,-28), Vector2(28,-16), Vector2(25,0), Vector2(28,15), Vector2(17,27), Vector2(2,28), Vector2(-12,25), Vector2(-28,28)])
	var inside: Array[Vector2] = []
	var outside: Array[Vector2] = []
	for index: int in range(outline.size() + 1):
		var corner: Vector2 = outline[index % outline.size()]
		var previous: Vector2 = outline[(index - 1 + outline.size()) % outline.size()]
		var following: Vector2 = outline[(index + 1) % outline.size()]
		var bisector: Vector2 = ((previous - corner).normalized() + (following - corner).normalized()).normalized()
		var toward_center: Vector2 = bisector if bisector.dot(-corner) > 0.0 else -bisector
		inside.append(corner + toward_center * 1.3)
		outside.append(corner - toward_center * 1.6)
	var outside_route: Array[Vector2] = [Vector2(-0.5, -31)]
	outside_route.append_array(outside)
	routes["palisade_inside_ground"] = [inside, true]
	routes["palisade_outside_ground"] = [outside_route, true]
	routes["palisade_outside"] = [outside_route, false]
	routes["lookout_ramp"] = [[Vector2(-23, 16), Vector2(-23, 12.8), Vector2(-23, 3.4), Vector2(-23, 2.2)] as Array[Vector2], false]
	# Straight crossings of the village ground edge, outward and back, on all four sides and the gate.
	var crossings: Array[Vector2] = []
	for spot: Vector2 in [Vector2(0.5, -24), Vector2(0.5, -36), Vector2(-2.5, -24), Vector2(-2.5, -36), Vector2(26.5, 3), Vector2(36, 3), Vector2(26, -27), Vector2(34, -34), Vector2(5, 26.5), Vector2(5, 36), Vector2(-26.5, 0), Vector2(-36, 0), Vector2(-26, 27.5), Vector2(-34, 34)]:
		crossings.append(spot)
	routes["border_crossings_ground"] = [crossings, true]
	var loop: Array[Vector2] = []
	for index: int in range(25):
		var angle: float = float(index) / 24.0 * TAU
		loop.append(Vector2(cos(angle), sin(angle)) * 50.0)
	routes["foothill_loop_50m_ground"] = [loop, true]
	var walkers: Dictionary[String, Walker] = {}
	for name: String in routes:
		var path: Array = routes[name][0]
		var walker: Walker = Walker.new(bool(routes[name][1]))
		for point: Vector2 in path:
			var physical: Array = physical_ground(point.x, point.y)
			var height: float = float(physical[3]) if not is_nan(float(physical[3])) else 0.0
			walker.route.append(Vector3(point.x, height, point.y))
		world.add_child(walker)
		ignore_players(walker)
		walker.global_position = walker.route[0] + Vector3.UP * (HEIGHT * 0.5 + 0.2)
		walkers[name] = walker
	var results: Dictionary = {}
	for frame: int in range(60 * 90):
		await physics_frame
		var moving: bool = false
		for name: String in walkers:
			var walker: Walker = walkers[name]
			if walker.done_frame < 0:
				moving = true
				if walker.frames % 15 == 0:
					var feet: float = walker.global_position.y - HEIGHT * 0.5
					var ground: float = float(physical_ground(walker.global_position.x, walker.global_position.z)[0])
					if not is_nan(ground) and feet - ground < walker.lowest_margin:
						walker.lowest_margin = feet - ground
						walker.set_meta("lowest_at", walker.global_position.snappedf(0.1))
		if not moving:
			break
	for name: String in walkers:
		var walker: Walker = walkers[name]
		var length: float = 0.0
		for index: int in range(1, walker.route.size()):
			length += Vector2(walker.route[index].x - walker.route[index - 1].x, walker.route[index].z - walker.route[index - 1].z).length()
		var stuck: Array[String] = []
		for index: int in range(10, walker.history.size(), 10):
			var moved: float = Vector2(walker.history[index].x - walker.history[index - 10].x, walker.history[index].z - walker.history[index - 10].z).length()
			if moved < 1.5 and (stuck.is_empty() or not str(walker.history[index].snappedf(1.0)) in stuck[-1]):
				stuck.append(str(walker.history[index].snappedf(1.0)))
		var walls: Array[String] = []
		for point: Vector3 in walker.walls:
			walls.append(str(point.snappedf(0.1)))
		var finished: bool = walker.done_frame >= 0
		var seconds: float = (walker.done_frame if finished else walker.frames) / 60.0
		var result: Dictionary = {"terrain_only": walker.collision_mask == GROUND_LAYER, "finished": finished, "reached": "%d/%d" % [walker.next, walker.route.size()], "seconds": snappedf(seconds, 0.01), "ideal_seconds": snappedf(length / 6.5, 0.01), "longest_airborne_frames": walker.longest_air, "lowest_feet_margin": snappedf(walker.lowest_margin, 0.001), "lowest_at": str(walker.get_meta("lowest_at", "")), "stuck_at": stuck, "wall_contacts": walls.slice(0, 12), "wall_contact_count": walls.size()}
		results[name] = result
		note("walk %s %s" % [name, result])
		if not finished or not stuck.is_empty():
			fail("walk_" + name, "reached %s, stuck at %s, walls %s" % [result["reached"], stuck, walls.slice(0, 8)])
		if walker.lowest_margin < -0.3:
			fail("walk_under_ground_" + name, "feet %.2f m under the top ground collider at %s" % [walker.lowest_margin, result["lowest_at"]])
		if walker.longest_air > 20:
			fail("walk_airborne_" + name, "%d frames airborne in a row (a drop or launch off a ground edge)" % walker.longest_air)
		walker.queue_free()
	summary["walks"] = results

func drop_real_player() -> void:
	var players: Node = world.get("players") as Node
	if players == null or players.get_child_count() == 0:
		note("real player drops skipped (no --host)")
		return
	var player: CharacterBody3D = players.get_child(0) as CharacterBody3D
	var failed: Array[String] = []
	for point: Vector2 in [Vector2(0, 0), Vector2(26.5, 26.5), Vector2(-27.5, 5), Vector2(29, -10), Vector2(-0.5, -29), Vector2(2.4, -31), Vector2(-3.4, -33), Vector2(0, -45), Vector2(-4, -100), Vector2(40, 40)]:
		var physical: Array = physical_ground(point.x, point.y)
		player.position = Vector3(point.x, float(physical[0]) + 3.0, point.y)
		player.velocity = Vector3.ZERO
		for frame: int in range(90):
			await physics_frame
		var feet: float = player.position.y - HEIGHT * 0.5
		if not player.is_on_floor() or absf(feet - float(physical[0])) > 0.12:
			failed.append("%s feet %.3f ground %.3f" % [point, feet, physical[0]])
	player.position = Vector3(0, 0.95, 3)
	player.velocity = Vector3.ZERO
	summary["real_player_drops"] = {"points": 10, "failed": failed}
	note("real player drops: %d of 10 failed %s" % [failed.size(), failed])
	if not failed.is_empty():
		fail("real_player", str(failed))

# --- Captures ---------------------------------------------------------------------------------

func capture_views(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var players: Node = world.get("players") as Node
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	if players != null and players.get_child_count() > 0:
		camera.fov = ((players.get_child(0) as Node).get("camera") as Camera3D).fov
	camera.far = 600.0
	var presentation: CanvasLayer = world.get_node_or_null("GameUI") as CanvasLayer
	if presentation != null:
		presentation.visible = false
	# [name, eye xz, eye height above ground, target xz, target height above ground]
	var views: Array[Array] = [
		["gate_apron_from_trail", Vector2(1.5, -40), 1.7, Vector2(-0.5, -27), 0.6],
		["apron_side_west", Vector2(-8, -33), 1.7, Vector2(-2, -29), 0.0],
		["apron_side_east", Vector2(7, -34), 1.7, Vector2(1.5, -29), 0.0],
		["border_north_east", Vector2(14, -34), 1.7, Vector2(14, -27), 0.0],
		["border_corner_ne", Vector2(36, -36), 1.7, Vector2(27, -27), 0.0],
		["border_east", Vector2(35, 4), 1.7, Vector2(28, 0), 0.0],
		["border_corner_se", Vector2(35, 35), 1.7, Vector2(27, 27), 0.0],
		["border_south", Vector2(6, 35), 1.7, Vector2(4, 28), 0.0],
		["border_west", Vector2(-35, 12), 1.7, Vector2(-28, 10), 0.0],
		["border_corner_nw", Vector2(-35, -32), 1.7, Vector2(-27, -26), 0.0],
		["inside_north_wall", Vector2(4.5, -19), 1.7, Vector2(5.5, -25.5), 0.3],
		["wall_base_east_outside", Vector2(31, -6), 1.2, Vector2(26.5, -8), 0.2],
		["inside_west_wall", Vector2(-18, 14), 1.7, Vector2(-27, 22), 0.3],
		["aerial_border", Vector2(44, -44), 18.0, Vector2(22, -22), 0.0],
		["trail_mid", Vector2(3, -58), 1.7, Vector2(1, -80), 0.5],
		["church_yard", Vector2(-2, -92), 1.7, Vector2(-4, -110), 1.0],
		["foothills_east", Vector2(48, -6), 1.7, Vector2(110, -20), 3.0],
		["foothills_south", Vector2(-6, 50), 1.7, Vector2(-20, 120), 3.0],
		["village_ground", Vector2(-6, 6), 1.7, Vector2(-14, 14), 0.0],
	]
	for view: Array in views:
		var eye_xz: Vector2 = view[1]
		var target_xz: Vector2 = view[3]
		var eye_ground: float = float(visible_ground(eye_xz.x, eye_xz.y)[0])
		var target_ground: float = float(visible_ground(target_xz.x, target_xz.y)[0])
		camera.position = Vector3(eye_xz.x, eye_ground + float(view[2]), eye_xz.y)
		camera.look_at(Vector3(target_xz.x, target_ground + float(view[4]), target_xz.y))
		camera.make_current()
		for frame: int in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = directory.path_join("%s.png" % view[0])
		root.get_texture().get_image().save_png(path)
		note("capture %s" % path)
