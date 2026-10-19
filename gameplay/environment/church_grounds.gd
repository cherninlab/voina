extends Node3D
## The church and its graveyard north of the village (ChurchSite). Cosmetic scenery plus static
## collision; it owns no gameplay or network state. Geometry is original and procedural; it reuses
## repository textures and sounds listed in content/environments/church/README.md.

const TEXTURES: String = "res://content/environments/valhalla/textures/KB3D_VHL_"
const GENERATED: String = "res://content/environments/village_generated/"
const SHADERS: String = "res://content/environments/church/"
const AMBIENCE: String = "res://content/audio/clips/ambience/"
# Church frame: x east, y up from the nave floor, z = 0 on the door plane and negative northward.
const TOWER_HALF: float = 2.6
const TOWER_BACK: float = -5.2
const TOWER_TOP: float = 16.5
const NAVE_HALF: float = ChurchSite.NAVE_WIDTH * 0.5
const NAVE_FRONT: float = -1.6
const NAVE_BACK: float = -ChurchSite.NAVE_LENGTH
const EAVES: float = 8.0
const RIDGE: float = 15.4
const WALL: float = 0.9
const BELFRY_RADIUS: float = 2.15
const BELFRY_TOP: float = 21.8
const SPIRE_TIP: float = 35.0
const PODIUM_HALF: float = 6.4
const PODIUM_FRONT: float = 1.7
const PODIUM_BACK: float = -17.6
const BURIED: float = -2.4 # walls reach this far below the floor, so the slope never shows a gap
const DOOR_HALF: float = 1.0
const DOOR_SPRING: float = 2.5
# Graveyard enclosure in world x/z.
const WALL_FRONT_Z: float = -87.5
const WALL_BACK_Z: float = -111.0
const WALL_WEST_X: float = -20.5
const WALL_EAST_X: float = 12.5
const GATE_HALF: float = 1.75
const WEST_GAP_Z: float = -99.5
const EAST_GAP_Z: float = -102.0
const CHURCH_CLEAR: Rect2 = Rect2(-14.0, -134.0, 20.0, 28.0)
const YARD_CLEAR: Rect2 = Rect2(-21.5, -112.0, 35.0, 25.0)
# Hand-placed features (world x, z[, size]). The villagers rise at MobSystem.SPAWN_SPOTS: three
# open graves and three freshly disturbed mounds sit on those points, kept free of collision.
const OPEN_GRAVES: Array[Vector2] = [Vector2(-12.0, -109.0), Vector2(4.0, -108.0), Vector2(6.0, -99.0)]
const FRESH_MOUNDS: Array[Vector2] = [Vector2(-15.0, -100.0), Vector2(-7.0, -96.0), Vector2(-1.0, -105.0)]
const FIRE: Vector2 = Vector2(-11.0, -95.8)
const FIGURE: Vector2 = Vector2(2.9, -94.0)
const CROW_STONE: Vector2 = Vector2(-3.4, -91.4)
const CROSS_STONE: Vector2 = Vector2(4.0, -90.8)
const MONUMENT: Vector2 = Vector2(-17.6, -104.6)
const TALL_TREES: Array[Vector3] = [Vector3(-16.6, -96.6, 13.0), Vector3(9.6, -95.0, 11.5), Vector3(-15.4, -108.8, 14.5), Vector3(7.4, -121.8, 12.0)]
const GATE_TREES: Array[Vector3] = [Vector3(-5.6, -85.1, 8.0), Vector3(7.4, -85.5, 7.0)]
const BOULDERS: Array[Vector3] = [Vector3(-18.6, -89.9, 0.9), Vector3(10.8, -109.5, 1.1), Vector3(-18.9, -108.9, 0.8), Vector3(11.0, -90.2, 0.65), Vector3(-9.0, -89.0, 0.55)]
const EMBERS: Array[Vector3] = [Vector3(-8.4, -108.9, 1.2), Vector3(-7.9, -103.6, 1.15), Vector3(8.4, -107.2, 1.3), Vector3(10.0, -102.0, 0.9)]
enum Glass { DARK, AMBER, RED, BROKEN, BOARDED }

var village: Node3D
var floor_y: float = 0.0
var gate_x: float = 0.0
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var batches: Dictionary[String, SurfaceTool] = {}
var materials: Dictionary[String, Material] = {}
var glass_materials: Dictionary[int, ShaderMaterial] = {}
var collision: StaticBody3D
var shape_count: int = 0
var flames: Array[Transform3D] = []
var flame_colors: Array[Color] = []
var tufts: Array[Transform3D] = []
var reeds: Array[Transform3D] = []
var reserved: Array[Vector3] = []
var lamps: Array[OmniLight3D] = []
var lamp_energy: PackedFloat32Array = PackedFloat32Array()
var lamp_flicker: PackedFloat32Array = PackedFloat32Array()
var crow_head: Node3D
var crow_body: Node3D
var crow_rest: Vector3 = Vector3.ZERO
var crow_target: float = 0.0
var crow_wait: float = 2.0
var elapsed: float = 0.0
var beds: Array[Dictionary] = []
var bell: AudioStreamPlayer3D
var bell_wait: float = 25.0
var bell_volume: float = 2.0
var built: bool = false

func _ready() -> void:
	name = "ChurchGrounds"
	village = find_village()
	if village == null:
		# Built standalone (for example in a test): wait one frame for a sibling village.
		build.call_deferred()
		return
	# The village builds synchronously in its own _ready, so terrain heights are valid now and
	# church collision exists before the first physics frame.
	build()

func find_village() -> Node3D:
	if get_parent() == null:
		return null
	var node: Node3D = get_parent().get_node_or_null("WoodlandVillage") as Node3D
	if node != null and node.has_method("landscape_surface_height"):
		return node
	return null

func build() -> void:
	if built:
		return
	built = true
	if village == null:
		village = find_village()
	if village == null:
		push_warning("ChurchGrounds: no WoodlandVillage sibling; building on flat ground")
	transform = Transform3D.IDENTITY
	random.seed = 851127
	gate_x = ChurchSite.road_x(WALL_FRONT_Z)
	var front: float = -INF
	for offset: float in [-TOWER_HALF, 0.0, TOWER_HALF]:
		front = maxf(front, ground(ChurchSite.DOOR.x + offset, ChurchSite.DOOR.y))
	floor_y = front + 0.62
	collision = StaticBody3D.new()
	collision.name = "ChurchCollision"
	add_child(collision)
	make_materials()
	reserve_features()
	build_building()
	build_enclosure()
	build_gate()
	build_graves()
	build_trees()
	build_props()
	build_ground_layers()
	finish_batches()
	finish_flames()
	finish_tufts()
	build_particles()
	build_audio()
	var hidden: int = clear_village_plants()
	print("CHURCH_GROUNDS_OK: floor ", snappedf(floor_y, 0.01), " m, ", shape_count, " collision shapes, ", lamps.size(), " lights, ", flames.size(), " flames, ", tufts.size() + reeds.size(), " dead grass clumps, ", hidden, " village plants hidden")

func ground(x: float, z: float) -> float:
	if village == null:
		return 0.0
	return float(village.call("landscape_surface_height", x, z))

func at(x: float, y: float, z: float) -> Vector3:
	return Vector3(ChurchSite.DOOR.x + x, floor_y + y, ChurchSite.DOOR.y + z)

func frame(local: Vector3, basis: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, at(local.x, local.y, local.z))

func vary(amount: float, tone: Color = Color.WHITE) -> Color:
	var shade: float = 1.0 + random.randf_range(-amount, amount)
	return Color(tone.r * shade, tone.g * shade * random.randf_range(0.97, 1.03), tone.b * shade, tone.a)

# --- Materials -----------------------------------------------------------------------------

func make_materials() -> void:
	materials["stone"] = stone_material("StoneGeneric", Color(0.36, 0.37, 0.35), 0.42, 0.65, 0.22)
	materials["trim"] = stone_material("StoneGeneric", Color(0.46, 0.46, 0.43), 0.6, 0.45, 0.12)
	materials["base"] = stone_material("StoneFloor", Color(0.42, 0.41, 0.38), 0.5, 0.55, 0.1)
	materials["grave"] = stone_material("StoneGeneric", Color(0.5, 0.5, 0.47), 0.9, 0.55, 0.15)
	var slate: ShaderMaterial = ShaderMaterial.new()
	slate.shader = load(SHADERS + "church_slate.gdshader") as Shader
	materials["slate"] = slate
	materials["iron"] = pbr("MetalHammeredDark", Color(0.4, 0.34, 0.3), 2.0, 0.65, 0.5)
	materials["wood"] = pbr("WoodPlanksSeededDark", Color(0.5, 0.46, 0.42), 0.7, 0.0, 0.9)
	var bark: StandardMaterial3D = pbr("LogBark", Color(0.46, 0.45, 0.42), 0.9, 0.0, 0.95)
	bark.vertex_color_use_as_albedo = true
	materials["bark"] = bark
	var earth: StandardMaterial3D = StandardMaterial3D.new()
	earth.albedo_texture = load(GENERATED + "soil_gravel.png") as Texture2D
	earth.albedo_color = Color(0.4, 0.34, 0.28)
	earth.uv1_triplanar = true
	earth.uv1_world_triplanar = true
	earth.uv1_scale = Vector3.ONE * 0.6
	earth.roughness = 1.0
	earth.vertex_color_use_as_albedo = true
	earth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials["earth"] = earth
	materials["wax"] = flat(Color(0.74, 0.7, 0.58), 0.55)
	var cloth: StandardMaterial3D = flat(Color(0.03, 0.03, 0.035), 1.0)
	cloth.rim_enabled = true
	cloth.rim = 0.25
	cloth.rim_tint = 0.6
	materials["cloth"] = cloth
	var void_material: StandardMaterial3D = flat(Color.BLACK, 1.0)
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["void"] = void_material
	var glow: StandardMaterial3D = flat(Color.BLACK, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.62, 0.76, 1.0)
	glow.emission_energy_multiplier = 4.0
	materials["glow"] = glow
	var crow: StandardMaterial3D = flat(Color(0.022, 0.022, 0.028), 0.35)
	crow.metallic = 0.25
	materials["crow"] = crow
	var grass: ShaderMaterial = ShaderMaterial.new()
	grass.shader = load(SHADERS + "church_grass.gdshader") as Shader
	materials["grass"] = grass
	var strand: ShaderMaterial = ShaderMaterial.new()
	strand.shader = grass.shader
	strand.set_shader_parameter("sway", 0.14)
	strand.set_shader_parameter("backlight", 0.2)
	materials["strand"] = strand
	var states: Dictionary[int, Array] = {Glass.DARK: [Color(1.0, 0.5, 0.2), 0.0, 0.0], Glass.AMBER: [Color(1.0, 0.5, 0.16), 1.7, 0.0], Glass.RED: [Color(0.9, 0.12, 0.05), 0.8, 0.0], Glass.BROKEN: [Color(1.0, 0.5, 0.2), 0.0, 0.85], Glass.BOARDED: [Color(1.0, 0.5, 0.2), 0.0, 0.4]}
	for state: int in states:
		var glass: ShaderMaterial = ShaderMaterial.new()
		glass.shader = load(SHADERS + "church_glass.gdshader") as Shader
		var values: Array = states[state]
		glass.set_shader_parameter("glow_color", values[0])
		glass.set_shader_parameter("glow", values[1])
		glass.set_shader_parameter("broken", values[2])
		glass_materials[state] = glass

func stone_material(family: String, tint: Color, scale: float, moss: float, ash: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADERS + "church_stone.gdshader") as Shader
	material.set_shader_parameter("albedo_map", load(TEXTURES + family + "_basecolor.png"))
	material.set_shader_parameter("normal_map", load(TEXTURES + family + "_normal.png"))
	material.set_shader_parameter("roughness_map", load(TEXTURES + family + "_roughness.png"))
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	material.set_shader_parameter("scale", scale)
	material.set_shader_parameter("moss", moss)
	material.set_shader_parameter("ash", ash)
	return material

func pbr(family: String, tint: Color, scale: float, metallic: float, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(TEXTURES + family + "_basecolor.png") as Texture2D
	material.normal_enabled = true
	material.normal_texture = load(TEXTURES + family + "_normal.png") as Texture2D
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = roughness
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

func flat(color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

# --- Mesh helpers --------------------------------------------------------------------------

func tool(key: String) -> SurfaceTool:
	if not batches.has(key):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = surface
	return batches[key]

# Yard meshes are split in four, so each piece only meets the lights near it (Mobile per-mesh limit).
func chunk(x: float, z: float) -> String:
	return "yard%d" % ((0 if x < -4.0 else 1) + (0 if z > -99.0 else 2))

# Flat-shaded triangle; the winding is fixed from the outward hint (Godot fronts are clockwise).
func tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color, uv: PackedVector2Array = PackedVector2Array()) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 1e-12:
		return
	var points: Array[Vector3] = [a, b, c]
	var coords: PackedVector2Array = uv
	if normal.dot(outward) < 0.0:
		points = [a, c, b]
		normal = -normal
		if uv.size() == 3:
			coords = PackedVector2Array([uv[0], uv[2], uv[1]])
	normal = normal.normalized()
	for index: int in range(3):
		surface.set_color(color)
		surface.set_normal(normal)
		if coords.size() == 3:
			surface.set_uv(coords[index])
		surface.add_vertex(points[index])

func quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color, uv: PackedVector2Array = PackedVector2Array()) -> void:
	if uv.size() == 4:
		tri(surface, a, b, c, outward, color, PackedVector2Array([uv[0], uv[1], uv[2]]))
		tri(surface, a, c, d, outward, color, PackedVector2Array([uv[0], uv[2], uv[3]]))
	else:
		tri(surface, a, b, c, outward, color)
		tri(surface, a, c, d, outward, color)

# Smooth-shaded triangle with per-vertex normals, wound to face the average normal.
func smooth(surface: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], colors: Array[Color]) -> void:
	var face: Vector3 = (points[2] - points[0]).cross(points[1] - points[0])
	if face.length_squared() < 1e-14:
		return
	var order: Array[int] = [0, 1, 2]
	if face.dot(normals[0] + normals[1] + normals[2]) < 0.0:
		order = [0, 2, 1]
	for index: int in order:
		surface.set_color(colors[index])
		surface.set_normal(normals[index])
		surface.add_vertex(points[index])

func box(surface: SurfaceTool, transform: Transform3D, size: Vector3, color: Color) -> void:
	var half: Vector3 = size * 0.5
	var corners: Array[Vector3] = []
	for index: int in range(8):
		corners.append(transform * Vector3(half.x if (index & 1) != 0 else -half.x, half.y if (index & 2) != 0 else -half.y, half.z if (index & 4) != 0 else -half.z))
	var faces: Array[PackedInt32Array] = [PackedInt32Array([0, 2, 6, 4]), PackedInt32Array([1, 3, 7, 5]), PackedInt32Array([0, 1, 5, 4]), PackedInt32Array([2, 3, 7, 6]), PackedInt32Array([0, 1, 3, 2]), PackedInt32Array([4, 5, 7, 6])]
	var normals: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	for face: int in range(6):
		var corner_loop: PackedInt32Array = faces[face]
		quad(surface, corners[corner_loop[0]], corners[corner_loop[1]], corners[corner_loop[2]], corners[corner_loop[3]], transform.basis * normals[face], color)

# A box spanning two points along its local z axis (beams, bars, rails).
func beam(surface: SurfaceTool, start: Vector3, finish: Vector3, width: float, height: float, color: Color) -> void:
	var direction: Vector3 = finish - start
	if direction.length_squared() < 1e-8:
		return
	var up: Vector3 = Vector3.UP if absf(direction.normalized().y) < 0.98 else Vector3.RIGHT
	var basis: Basis = Basis.looking_at(direction, up)
	box(surface, Transform3D(basis, (start + finish) * 0.5), Vector3(width, height, direction.length()), color)

func signed_area(outline: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(outline.size()):
		var p: Vector2 = outline[index]
		var q: Vector2 = outline[(index + 1) % outline.size()]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

# Extrude a polygon drawn in local x/y between local z = +depth/2 and -depth/2.
func extrude(surface: SurfaceTool, transform: Transform3D, outline: PackedVector2Array, depth: float, color: Color) -> void:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		push_warning("ChurchGrounds: could not triangulate an outline of %d points" % outline.size())
		return
	var front: Vector3 = transform.basis * Vector3.BACK
	var half: float = depth * 0.5
	for index: int in range(0, triangles.size(), 3):
		var a: Vector2 = outline[triangles[index]]
		var b: Vector2 = outline[triangles[index + 1]]
		var c: Vector2 = outline[triangles[index + 2]]
		tri(surface, transform * Vector3(a.x, a.y, half), transform * Vector3(b.x, b.y, half), transform * Vector3(c.x, c.y, half), front, color)
		tri(surface, transform * Vector3(a.x, a.y, -half), transform * Vector3(b.x, b.y, -half), transform * Vector3(c.x, c.y, -half), -front, color)
	var direction: float = 1.0 if signed_area(outline) > 0.0 else -1.0
	for index: int in range(outline.size()):
		var p: Vector2 = outline[index]
		var q: Vector2 = outline[(index + 1) % outline.size()]
		var side: Vector2 = Vector2(q.y - p.y, p.x - q.x) * direction
		quad(surface, transform * Vector3(p.x, p.y, half), transform * Vector3(q.x, q.y, half), transform * Vector3(q.x, q.y, -half), transform * Vector3(p.x, p.y, -half), transform.basis * Vector3(side.x, side.y, 0.0), color)

# A moulding between two outlines with equal point counts, from local z = 0 out to z = depth.
func ring(surface: SurfaceTool, transform: Transform3D, outer: PackedVector2Array, inner: PackedVector2Array, depth: float, color: Color, closed: bool = true) -> void:
	var count: int = outer.size()
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in inner:
		center += point / float(inner.size())
	var front: Vector3 = transform.basis * Vector3.BACK
	var last: int = count if closed else count - 1
	for index: int in range(last):
		var next: int = (index + 1) % count
		var o0: Vector2 = outer[index]
		var o1: Vector2 = outer[next]
		var i0: Vector2 = inner[index]
		var i1: Vector2 = inner[next]
		quad(surface, transform * Vector3(o0.x, o0.y, depth), transform * Vector3(o1.x, o1.y, depth), transform * Vector3(i1.x, i1.y, depth), transform * Vector3(i0.x, i0.y, depth), front, color)
		var away: Vector2 = (o0 + o1) * 0.5 - center
		quad(surface, transform * Vector3(o0.x, o0.y, 0.0), transform * Vector3(o1.x, o1.y, 0.0), transform * Vector3(o1.x, o1.y, depth), transform * Vector3(o0.x, o0.y, depth), transform.basis * Vector3(away.x, away.y, 0.0), color)
		var toward: Vector2 = center - (i0 + i1) * 0.5
		quad(surface, transform * Vector3(i0.x, i0.y, 0.0), transform * Vector3(i1.x, i1.y, 0.0), transform * Vector3(i1.x, i1.y, depth), transform * Vector3(i0.x, i0.y, depth), transform.basis * Vector3(toward.x, toward.y, 0.0), color)
	if not closed:
		for index: int in [0, count - 1]:
			var o: Vector2 = outer[index]
			var i: Vector2 = inner[index]
			quad(surface, transform * Vector3(o.x, o.y, 0.0), transform * Vector3(i.x, i.y, 0.0), transform * Vector3(i.x, i.y, depth), transform * Vector3(o.x, o.y, depth), transform.basis * Vector3.DOWN, color)

# Convex solid between two point loops of equal size; a collapsed top makes a pyramid.
func prism(surface: SurfaceTool, bottom: PackedVector3Array, top: PackedVector3Array, color: Color) -> void:
	var count: int = bottom.size()
	var low: Vector3 = Vector3.ZERO
	var high: Vector3 = Vector3.ZERO
	for index: int in range(count):
		low += bottom[index] / float(count)
		high += top[index] / float(count)
	var middle: Vector3 = (low + high) * 0.5
	for index: int in range(1, count - 1):
		tri(surface, bottom[0], bottom[index], bottom[index + 1], low - high, color)
		tri(surface, top[0], top[index], top[index + 1], high - low, color)
	for index: int in range(count):
		var next: int = (index + 1) % count
		var outward: Vector3 = (bottom[index] + bottom[next] + top[index] + top[next]) * 0.25 - middle
		quad(surface, bottom[index], bottom[next], top[next], top[index], outward, color)

func ring_points(center: Vector3, radius: float, sides: int, turn: float = 0.0) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for index: int in range(sides):
		var angle: float = turn + TAU * float(index) / float(sides)
		points.append(center + Vector3(sin(angle), 0.0, cos(angle)) * radius)
	return points

func pyramid(surface: SurfaceTool, base: Vector3, radius: float, height: float, sides: int, color: Color, turn: float = PI / 4.0, tip_offset: Vector3 = Vector3.ZERO) -> void:
	var bottom: PackedVector3Array = ring_points(base, radius, sides, turn)
	var top: PackedVector3Array = PackedVector3Array()
	for index: int in range(sides):
		top.append(base + Vector3.UP * height + tip_offset)
	prism(surface, bottom, top, color)

# Smooth tapered cylinder between two points (branches, shafts, candles).
func cylinder(surface: SurfaceTool, start: Vector3, finish: Vector3, start_radius: float, finish_radius: float, sides: int, color: Color, finish_color: Color = Color(-1, 0, 0), capped: bool = false) -> void:
	var axis: Vector3 = finish - start
	if axis.length_squared() < 1e-10:
		return
	var direction: Vector3 = axis.normalized()
	var helper: Vector3 = Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	var u: Vector3 = direction.cross(helper).normalized()
	var v: Vector3 = direction.cross(u).normalized()
	var top_color: Color = color if finish_color.r < 0.0 else finish_color
	var slope: float = (start_radius - finish_radius) / axis.length()
	for index: int in range(sides):
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var r0: Vector3 = u * cos(a0) + v * sin(a0)
		var r1: Vector3 = u * cos(a1) + v * sin(a1)
		var n0: Vector3 = (r0 + direction * slope).normalized()
		var n1: Vector3 = (r1 + direction * slope).normalized()
		var p0: Vector3 = start + r0 * start_radius
		var p1: Vector3 = start + r1 * start_radius
		var q0: Vector3 = finish + r0 * finish_radius
		var q1: Vector3 = finish + r1 * finish_radius
		smooth(surface, [p0, p1, q1], [n0, n1, n1], [color, color, top_color])
		smooth(surface, [p0, q1, q0], [n0, n1, n0], [color, top_color, top_color])
		if capped:
			tri(surface, finish, q0, q1, direction, top_color)

# Ellipsoid (optionally cut off below `lowest` of its height) with radial noise; faceted rocks or
# smooth mounds.
func ellipsoid(surface: SurfaceTool, transform: Transform3D, radii: Vector3, rings: int, sides: int, color: Color, jitter: float = 0.0, faceted: bool = false, lowest: float = -1.0) -> void:
	var grid: Array[PackedVector3Array] = []
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = random.randi()
	noise.frequency = 1.6
	var last_polar: float = acos(clampf(lowest, -1.0, 1.0))
	for ring_index: int in range(rings + 1):
		var row: PackedVector3Array = PackedVector3Array()
		var polar: float = last_polar * float(ring_index) / float(rings)
		for side: int in range(sides):
			var angle: float = TAU * float(side) / float(sides)
			var unit: Vector3 = Vector3(sin(polar) * cos(angle), cos(polar), sin(polar) * sin(angle))
			var bump: float = 1.0 + noise.get_noise_3dv(unit * 2.0) * jitter
			row.append(unit * radii * bump)
		grid.append(row)
	for ring_index: int in range(rings):
		for side: int in range(sides):
			var next: int = (side + 1) % sides
			var a: Vector3 = grid[ring_index][side]
			var b: Vector3 = grid[ring_index][next]
			var c: Vector3 = grid[ring_index + 1][next]
			var d: Vector3 = grid[ring_index + 1][side]
			if faceted:
				quad(surface, transform * a, transform * b, transform * c, transform * d, transform.basis * (a + b + c + d), color)
			else:
				var normals: Array[Vector3] = []
				for point: Vector3 in [a, b, c, d]:
					normals.append((transform.basis * (point / (radii * radii))).normalized())
				smooth(surface, [transform * a, transform * b, transform * c], [normals[0], normals[1], normals[2]], [color, color, color])
				smooth(surface, [transform * a, transform * c, transform * d], [normals[0], normals[2], normals[3]], [color, color, color])

# Revolve a (radius, height) profile, bottom to top, around local y; folds ripple the radius.
func lathe(surface: SurfaceTool, transform: Transform3D, profile: PackedVector2Array, sides: int, color: Color, folds: int = 0, fold_depth: float = 0.0) -> void:
	for index: int in range(profile.size() - 1):
		var p: Vector2 = profile[index]
		var q: Vector2 = profile[index + 1]
		var slope: Vector2 = q - p
		var normal2: Vector2 = Vector2(slope.y, -slope.x).normalized()
		var low_fade: float = 1.0 - float(index) / float(profile.size())
		var high_fade: float = 1.0 - float(index + 1) / float(profile.size())
		for side: int in range(sides):
			var a0: float = TAU * float(side) / float(sides)
			var a1: float = TAU * float(side + 1) / float(sides)
			var f0: float = 1.0 + sin(a0 * float(folds)) * fold_depth * low_fade
			var f1: float = 1.0 + sin(a1 * float(folds)) * fold_depth * low_fade
			var g0: float = 1.0 + sin(a0 * float(folds)) * fold_depth * high_fade
			var g1: float = 1.0 + sin(a1 * float(folds)) * fold_depth * high_fade
			var d0: Vector3 = Vector3(sin(a0), 0.0, cos(a0))
			var d1: Vector3 = Vector3(sin(a1), 0.0, cos(a1))
			var points: Array[Vector3] = [transform * (d0 * p.x * f0 + Vector3.UP * p.y), transform * (d1 * p.x * f1 + Vector3.UP * p.y), transform * (d1 * q.x * g1 + Vector3.UP * q.y), transform * (d0 * q.x * g0 + Vector3.UP * q.y)]
			var n0: Vector3 = (transform.basis * (d0 * normal2.x + Vector3.UP * normal2.y)).normalized()
			var n1: Vector3 = (transform.basis * (d1 * normal2.x + Vector3.UP * normal2.y)).normalized()
			smooth(surface, [points[0], points[1], points[2]], [n0, n1, n1], [color, color, color])
			smooth(surface, [points[0], points[2], points[3]], [n0, n1, n0], [color, color, color])

# Pointed (drop) arch outline: the bottom edge, then the arch from right to left.
func lancet(half_width: float, sill: float, spring: float, ratio: float, steps: int = 12) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([Vector2(-half_width, sill), Vector2(half_width, sill)])
	var radius: float = ratio * half_width
	var offset: float = radius - half_width
	for index: int in range(steps + 1):
		var x: float = lerpf(half_width, -half_width, float(index) / float(steps))
		points.append(Vector2(x, spring + sqrt(maxf(radius * radius - pow(absf(x) + offset, 2.0), 0.0))))
	return points

func circle(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(steps):
		var angle: float = TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

# A wall slab with a pointed opening: front face at local z = 0, back at -depth.
func arch_panel(surface: SurfaceTool, transform: Transform3D, half_width: float, bottom: float, top: float, opening: float, sill: float, spring: float, ratio: float, depth: float, color: Color) -> void:
	var outline: PackedVector2Array = lancet(opening, sill, spring, ratio)
	var arch: PackedVector2Array = outline.slice(2)
	for z: float in [0.0, -depth]:
		var outward: Vector3 = transform.basis * (Vector3.BACK if z == 0.0 else Vector3.FORWARD)
		if sill > bottom:
			quad(surface, transform * Vector3(-half_width, bottom, z), transform * Vector3(half_width, bottom, z), transform * Vector3(half_width, sill, z), transform * Vector3(-half_width, sill, z), outward, color)
		quad(surface, transform * Vector3(-half_width, sill, z), transform * Vector3(-opening, sill, z), transform * Vector3(-opening, top, z), transform * Vector3(-half_width, top, z), outward, color)
		quad(surface, transform * Vector3(opening, sill, z), transform * Vector3(half_width, sill, z), transform * Vector3(half_width, top, z), transform * Vector3(opening, top, z), outward, color)
		for index: int in range(arch.size() - 1):
			var p: Vector2 = arch[index]
			var q: Vector2 = arch[index + 1]
			quad(surface, transform * Vector3(p.x, p.y, z), transform * Vector3(q.x, q.y, z), transform * Vector3(q.x, top, z), transform * Vector3(p.x, top, z), outward, color)
	quad(surface, transform * Vector3(-opening, sill, 0.0), transform * Vector3(-opening, spring, 0.0), transform * Vector3(-opening, spring, -depth), transform * Vector3(-opening, sill, -depth), transform.basis * Vector3.RIGHT, color)
	quad(surface, transform * Vector3(opening, sill, 0.0), transform * Vector3(opening, spring, 0.0), transform * Vector3(opening, spring, -depth), transform * Vector3(opening, sill, -depth), transform.basis * Vector3.LEFT, color)
	if sill > bottom:
		quad(surface, transform * Vector3(-opening, sill, 0.0), transform * Vector3(opening, sill, 0.0), transform * Vector3(opening, sill, -depth), transform * Vector3(-opening, sill, -depth), transform.basis * Vector3.UP, color)
	for index: int in range(arch.size() - 1):
		var p: Vector2 = arch[index]
		var q: Vector2 = arch[index + 1]
		var mid: Vector2 = (p + q) * 0.5
		quad(surface, transform * Vector3(p.x, p.y, 0.0), transform * Vector3(q.x, q.y, 0.0), transform * Vector3(q.x, q.y, -depth), transform * Vector3(p.x, p.y, -depth), transform.basis * Vector3(-mid.x, spring - mid.y, 0.0), color)
	for x: float in [-half_width, half_width]:
		quad(surface, transform * Vector3(x, bottom, 0.0), transform * Vector3(x, top, 0.0), transform * Vector3(x, top, -depth), transform * Vector3(x, bottom, -depth), transform.basis * Vector3(x, 0.0, 0.0), color)
	quad(surface, transform * Vector3(-half_width, top, 0.0), transform * Vector3(half_width, top, 0.0), transform * Vector3(half_width, top, -depth), transform * Vector3(-half_width, top, -depth), transform.basis * Vector3.UP, color)

# Static collision: unscaled boxes and cylinders sized through their resources.
func solid(shape_transform: Transform3D, size: Vector3) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.transform = shape_transform.orthonormalized()
	collision.add_child(shape)
	shape_count += 1

func post_shape(base: Vector3, radius: float, height: float) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cylinder_shape: CylinderShape3D = CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	shape.shape = cylinder_shape
	shape.position = base + Vector3.UP * height * 0.5
	collision.add_child(shape)
	shape_count += 1

# --- Church building ------------------------------------------------------------------------
# Everything inside CHURCH_CLEAR (terrace, steps, nave, tower, spire, turret, door light) is built
# from here, so the procedural building can be swapped for an imported model in one place.

func build_building() -> void:
	build_church()
	build_tower()
	build_turret()
	# The cold doorway light spills out over the threshold and steps.
	lamp(at(0.0, 1.9, -1.7), Color(0.7, 0.82, 1.0), 2.4, 7.5, 0.0)

func build_church() -> void:
	var stone: SurfaceTool = tool("stone|church")
	var trim: SurfaceTool = tool("trim|church")
	var base: SurfaceTool = tool("base|church")
	# Terrace: flush with the floor at the door, buried into the hillside behind.
	var podium_z: float = (PODIUM_FRONT + PODIUM_BACK) * 0.5
	var podium_size: Vector3 = Vector3(PODIUM_HALF * 2.0, -0.18 - BURIED, PODIUM_FRONT - PODIUM_BACK)
	box(base, frame(Vector3(0.0, (BURIED - 0.18) * 0.5, podium_z)), podium_size, Color.WHITE)
	box(trim, frame(Vector3(0.0, -0.1, podium_z)), Vector3(podium_size.x + 0.16, 0.2, podium_size.z + 0.16), Color(0.85, 0.85, 0.82))
	solid(frame(Vector3(0.0, BURIED * 0.5, podium_z)), Vector3(podium_size.x + 0.16, -BURIED, podium_size.z + 0.16))
	# Worn steps down to the path.
	var foot: float = ground(ChurchSite.DOOR.x, ChurchSite.DOOR.y + PODIUM_FRONT + 0.6)
	var drop: float = floor_y - foot
	var count: int = clampi(ceili(drop / 0.23), 2, 6)
	var rise: float = drop / (float(count) + 0.4)
	for step: int in range(1, count + 1):
		var top: float = -float(step) * rise
		var center: Vector3 = Vector3(0.0, (top + BURIED - 1.0) * 0.5, PODIUM_FRONT + (float(step) - 0.5) * 0.44)
		var size: Vector3 = Vector3(4.4 - float(step) * 0.05, top - BURIED + 1.0, 0.46)
		box(base, frame(center), size, vary(0.08))
		solid(frame(center), size)
	var landing: float = -float(count) * rise
	for side: float in [-1.0, 1.0]:
		var plinth: Vector3 = Vector3(side * 2.75, (landing + 0.55 + BURIED - 1.0) * 0.5, PODIUM_FRONT + float(count) * 0.44 - 0.35)
		var plinth_size: Vector3 = Vector3(0.62, landing + 0.55 - BURIED + 1.0, 0.62)
		box(base, frame(plinth), plinth_size, vary(0.06))
		box(trim, frame(Vector3(plinth.x, landing + 0.6, plinth.z)), Vector3(0.74, 0.1, 0.74), Color.WHITE)
		solid(frame(plinth), plinth_size)
		candle_cluster(at(plinth.x, landing + 0.65, plinth.z), 3, 0.22)
	# Door-side candles on the terrace and the treads.
	for index: int in range(7):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		candle(at(side * random.randf_range(1.35, 2.1), 0.0, random.randf_range(0.35, 1.5)))
	for step: int in range(1, mini(count, 3) + 1):
		for side: float in [-1.0, 1.0]:
			if random.randf() < 0.7:
				candle(at(side * random.randf_range(1.2, 1.9), -float(step) * rise, PODIUM_FRONT + (float(step) - 0.5) * 0.44 + random.randf_range(-0.12, 0.12)))
	# Nave shell: side, front and back walls reach below the sloping ground.
	var wall_height: float = EAVES - BURIED
	var wall_mid: float = (EAVES + BURIED) * 0.5
	for side: float in [-1.0, 1.0]:
		var center: Vector3 = Vector3(side * (NAVE_HALF - WALL * 0.5), wall_mid, (NAVE_FRONT + NAVE_BACK) * 0.5)
		var size: Vector3 = Vector3(WALL, wall_height, NAVE_FRONT - NAVE_BACK)
		box(stone, frame(center), size, Color.WHITE)
		solid(frame(center), size)
	var back: Vector3 = Vector3(0.0, wall_mid, NAVE_BACK + WALL * 0.5)
	box(stone, frame(back), Vector3(NAVE_HALF * 2.0, wall_height, WALL), Color.WHITE)
	solid(frame(back), Vector3(NAVE_HALF * 2.0, wall_height, WALL))
	# The front wall stops at the tower so the vestibule behind the door stays open.
	for side: float in [-1.0, 1.0]:
		var shoulder: Vector3 = Vector3(side * (TOWER_HALF + NAVE_HALF - 0.1) * 0.5, wall_mid, NAVE_FRONT - WALL * 0.5)
		var size: Vector3 = Vector3(NAVE_HALF - TOWER_HALF + 0.1, wall_height, WALL)
		box(stone, frame(shoulder), size, Color.WHITE)
		solid(frame(shoulder), size)
	# Gables, coped with stone along their raking edges.
	for z: float in [NAVE_FRONT - WALL * 0.5, NAVE_BACK + WALL * 0.5]:
		var outline: PackedVector2Array = PackedVector2Array([Vector2(-NAVE_HALF, EAVES - 0.05), Vector2(NAVE_HALF, EAVES - 0.05), Vector2(0.0, RIDGE + 0.35)])
		extrude(stone, frame(Vector3(0.0, 0.0, z)), outline, WALL, Color.WHITE)
		for side: float in [-1.0, 1.0]:
			beam(trim, at(side * (NAVE_HALF + 0.12), EAVES + 0.12, z), at(0.0, RIDGE + 0.6, z), 1.06, 0.26, Color(0.9, 0.9, 0.88))
	cross_finial(at(0.0, RIDGE + 0.7, NAVE_BACK + WALL * 0.5), 1.5, Basis(Vector3.BACK, 0.05))
	# Cornice, ragged parapet, buttresses with pinnacles, and the lancet windows between them.
	for side: float in [-1.0, 1.0]:
		box(trim, frame(Vector3(side * (NAVE_HALF + 0.08), EAVES - 0.22, (NAVE_FRONT + NAVE_BACK) * 0.5)), Vector3(0.36, 0.3, NAVE_FRONT - NAVE_BACK + 0.3), Color.WHITE)
		box(stone, frame(Vector3(side * (NAVE_HALF - 0.2), EAVES + 0.24, (NAVE_FRONT + NAVE_BACK) * 0.5)), Vector3(0.46, 0.6, NAVE_FRONT - NAVE_BACK), Color.WHITE)
		var z: float = NAVE_FRONT - 0.4
		while z > NAVE_BACK + 0.3:
			var height: float = random.randf_range(0.42, 0.72)
			if random.randf() < 0.18:
				height = random.randf_range(0.08, 0.25)
			if random.randf() > 0.1:
				var merlon: Basis = Basis(Vector3.BACK, random.randf_range(-0.05, 0.05)) * Basis(Vector3.UP, random.randf_range(-0.06, 0.06))
				box(stone, frame(Vector3(side * (NAVE_HALF - 0.2), EAVES + 0.54 + height * 0.5, z), merlon), Vector3(0.46, height, 0.52), vary(0.08))
			z -= random.randf_range(0.95, 1.2)
	for z: float in [-5.9, -9.0, -12.5, -15.6]:
		for side: float in [-1.0, 1.0]:
			buttress(side, z)
	var states: Array[int] = [Glass.AMBER, Glass.BROKEN, Glass.BOARDED, Glass.DARK, Glass.RED, Glass.DARK]
	var index: int = 0
	for side: float in [-1.0, 1.0]:
		for z: float in [-7.45, -10.75, -14.05]:
			var facing: Basis = Basis(Vector3.UP, side * PI * 0.5)
			window(frame(Vector3(side * NAVE_HALF, 0.0, z), facing), 0.55, 2.3, 5.3, states[index], float(index) * 1.37)
			index += 1
	window(frame(Vector3(0.0, 0.0, NAVE_BACK), Basis(Vector3.UP, PI)), 0.8, 5.6, 10.2, Glass.AMBER, 9.1)
	build_roof()

func buttress(side: float, z: float) -> void:
	var stone: SurfaceTool = tool("stone|church")
	var trim: SurfaceTool = tool("trim|church")
	var basis: Basis = Basis(Vector3(side, 0.0, 0.0), Vector3.UP, Vector3.BACK)
	var outline: PackedVector2Array = PackedVector2Array([Vector2(-0.1, BURIED), Vector2(1.3, BURIED), Vector2(1.3, 4.6), Vector2(0.78, 5.35), Vector2(0.78, 7.3), Vector2(-0.1, 8.25)])
	extrude(stone, frame(Vector3(side * NAVE_HALF, 0.0, z), basis), outline, 0.86, vary(0.05))
	solid(frame(Vector3(side * (NAVE_HALF + 0.6), (BURIED + 4.6) * 0.5, z)), Vector3(1.4, 4.6 - BURIED, 0.86))
	box(trim, frame(Vector3(side * (NAVE_HALF + 0.66), 4.62, z)), Vector3(1.36, 0.1, 0.94), Color.WHITE)
	pinnacle(trim, at(side * (NAVE_HALF + 0.32), 8.1, z), 0.24, 1.7, 1.4)

func pinnacle(surface: SurfaceTool, base: Vector3, half: float, shaft: float, spire_height: float) -> void:
	box(surface, Transform3D(Basis.IDENTITY, base + Vector3.UP * shaft * 0.5), Vector3(half * 2.0, shaft, half * 2.0), vary(0.06))
	box(surface, Transform3D(Basis.IDENTITY, base + Vector3.UP * (shaft + 0.05)), Vector3(half * 2.5, 0.1, half * 2.5), Color.WHITE)
	pyramid(surface, base + Vector3.UP * (shaft + 0.1), half * 1.45, spire_height, 4, vary(0.06))

func cross_finial(base: Vector3, height: float, tilt: Basis) -> void:
	var trim: SurfaceTool = tool("trim|church")
	var outline: PackedVector2Array = PackedVector2Array([Vector2(-0.09, 0.0), Vector2(0.09, 0.0), Vector2(0.09, height * 0.62), Vector2(0.36, height * 0.62), Vector2(0.36, height * 0.76), Vector2(0.09, height * 0.76), Vector2(0.09, height), Vector2(-0.09, height), Vector2(-0.09, height * 0.76), Vector2(-0.36, height * 0.76), Vector2(-0.36, height * 0.62), Vector2(-0.09, height * 0.62)])
	extrude(trim, Transform3D(tilt, base), outline, 0.16, Color.WHITE)
	ring(trim, Transform3D(tilt, base + tilt * Vector3(0.0, 0.0, -0.04)), circle(Vector2(0.0, height * 0.69), 0.27, 16), circle(Vector2(0.0, height * 0.69), 0.21, 16), 0.08, Color.WHITE)

func build_roof() -> void:
	var slate: SurfaceTool = tool("slate|church")
	var trim: SurfaceTool = tool("trim|church")
	var z0: float = NAVE_FRONT + 0.25
	var z1: float = NAVE_BACK - 0.4
	var columns: int = 14
	var rows: int = 6
	var ridge_points: Array[Vector3] = []
	var edge_uv: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 0.2), Vector2(0, 0.2)])
	for side: float in [-1.0, 1.0]:
		var eave: Vector2 = Vector2(side * (NAVE_HALF - 0.45), EAVES + 0.3)
		var crest: Vector2 = Vector2(0.0, RIDGE)
		var slope_length: float = eave.distance_to(crest)
		var grid: Array[PackedVector3Array] = []
		for i: int in range(columns + 1):
			var row: PackedVector3Array = PackedVector3Array()
			var z: float = lerpf(z0, z1, float(i) / float(columns))
			for j: int in range(rows + 1):
				var t: float = float(j) / float(rows)
				var point: Vector2 = eave.lerp(crest, t)
				var sag: float = 0.3 * sin(PI * float(i) / float(columns)) * (0.35 + 0.65 * sin(PI * t))
				if i > 0 and i < columns and j > 0 and j < rows:
					sag += random.randf_range(-0.03, 0.05)
				row.append(at(point.x, point.y - sag, z))
			grid.append(row)
		var lift: Vector3 = Vector3(side * 0.6, 1.0, 0.0).normalized()
		var down: Vector3 = Vector3.DOWN * 0.24
		for i: int in range(columns):
			for j: int in range(rows):
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i + 1][j]
				var c: Vector3 = grid[i + 1][j + 1]
				var d: Vector3 = grid[i][j + 1]
				var u0: float = absf(a.z - at(0, 0, z0).z)
				var u1: float = absf(b.z - at(0, 0, z0).z)
				var v0: float = (1.0 - float(j) / float(rows)) * slope_length
				var v1: float = (1.0 - float(j + 1) / float(rows)) * slope_length
				var uv: PackedVector2Array = PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
				quad(slate, a, b, c, d, lift, Color.WHITE, uv)
				quad(slate, a + down, b + down, c + down, d + down, -lift, Color(0.5, 0.5, 0.5), uv)
		for i: int in range(columns):
			var a: Vector3 = grid[i][0]
			var b: Vector3 = grid[i + 1][0]
			quad(slate, a, b, b + down, a + down, Vector3(side, -0.3, 0.0), Color(0.6, 0.6, 0.6), edge_uv)
		for i: int in [0, columns]:
			var outward: Vector3 = Vector3.BACK if i == 0 else Vector3.FORWARD
			for j: int in range(rows):
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i][j + 1]
				quad(slate, a, b, b + down, a + down, outward, Color(0.6, 0.6, 0.6), edge_uv)
		if side < 0.0:
			for i: int in range(columns + 1):
				ridge_points.append(grid[i][rows])
		var mid_point: Vector2 = eave.lerp(crest, 0.5)
		var angle: float = atan2(crest.y - eave.y, crest.x - eave.x)
		solid(frame(Vector3(mid_point.x, mid_point.y - 0.12, (z0 + z1) * 0.5), Basis(Vector3.BACK, angle)), Vector3(slope_length, 0.3, z0 - z1))
	for i: int in range(ridge_points.size() - 1):
		beam(trim, ridge_points[i] + Vector3.UP * 0.06, ridge_points[i + 1] + Vector3.UP * 0.06, 0.34, 0.24, vary(0.05))

# Lancet window on a wall face; the frame origin sits on the face at floor height, +z outward.
func window(transform: Transform3D, half_width: float, sill: float, spring: float, state: int, seed_value: float) -> void:
	var trim: SurfaceTool = tool("trim|church")
	var ratio: float = 1.6
	var radius: float = ratio * half_width
	var surround: float = 0.17
	var inner: PackedVector2Array = lancet(half_width, sill, spring, ratio)
	var outer: PackedVector2Array = lancet(half_width + surround, sill - surround, spring, (radius + surround) / (half_width + surround))
	ring(trim, transform, outer, inner, 0.13, vary(0.05))
	box(trim, transform * Transform3D(Basis.IDENTITY, Vector3(0.0, sill - surround - 0.06, 0.1)), Vector3(half_width * 2.0 + 0.6, 0.12, 0.26), Color.WHITE)
	if half_width > 0.45:
		box(trim, transform * Transform3D(Basis.IDENTITY, Vector3(0.0, (sill + spring + 0.4) * 0.5, 0.05)), Vector3(0.09, spring + 0.4 - sill, 0.1), Color.WHITE)
	glass_pane(transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.025)), inner, Vector2(-half_width, sill), state, seed_value)
	if state == Glass.BOARDED:
		var wood: SurfaceTool = tool("wood|church")
		for plank: int in range(4):
			var y: float = sill + 0.5 + float(plank) * (spring - sill) / 4.0
			var tilt: Basis = Basis(Vector3.BACK, random.randf_range(-0.25, 0.25))
			box(wood, transform * Transform3D(tilt, Vector3(random.randf_range(-0.05, 0.05), y, 0.11)), Vector3(half_width * 2.0 + 0.45, 0.2, 0.05), vary(0.15))

func glass_pane(transform: Transform3D, outline: PackedVector2Array, origin: Vector2, state: int, seed_value: float) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	var front: Vector3 = transform.basis * Vector3.BACK
	for index: int in range(0, triangles.size(), 3):
		var points: Array[Vector3] = []
		var uv: PackedVector2Array = PackedVector2Array()
		for corner: int in range(3):
			var p: Vector2 = outline[triangles[index + corner]]
			points.append(transform * Vector3(p.x, p.y, 0.0))
			uv.append(p - origin)
		tri(surface, points[0], points[1], points[2], front, Color.WHITE, uv)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Glass"
	visual.mesh = surface.commit()
	visual.material_override = glass_materials[state]
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	visual.set_instance_shader_parameter("seed", seed_value)

# --- Tower, belfry, spire and turret --------------------------------------------------------

func build_tower() -> void:
	var stone: SurfaceTool = tool("stone|church")
	var trim: SurfaceTool = tool("trim|church")
	# Front face with the portal, side walls and a closed vestibule behind the door.
	arch_panel(stone, frame(Vector3.ZERO), TOWER_HALF, BURIED, TOWER_TOP, DOOR_HALF, 0.02, DOOR_SPRING, 1.5, WALL, Color.WHITE)
	for side: float in [-1.0, 1.0]:
		box(stone, frame(Vector3(side * (TOWER_HALF - 0.45), (BURIED + TOWER_TOP) * 0.5, (-WALL + TOWER_BACK) * 0.5)), Vector3(0.9, TOWER_TOP - BURIED, -TOWER_BACK - WALL), Color.WHITE)
	box(stone, frame(Vector3(0.0, (BURIED + TOWER_TOP) * 0.5, (-2.6 + TOWER_BACK) * 0.5)), Vector3(TOWER_HALF * 2.0 - 1.8, TOWER_TOP - BURIED, -TOWER_BACK - 2.6), Color.WHITE)
	box(stone, frame(Vector3(0.0, (4.4 + TOWER_TOP) * 0.5, (-WALL - 2.6) * 0.5)), Vector3(TOWER_HALF * 2.0 - 1.8, TOWER_TOP - 4.4, 2.6 - WALL), Color.WHITE)
	solid(frame(Vector3(0.0, (BURIED + TOWER_TOP) * 0.5, TOWER_BACK * 0.5)), Vector3(TOWER_HALF * 2.0, TOWER_TOP - BURIED, -TOWER_BACK))
	# The vestibule is filled with pale light, so the ajar door shows it from any approach angle:
	# the only bright opening in the building.
	var vestibule: float = TOWER_HALF - 0.9
	glow_panel(frame(Vector3(0.0, 0.0, -2.58)), PackedVector2Array([Vector2(-vestibule, 0.0), Vector2(vestibule, 0.0), Vector2(vestibule, 4.4), Vector2(-vestibule, 4.4)]))
	for side: float in [-1.0, 1.0]:
		glow_panel(frame(Vector3(side * (vestibule - 0.02), 0.0, -1.75), Basis(Vector3.UP, -side * PI * 0.5)), PackedVector2Array([Vector2(-0.85, 0.0), Vector2(0.85, 0.0), Vector2(0.85, 4.4), Vector2(-0.85, 4.4)]))
	# Portal mouldings in two orders, a gabled hood, and the heavy door leaves, one ajar.
	var orders: Array[float] = [0.42, 0.22]
	for order: int in range(2):
		var grow: float = orders[order]
		var radius: float = 1.5 * DOOR_HALF
		var inner_grow: float = grow - 0.2
		var outer: PackedVector2Array = lancet(DOOR_HALF + grow, 0.0, DOOR_SPRING, (radius + grow) / (DOOR_HALF + grow))
		var inner: PackedVector2Array = lancet(DOOR_HALF + inner_grow, 0.0, DOOR_SPRING, (radius + inner_grow) / (DOOR_HALF + inner_grow))
		# Drop the sill edge: an open moulding from the right jamb foot over the arch to the left.
		outer.remove_at(0)
		inner.remove_at(0)
		ring(trim, frame(Vector3(0.0, 0.0, -0.02)), outer, inner, 0.24 - float(order) * 0.1, Color.WHITE, false)
	extrude(trim, frame(Vector3(0.0, 0.0, 0.1)), PackedVector2Array([Vector2(-1.95, 3.7), Vector2(1.95, 3.7), Vector2(0.0, 6.05)]), 0.2, Color.WHITE)
	pinnacle(trim, at(0.0, 6.0, 0.1), 0.1, 0.4, 0.55)
	door_leaf(-1.0, 0.0)
	door_leaf(1.0, 0.8)
	# Corner buttresses rise in three set-backs.
	var stages: PackedVector2Array = PackedVector2Array([Vector2(-0.1, BURIED), Vector2(0.9, BURIED), Vector2(0.9, 4.4), Vector2(0.6, 5.0), Vector2(0.6, 9.0), Vector2(0.35, 9.6), Vector2(0.35, 12.6), Vector2(-0.1, 13.2)])
	for side: float in [-1.0, 1.0]:
		extrude(stone, frame(Vector3(side * (TOWER_HALF - 0.45), 0.0, 0.0), Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))), stages, 0.9, vary(0.05))
		extrude(stone, frame(Vector3(side * TOWER_HALF, 0.0, -0.45), Basis(Vector3(side, 0, 0), Vector3.UP, Vector3.BACK)), stages, 0.9, vary(0.05))
		solid(frame(Vector3(side * (TOWER_HALF - 0.45), (BURIED + 4.4) * 0.5, 0.45)), Vector3(0.9, 4.4 - BURIED, 0.9))
		solid(frame(Vector3(side * (TOWER_HALF + 0.45), (BURIED + 4.4) * 0.5, -0.45)), Vector3(0.9, 4.4 - BURIED, 0.9))
	# String courses and cornice.
	for y: float in [6.4, 11.0]:
		box(trim, frame(Vector3(0.0, y, TOWER_BACK * 0.5)), Vector3(TOWER_HALF * 2.0 + 0.24, 0.22, -TOWER_BACK + 0.24), Color.WHITE)
	box(trim, frame(Vector3(0.0, TOWER_TOP - 0.12, TOWER_BACK * 0.5)), Vector3(TOWER_HALF * 2.0 + 0.5, 0.3, -TOWER_BACK + 0.5), Color.WHITE)
	# Rose window over the door, with stone tracery.
	var rose: Vector2 = Vector2(0.0, 8.3)
	ring(trim, frame(Vector3.ZERO), circle(rose, 1.38, 32), circle(rose, 1.15, 32), 0.16, Color.WHITE)
	glass_pane(frame(Vector3(0.0, 0.0, 0.025)), circle(rose, 1.15, 32), rose - Vector2(1.15, 1.15), Glass.RED, 4.4)
	ring(trim, frame(Vector3(0.0, 0.0, 0.02)), circle(rose, 0.36, 16), circle(rose, 0.26, 16), 0.1, Color.WHITE)
	for spoke: int in range(8):
		var angle: float = TAU * float(spoke) / 8.0
		var direction: Vector3 = Vector3(cos(angle), sin(angle), 0.0)
		beam(trim, at(rose.x, rose.y, 0.07) + direction * 0.32, at(rose.x, rose.y, 0.07) + direction * 1.16, 0.07, 0.07, Color.WHITE)
	# Paired dark lancets on the upper stage.
	var faces: Array[Basis] = [Basis.IDENTITY, Basis(Vector3.UP, PI * 0.5), Basis(Vector3.UP, -PI * 0.5)]
	var origins: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(TOWER_HALF, 0.0, TOWER_BACK * 0.5), Vector3(-TOWER_HALF, 0.0, TOWER_BACK * 0.5)]
	for face: int in range(3):
		for offset: float in [-0.75, 0.75]:
			var origin: Vector3 = origins[face] + faces[face] * Vector3(offset, 0.0, 0.0)
			window(frame(origin, faces[face]), 0.26, 11.8, 14.3, Glass.BROKEN if face == 1 and offset > 0.0 else Glass.DARK, float(face) * 2.1 + offset)
	# Square-top parapet and corner pinnacles around the octagonal belfry.
	for corner: int in range(4):
		var cx: float = TOWER_HALF - 0.3 if corner % 2 == 0 else -TOWER_HALF + 0.3
		var cz: float = -0.3 if corner < 2 else TOWER_BACK + 0.3
		pinnacle(trim, at(cx, TOWER_TOP, cz), 0.3, 2.1, 1.9)
	for side: float in [-1.0, 1.0]:
		box(stone, frame(Vector3(side * (TOWER_HALF - 0.15), TOWER_TOP + 0.3, TOWER_BACK * 0.5)), Vector3(0.3, 0.6, -TOWER_BACK), vary(0.05))
		box(stone, frame(Vector3(0.0, TOWER_TOP + 0.3, -0.15 if side > 0.0 else TOWER_BACK + 0.15)), Vector3(TOWER_HALF * 2.0, 0.6, 0.3), vary(0.05))
	build_belfry()

func glow_panel(panel: Transform3D, outline: PackedVector2Array) -> void:
	var surface: SurfaceTool = tool("glow|church")
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for index: int in range(0, triangles.size(), 3):
		var a: Vector2 = outline[triangles[index]]
		var b: Vector2 = outline[triangles[index + 1]]
		var c: Vector2 = outline[triangles[index + 2]]
		tri(surface, panel * Vector3(a.x, a.y, 0.0), panel * Vector3(b.x, b.y, 0.0), panel * Vector3(c.x, c.y, 0.0), panel.basis * Vector3.BACK, Color.WHITE)

# One leaf of the double door, hinged at x = side * DOOR_HALF; swing opens it into the vestibule.
func door_leaf(side: float, swing: float) -> void:
	var wood: SurfaceTool = tool("wood|church")
	var iron: SurfaceTool = tool("iron|church")
	var outline: PackedVector2Array = lancet(DOOR_HALF - 0.02, 0.03, DOOR_SPRING, 1.5 * DOOR_HALF / (DOOR_HALF - 0.02))
	var half: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.03)])
	if side < 0.0:
		half = PackedVector2Array([Vector2(-(DOOR_HALF - 0.02), 0.03), Vector2(0.0, 0.03)])
		for point: Vector2 in outline.slice(2):
			if point.x <= 0.0001:
				half.append(point)
	else:
		half = PackedVector2Array([Vector2(0.0, 0.03), Vector2(DOOR_HALF - 0.02, 0.03)])
		for point: Vector2 in outline.slice(2):
			if point.x >= -0.0001:
				half.append(point)
	var local: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in half:
		local.append(point - Vector2(side * DOOR_HALF, 0.0))
	var hinge: Transform3D = frame(Vector3(side * DOOR_HALF, 0.0, -0.4), Basis(Vector3.UP, -side * swing))
	extrude(wood, hinge, local, 0.12, Color(0.7, 0.66, 0.62))
	for y: float in [0.55, 1.6, 2.6]:
		box(iron, hinge * Transform3D(Basis.IDENTITY, Vector3(-side * 0.42, y, 0.07)), Vector3(0.8, 0.07, 0.025), Color.WHITE)
	ring(iron, hinge * Transform3D(Basis.IDENTITY, Vector3(-side * 0.82, 1.3, 0.07)), circle(Vector2.ZERO, 0.1, 10), circle(Vector2.ZERO, 0.075, 10), 0.03, Color.WHITE)

func build_belfry() -> void:
	var stone: SurfaceTool = tool("stone|church")
	var trim: SurfaceTool = tool("trim|church")
	var slate: SurfaceTool = tool("slate|church")
	var iron: SurfaceTool = tool("iron|church")
	var axis: Vector3 = Vector3(0.0, 0.0, TOWER_BACK * 0.5)
	var apothem: float = BELFRY_RADIUS * cos(PI / 8.0)
	var half_face: float = BELFRY_RADIUS * sin(PI / 8.0)
	for face: int in range(8):
		var angle: float = TAU * float(face) / 8.0
		var basis: Basis = Basis(Vector3.UP, angle)
		var origin: Vector3 = axis + basis * Vector3(0.0, 0.0, apothem)
		arch_panel(stone, frame(origin, basis), half_face, TOWER_TOP - 0.1, BELFRY_TOP, 0.4, 17.3, 19.9, 1.6, 0.35, vary(0.04))
		ring(trim, frame(origin, basis), lancet(0.52, 17.18, 19.9, 0.76 / 0.52), lancet(0.4, 17.3, 19.9, 1.6), 0.08, Color.WHITE)
		var corner_angle: float = angle + PI / 8.0
		var corner: Vector3 = axis + Basis(Vector3.UP, corner_angle) * Vector3(0.0, 0.0, BELFRY_RADIUS)
		box(trim, frame(corner + Vector3(0.0, (TOWER_TOP + BELFRY_TOP) * 0.5, 0.0), Basis(Vector3.UP, corner_angle)), Vector3(0.26, BELFRY_TOP - TOWER_TOP, 0.26), Color.WHITE)
	prism(stone, ring_points(at(axis.x, TOWER_TOP - 0.05, axis.z), BELFRY_RADIUS - 0.1, 8, PI / 8.0), ring_points(at(axis.x, TOWER_TOP + 0.12, axis.z), BELFRY_RADIUS - 0.1, 8, PI / 8.0), Color(0.3, 0.3, 0.3))
	prism(trim, ring_points(at(axis.x, BELFRY_TOP - 0.05, axis.z), BELFRY_RADIUS + 0.3, 8, PI / 8.0), ring_points(at(axis.x, BELFRY_TOP + 0.35, axis.z), BELFRY_RADIUS + 0.3, 8, PI / 8.0), Color.WHITE)
	# The bell hangs from a beam, a silhouette against the far openings.
	beam(tool("wood|church"), at(axis.x - 1.7, 20.9, axis.z), at(axis.x + 1.7, 20.9, axis.z), 0.22, 0.26, Color(0.5, 0.48, 0.45))
	var bell_profile: PackedVector2Array = PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.6, 0.08), Vector2(0.5, 0.2), Vector2(0.42, 0.45), Vector2(0.39, 0.75), Vector2(0.33, 0.95), Vector2(0.18, 1.04), Vector2(0.0, 1.06)])
	lathe(iron, frame(axis + Vector3(0.0, 19.7, 0.0)), bell_profile, 16, Color(0.75, 0.62, 0.45))
	# Spire, leaning very slightly, with lucarnes and a crooked iron cross.
	var base: Vector3 = at(axis.x, BELFRY_TOP + 0.35, axis.z)
	var tip: Vector3 = at(axis.x + 0.3, SPIRE_TIP, axis.z + 0.12)
	spire(slate, base, BELFRY_RADIUS + 0.12, tip, 8)
	for face: int in range(4):
		lucarne(Basis(Vector3.UP, TAU * float(face) / 4.0), axis)
	var tilt: Basis = Basis(Vector3.UP, 0.35) * Basis(Vector3.BACK, 0.24)
	var cross_base: Vector3 = tip + Vector3.DOWN * 0.3
	box(iron, Transform3D(tilt, cross_base + tilt * Vector3(0.0, 1.3, 0.0)), Vector3(0.1, 2.6, 0.1), Color.WHITE)
	box(iron, Transform3D(tilt, cross_base + tilt * Vector3(0.0, 1.85, 0.0)), Vector3(1.3, 0.1, 0.1), Color.WHITE)

func spire(surface: SurfaceTool, base: Vector3, radius: float, tip: Vector3, sides: int) -> void:
	var points: PackedVector3Array = ring_points(base, radius, sides, PI / 8.0)
	for index: int in range(sides):
		var a: Vector3 = points[index]
		var b: Vector3 = points[(index + 1) % sides]
		var outward: Vector3 = (a + b) * 0.5 - base
		var edge: Vector3 = (b - a).normalized()
		var uv: PackedVector2Array = PackedVector2Array([Vector2((a - tip).dot(edge), a.distance_to(tip)), Vector2((b - tip).dot(edge), b.distance_to(tip)), Vector2(0.0, 0.0)])
		tri(surface, a, b, tip, outward + Vector3.UP * 0.3, Color.WHITE, uv)

func lucarne(basis: Basis, axis: Vector3) -> void:
	var slate: SurfaceTool = tool("slate|church")
	var trim: SurfaceTool = tool("trim|church")
	var origin: Vector3 = axis + basis * Vector3(0.0, 0.0, BELFRY_RADIUS * 0.8)
	var dormer: Transform3D = frame(origin, basis)
	extrude(trim, dormer, PackedVector2Array([Vector2(-0.42, BELFRY_TOP + 0.3), Vector2(0.42, BELFRY_TOP + 0.3), Vector2(0.42, BELFRY_TOP + 1.2), Vector2(0.0, BELFRY_TOP + 1.85), Vector2(-0.42, BELFRY_TOP + 1.2)]), 0.9, Color.WHITE)
	glass_pane(dormer * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.46)), lancet(0.2, BELFRY_TOP + 0.45, BELFRY_TOP + 1.05, 1.5, 8), Vector2(-0.2, BELFRY_TOP + 0.45), Glass.DARK, 3.3)
	for side: float in [-1.0, 1.0]:
		beam(slate, dormer * Vector3(side * 0.5, BELFRY_TOP + 1.13, 0.5), dormer * Vector3(0.0, BELFRY_TOP + 1.95, 0.5), 0.06, 0.06, Color.WHITE)

func build_turret() -> void:
	var stone: SurfaceTool = tool("stone|church")
	var trim: SurfaceTool = tool("trim|church")
	var slate: SurfaceTool = tool("slate|church")
	var center: Vector3 = Vector3(NAVE_HALF + 0.3, 0.0, NAVE_FRONT - 0.3)
	prism(stone, ring_points(at(center.x, BURIED, center.z), 0.95, 8, PI / 8.0), ring_points(at(center.x, 12.0, center.z), 0.95, 8, PI / 8.0), Color.WHITE)
	post_shape(at(center.x, BURIED, center.z), 0.95, 12.0 - BURIED)
	prism(trim, ring_points(at(center.x, 11.9, center.z), 1.12, 8, PI / 8.0), ring_points(at(center.x, 12.25, center.z), 1.12, 8, PI / 8.0), Color.WHITE)
	spire(slate, at(center.x, 12.25, center.z), 1.08, at(center.x - 0.08, 16.6, center.z + 0.05), 8)
	pyramid(tool("iron|church"), at(center.x - 0.08, 16.5, center.z + 0.05), 0.05, 0.9, 4, Color.WHITE)
	for height: float in [3.2, 6.6, 9.8]:
		for angle: float in [PI * 0.25, PI * 0.75]:
			var basis: Basis = Basis(Vector3.UP, angle)
			var origin: Vector3 = center + basis * Vector3(0.0, 0.0, 0.95 * cos(PI / 8.0))
			window(frame(origin, basis), 0.12, height, height + 0.7, Glass.DARK, height + angle)

# --- Graveyard enclosure -------------------------------------------------------------------

func build_enclosure() -> void:
	var gate_left: float = gate_x - GATE_HALF - 0.85
	var gate_right: float = gate_x + GATE_HALF + 0.85
	wall_run(Vector2(WALL_WEST_X, WALL_FRONT_Z), Vector2(gate_left, WALL_FRONT_Z), -1000.0)
	wall_run(Vector2(gate_right, WALL_FRONT_Z), Vector2(WALL_EAST_X, WALL_FRONT_Z), -1000.0)
	wall_run(Vector2(WALL_WEST_X, WALL_FRONT_Z), Vector2(WALL_WEST_X, WALL_BACK_Z), WALL_FRONT_Z - WEST_GAP_Z)
	wall_run(Vector2(WALL_EAST_X, WALL_FRONT_Z), Vector2(WALL_EAST_X, WALL_BACK_Z), WALL_FRONT_Z - EAST_GAP_Z)
	wall_run(Vector2(WALL_WEST_X, WALL_BACK_Z), Vector2(ChurchSite.DOOR.x - PODIUM_HALF - 0.1, WALL_BACK_Z), -1000.0)
	wall_run(Vector2(ChurchSite.DOOR.x + PODIUM_HALF + 0.1, WALL_BACK_Z), Vector2(WALL_EAST_X, WALL_BACK_Z), -1000.0)

# Mossy waist-high wall topped by a spiked railing, in ~2.4 m bays with piers between them.
func wall_run(start: Vector2, finish: Vector2, gap_at: float) -> void:
	var delta: Vector2 = finish - start
	var length: float = delta.length()
	var bays: int = maxi(1, roundi(length / 2.4))
	var bay: float = length / float(bays)
	var direction: Vector2 = delta / length
	var basis: Basis = Basis(Vector3.UP, -atan2(direction.y, direction.x))
	for index: int in range(bays):
		var a: Vector2 = start + direction * (bay * float(index))
		var b: Vector2 = start + direction * (bay * float(index + 1))
		var middle: Vector2 = (a + b) * 0.5
		var along: float = bay * (float(index) + 0.5)
		var key: String = chunk(middle.x, middle.y)
		var lowest: float = INF
		var highest: float = -INF
		for sample: int in range(5):
			var point: Vector2 = a.lerp(b, float(sample) / 4.0)
			var height: float = ground(point.x, point.y)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
		if absf(along - gap_at) < 1.4:
			rubble(middle, direction, basis, key, lowest)
			continue
		var top: float = highest + 0.95
		var bottom: float = lowest - 0.6
		box(tool("base|" + key), Transform3D(basis, Vector3(middle.x, (top + bottom) * 0.5, middle.y)), Vector3(bay + 0.02, top - bottom, 0.5), vary(0.08))
		box(tool("trim|" + key), Transform3D(basis, Vector3(middle.x, top + 0.05, middle.y)), Vector3(bay + 0.04, 0.12, 0.62), vary(0.05))
		solid(Transform3D(basis, Vector3(middle.x, (top + 1.05 + bottom) * 0.5, middle.y)), Vector3(bay, top + 1.05 - bottom, 0.5))
		railing(Vector3(a.x, top + 0.11, a.y), Vector3(b.x, top + 0.11, b.y), key)
		if index > 0:
			pier(Vector3(a.x, top, a.y), basis, bottom, key)
	for end: Vector2 in [start, finish]:
		var height: float = ground(end.x, end.y)
		pier(Vector3(end.x, height + 0.95, end.y), basis, height - 0.6, chunk(end.x, end.y))

func pier(point: Vector3, basis: Basis, bottom: float, key: String) -> void:
	var top: float = point.y + 0.35
	box(tool("base|" + key), Transform3D(basis, Vector3(point.x, (top + bottom) * 0.5, point.z)), Vector3(0.6, top - bottom, 0.62), vary(0.08))
	box(tool("trim|" + key), Transform3D(basis, Vector3(point.x, top + 0.05, point.z)), Vector3(0.72, 0.1, 0.74), Color.WHITE)
	pyramid(tool("trim|" + key), Vector3(point.x, top + 0.1, point.z), 0.4, 0.28, 4, vary(0.05), PI / 4.0 + basis.get_euler().y)

func railing(start: Vector3, finish: Vector3, key: String) -> void:
	var iron: SurfaceTool = tool("iron|" + key)
	for height: float in [0.14, 0.78]:
		beam(iron, start + Vector3.UP * height, finish + Vector3.UP * height, 0.04, 0.04, Color.WHITE)
	var length: float = start.distance_to(finish)
	var count: int = int(length / 0.15)
	var along: Vector3 = (finish - start).normalized()
	var across: Vector3 = along.cross(Vector3.UP)
	for index: int in range(1, count):
		if random.randf() < 0.05:
			continue
		var base: Vector3 = start.lerp(finish, float(index) / float(count))
		var lean: Vector3 = Vector3.UP
		if random.randf() < 0.08:
			lean = (Vector3.UP + across * random.randf_range(-0.45, 0.45) + along * random.randf_range(-0.2, 0.2)).normalized()
		var tip: Vector3 = base + lean * 0.92
		beam(iron, base, tip, 0.022, 0.022, Color.WHITE)
		pyramid(iron, tip - lean * 0.02, 0.035, 0.13, 4, Color.WHITE)

# A collapsed bay: tumbled stones and a fallen length of railing; no collision, so it can be crossed.
func rubble(middle: Vector2, direction: Vector2, basis: Basis, key: String, lowest: float) -> void:
	var stone: SurfaceTool = tool("base|" + key)
	var across: Vector3 = Vector3(-direction.y, 0.0, direction.x)
	for index: int in range(10):
		var offset: Vector2 = direction * random.randf_range(-1.3, 1.3) + Vector2(-direction.y, direction.x) * random.randf_range(-0.9, 0.9)
		var point: Vector2 = middle + offset
		var size: float = random.randf_range(0.18, 0.42)
		var tumble: Basis = Basis.from_euler(Vector3(random.randf_range(-0.6, 0.6), random.randf_range(0.0, TAU), random.randf_range(-0.6, 0.6)))
		box(stone, Transform3D(tumble, Vector3(point.x, ground(point.x, point.y) + size * 0.2, point.y)), Vector3(size * 1.4, size, size * 0.9), vary(0.12))
	for end: float in [-1.0, 1.0]:
		var stub: Vector2 = middle + direction * end * 1.0
		var height: float = ground(stub.x, stub.y)
		box(stone, Transform3D(basis, Vector3(stub.x, height + 0.05, stub.y)), Vector3(0.4, 0.6 + random.randf_range(0.0, 0.3), 0.5), vary(0.08))
	var fallen_start: Vector3 = Vector3(middle.x - direction.x * 1.1, lowest + 0.12, middle.y - direction.y * 1.1) + across * 0.7
	var fallen_end: Vector3 = Vector3(middle.x + direction.x * 1.0, lowest + 0.35, middle.y + direction.y * 1.0) + across * 1.1
	var iron: SurfaceTool = tool("iron|" + key)
	beam(iron, fallen_start, fallen_end, 0.04, 0.04, Color.WHITE)
	for index: int in range(10):
		var base: Vector3 = fallen_start.lerp(fallen_end, float(index) / 9.0)
		beam(iron, base, base + (across * 0.85 + Vector3.UP * 0.18).normalized() * 0.8, 0.022, 0.022, Color.WHITE)

func build_gate() -> void:
	var height: float = ground(gate_x, WALL_FRONT_Z)
	for side: float in [-1.0, 1.0]:
		var x: float = gate_x + side * (GATE_HALF + 0.42)
		var key: String = chunk(x, WALL_FRONT_Z)
		var base_height: float = ground(x, WALL_FRONT_Z)
		var top: float = base_height + 2.65
		var bottom: float = base_height - 0.6
		box(tool("base|" + key), Transform3D(Basis.IDENTITY, Vector3(x, (top + bottom) * 0.5, WALL_FRONT_Z)), Vector3(0.84, top - bottom, 0.84), vary(0.06))
		box(tool("trim|" + key), Transform3D(Basis.IDENTITY, Vector3(x, base_height + 0.2, WALL_FRONT_Z)), Vector3(0.98, 0.42, 0.98), Color.WHITE)
		box(tool("trim|" + key), Transform3D(Basis.IDENTITY, Vector3(x, top + 0.08, WALL_FRONT_Z)), Vector3(1.04, 0.16, 1.04), Color.WHITE)
		box(tool("trim|" + key), Transform3D(Basis.IDENTITY, Vector3(x, top + 0.25, WALL_FRONT_Z)), Vector3(0.5, 0.18, 0.5), Color.WHITE)
		ellipsoid(tool("trim|" + key), Transform3D(Basis.IDENTITY, Vector3(x, top + 0.62, WALL_FRONT_Z)), Vector3.ONE * 0.3, 8, 12, vary(0.05))
		solid(Transform3D(Basis.IDENTITY, Vector3(x, (top + 0.9 + bottom) * 0.5, WALL_FRONT_Z)), Vector3(0.84, top + 0.9 - bottom, 0.84))
		torch(Vector3(x, base_height + 2.0, WALL_FRONT_Z + 0.42), side)
		gate_leaf(side, height)
	# Iron overthrow arch with a small cross between the pillar tops.
	var iron: SurfaceTool = tool("iron|" + chunk(gate_x, WALL_FRONT_Z))
	var previous: Vector3 = Vector3.ZERO
	for index: int in range(13):
		var t: float = float(index) / 12.0
		var x: float = lerpf(gate_x - GATE_HALF - 0.1, gate_x + GATE_HALF + 0.1, t)
		var point: Vector3 = Vector3(x, height + 2.75 + sin(t * PI) * 0.75, WALL_FRONT_Z)
		if index > 0:
			beam(iron, previous, point, 0.06, 0.06, Color.WHITE)
			beam(iron, previous + Vector3.DOWN * 0.22, point + Vector3.DOWN * 0.22, 0.035, 0.035, Color.WHITE)
		previous = point
	var apex: Vector3 = Vector3(gate_x, height + 3.5, WALL_FRONT_Z)
	beam(iron, apex, apex + Vector3.UP * 0.65, 0.05, 0.05, Color.WHITE)
	beam(iron, apex + Vector3(-0.22, 0.42, 0.0), apex + Vector3(0.22, 0.42, 0.0), 0.05, 0.05, Color.WHITE)

# One arched leaf hinged on a pillar, swung open into the yard (-z).
func gate_leaf(side: float, height: float) -> void:
	var iron: SurfaceTool = tool("iron|" + chunk(gate_x + side, WALL_FRONT_Z))
	var hinge: Vector3 = Vector3(gate_x + side * GATE_HALF, height, WALL_FRONT_Z)
	var swing: float = deg_to_rad(76.0 if side < 0.0 else 97.0)
	# Closed, a leaf reaches from its hinge toward the gate centre (-side along x).
	var closed: Vector3 = Vector3(-side, 0.0, 0.0)
	var reach: Vector3 = closed.rotated(Vector3.UP, side * swing)
	if reach.z > 0.0:
		reach = closed.rotated(Vector3.UP, -side * swing)
	var width: float = GATE_HALF - 0.04
	var top_points: Array[Vector3] = []
	var bars: int = 13
	for index: int in range(bars + 1):
		var t: float = float(index) / float(bars)
		var top: float = 1.85 + sin(t * PI * 0.5) * 0.7
		var base: Vector3 = hinge + reach * (t * width) + Vector3.UP * 0.12
		var tip: Vector3 = base + Vector3.UP * (top - 0.12)
		var thick: float = 0.055 if index % bars == 0 else 0.028
		beam(iron, base, tip, thick, thick, Color.WHITE)
		pyramid(iron, tip, 0.04, 0.16, 4, Color.WHITE)
		top_points.append(tip + Vector3.DOWN * 0.1)
	for index: int in range(bars):
		beam(iron, top_points[index], top_points[index + 1], 0.04, 0.04, Color.WHITE)
	for y: float in [0.16, 1.0]:
		beam(iron, hinge + Vector3.UP * y, hinge + reach * width + Vector3.UP * y, 0.045, 0.045, Color.WHITE)
	var middle: Vector3 = hinge + reach * (width * 0.5) + Vector3.UP * 1.45
	ring(iron, Transform3D(Basis.looking_at(reach.cross(Vector3.UP), Vector3.UP), middle), circle(Vector2.ZERO, 0.24, 14), circle(Vector2.ZERO, 0.2, 14), 0.035, Color.WHITE)
	solid(Transform3D(Basis.looking_at(reach, Vector3.UP), hinge + reach * (width * 0.5) + Vector3.UP * 1.2), Vector3(0.08, 2.3, width))

func torch(point: Vector3, side: float) -> void:
	var key: String = chunk(point.x, point.z)
	var iron: SurfaceTool = tool("iron|" + key)
	beam(iron, point + Vector3(0.0, -0.12, -0.02), point + Vector3(0.0, -0.12, 0.28), 0.05, 0.05, Color.WHITE)
	ring(iron, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), point + Vector3(0.0, -0.1, 0.3)), circle(Vector2.ZERO, 0.08, 10), circle(Vector2.ZERO, 0.06, 10), 0.04, Color.WHITE)
	var lean: Vector3 = Vector3(side * 0.12, 1.0, 0.28).normalized()
	var shaft_base: Vector3 = point + Vector3(0.0, -0.35, 0.3)
	var head: Vector3 = shaft_base + lean * 0.72
	cylinder(tool("wood|" + key), shaft_base, head, 0.035, 0.045, 7, Color(0.6, 0.55, 0.5))
	cylinder(tool("cloth|" + key), head - lean * 0.1, head + lean * 0.08, 0.07, 0.065, 8, Color.WHITE, Color.WHITE, true)
	flame(head + lean * 0.05, 0.36, 0.55, 1.0, 0.9)
	flame(head + lean * 0.1 + Vector3(0.03, 0, 0.02), 0.24, 0.42, 0.85, 1.0)
	lamp(head + Vector3.UP * 0.35, Color(1.0, 0.55, 0.22), 1.3, 6.5, 1.0)

# --- Graves --------------------------------------------------------------------------------

func reserve_features() -> void:
	for site: Vector2 in OPEN_GRAVES:
		reserved.append(Vector3(site.x, site.y, 2.2))
	for site: Vector2 in FRESH_MOUNDS:
		reserved.append(Vector3(site.x, site.y, 2.0))
	reserved.append(Vector3(FIRE.x, FIRE.y, 1.7))
	reserved.append(Vector3(FIGURE.x, FIGURE.y, 1.2))
	reserved.append(Vector3(CROW_STONE.x, CROW_STONE.y, 1.3))
	reserved.append(Vector3(CROSS_STONE.x, CROSS_STONE.y, 1.3))
	reserved.append(Vector3(MONUMENT.x, MONUMENT.y, 1.8))
	for tree: Vector3 in TALL_TREES:
		reserved.append(Vector3(tree.x, tree.y, 1.4))
	for stone: Vector3 in BOULDERS:
		reserved.append(Vector3(stone.x, stone.y, stone.z + 0.8))
	for patch: Vector3 in EMBERS:
		reserved.append(Vector3(patch.x, patch.y, patch.z + 0.3))

func grave_site_clear(x: float, z: float) -> bool:
	if x < WALL_WEST_X + 1.0 or x > WALL_EAST_X - 1.0 or z < WALL_BACK_Z + 1.0 or z > WALL_FRONT_Z - 2.4:
		return false
	for along: float in [0.0, 1.0, 2.0]:
		if absf(x - ChurchSite.road_x(z + along)) < 1.95:
			return false
	if x > ChurchSite.DOOR.x - PODIUM_HALF - 1.2 and x < ChurchSite.DOOR.x + PODIUM_HALF + 1.2 and z < -106.4:
		return false
	for site: Vector3 in reserved:
		if Vector2(x, z).distance_to(Vector2(site.x, site.y)) < site.z or Vector2(x, z + 1.0).distance_to(Vector2(site.x, site.y)) < site.z:
			return false
	return true

# Rows of tilted markers with lanes between them. Markers carry no collision so the villagers'
# leaps and grid stay open; only the monument, boulders, trees and walls block.
func build_graves() -> void:
	headstone(CROW_STONE.x, CROW_STONE.y, 0, 0.72, 1.3, Vector3(-0.06, 0.45, 0.05))
	crow_perch(CROW_STONE.x, CROW_STONE.y, 0.45, 1.3)
	headstone(CROSS_STONE.x, CROSS_STONE.y, 3, 0.68, 1.38, Vector3(0.08, -0.3, 0.26))
	grave_plot(CROSS_STONE.x, CROSS_STONE.y, -0.3, 1)
	monument()
	var count: int = 0
	for row: int in range(6):
		var row_z: float = -91.9 - float(row) * 3.1
		for column: int in range(14):
			var x: float = -19.0 + float(column) * 2.35 + random.randf_range(-0.35, 0.35)
			var z: float = row_z + random.randf_range(-0.45, 0.45)
			if random.randf() < 0.1 or not grave_site_clear(x, z):
				continue
			var tilt: Vector3 = Vector3(random.randf_range(-0.2, 0.16), random.randf_range(-0.16, 0.16), random.randf_range(-0.14, 0.14))
			if random.randf() < 0.25:
				tilt.z *= 2.0
			headstone(x, z, random.randi_range(0, 6), random.randf_range(0.5, 0.78), random.randf_range(0.65, 1.2), tilt)
			grave_plot(x, z, tilt.y, random.randi_range(0, 4))
			count += 1
	for index: int in range(OPEN_GRAVES.size()):
		open_grave(OPEN_GRAVES[index], index == 2)
	for site: Vector2 in FRESH_MOUNDS:
		fresh_mound(site)
	scatter_grass()
	print("CHURCH_GRAVES: ", count + 3, " markers, ", OPEN_GRAVES.size(), " open graves, ", FRESH_MOUNDS.size(), " disturbed mounds")

# Loose dead grass and reeds across the yard, off the path, terrace and open pits.
func scatter_grass() -> void:
	var placed: int = 0
	while placed < 220:
		var x: float = random.randf_range(WALL_WEST_X + 0.6, WALL_EAST_X - 0.6)
		var z: float = random.randf_range(WALL_BACK_Z + 0.6, WALL_FRONT_Z - 0.6)
		placed += 1
		if absf(x - ChurchSite.road_x(z)) < 1.3:
			continue
		if x > ChurchSite.DOOR.x - PODIUM_HALF - 0.3 and x < ChurchSite.DOOR.x + PODIUM_HALF + 0.3 and z < ChurchSite.DOOR.y + PODIUM_FRONT + 2.6:
			continue
		var pit: bool = false
		for site: Vector2 in OPEN_GRAVES:
			pit = pit or absf(x - site.x) < 0.8 and absf(z - site.y) < 1.3
		if not pit:
			grass_at(x, z, random.randf_range(0.8, 1.5), random.randf() < 0.25)

# Kinds: 0 round slab, 1 pointed slab, 2 shouldered slab, 3 stone cross, 4 broken slab,
# 5 small obelisk, 6 crude wooden cross.
func headstone(x: float, z: float, kind: int, width: float, height: float, tilt: Vector3) -> Transform3D:
	var key: String = chunk(x, z)
	var surface: SurfaceTool = tool("grave|" + key)
	var lichen: Color = vary(0.18, Color(0.95, 1.0, 0.92) if random.randf() < 0.4 else Color(1.0, 0.97, 0.93))
	var marker: Transform3D = Transform3D(Basis.from_euler(tilt), Vector3(x, ground(x, z) - 0.04, z))
	var thickness: float = random.randf_range(0.11, 0.17)
	var w: float = width * 0.5
	match kind:
		0:
			var outline: PackedVector2Array = PackedVector2Array([Vector2(-w, -0.45), Vector2(w, -0.45)])
			for index: int in range(13):
				var angle: float = PI * float(index) / 12.0
				outline.append(Vector2(cos(angle) * w, height - w + sin(angle) * w))
			extrude(surface, marker, outline, thickness, lichen)
		1:
			extrude(surface, marker, lancet(w, -0.45, height - w * 1.1, 1.5, 10), thickness, lichen)
		2:
			extrude(surface, marker, PackedVector2Array([Vector2(-w, -0.45), Vector2(w, -0.45), Vector2(w, height * 0.84), Vector2(w * 0.3, height * 0.9), Vector2(0.0, height), Vector2(-w * 0.3, height * 0.9), Vector2(-w, height * 0.84)]), thickness, lichen)
		3:
			var s: float = 0.075
			var c: float = height * 0.7
			var arm: float = maxf(w * 0.8, 0.26)
			extrude(surface, marker, PackedVector2Array([Vector2(-s, -0.45), Vector2(s, -0.45), Vector2(s, c - s), Vector2(arm, c - s), Vector2(arm, c + s), Vector2(s, c + s), Vector2(s, height), Vector2(-s, height), Vector2(-s, c + s), Vector2(-arm, c + s), Vector2(-arm, c - s), Vector2(-s, c - s)]), 0.14, lichen)
			if random.randf() < 0.5:
				ring(surface, marker * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.035)), circle(Vector2(0.0, c), arm * 0.72, 16), circle(Vector2(0.0, c), arm * 0.58, 16), 0.07, lichen)
		4:
			extrude(surface, marker, PackedVector2Array([Vector2(-w, -0.45), Vector2(w, -0.45), Vector2(w, height * 0.55), Vector2(w * 0.25, height * 0.72), Vector2(0.0, height * 0.5), Vector2(-w * 0.2, height * 0.64), Vector2(-w, height * 0.42)]), thickness + 0.03, lichen)
		5:
			var bottom: PackedVector3Array = PackedVector3Array()
			var top: PackedVector3Array = PackedVector3Array()
			var tip: PackedVector3Array = PackedVector3Array()
			for corner: int in range(4):
				var angle: float = PI * 0.25 + PI * 0.5 * float(corner)
				bottom.append(marker * Vector3(cos(angle) * 0.2, -0.45, sin(angle) * 0.2))
				top.append(marker * Vector3(cos(angle) * 0.13, height * 0.85, sin(angle) * 0.13))
				tip.append(marker * Vector3(0.0, height * 1.05, 0.0))
			prism(surface, bottom, top, lichen)
			prism(surface, top, tip, lichen)
			box(surface, marker, Vector3(0.52, 0.26, 0.52), lichen)
		_:
			var wood: SurfaceTool = tool("wood|" + key)
			box(wood, marker * Transform3D(Basis.IDENTITY, Vector3(0.0, (height - 0.4) * 0.5, 0.0)), Vector3(0.09, height + 0.4, 0.07), vary(0.15))
			box(wood, marker * Transform3D(Basis(Vector3.BACK, random.randf_range(-0.15, 0.15)), Vector3(0.0, height * 0.72, 0.0)), Vector3(w * 1.4, 0.08, 0.07), vary(0.15))
	if kind <= 2 and random.randf() < 0.5:
		box(surface, Transform3D(Basis(Vector3.UP, tilt.y), Vector3(x, ground(x, z) + 0.02, z)), Vector3(width + 0.2, 0.22, thickness + 0.24), lichen * Color(0.9, 0.9, 0.9))
	for tuft: int in range(random.randi_range(2, 4)):
		var angle: float = random.randf_range(0.0, TAU)
		var reach: float = random.randf_range(0.25, 0.55)
		grass_at(x + cos(angle) * reach, z + sin(angle) * reach * 0.6, random.randf_range(0.7, 1.25), random.randf() < 0.15)
	return marker

# The plot in front (+z) of a marker: 1 kerbs, 2 an old mound, 3 both, 4 overgrown, 0 bare.
func grave_plot(x: float, z: float, yaw: float, style: int) -> void:
	var key: String = chunk(x, z)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var center: Vector3 = Vector3(x, 0.0, z) + basis * Vector3(0.0, 0.0, 1.1)
	if style == 1 or style == 3:
		for edge: int in range(4):
			var along_z: bool = edge < 2
			var offset: Vector3 = basis * (Vector3(-0.45 if edge == 0 else 0.45, 0.0, 0.0) if along_z else Vector3(0.0, 0.0, -0.92 if edge == 2 else 0.92))
			var middle: Vector3 = center + offset
			var length: float = 1.84 if along_z else 0.9
			var axis: Vector3 = basis * (Vector3.BACK if along_z else Vector3.RIGHT)
			var start: Vector3 = middle - axis * length * 0.5
			var finish: Vector3 = middle + axis * length * 0.5
			start.y = ground(start.x, start.z) + 0.05
			finish.y = ground(finish.x, finish.z) + 0.05
			beam(tool("grave|" + key), start, finish, 0.11, 0.32, vary(0.1))
	if style == 2 or style == 3:
		var mound: Transform3D = Transform3D(basis, Vector3(center.x, ground(center.x, center.z) - 0.12, center.z))
		ellipsoid(tool("earth|" + key), mound, Vector3(0.42, 0.34, 0.95), 5, 12, vary(0.12, Color(0.8, 0.72, 0.62)), 0.12, false, -0.2)
	elif style == 4:
		for tuft: int in range(3):
			grass_at(center.x + random.randf_range(-0.3, 0.3), center.z + random.randf_range(-0.7, 0.7), random.randf_range(0.8, 1.3), false)

# A tall stepped obelisk: the one marker big enough to block, kept away from the spawn graves.
func monument() -> void:
	var key: String = chunk(MONUMENT.x, MONUMENT.y)
	var stone: SurfaceTool = tool("grave|" + key)
	var height: float = ground(MONUMENT.x, MONUMENT.y)
	var lean: Basis = Basis(Vector3.BACK, 0.06) * Basis(Vector3.UP, 0.2)
	for step: int in range(2):
		var size: float = 1.5 - float(step) * 0.45
		box(stone, Transform3D(lean, Vector3(MONUMENT.x, height - 0.25 + float(step) * 0.38, MONUMENT.y)), Vector3(size, 0.6, size), vary(0.06))
	var base: Vector3 = Vector3(MONUMENT.x, height + 0.45, MONUMENT.y)
	var bottom: PackedVector3Array = PackedVector3Array()
	var top: PackedVector3Array = PackedVector3Array()
	var tip: PackedVector3Array = PackedVector3Array()
	for corner: int in range(4):
		var angle: float = PI * 0.25 + PI * 0.5 * float(corner)
		bottom.append(base + lean * Vector3(cos(angle) * 0.36, 0.0, sin(angle) * 0.36))
		top.append(base + lean * Vector3(cos(angle) * 0.22, 2.3, sin(angle) * 0.22))
		tip.append(base + lean * Vector3(0.0, 2.75, 0.0))
	prism(stone, bottom, top, vary(0.06))
	prism(stone, top, tip, vary(0.06))
	solid(Transform3D(Basis(Vector3.UP, 0.2), Vector3(MONUMENT.x, height + 1.3, MONUMENT.y)), Vector3(1.4, 2.8, 1.4))
	for tuft: int in range(6):
		var angle: float = random.randf_range(0.0, TAU)
		grass_at(MONUMENT.x + cos(angle) * 0.95, MONUMENT.y + sin(angle) * 0.95, 1.2, random.randf() < 0.3)

# An open grave on a villager spawn point: a ray-marched pit, spoil heap and leaning cross.
func open_grave(site: Vector2, candles: bool) -> void:
	var key: String = chunk(site.x, site.y)
	var highest: float = -INF
	for corner: Vector2 in [Vector2(-0.6, -1.15), Vector2(0.6, -1.15), Vector2(0.6, 1.15), Vector2(-0.6, 1.15), Vector2.ZERO]:
		highest = maxf(highest, ground(site.x + corner.x, site.y + corner.y))
	var level: float = highest + 0.035
	var pit: MeshInstance3D = MeshInstance3D.new()
	pit.name = "OpenGrave"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(0.9, 1.96)
	pit.mesh = plane
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADERS + "church_pit.gdshader") as Shader
	material.set_shader_parameter("earth_map", load(GENERATED + "soil_gravel.png"))
	pit.material_override = material
	pit.position = Vector3(site.x, level, site.y)
	add_child(pit)
	# A berm of loose earth slopes from the pit edge down to the terrain, hiding the seam.
	var earth: SurfaceTool = tool("earth|" + key)
	var edge_loop: PackedVector2Array = PackedVector2Array()
	for index: int in range(20):
		var angle: float = TAU * float(index) / 20.0
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var reach: float = minf(0.45 / maxf(absf(direction.x), 0.001), 0.98 / maxf(absf(direction.y), 0.001))
		edge_loop.append(direction * reach)
	for index: int in range(edge_loop.size()):
		var p: Vector2 = edge_loop[index]
		var q: Vector2 = edge_loop[(index + 1) % edge_loop.size()]
		var p_out: Vector2 = p + p.normalized() * random.randf_range(0.4, 0.6)
		var q_out: Vector2 = q + q.normalized() * random.randf_range(0.4, 0.6)
		var a: Vector3 = Vector3(site.x + p.x, level + 0.06, site.y + p.y)
		var b: Vector3 = Vector3(site.x + q.x, level + 0.06, site.y + q.y)
		var c: Vector3 = Vector3(site.x + q_out.x, ground(site.x + q_out.x, site.y + q_out.y) - 0.04, site.y + q_out.y)
		var d: Vector3 = Vector3(site.x + p_out.x, ground(site.x + p_out.x, site.y + p_out.y) - 0.04, site.y + p_out.y)
		quad(earth, a, b, c, d, Vector3(p.x + q.x, 1.5, p.y + q.y), Color(0.75, 0.68, 0.6))
		quad(earth, a, b, b + Vector3.DOWN * 0.12, a + Vector3.DOWN * 0.12, -Vector3(p.x + q.x, 0.0, p.y + q.y), Color(0.45, 0.4, 0.35))
	var heap: Vector3 = Vector3(site.x + 1.25, ground(site.x + 1.25, site.y) - 0.15, site.y + 0.1)
	ellipsoid(earth, Transform3D(Basis(Vector3.UP, 0.15), heap), Vector3(0.62, 0.62, 1.15), 6, 14, Color(0.85, 0.76, 0.66), 0.22, false, -0.25)
	var wood: SurfaceTool = tool("wood|" + key)
	cylinder(wood, heap + Vector3(-0.1, 0.25, 0.3), heap + Vector3(0.1, 1.45, 0.55), 0.025, 0.022, 6, Color(0.7, 0.65, 0.6))
	box(tool("iron|" + key), Transform3D(Basis(Vector3.RIGHT, 0.2) * Basis(Vector3.BACK, -0.16), heap + Vector3(-0.12, 0.2, 0.27)), Vector3(0.22, 0.3, 0.02), Color.WHITE)
	box(wood, Transform3D(Basis(Vector3.BACK, 0.35), Vector3(site.x - 0.15, level + 0.55, site.y - 1.35)), Vector3(0.08, 1.3, 0.07), vary(0.15))
	box(wood, Transform3D(Basis(Vector3.BACK, 0.35), Vector3(site.x - 0.03, level + 0.82, site.y - 1.35)), Vector3(0.55, 0.07, 0.07), vary(0.15))
	for index: int in range(3):
		grass_at(site.x + random.randf_range(-1.0, 1.0) * 1.3, site.y + random.randf_range(-1.6, 1.6), 1.1, true)
	if candles:
		for index: int in range(7):
			var angle: float = TAU * float(index) / 7.0 + random.randf_range(-0.2, 0.2)
			var point: Vector2 = site + Vector2(cos(angle) * 0.85, sin(angle) * 1.4)
			candle(Vector3(point.x, ground(point.x, point.y), point.y))
		lamp(Vector3(site.x, highest + 0.9, site.y + 0.3), Color(1.0, 0.6, 0.28), 1.3, 4.2, 0.7)

# Freshly broken earth on a spawn point: clods heaped and scattered, a marker knocked askew.
func fresh_mound(site: Vector2) -> void:
	var key: String = chunk(site.x, site.y)
	var earth: SurfaceTool = tool("earth|" + key)
	ellipsoid(earth, Transform3D(Basis(Vector3.UP, random.randf_range(-0.2, 0.2)), Vector3(site.x, ground(site.x, site.y) - 0.18, site.y)), Vector3(0.6, 0.38, 1.1), 6, 14, Color(0.8, 0.7, 0.6), 0.35, false, -0.3)
	for clod: int in range(9):
		var angle: float = random.randf_range(0.0, TAU)
		var reach: float = random.randf_range(0.7, 1.6)
		var point: Vector2 = site + Vector2(cos(angle) * reach, sin(angle) * reach)
		var size: float = random.randf_range(0.08, 0.2)
		ellipsoid(earth, Transform3D(Basis(Vector3.UP, angle), Vector3(point.x, ground(point.x, point.y) - size * 0.3, point.y)), Vector3(size, size * 0.7, size * 1.2), 3, 6, Color(0.7, 0.62, 0.55), 0.4, true)
	headstone(site.x + random.randf_range(-0.2, 0.2), site.y - 1.35, random.randi_range(0, 2), 0.6, 0.85, Vector3(random.randf_range(-0.42, -0.25), random.randf_range(-0.3, 0.3), random.randf_range(-0.3, 0.3)))

# --- Trees ---------------------------------------------------------------------------------

func build_trees() -> void:
	for index: int in range(TALL_TREES.size()):
		var tree: Vector3 = TALL_TREES[index]
		dead_tree(Vector3(tree.x, ground(tree.x, tree.y), tree.y), tree.z, 0.0, 7101 + index * 31)
	for index: int in range(GATE_TREES.size()):
		var tree: Vector3 = GATE_TREES[index]
		dead_tree(Vector3(tree.x, ground(tree.x, tree.y), tree.y), tree.z, 1.0, 9203 + index * 17)

# Tall, thin, bare trees with broken limbs; gnarl > 0 makes shorter, twisted gate trees.
func dead_tree(base: Vector3, height: float, gnarl: float, seed_value: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var key: String = chunk(base.x, base.z) if base.z > -112.0 else "church"
	var bark: SurfaceTool = tool("bark|" + key)
	var trunk: Array[Vector3] = [base + Vector3.DOWN * 0.6]
	var lean: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.04, 0.12 + gnarl * 0.1)
	var direction: Vector3 = Vector3.UP
	var segments: int = 8
	for index: int in range(segments):
		direction = (direction + lean + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * (0.1 + gnarl * 0.22)).normalized()
		trunk.append(trunk[trunk.size() - 1] + direction * ((height + 0.6) / float(segments)))
	var root_radius: float = 0.16 + height * 0.012 + gnarl * 0.12
	for index: int in range(segments):
		var r0: float = lerpf(root_radius, 0.03, pow(float(index) / float(segments), 0.8))
		var r1: float = lerpf(root_radius, 0.03, pow(float(index + 1) / float(segments), 0.8))
		var shade: Color = Color.WHITE * (0.8 + 0.03 * float(index))
		cylinder(bark, trunk[index], trunk[index + 1], r0 * (1.25 if index == 0 else 1.0), r1, 9, shade)
	for root: int in range(5):
		var angle: float = TAU * float(root) / 5.0 + rng.randf_range(-0.3, 0.3)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		cylinder(bark, base + Vector3.UP * 0.5 + out * root_radius * 0.3, base + out * (root_radius * 4.0 + rng.randf_range(0.0, 0.4)) + Vector3.DOWN * 0.25, root_radius * 0.55, 0.03, 6, Color(0.75, 0.75, 0.75))
	var limbs: int = 7 + int(gnarl * 3.0) + rng.randi_range(0, 2)
	for limb: int in range(limbs):
		var t: float = rng.randf_range(0.28, 0.93)
		var along: float = t * float(segments)
		var segment: int = mini(int(along), segments - 1)
		var start: Vector3 = trunk[segment].lerp(trunk[segment + 1], along - float(segment))
		var azimuth: float = rng.randf_range(0.0, TAU)
		var rise: float = rng.randf_range(0.35, 1.05) if gnarl < 0.5 else rng.randf_range(-0.05, 0.55)
		var heading: Vector3 = Vector3(cos(azimuth) * cos(rise), sin(rise), sin(azimuth) * cos(rise))
		var length: float = height * rng.randf_range(0.16, 0.34) * (1.15 - t * 0.55) * (1.0 + gnarl * 0.4)
		var radius: float = lerpf(root_radius, 0.03, t) * 0.6
		var broken: bool = rng.randf() < 0.3
		if broken:
			length *= rng.randf_range(0.2, 0.45)
		limb_branch(bark, key, start, heading, length, radius, 0, broken, gnarl, rng)
	if base.z > -112.0:
		post_shape(base + Vector3.DOWN * 0.2, root_radius, 3.2)
	for tuft: int in range(6):
		var angle: float = rng.randf_range(0.0, TAU)
		grass_at(base.x + cos(angle) * rng.randf_range(0.4, 1.1), base.z + sin(angle) * rng.randf_range(0.4, 1.1), rng.randf_range(0.9, 1.4), rng.randf() < 0.4)

func limb_branch(bark: SurfaceTool, key: String, start: Vector3, heading: Vector3, length: float, radius: float, depth: int, broken: bool, gnarl: float, rng: RandomNumberGenerator) -> void:
	var points: Array[Vector3] = [start]
	var direction: Vector3 = heading
	var pieces: int = 3
	for index: int in range(pieces):
		direction = (direction + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.4), rng.randf_range(-1.0, 1.0)) * (0.22 + gnarl * 0.3)).normalized()
		points.append(points[points.size() - 1] + direction * (length / float(pieces)))
	var tip_radius: float = radius * 0.65 if broken else maxf(radius * 0.25, 0.012)
	for index: int in range(pieces):
		var r0: float = lerpf(radius, tip_radius, float(index) / float(pieces))
		var r1: float = lerpf(radius, tip_radius, float(index + 1) / float(pieces))
		cylinder(bark, points[index], points[index + 1], r0, r1, 6 if depth == 0 else 5, Color(0.85, 0.84, 0.8), Color(0.85, 0.84, 0.8), broken and index == pieces - 1)
		if depth < 2 and length > 1.0 and rng.randf() < 0.3:
			moss_strand(key, points[index + 1], rng.randf_range(0.5, 2.0), rng)
	if broken:
		var end: Vector3 = points[pieces]
		cylinder(bark, end, end + direction * 0.12 + Vector3(rng.randf_range(-0.04, 0.04), 0.05, 0.0), tip_radius, tip_radius * 0.2, 5, Color(0.6, 0.58, 0.55))
		return
	if depth >= 2:
		return
	for child: int in range(rng.randi_range(1, 3 - depth)):
		var from: int = rng.randi_range(1, pieces)
		var side: Vector3 = direction.cross(Vector3.UP)
		side = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
		var turn: Vector3 = (direction + side * rng.randf_range(-1.1, 1.1) + Vector3.UP * rng.randf_range(-0.1, 0.6)).normalized()
		var child_broken: bool = rng.randf() < 0.22
		var child_length: float = length * rng.randf_range(0.45, 0.7) * (0.4 if child_broken else 1.0)
		limb_branch(bark, key, points[from], turn, child_length, maxf(lerpf(radius, tip_radius, float(from) / float(pieces)) * 0.62, 0.012), depth + 1, child_broken, gnarl, rng)

# Long drooping strands of dead moss: two crossed ribbons that sway at their free end.
func moss_strand(key: String, anchor: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	var surface: SurfaceTool = tool("strand|" + key)
	var color: Color = Color(0.11, 0.12, 0.09) * rng.randf_range(0.7, 1.3)
	var drift: Vector3 = Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	for plane: int in range(2):
		var across: Vector3 = Vector3.RIGHT if plane == 0 else Vector3.BACK
		var normal: Vector3 = across.cross(Vector3.UP)
		var previous: Vector3 = anchor
		var previous_width: float = 0.07
		for segment: int in range(1, 6):
			var t: float = float(segment) / 5.0
			var point: Vector3 = anchor + Vector3.DOWN * (length * t) + drift * sin(t * PI) + Vector3(sin(t * 7.0 + anchor.x) * 0.03, 0.0, 0.0)
			var width: float = lerpf(0.07, 0.012, t)
			var a0: Color = Color(color.r, color.g, color.b, t - 0.2)
			var a1: Color = Color(color.r, color.g, color.b, t)
			smooth(surface, [previous - across * previous_width, previous + across * previous_width, point + across * width], [normal, normal, normal], [a0, a0, a1])
			smooth(surface, [previous - across * previous_width, point + across * width, point - across * width], [normal, normal, normal], [a0, a1, a1])
			previous = point
			previous_width = width

# --- Props: figure, crow, boulders, fire, candles ------------------------------------------

func build_props() -> void:
	cloaked_figure()
	for stone: Vector3 in BOULDERS:
		var key: String = chunk(stone.x, stone.y)
		var center: Vector3 = Vector3(stone.x, ground(stone.x, stone.y) + stone.z * 0.15, stone.y)
		ellipsoid(tool("grave|" + key), Transform3D(Basis(Vector3.UP, random.randf_range(0.0, TAU)), center), Vector3(stone.z * 1.2, stone.z * 0.75, stone.z), 6, 10, vary(0.1, Color(0.85, 0.9, 0.82)), 0.35, true)
		post_shape(center + Vector3.DOWN * stone.z * 0.5, stone.z * 0.9, stone.z * 1.3)
		for tuft: int in range(4):
			var angle: float = random.randf_range(0.0, TAU)
			grass_at(stone.x + cos(angle) * stone.z * 1.3, stone.y + sin(angle) * stone.z * 1.2, 1.2, random.randf() < 0.3)
	# A small grave fire in a ring of stones.
	var fire_key: String = chunk(FIRE.x, FIRE.y)
	var fire_ground: float = ground(FIRE.x, FIRE.y)
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0 + random.randf_range(-0.15, 0.15)
		var point: Vector3 = Vector3(FIRE.x + cos(angle) * 0.62, fire_ground + 0.04, FIRE.y + sin(angle) * 0.62)
		ellipsoid(tool("grave|" + fire_key), Transform3D(Basis(Vector3.UP, angle), point), Vector3(0.2, 0.14, 0.16), 4, 7, vary(0.15, Color(0.6, 0.58, 0.55)), 0.3, true)
	for index: int in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5 + random.randf_range(-0.3, 0.3)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		cylinder(tool("bark|" + fire_key), Vector3(FIRE.x, fire_ground + 0.32, FIRE.y) + out * 0.08, Vector3(FIRE.x, fire_ground + 0.04, FIRE.y) + out * 0.55, 0.05, 0.06, 6, Color(0.18, 0.15, 0.13))
	for index: int in range(4):
		var offset: Vector3 = Vector3(random.randf_range(-0.16, 0.16), 0.05, random.randf_range(-0.16, 0.16))
		flame(Vector3(FIRE.x, fire_ground, FIRE.y) + offset, random.randf_range(0.35, 0.55), random.randf_range(0.55, 0.95), random.randf_range(0.8, 1.0), 1.0)
	lamp(Vector3(FIRE.x, fire_ground + 0.8, FIRE.y), Color(1.0, 0.5, 0.2), 1.8, 6.0, 1.0)

# A faceless hooded watcher just inside the gate, turned toward the road.
func cloaked_figure() -> void:
	var key: String = chunk(FIGURE.x, FIGURE.y)
	var cloth: SurfaceTool = tool("cloth|" + key)
	var base: Vector3 = Vector3(FIGURE.x, ground(FIGURE.x, FIGURE.y) - 0.04, FIGURE.y)
	var toward: Vector3 = Vector3(gate_x - FIGURE.x, 0.0, WALL_FRONT_Z - FIGURE.y).normalized()
	var body: Transform3D = Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.z)), base)
	var robe: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.42, 0.05), Vector2(0.36, 0.4), Vector2(0.3, 0.85), Vector2(0.27, 1.15), Vector2(0.26, 1.33), Vector2(0.22, 1.45), Vector2(0.14, 1.53), Vector2(0.0, 1.56)])
	lathe(cloth, body, robe, 18, Color.WHITE, 9, 0.07)
	ellipsoid(cloth, body * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)), Vector3(0.27, 0.13, 0.18), 6, 14, Color.WHITE)
	var hood: Transform3D = body * Transform3D(Basis(Vector3.BACK, 0.2) * Basis(Vector3.RIGHT, 0.18), Vector3(0.0, 1.62, -0.02))
	ellipsoid(cloth, hood, Vector3(0.17, 0.21, 0.2), 8, 14, Color.WHITE)
	pyramid(cloth, hood * Vector3(0.0, 0.14, -0.1), 0.08, 0.16, 6, Color.WHITE, 0.0, Vector3(0.0, -0.02, -0.12))
	var face: Transform3D = hood * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.02, 0.135))
	ellipsoid(tool("void|" + key), face, Vector3(0.105, 0.14, 0.08), 6, 12, Color.WHITE)
	ring(cloth, face * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.04)), circle(Vector2.ZERO, 0.15, 14), circle(Vector2.ZERO, 0.105, 14), 0.05, Color.WHITE)
	post_shape(base, 0.34, 1.8)

func crow_perch(x: float, z: float, yaw: float, height: float) -> void:
	var stone: Transform3D = Transform3D(Basis.from_euler(Vector3(-0.06, yaw, 0.05)), Vector3(x, ground(x, z) - 0.04, z))
	crow_rest = stone * Vector3(0.0, height, 0.0)
	crow_body = Node3D.new()
	crow_body.name = "Crow"
	add_child(crow_body)
	crow_body.position = crow_rest
	crow_body.rotation.y = yaw + PI * 0.5
	var body: SurfaceTool = SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	ellipsoid(body, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.0, 0.13, 0.0)), Vector3(0.075, 0.075, 0.15), 6, 10, Color.WHITE)
	for side: float in [-1.0, 1.0]:
		ellipsoid(body, Transform3D(Basis(Vector3.RIGHT, -0.4) * Basis(Vector3.BACK, side * 0.15), Vector3(side * 0.055, 0.14, -0.03)), Vector3(0.03, 0.07, 0.15), 4, 8, Color.WHITE)
		cylinder(body, Vector3(side * 0.025, 0.07, 0.0), Vector3(side * 0.03, 0.0, 0.01), 0.008, 0.007, 4, Color.WHITE)
	var tail: PackedVector3Array = PackedVector3Array([Vector3(-0.03, 0.12, -0.12), Vector3(0.03, 0.12, -0.12), Vector3(0.06, 0.06, -0.32), Vector3(-0.06, 0.06, -0.32)])
	quad(body, tail[0], tail[1], tail[2], tail[3], Vector3.UP, Color.WHITE)
	quad(body, tail[0], tail[1], tail[2], tail[3], Vector3.DOWN, Color.WHITE)
	var body_visual: MeshInstance3D = MeshInstance3D.new()
	body_visual.mesh = body.commit()
	body_visual.material_override = materials["crow"]
	crow_body.add_child(body_visual)
	crow_head = Node3D.new()
	crow_head.position = Vector3(0.0, 0.23, 0.11)
	crow_body.add_child(crow_head)
	var head: SurfaceTool = SurfaceTool.new()
	head.begin(Mesh.PRIMITIVE_TRIANGLES)
	ellipsoid(head, Transform3D.IDENTITY, Vector3(0.05, 0.05, 0.06), 6, 10, Color.WHITE)
	# The beak is a four-sided spike pointing forward (+z).
	var beak_base: PackedVector3Array = PackedVector3Array([Vector3(-0.018, -0.02, 0.04), Vector3(0.018, -0.02, 0.04), Vector3(0.018, 0.01, 0.04), Vector3(-0.018, 0.01, 0.04)])
	var beak_tip: PackedVector3Array = PackedVector3Array()
	for corner: int in range(4):
		beak_tip.append(Vector3(0.0, -0.012, 0.12))
	prism(head, beak_base, beak_tip, Color.WHITE)
	var head_visual: MeshInstance3D = MeshInstance3D.new()
	head_visual.mesh = head.commit()
	head_visual.material_override = materials["crow"]
	crow_head.add_child(head_visual)

func candle(point: Vector3) -> void:
	var key: String = chunk(point.x, point.z) if point.z > -109.5 else "church"
	var wax: SurfaceTool = tool("wax|" + key)
	var height: float = random.randf_range(0.07, 0.26)
	var radius: float = random.randf_range(0.022, 0.04)
	var lean: Vector3 = Vector3(random.randf_range(-0.06, 0.06), 1.0, random.randf_range(-0.06, 0.06)).normalized()
	cylinder(wax, point + Vector3.DOWN * 0.01, point + lean * height, radius, radius * 0.92, 8, vary(0.06), vary(0.06), true)
	cylinder(wax, point + Vector3.DOWN * 0.005, point + Vector3.UP * 0.012, radius * 1.9, radius * 1.4, 8, vary(0.06), vary(0.06), true)
	flame(point + lean * (height + 0.008), 0.045, 0.11, random.randf_range(0.7, 1.0), 0.4)

func candle_cluster(point: Vector3, count: int, spread: float) -> void:
	for index: int in range(count):
		var angle: float = random.randf_range(0.0, TAU)
		var reach: float = random.randf_range(0.0, spread)
		candle(Vector3(point.x + cos(angle) * reach, point.y, point.z + sin(angle) * reach))

func flame(point: Vector3, width: float, height: float, brightness: float, sway: float) -> void:
	flames.append(Transform3D(Basis.IDENTITY.scaled(Vector3(width, height, width)), point))
	flame_colors.append(Color(random.randf(), brightness, sway, 1.0))

func grass_at(x: float, z: float, size: float, reed: bool) -> void:
	var placement: Transform3D = Transform3D(Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3.ONE * size), Vector3(x, ground(x, z) - 0.03, z))
	if reed:
		reeds.append(placement)
	else:
		tufts.append(placement)

# --- Ground: dark earth, flagstone path, ember cracks, mist ---------------------------------

func build_ground_layers() -> void:
	# Terrain-following sheets exactly on the landscape's 3 m triangles.
	var earth: ShaderMaterial = ShaderMaterial.new()
	earth.shader = load(SHADERS + "church_ground.gdshader") as Shader
	earth.set_shader_parameter("dirt_map", load(GENERATED + "soil_gravel.png"))
	earth.set_shader_parameter("earth_map", load(GENERATED + "mineral_earth.png"))
	# Reaches past the gate so the pillar torches' light pools fall on it, not on the landscape
	# mesh, which already spends its Mobile per-mesh light slots on the village lamps.
	earth.set_shader_parameter("region", Vector4(-22.0, -113.0, 14.0, -83.0))
	for half: int in range(2):
		var sheet: MeshInstance3D = terrain_sheet(-24, 15, -114 if half == 0 else -99, -99 if half == 0 else -81, 0.03)
		sheet.name = "YardEarth"
		sheet.material_override = earth
	var mist_shader: Shader = load(SHADERS + "church_mist.gdshader") as Shader
	var layers: Array[Vector2] = [Vector2(0.3, 0.42), Vector2(0.72, 0.3), Vector2(1.15, 0.18)]
	for index: int in range(layers.size()):
		var mist: ShaderMaterial = ShaderMaterial.new()
		mist.shader = mist_shader
		mist.set_shader_parameter("density", layers[index].y)
		mist.set_shader_parameter("layer", float(index))
		mist.render_priority = index
		for half: int in range(2):
			var sheet: MeshInstance3D = terrain_sheet(-24, 15, -117 if half == 0 else -99, -99 if half == 0 else -84, layers[index].x)
			sheet.name = "GroundMist"
			sheet.material_override = mist
			sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flagstones()
	var embers: ShaderMaterial = ShaderMaterial.new()
	embers.shader = load(SHADERS + "church_embers.gdshader") as Shader
	for patch: Vector3 in EMBERS:
		ember_patch(Vector2(patch.x, patch.y), patch.z, embers)
	lamp(Vector3(EMBERS[0].x, ground(EMBERS[0].x, EMBERS[0].y) + 0.45, EMBERS[0].y), Color(1.0, 0.36, 0.08), 1.1, 4.5, 0.45)

func terrain_sheet(x0: int, x1: int, z0: int, z1: int, lift: float) -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x: int = x0
	while x < x1:
		var z: int = z0
		while z < z1:
			var a: Vector3 = Vector3(x, ground(x, z) + lift, z)
			var b: Vector3 = Vector3(x + 3, ground(x + 3, z) + lift, z)
			var c: Vector3 = Vector3(x, ground(x, z + 3) + lift, z + 3)
			var d: Vector3 = Vector3(x + 3, ground(x + 3, z + 3) + lift, z + 3)
			# Same diagonal split as the landscape mesh.
			tri(surface, a, b, c, Vector3.UP, Color.WHITE, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
			tri(surface, b, d, c, Vector3.UP, Color.WHITE, PackedVector2Array([Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
			z += 3
		x += 3
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = surface.commit()
	add_child(visual)
	return visual

func flagstones() -> void:
	var z: float = WALL_FRONT_Z + 0.4
	var foot: float = ChurchSite.DOOR.y + PODIUM_FRONT + 2.3
	while z > foot:
		for slot: int in range(2):
			if random.randf() < 0.15:
				continue
			var x: float = ChurchSite.road_x(z) + (-0.45 if slot == 0 else 0.45) + random.randf_range(-0.12, 0.12)
			var radius: float = random.randf_range(0.26, 0.4)
			var sides: int = random.randi_range(5, 7)
			var outline: PackedVector2Array = PackedVector2Array()
			var highest: float = -INF
			var turn: float = random.randf_range(0.0, TAU)
			for index: int in range(sides):
				var angle: float = turn - TAU * float(index) / float(sides)
				var point: Vector2 = Vector2(cos(angle), sin(angle)) * radius * random.randf_range(0.8, 1.15)
				outline.append(point)
				highest = maxf(highest, ground(x + point.x, z - point.y))
			var slab: Transform3D = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, highest - 0.1, z))
			extrude(tool("base|" + chunk(x, z)), slab, outline, 0.26, vary(0.12, Color(0.85, 0.85, 0.82)))
		z -= random.randf_range(0.62, 0.82)

func ember_patch(center: Vector2, radius: float, material: ShaderMaterial) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = maxi(4, ceili(radius * 2.0 / 0.4))
	var cell: float = radius * 2.0 / float(steps)
	for i: int in range(steps):
		for j: int in range(steps):
			var corners: Array[Vector3] = []
			var uv: PackedVector2Array = PackedVector2Array()
			for offset: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var x: float = center.x - radius + (float(i) + offset.x) * cell
				var z: float = center.y - radius + (float(j) + offset.y) * cell
				corners.append(Vector3(x, ground(x, z) + 0.05, z))
				uv.append(Vector2((float(i) + offset.x) / float(steps), (float(j) + offset.y) / float(steps)))
			quad(surface, corners[0], corners[1], corners[2], corners[3], Vector3.UP, Color.WHITE, uv)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "EmberCracks"
	visual.mesh = surface.commit()
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var sparks: GPUParticles3D = GPUParticles3D.new()
	sparks.name = "EmberSparks"
	sparks.amount = int(6.0 + radius * 6.0)
	sparks.lifetime = 2.4
	sparks.position = Vector3(center.x, ground(center.x, center.y) + 0.05, center.y)
	sparks.visibility_aabb = AABB(Vector3(-radius - 1.0, -0.5, -radius - 1.0), Vector3(radius * 2.0 + 2.0, 4.0, radius * 2.0 + 2.0))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(radius * 0.55, 0.02, radius * 0.55)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0.05, 0.12, 0.0)
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1.0, 0.55, 0.15))
	fade.set_color(1, Color(0.0, 0.0, 0.0))
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	sparks.process_material = process
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.025, 0.025)
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(1.0, 0.6, 0.25)
	mesh.material = glow
	sparks.draw_pass_1 = mesh
	add_child(sparks)

# --- Finishing ------------------------------------------------------------------------------

func finish_batches() -> void:
	for key: String in batches:
		var surface: SurfaceTool = batches[key]
		var kind: String = key.get_slice("|", 0)
		if kind == "slate":
			surface.generate_tangents()
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = kind.capitalize() + key.get_slice("|", 1).capitalize()
		visual.mesh = surface.commit()
		visual.material_override = materials[kind]
		if kind in ["strand", "glow", "void", "wax"]:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	batches.clear()

func finish_flames() -> void:
	var quad_tool: SurfaceTool = SurfaceTool.new()
	quad_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tri(quad_tool, Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3.BACK, Color.WHITE, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]))
	tri(quad_tool, Vector3(-0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3.BACK, Color.WHITE, PackedVector2Array([Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)]))
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = quad_tool.commit()
	multi.instance_count = flames.size()
	for index: int in range(flames.size()):
		multi.set_instance_transform(index, flames[index])
		multi.set_instance_color(index, flame_colors[index])
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.name = "Flames"
	visual.multimesh = multi
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADERS + "church_flame.gdshader") as Shader
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.extra_cull_margin = 1.0
	add_child(visual)

func finish_tufts() -> void:
	var tuft: SurfaceTool = SurfaceTool.new()
	tuft.begin(Mesh.PRIMITIVE_TRIANGLES)
	var reed: SurfaceTool = SurfaceTool.new()
	reed.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 33017
	for blade: int in range(12):
		grass_blade(tuft, rng, rng.randf_range(0.25, 0.62), rng.randf_range(0.012, 0.02), Color(0.5, 0.45, 0.33))
	for blade: int in range(6):
		grass_blade(reed, rng, rng.randf_range(0.3, 0.5), 0.016, Color(0.42, 0.38, 0.28))
	for stalk: int in range(4):
		var angle: float = rng.randf_range(0.0, TAU)
		var base: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.08)
		var top: Vector3 = base + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.8, 1.25), rng.randf_range(-0.08, 0.08))
		cylinder(reed, base, top, 0.006, 0.004, 4, Color(0.36, 0.32, 0.22, 0.0), Color(0.36, 0.32, 0.22, 1.0))
		cylinder(reed, top - Vector3.UP * 0.16, top - Vector3.UP * 0.02, 0.016, 0.014, 5, Color(0.16, 0.11, 0.07, 0.9), Color(0.16, 0.11, 0.07, 1.0), true)
	var meshes: Array[ArrayMesh] = [tuft.commit(), reed.commit()]
	var sets: Array[Array] = [tufts, reeds]
	for index: int in range(2):
		var placements: Array = sets[index]
		if placements.is_empty():
			continue
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = meshes[index]
		multi.instance_count = placements.size()
		for item: int in range(placements.size()):
			multi.set_instance_transform(item, placements[item] as Transform3D)
			var shade: float = rng.randf_range(0.7, 1.15)
			multi.set_instance_color(item, Color(shade, shade * rng.randf_range(0.95, 1.03), shade * 0.95, 1.0))
		var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
		visual.name = "DeadGrass" if index == 0 else "DryReeds"
		visual.multimesh = multi
		visual.material_override = materials["grass"]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)

func grass_blade(surface: SurfaceTool, rng: RandomNumberGenerator, height: float, width: float, tip_color: Color) -> void:
	var angle: float = rng.randf_range(0.0, TAU)
	var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var across: Vector3 = Vector3(-out.z, 0.0, out.x)
	var base: Vector3 = out * rng.randf_range(0.0, 0.1)
	var bend: float = rng.randf_range(0.15, 0.6)
	var previous_left: Vector3 = base - across * width
	var previous_right: Vector3 = base + across * width
	var root: Color = Color(0.13, 0.11, 0.08, 0.0)
	var normal: Vector3 = (out + Vector3.UP * 0.4).normalized()
	for segment: int in range(1, 4):
		var t: float = float(segment) / 3.0
		var center: Vector3 = base + out * (bend * height * t * t) + Vector3.UP * (height * (t - 0.25 * bend * t * t))
		var w: float = width * (1.0 - t * 0.85)
		var left: Vector3 = center - across * w
		var right: Vector3 = center + across * w
		var c0: Color = root.lerp(tip_color, t - 1.0 / 3.0)
		c0.a = t - 1.0 / 3.0
		var c1: Color = root.lerp(tip_color, t)
		c1.a = t
		smooth(surface, [previous_left, previous_right, right], [normal, normal, normal], [c0, c0, c1])
		smooth(surface, [previous_left, right, left], [normal, normal, normal], [c0, c1, c1])
		previous_left = left
		previous_right = right

func build_particles() -> void:
	var ash: GPUParticles3D = GPUParticles3D.new()
	ash.name = "AshFall"
	ash.amount = 320
	ash.lifetime = 16.0
	ash.preprocess = 16.0
	ash.position = Vector3(ChurchSite.YARD_CENTER.x, ground(ChurchSite.YARD_CENTER.x, ChurchSite.YARD_CENTER.y) + 8.0, ChurchSite.YARD_CENTER.y - 1.0)
	ash.visibility_aabb = AABB(Vector3(-20.0, -12.0, -17.0), Vector3(40.0, 15.0, 34.0))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(17.0, 1.0, 14.0)
	process.direction = Vector3(0.15, -1.0, 0.05)
	process.spread = 20.0
	process.initial_velocity_min = 0.32
	process.initial_velocity_max = 0.5
	process.gravity = Vector3(0.04, -0.02, 0.015)
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	ash.process_material = process
	var flake: QuadMesh = QuadMesh.new()
	flake.size = Vector2(0.04, 0.04)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(0.7, 0.7, 0.68)
	material.roughness = 1.0
	flake.material = material
	ash.draw_pass_1 = flake
	add_child(ash)

func lamp(point: Vector3, color: Color, energy: float, reach: float, flicker: float) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "ChurchLight%d" % lamps.size()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_bake_mode = Light3D.BAKE_DISABLED
	# Fade with distance so the far village view does not spend the Mobile per-mesh light budget.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 60.0
	light.distance_fade_length = 20.0
	light.position = point
	add_child(light)
	lamps.append(light)
	lamp_energy.append(energy)
	lamp_flicker.append(flicker)

# --- Audio ---------------------------------------------------------------------------------

func build_audio() -> void:
	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args():
		return
	var yard: Vector3 = Vector3(ChurchSite.YARD_CENTER.x, ground(ChurchSite.YARD_CENTER.x, ChurchSite.YARD_CENTER.y) + 2.0, ChurchSite.YARD_CENTER.y)
	bed("forest_dark_synth_01", yard, -15.0, 12.0, 46.0)
	bed("chimney_wind_01", at(0.0, 2.0, 0.6), -4.0, 5.0, 24.0)
	bell = AudioStreamPlayer3D.new()
	bell.name = "BellToll"
	bell.stream = load(AMBIENCE + "church_bells_01.ogg") as AudioStream
	bell.unit_size = 40.0
	bell.max_distance = 170.0
	bell.max_db = 6.0
	bell.volume_db = -50.0
	bell.position = at(0.0, 20.0, TOWER_BACK * 0.5)
	add_child(bell)
	bell_wait = random.randf_range(12.0, 30.0)

# Two players crossfade at the clip end because no ambience recording is a verified loop.
func bed(id: String, point: Vector3, volume: float, unit: float, reach: float) -> void:
	var stream: AudioStream = load(AMBIENCE + id + ".ogg") as AudioStream
	var players: Array[AudioStreamPlayer3D] = []
	for index: int in range(2):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "%s_%d" % [id, index]
		player.stream = stream
		player.unit_size = unit
		player.max_distance = reach
		player.volume_db = volume
		player.position = point
		add_child(player)
		players.append(player)
	players[0].play(random.randf_range(0.0, stream.get_length() * 0.6))
	beds.append({"players": players, "active": 0, "volume": volume, "length": stream.get_length()})

func update_audio(delta: float) -> void:
	for entry: Dictionary in beds:
		var players: Array[AudioStreamPlayer3D] = entry["players"]
		var current: AudioStreamPlayer3D = players[int(entry["active"])]
		if current.playing and current.get_playback_position() < float(entry["length"]) - 4.0:
			continue
		var next: int = 1 - int(entry["active"])
		entry["active"] = next
		var incoming: AudioStreamPlayer3D = players[next]
		incoming.volume_db = -60.0
		incoming.play(0.0)
		var fade: Tween = create_tween()
		fade.tween_property(incoming, "volume_db", float(entry["volume"]), 4.0)
		fade.parallel().tween_property(current, "volume_db", -60.0, 4.0)
	if bell == null:
		return
	bell_wait -= delta
	if bell_wait > 0.0:
		return
	bell_wait = random.randf_range(38.0, 75.0)
	bell.volume_db = -50.0
	bell.play(random.randf_range(2.0, 70.0))
	var toll: Tween = create_tween()
	toll.tween_property(bell, "volume_db", bell_volume, 1.5)
	toll.tween_interval(7.0)
	toll.tween_property(bell, "volume_db", -50.0, 3.5)
	toll.tween_callback(bell.stop)

# --- Village vegetation inside the church and yard -------------------------------------------

func clear_village_plants() -> int:
	if village == null:
		return 0
	var hidden: int = 0
	var instances: int = 0
	var gate_clear: Rect2 = Rect2(gate_x - 9.5, -87.5, 19.0, 4.5)
	for node: Node in village.find_children("*", "GeometryInstance3D", true, false):
		if node is MultiMeshInstance3D:
			instances += thin_multimesh(node as MultiMeshInstance3D, gate_clear)
			continue
		var visual: GeometryInstance3D = node as GeometryInstance3D
		if not visual.visible:
			continue
		var bounds: AABB = visual.global_transform * visual.get_aabb()
		if bounds.size.x > 40.0 or bounds.size.z > 40.0:
			continue
		var footprint: Rect2 = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		var center: Vector2 = footprint.get_center()
		if footprint.intersects(CHURCH_CLEAR) or YARD_CLEAR.grow(1.0).has_point(center) or gate_clear.has_point(center):
			visual.visible = false
			hidden += 1
	print("CHURCH_CLEARED: ", hidden, " village plant/rock meshes hidden, ", instances, " instanced plants collapsed")
	return hidden + instances

# Collapse instances inside the cleared areas. The dummy headless renderer keeps no buffer.
func thin_multimesh(visual: MultiMeshInstance3D, gate_clear: Rect2) -> int:
	var multi: MultiMesh = visual.multimesh
	if multi == null or multi.mesh == null or multi.transform_format != MultiMesh.TRANSFORM_3D:
		return 0
	var stride: int = 12 + (4 if multi.use_colors else 0) + (4 if multi.use_custom_data else 0)
	var buffer: PackedFloat32Array = multi.buffer
	if buffer.size() < multi.instance_count * stride:
		return 0
	var tree: bool = multi.mesh.get_aabb().size.y > 3.0
	var hidden: int = 0
	for index: int in range(multi.instance_count):
		var offset: int = index * stride
		var origin: Vector3 = visual.global_transform * Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var point: Vector2 = Vector2(origin.x, origin.z)
		var remove: bool = false
		if tree:
			var radius: float = Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]).length() * 4.0
			remove = Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).intersects(CHURCH_CLEAR) or YARD_CLEAR.grow(1.0).has_point(point) or gate_clear.has_point(point)
		else:
			remove = CHURCH_CLEAR.has_point(point) or YARD_CLEAR.grow(0.4).has_point(point)
		if not remove or (buffer[offset] == 0.0 and buffer[offset + 5] == 0.0 and buffer[offset + 10] == 0.0):
			continue
		for column: int in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
			buffer[offset + column] = 0.0
		hidden += 1
	if hidden > 0:
		multi.buffer = buffer
	return hidden

# --- Per frame: light flicker, the crow, ambience --------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	for index: int in range(lamps.size()):
		var phase: float = elapsed + float(index) * 1.73
		var flicker: float = lamp_flicker[index]
		var wobble: float = 0.1 * sin(phase * 7.3) + 0.06 * sin(phase * 13.1 + 1.2) + 0.04 * sin(phase * 23.7)
		var slow: float = 0.08 * sin(elapsed * 0.6 + float(index))
		lamps[index].light_energy = lamp_energy[index] * (1.0 + wobble * flicker * 1.6 + slow * (1.0 - flicker))
	if crow_head != null:
		crow_wait -= delta
		if crow_wait <= 0.0:
			crow_wait = random.randf_range(0.6, 3.5)
			crow_target = random.randf_range(-1.1, 1.1)
		crow_head.rotation.y = lerpf(crow_head.rotation.y, crow_target, minf(1.0, delta * 18.0))
		crow_body.position = crow_rest + Vector3.UP * (0.006 * sin(elapsed * 2.1))
	update_audio(delta)
