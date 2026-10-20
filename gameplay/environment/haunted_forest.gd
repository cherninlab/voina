extends Node3D
## Haunted forest along the north trail to the church (T-092). Cosmetic scenery plus a per-peer fog
## zone; it owns no gameplay or network state. Placement is seeded, so every peer builds the same
## trees and the same trunk collision.
##
## Fog zone: while the local camera is outside the village palisade and near the ground, the shared
## Environment and the sun ease from whatever grade is active (the grim village grade or a shading
## theme) toward a dense, cold forest grade. A value another script writes becomes the new base, and
## the base comes back exactly inside the village and for the high lobby camera.
## The grade's colours are tuned for Folk Ink; the active shading theme can dim its fog and ambient
## colours (Forest fog / Forest ambient sliders) so night looks stay dark out here.

const ART: String = "res://content/environments/haunted_forest/"
const BARK_MAPS: String = "res://content/environments/valhalla/textures/KB3D_VHL_LogBark_"
const WOODLAND_TREE: Script = preload("res://gameplay/environment/woodland_tree.gd")

# The forest grade, reached at weight 1. Densities and colours are absolute; the rest scale the base.
const FOG_COLOR: Color = Color("65757f")
const FOG_DENSITY: float = 0.044
const FOG_SKY_AFFECT: float = 0.8
const FOG_AERIAL: float = 0.1
const AMBIENT_COLOR: Color = Color("5a6a74")
const AMBIENT_SCALE: float = 0.8
const SUN_COLOR: Color = Color("aebdcc")
const SUN_SCALE: float = 0.45
const EXPOSURE_SCALE: float = 0.95
const ENVIRONMENT_KEYS: Array[StringName] = [&"fog_density", &"fog_light_color", &"fog_sky_affect", &"fog_aerial_perspective", &"fog_sun_scatter", &"ambient_light_energy", &"ambient_light_color", &"tonemap_exposure"]
const SUN_KEYS: Array[StringName] = [&"light_energy", &"light_color"]
# Distances from the road centre (ChurchSite.road_x): torches stand at 2.5 m, people walk inside 2.8 m.
const GROUND_CLEAR: float = 2.9
const TRUNK_CLEAR: float = 3.9
const SHAFT_INTENSITY: float = 0.07
const MIST_OPACITY: float = 0.3

enum Kind { GNARLED, SNAG, ARCH }

var environment: Environment # the shared grade being blended (the capture script reads it)
var sun: DirectionalLight3D
var weight: float = 0.0 # 0 = base grade, 1 = full forest grade (the capture script reads it)
var applied: float = 0.0
var fog_scale: float = 1.0 # Forest fog slider of the active shading theme
var ambient_scale: float = 1.0 # Forest ambient slider of the active shading theme
var grading: bool = false
var base: Dictionary[String, Variant] = {}
var written: Dictionary[String, Variant] = {}
var village: Node3D
# The village palisade outline (village_arena.gd); the north gate is at (-0.5, -26.5).
var palisade: PackedVector2Array = PackedVector2Array([Vector2(-28, -10), Vector2(-24, -23), Vector2(-9, -28), Vector2(8, -25), Vector2(22, -28), Vector2(28, -16), Vector2(25, 0), Vector2(28, 15), Vector2(17, 27), Vector2(2, 28), Vector2(-12, 25), Vector2(-28, 28)])
var trunks: Array[Vector2] = []
var pools: Array[Vector2] = []
var batches: Dictionary[Mesh, Array] = {}
var shadowed: Dictionary[Mesh, bool] = {}
var trunk_body: StaticBody3D = StaticBody3D.new()
var bark: ShaderMaterial
var moss: ShaderMaterial
var shaft_material: ShaderMaterial
var mist_material: ShaderMaterial
var water_materials: Array[ShaderMaterial] = []
var ash: CPUParticles3D = CPUParticles3D.new()
var strands_added: int = 0
var counts: Dictionary[String, int] = {}

func _ready() -> void:
	name = "HauntedForest"
	village = get_parent().get_node_or_null("WoodlandVillage") as Node3D
	if village == null or not village.has_method("landscape_surface_height"):
		push_warning("HauntedForest: no woodland village terrain to stand on")
		return
	bark = material("dead_bark")
	bark.set_shader_parameter("basecolor", load(BARK_MAPS + "basecolor.png"))
	bark.set_shader_parameter("normal_map", load(BARK_MAPS + "normal.png"))
	bark.set_shader_parameter("roughness_map", load(BARK_MAPS + "roughness.png"))
	moss = material("hanging_moss")
	trunk_body.name = "TrunkCollision"
	add_child(trunk_body)
	flood_bogs()
	plant_dead_trees()
	plant_spruces()
	lay_deadfall()
	grow_reeds()
	flush_batches()
	hang_light_shafts()
	spread_ground_mist()
	smoulder()
	drift_ash()
	finish.call_deferred()

func finish() -> void:
	# The grim grade and its material copies land deferred; start after them.
	for frame: int in range(3):
		await get_tree().process_frame
	subdue_village_trees()
	find_grade_targets()
	tune_cards(null)
	grading = true
	print("HAUNTED_FOREST_OK: ", counts)

# --- Fog zone -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not grading:
		return
	if not is_instance_valid(environment) or (sun != null and not is_instance_valid(sun)):
		find_grade_targets()
		if environment == null:
			return
	var lighting: Node = get_tree().get_first_node_in_group(&"shading_lighting")
	var scales_changed: bool = false
	if lighting != null:
		var fog_wanted: float = float(lighting.call("forest_scale", "forest_fog"))
		var ambient_wanted: float = float(lighting.call("forest_scale", "forest_ambient"))
		scales_changed = fog_wanted != fog_scale or ambient_wanted != ambient_scale
		fog_scale = fog_wanted
		ambient_scale = ambient_wanted
	var camera: Camera3D = get_viewport().get_camera_3d()
	var target: float = zone_weight(camera.global_position) if camera != null else 0.0
	weight = lerpf(weight, target, 1.0 - exp(-delta * 2.5))
	if absf(weight - target) < 0.002:
		weight = target
	if weight == 0.0 and applied == 0.0 and not scales_changed:
		return
	layer(environment, ENVIRONMENT_KEYS, "environment/")
	if sun != null:
		layer(sun, SUN_KEYS, "sun/")
	tune_cards(camera)
	applied = weight

## Shafts only shine under the forest grade; mist and still water take the current fog colour;
## the ash drift follows the camera and thins out toward the village.
func tune_cards(camera: Camera3D) -> void:
	shaft_material.set_shader_parameter("intensity", SHAFT_INTENSITY * minf(fog_scale, 1.0) * smoothstep(0.5, 1.0, weight))
	ash.emitting = weight > 0.35
	if camera != null:
		ash.global_position = camera.global_position
	mist_material.set_shader_parameter("opacity", MIST_OPACITY * lerpf(0.55, 1.0, weight))
	if environment != null:
		mist_material.set_shader_parameter("color", environment.fog_light_color.lightened(0.08))
		for water: ShaderMaterial in water_materials:
			water.set_shader_parameter("sky_tint", environment.fog_light_color)

## 0 inside the palisade, rising to 1 over about 13 m of travel beyond it; 0 again for cameras high
## above the ground such as the lobby view.
func zone_weight(point: Vector3) -> float:
	var flat: Vector2 = Vector2(point.x, point.z)
	var outside: float = 0.0
	if not Geometry2D.is_point_in_polygon(flat, palisade):
		outside = INF
		for index: int in range(palisade.size()):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(flat, palisade[index], palisade[(index + 1) % palisade.size()])
			outside = minf(outside, flat.distance_to(closest))
	var amount: float = smoothstep(1.0, 14.0, outside)
	return amount * (1.0 - smoothstep(9.0, 16.0, point.y - ground(point.x, point.z)))

func layer(target: Object, keys: Array[StringName], prefix: String) -> void:
	for key: StringName in keys:
		var slot: String = prefix + String(key)
		var current: Variant = target.get(key)
		if not written.has(slot) or not same(current, written[slot]):
			base[slot] = current
		target.set(key, graded(key, base[slot], weight))
		written[slot] = target.get(key)

func graded(key: StringName, value: Variant, amount: float) -> Variant:
	match key:
		&"fog_density":
			return lerpf(float(value), maxf(float(value), FOG_DENSITY), amount)
		&"fog_light_color":
			return (value as Color).lerp(dimmed(FOG_COLOR, fog_scale), amount)
		&"fog_sky_affect":
			return lerpf(float(value), maxf(float(value), FOG_SKY_AFFECT), amount)
		&"fog_aerial_perspective":
			return lerpf(float(value), FOG_AERIAL, amount)
		&"fog_sun_scatter":
			return lerpf(float(value), 0.0, amount)
		&"ambient_light_energy":
			return float(value) * lerpf(1.0, AMBIENT_SCALE, amount)
		&"ambient_light_color":
			return (value as Color).lerp(dimmed(AMBIENT_COLOR, ambient_scale), amount)
		&"tonemap_exposure":
			return float(value) * lerpf(1.0, EXPOSURE_SCALE, amount)
		&"light_energy":
			return float(value) * lerpf(1.0, SUN_SCALE, amount)
		&"light_color":
			return (value as Color).lerp(SUN_COLOR, amount)
	return value

static func dimmed(colour: Color, scale: float) -> Color:
	return Color(colour.r * scale, colour.g * scale, colour.b * scale, colour.a)

static func same(a: Variant, b: Variant) -> bool:
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	if a is float and b is float:
		return is_equal_approx(float(a), float(b))
	return a == b

func find_grade_targets() -> void:
	base.clear()
	written.clear()
	applied = 0.0
	environment = null
	sun = null
	for node: Node in get_parent().find_children("*", "WorldEnvironment", true, false):
		environment = (node as WorldEnvironment).environment
		break
	for node: Node in village.find_children("*", "DirectionalLight3D", true, false):
		if node.name != "DistantRedSheetLightning":
			sun = node as DirectionalLight3D
			break

# --- Placement rules ------------------------------------------------------------------------

func ground(x: float, z: float) -> float:
	return float(village.call("landscape_surface_height", x, z))

func steepness(x: float, z: float) -> float:
	var height: float = ground(x, z)
	return absf(ground(x + 1.0, z) - height) + absf(ground(x, z + 1.0) - height)

static func trail_offset(point: Vector2) -> float:
	return point.x - ChurchSite.road_x(point.y)

## Where scenery may not stand: the village and gate apron, the walking strip, the graveyard ring and
## the church footprint (theo-claude-7's), and optionally the bog pools.
func forbidden(point: Vector2, clearance: float, avoid_pools: bool = true) -> bool:
	if point.y > -31.0:
		return true
	if point.y > -116.0 and absf(trail_offset(point)) < clearance:
		return true
	if churchyard(point):
		return true
	if avoid_pools:
		for pool: Vector2 in pools:
			if point.distance_to(pool) < 5.5:
				return true
	return false

## theo-claude-7's ground (T-085): the graveyard ring, its walled rectangle (x -21..13,
## z -112..-87) and the church footprint (x -11..3, z -132..-106), each with a metre of margin.
static func churchyard(point: Vector2) -> bool:
	if point.distance_to(ChurchSite.YARD_CENTER) < ChurchSite.YARD_RADIUS + 1.5:
		return true
	if point.x > -22.0 and point.x < 14.0 and point.y > -113.0 and point.y < -86.0:
		return true
	return point.x > -12.0 and point.x < 4.0 and point.y > -133.0 and point.y < -105.0

func in_pool(point: Vector2) -> bool:
	for pool: Vector2 in pools:
		if point.distance_to(pool) < 4.2:
			return true
	return false

func spaced(point: Vector2, spacing: float) -> bool:
	for other: Vector2 in trunks:
		if point.distance_squared_to(other) < spacing * spacing:
			return false
	return true

func batch(mesh: Mesh, transform: Transform3D, shadows: bool = false) -> void:
	if not batches.has(mesh):
		batches[mesh] = []
		shadowed[mesh] = shadows
	batches[mesh].append(transform)

func flush_batches() -> void:
	for mesh: Mesh in batches:
		var transforms: Array = batches[mesh]
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index: int in range(transforms.size()):
			multi.set_instance_transform(index, transforms[index] as Transform3D)
		var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
		visual.multimesh = multi
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadowed[mesh] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(visual)
	batches.clear()

func material(shader_name: String) -> ShaderMaterial:
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = load(ART + shader_name + ".gdshader") as Shader
	return result

func count(key: String, amount: int = 1) -> void:
	counts[key] = counts.get(key, 0) + amount

# --- Dead trees -----------------------------------------------------------------------------

func plant_dead_trees() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 92117
	var variants: Array[Array] = [[], [], []]
	for kind: int in range(3):
		for variant: int in range(3):
			variants[kind].append(dead_tree(kind, 7100 + kind * 31 + variant * 7))
	# Leaning arches alternate sides over the last stretch, so the walk ends in a tunnel of bare
	# limbs before the graveyard opens up.
	var side: float = -1.0
	var z: float = -55.0
	while z > -86.5:
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + side * random.randf_range(4.6, 5.8), z + random.randf_range(-0.7, 0.7))
		if not forbidden(point, TRUNK_CLEAR + 0.6) and spaced(point, 3.0):
			var skew: float = random.randf_range(-0.35, 0.35)
			stand(variants[Kind.ARCH][random.randi() % 3] as ArrayMesh, point, atan2(-skew, -side), random.randf_range(0.95, 1.1), 0.0, random)
			count("arch trees")
		side = -side
		z -= random.randf_range(3.2, 4.2)
	scatter(variants[Kind.GNARLED], random, 14, -56.0, -88.0, 5.4, 12.0, 4.0, 0.06)
	scatter(variants[Kind.GNARLED], random, 14, -32.0, -124.0, 6.0, 26.0, 4.5, 0.08)
	scatter(variants[Kind.SNAG], random, 30, -32.0, -70.0, TRUNK_CLEAR, 28.0, 2.6, 0.2)
	scatter(variants[Kind.SNAG], random, 14, -70.0, -124.0, 7.0, 28.0, 2.6, 0.2)
	# A denser ring of dead wood just outside the graveyard wall.
	var ring: int = 0
	for attempt: int in range(600):
		if ring >= 26:
			break
		var angle: float = random.randf_range(0.0, TAU)
		var point: Vector2 = ChurchSite.YARD_CENTER + Vector2(cos(angle), sin(angle)) * random.randf_range(ChurchSite.YARD_RADIUS + 2.0, ChurchSite.YARD_RADIUS + 11.0)
		if forbidden(point, TRUNK_CLEAR + 1.0) or not spaced(point, 3.2) or steepness(point.x, point.y) > 1.6:
			continue
		var kind: int = Kind.GNARLED if ring % 3 != 2 else Kind.SNAG
		stand(variants[kind][random.randi() % 3] as ArrayMesh, point, random.randf_range(0.0, TAU), random.randf_range(0.85, 1.15), 0.06 if kind == Kind.GNARLED else 0.15, random)
		ring += 1
	count("graveyard ring trees", ring)

func scatter(meshes: Array, random: RandomNumberGenerator, wanted: int, z_from: float, z_to: float, near: float, far: float, spacing: float, max_lean: float) -> void:
	var placed: int = 0
	for attempt: int in range(wanted * 40):
		if placed >= wanted:
			break
		var z: float = random.randf_range(z_to, z_from)
		var offset: float = lerpf(near, far, pow(random.randf(), 1.4)) * (-1.0 if random.randf() < 0.5 else 1.0)
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + offset, z)
		if forbidden(point, near) or not spaced(point, spacing) or steepness(point.x, point.y) > 1.6:
			continue
		stand(meshes[random.randi() % meshes.size()] as ArrayMesh, point, random.randf_range(0.0, TAU), random.randf_range(0.85, 1.2), max_lean, random)
		placed += 1
	count("dead trees", placed)

func stand(mesh: ArrayMesh, point: Vector2, yaw: float, size: float, max_lean: float, random: RandomNumberGenerator) -> void:
	var lean_angle: float = random.randf() * TAU
	var lean_axis: Vector3 = Vector3(cos(lean_angle), 0.0, sin(lean_angle))
	var basis: Basis = Basis(lean_axis, random.randf_range(0.0, max_lean)) * Basis(Vector3.UP, yaw)
	var height: float = ground(point.x, point.y) - 0.12 - steepness(point.x, point.y) * 0.3
	batch(mesh, Transform3D(basis.scaled(Vector3.ONE * size), Vector3(point.x, height, point.y)), true)
	trunks.append(point)
	# Solid trunks only where people walk near them; thin snags and far trees stay cosmetic.
	var radius: float = float(mesh.get_meta("trunk_radius", 0.0)) * size
	if radius > 0.25 and absf(trail_offset(point)) < 16.0:
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.radius = radius * 0.9
		shape.height = 3.2
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(point.x, height + 1.6, point.y)
		trunk_body.add_child(collider)
		count("trunk colliders")

func dead_tree(kind: int, seed_value: int) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var wood: SurfaceTool = SurfaceTool.new()
	var strands: SurfaceTool = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	strands.begin(Mesh.PRIMITIVE_TRIANGLES)
	strands_added = 0
	var style: Dictionary[String, float] = {}
	var height: float = 0.0
	var radius: float = 0.0
	var lean: Vector3 = Vector3.UP
	var snapped: bool = false
	match kind:
		Kind.GNARLED:
			style = {"gnarl": 0.34, "rise": 0.16, "broken": 0.16, "depth": 4.0, "limbs": 6.0, "reach": 0.48, "moss": 0.5, "low": 0.45}
			height = random.randf_range(6.5, 8.5)
			radius = random.randf_range(0.3, 0.4)
			lean = Vector3(random.randf_range(-0.12, 0.12), 1.0, random.randf_range(-0.12, 0.12))
		Kind.SNAG:
			style = {"gnarl": 0.1, "rise": 0.12, "broken": 0.55, "depth": 2.0, "limbs": 6.0, "reach": 0.24, "moss": 0.15, "low": 0.3}
			height = random.randf_range(9.0, 13.5)
			radius = random.randf_range(0.16, 0.24)
			snapped = random.randf() < 0.6
		_:
			style = {"gnarl": 0.24, "rise": 0.12, "broken": 0.12, "depth": 4.0, "limbs": 4.0, "reach": 0.42, "moss": 0.65, "low": 0.55}
			height = random.randf_range(6.0, 7.2)
			radius = random.randf_range(0.3, 0.37)
			lean = Vector3(0.22, 1.0, 0.0)
	var trunk: PackedVector3Array = limb(wood, strands, random, Vector3(0.0, -0.4, 0.0), lean, height, radius, 0, style, snapped)
	if kind != Kind.SNAG:
		flare(wood, radius, random)
	if kind == Kind.ARCH:
		arch_limb(wood, strands, random, trunk, style)
	wood.generate_tangents()
	wood.index()
	var mesh: ArrayMesh = wood.commit()
	mesh.surface_set_material(0, bark)
	if strands_added > 0:
		strands.index()
		strands.commit(mesh)
		mesh.surface_set_material(1, moss)
	mesh.set_meta("trunk_radius", radius)
	return mesh

func limb(wood: SurfaceTool, strands: SurfaceTool, random: RandomNumberGenerator, start: Vector3, direction: Vector3, length: float, radius: float, depth: int, style: Dictionary[String, float], snapped: bool = false) -> PackedVector3Array:
	var segments: int = [8, 4, 3, 2, 2][mini(depth, 4)]
	var broken: bool = snapped or (depth > 0 and depth < 3 and random.randf() < style["broken"])
	var reach: float = length * (random.randf_range(0.35, 0.65) if broken and depth > 0 else 1.0)
	var points: PackedVector3Array = PackedVector3Array([start])
	var radii: PackedFloat32Array = PackedFloat32Array([radius])
	var heading: Vector3 = direction.normalized()
	var gnarl: float = style["gnarl"] * (0.5 if depth == 0 else (1.0 if depth < 3 else 1.6))
	var lift: float = style["rise"] if depth < 2 else -0.1
	var tip: float = maxf(radius * (0.55 if broken else (0.22 if depth == 0 else 0.3)), 0.005)
	for segment: int in range(segments):
		var wander: Vector3 = Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-0.4, 0.4), random.randf_range(-1.0, 1.0)) * gnarl
		heading = (heading + wander + Vector3.UP * lift).normalized()
		points.append(points[points.size() - 1] + heading * reach / float(segments))
		radii.append(lerpf(radius, tip, float(segment + 1) / float(segments)))
	tube(wood, points, radii, sides_for(radius))
	if broken:
		splinter(wood, points[points.size() - 1], heading, radii[radii.size() - 1], random)
	if depth >= 1 and depth <= 2 and random.randf() < style["moss"]:
		for strand: int in range(random.randi_range(1, 3 if depth == 1 else 2)):
			var anchor: Vector3 = sample(points, random.randf_range(0.3, 0.95))
			if anchor.y > 3.4:
				hang(strands, anchor, minf(random.randf_range(0.5, 2.2), anchor.y - 3.0), random)
	if depth >= int(style["depth"]) or (broken and depth > 0):
		return points
	var children: int = int(style["limbs"]) if depth == 0 else [0, 4, 4, 2][depth]
	var axis: Vector3 = (points[points.size() - 1] - points[0]).normalized()
	var turn: float = random.randf() * TAU
	for child: int in range(children):
		var t: float = random.randf_range(style["low"], 0.96) if depth == 0 else random.randf_range(0.3, 0.95)
		turn += 2.4 + random.randf_range(-0.35, 0.35)
		var spread: float = random.randf_range(0.6, 1.1) if depth == 0 else random.randf_range(0.45, 1.0)
		var child_direction: Vector3 = (axis * cos(spread) + perpendicular(axis, turn) * sin(spread)).normalized()
		var child_length: float = length * (style["reach"] * random.randf_range(0.7, 1.2) if depth == 0 else random.randf_range(0.4, 0.65))
		limb(wood, strands, random, sample(points, t), child_direction, child_length, maxf(lerpf(radius, tip, t) * random.randf_range(0.45, 0.65), 0.008), depth + 1, style)
	return points

## A long crooked limb from a leaning trunk that reaches toward and over the road (local +X),
## kept above head height; a shorter second limb at another height breaks up the rhythm.
func arch_limb(wood: SurfaceTool, strands: SurfaceTool, random: RandomNumberGenerator, trunk: PackedVector3Array, style: Dictionary[String, float]) -> void:
	for limb_index: int in range(2):
		var main: bool = limb_index == 0
		var start: Vector3 = sample(trunk, random.randf_range(0.55, 0.72) if main else random.randf_range(0.75, 0.9))
		var reach: float = random.randf_range(4.8, 7.4) if main else random.randf_range(2.5, 4.0)
		var rise: float = random.randf_range(1.0, 2.6)
		var skew: float = random.randf_range(-1.2, 1.2) if main else random.randf_range(-2.5, 2.5)
		var points: PackedVector3Array = PackedVector3Array()
		var radii: PackedFloat32Array = PackedFloat32Array()
		var bend: Vector3 = Vector3.ZERO
		for step: int in range(9):
			var t: float = float(step) / 8.0
			bend += Vector3(0.0, random.randf_range(-0.22, 0.22), random.randf_range(-0.25, 0.25)) * t
			points.append(start + Vector3(reach * t, rise * sin(t * PI * 0.8), skew * t * t) + bend)
			radii.append(lerpf(0.2 if main else 0.12, 0.035, t))
		tube(wood, points, radii, 6)
		for child: int in range(8 if main else 4):
			var t: float = random.randf_range(0.2, 1.0)
			var up: Vector3 = Vector3(random.randf_range(-1.0, 1.0), random.randf_range(0.5, 1.4), random.randf_range(-1.0, 1.0)).normalized()
			limb(wood, strands, random, sample(points, t), up, random.randf_range(1.0, 2.6), lerpf(0.09, 0.03, t), 2, style)
		for strand: int in range(random.randi_range(5, 9) if main else random.randi_range(1, 3)):
			var anchor: Vector3 = sample(points, random.randf_range(0.25, 0.95))
			hang(strands, anchor, clampf(anchor.y - 4.3, 0.3, random.randf_range(0.8, 2.0)), random)

## Root buttresses so trunks sit into sloping ground.
func flare(wood: SurfaceTool, radius: float, random: RandomNumberGenerator) -> void:
	var turn: float = random.randf() * TAU
	for root: int in range(5):
		turn += TAU / 5.0 + random.randf_range(-0.3, 0.3)
		var out: Vector3 = Vector3(cos(turn), 0.0, sin(turn))
		var reach: float = radius * random.randf_range(2.6, 4.0)
		var points: PackedVector3Array = PackedVector3Array([out * radius * 0.3 + Vector3.UP * 0.7, out * radius * 1.1 + Vector3.UP * 0.12, out * reach + Vector3.DOWN * 0.3])
		tube(wood, points, PackedFloat32Array([radius * 0.5, radius * 0.38, 0.04]), 5)

func hang(strands: SurfaceTool, anchor: Vector3, length: float, random: RandomNumberGenerator) -> void:
	# Two crossed ribbons that the moss shader frays into strings of uneven length.
	var angle: float = random.randf() * TAU
	var width: float = random.randf_range(0.1, 0.26)
	var kink: Vector3 = Vector3(random.randf_range(-0.2, 0.2), 0.0, random.randf_range(-0.2, 0.2))
	var shade: float = random.randf_range(0.75, 1.1)
	strands_added += 1
	for ribbon: int in range(2):
		var across: Vector3 = Vector3(cos(angle + ribbon * PI * 0.5), 0.0, sin(angle + ribbon * PI * 0.5))
		var normal: Vector3 = across.cross(Vector3.UP).normalized()
		var offset: float = float(random.randi_range(0, 40))
		for step: int in range(4):
			var t0: float = float(step) / 4.0
			var t1: float = float(step + 1) / 4.0
			var p0: Vector3 = anchor + Vector3.DOWN * length * t0 + kink * t0 * t0
			var p1: Vector3 = anchor + Vector3.DOWN * length * t1 + kink * t1 * t1
			var w0: float = width * (1.0 - t0 * 0.35)
			var w1: float = width * (1.0 - t1 * 0.35)
			var corners: Array[Vector3] = [p0 - across * w0, p0 + across * w0, p1 + across * w1, p1 - across * w1]
			var uvs: Array[Vector2] = [Vector2(offset, t0), Vector2(offset + 1.0, t0), Vector2(offset + 1.0, t1), Vector2(offset, t1)]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				strands.set_color(Color(shade, shade, shade))
				strands.set_normal(normal)
				strands.set_uv(uvs[corner])
				strands.add_vertex(corners[corner])

## Jagged snapped end of a broken trunk or limb.
func splinter(wood: SurfaceTool, end: Vector3, heading: Vector3, radius: float, random: RandomNumberGenerator, jag: float = 1.0) -> void:
	var sides: int = sides_for(radius)
	var ring: Array[Vector3] = []
	for side: int in range(sides):
		ring.append(end + perpendicular(heading, TAU * float(side) / float(sides)) * radius)
	for side: int in range(sides):
		var spike: Vector3 = end + heading * radius * random.randf_range(0.1, 1.2) * jag * (2.0 if random.randf() < 0.2 else 1.0) + perpendicular(heading, random.randf() * TAU) * radius * random.randf_range(0.0, 0.5)
		triangle(wood, ring[side], ring[(side + 1) % sides], spike, (ring[side] + ring[(side + 1) % sides]) * 0.5 - end + heading * radius)

# --- Spruce silhouettes ---------------------------------------------------------------------

func plant_spruces() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 51733
	var needles: ShaderMaterial = material("spruce_needles")
	var variants: Array[ArrayMesh] = [spruce(611, 13.0, 2.6, needles), spruce(612, 10.0, 2.2, needles), spruce(613, 15.5, 3.0, needles)]
	var placed: int = 0
	# Dark conifer masses in loose groups, mostly back from the road behind the dead trees.
	for group: int in range(30):
		var z: float = random.randf_range(-128.0, -34.0)
		var offset: float = random.randf_range(10.0, 34.0) * (-1.0 if group % 2 == 0 else 1.0)
		var centre: Vector2 = Vector2(ChurchSite.road_x(z) + offset, z)
		for member: int in range(random.randi_range(2, 5)):
			var point: Vector2 = centre + Vector2(random.randf_range(-5.0, 5.0), random.randf_range(-5.0, 5.0))
			if forbidden(point, 8.0) or not spaced(point, 2.8) or steepness(point.x, point.y) > 1.8:
				continue
			var size: float = random.randf_range(0.75, 1.25)
			var height: float = ground(point.x, point.y) - 0.2
			batch(variants[random.randi() % variants.size()], Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * size), Vector3(point.x, height, point.y)))
			trunks.append(point)
			placed += 1
	count("spruces", placed)

func spruce(seed_value: int, height: float, spread: float, needles: ShaderMaterial) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var wood: SurfaceTool = SurfaceTool.new()
	var fronds: SurfaceTool = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	fronds.begin(Mesh.PRIMITIVE_TRIANGLES)
	tube(wood, PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0.05, height * 0.5, -0.03), Vector3(0, height, 0)]), PackedFloat32Array([0.24, 0.13, 0.02]), 6)
	var tiers: int = int(height / 0.42)
	for tier: int in range(tiers):
		var t: float = float(tier) / float(tiers)
		var y: float = 1.0 + (height - 1.2) * t + random.randf_range(-0.12, 0.12)
		var radius: float = spread * pow(1.0 - t, 0.85) * random.randf_range(0.75, 1.15) + 0.15
		var blades: int = 8 + int(radius * 2.5)
		var phase: float = random.randf() * TAU
		for blade: int in range(blades):
			if random.randf() < 0.12:
				continue
			var angle: float = phase + TAU * float(blade) / float(blades) + random.randf_range(-0.25, 0.25)
			var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
			var side: Vector3 = Vector3(-out.z, 0.0, out.x)
			var root: Vector3 = Vector3(0.0, y, 0.0)
			var reach: float = radius * random.randf_range(0.55, 1.15)
			var droop: float = random.randf_range(0.25, 0.7)
			var normal: Vector3 = (out + Vector3.UP * 0.7).normalized()
			var previous_left: Vector3 = root
			var previous_right: Vector3 = root
			for step: int in range(1, 6):
				var f: float = float(step) / 5.0
				# Sags in the middle, the tip turns up a little.
				var centre: Vector3 = root + out * reach * f + Vector3.DOWN * reach * droop * (f * 1.4 - f * f * 0.6)
				var width: float = reach * 0.24 * sin(f * PI * 0.9 + 0.15) * (1.0 if step % 2 == 0 else 0.6)
				var left: Vector3 = centre - side * width + Vector3.DOWN * width * 0.4
				var right: Vector3 = centre + side * width + Vector3.DOWN * width * 0.4
				var shade: float = lerpf(0.5, 1.15, f) * random.randf_range(0.85, 1.1)
				frond_quad(fronds, previous_left, previous_right, right, left, normal, shade, f)
				previous_left = left
				previous_right = right
	wood.generate_tangents()
	wood.index()
	var mesh: ArrayMesh = wood.commit()
	mesh.surface_set_material(0, bark)
	fronds.index()
	fronds.commit(mesh)
	mesh.surface_set_material(1, needles)
	return mesh

func frond_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, shade: float, along: float) -> void:
	var corners: Array[Vector3] = [a, b, c, d]
	var uvs: Array[Vector2] = [Vector2(0.0, along - 0.25), Vector2(1.0, along - 0.25), Vector2(1.0, along), Vector2(0.0, along)]
	for corner: int in [0, 1, 2, 0, 2, 3]:
		tool.set_color(Color(shade, shade, shade))
		tool.set_normal(normal)
		tool.set_uv(uvs[corner])
		tool.add_vertex(corners[corner])

# --- Deadfall, stumps and rocks -------------------------------------------------------------

func lay_deadfall() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 38211
	var logs: Array[ArrayMesh] = [log_mesh(301, 6.5, 0.34), log_mesh(302, 4.5, 0.26), log_mesh(303, 8.0, 0.4)]
	var stumps: Array[ArrayMesh] = [stump(401, 0.9, 0.42), stump(402, 0.55, 0.32), stump(403, 1.3, 0.36)]
	var rock: ArrayMesh = rock_mesh(501)
	var rock_material: ShaderMaterial = material("mossy_rock")
	rock_material.set_shader_parameter("rock", load("res://content/environments/village_generated/schist_rock.png"))
	rock.surface_set_material(0, rock_material)
	var limits: Dictionary[String, int] = {"logs": 16, "stumps": 18, "rocks": 20}
	var placed: Dictionary[String, int] = {"logs": 0, "stumps": 0, "rocks": 0}
	var kinds: Array[String] = ["logs", "stumps", "rocks"]
	for attempt: int in range(900):
		var kind: String = kinds[attempt % 3]
		if placed[kind] >= limits[kind]:
			continue
		var z: float = random.randf_range(-124.0, -33.0)
		var offset: float = lerpf(4.6, 22.0, pow(random.randf(), 1.3)) * (-1.0 if random.randf() < 0.5 else 1.0)
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + offset, z)
		if forbidden(point, 4.4 if kind == "logs" else 3.4) or not spaced(point, 2.0) or steepness(point.x, point.y) > 1.4:
			continue
		var yaw: float = random.randf() * TAU
		if kind == "logs":
			var mesh: ArrayMesh = logs[random.randi() % logs.size()]
			var half: float = float(mesh.get_meta("length")) * 0.5
			var along: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
			var front: Vector3 = Vector3(point.x, 0.0, point.y) + along * half
			var back: Vector3 = Vector3(point.x, 0.0, point.y) - along * half
			# Keep both ends off the road as well.
			if forbidden(Vector2(front.x, front.z), 3.4) or forbidden(Vector2(back.x, back.z), 3.4):
				continue
			front.y = ground(front.x, front.z)
			back.y = ground(back.x, back.z)
			var axis: Vector3 = (front - back).normalized()
			var side: Vector3 = axis.cross(Vector3.UP).normalized()
			var basis: Basis = Basis(axis, random.randf_range(-0.6, 0.6)) * Basis(axis, side.cross(axis).normalized(), side)
			batch(mesh, Transform3D(basis, (front + back) * 0.5 + Vector3.UP * float(mesh.get_meta("radius")) * 0.45))
		elif kind == "stumps":
			var size: float = random.randf_range(0.85, 1.2)
			batch(stumps[random.randi() % stumps.size()], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(point.x, ground(point.x, point.y) - 0.08, point.y)))
		else:
			var size: float = random.randf_range(0.45, 1.3)
			var tilt_angle: float = random.randf() * TAU
			var tilt: Basis = Basis(Vector3(cos(tilt_angle), 0.0, sin(tilt_angle)), random.randf_range(0.0, 0.25))
			batch(rock, Transform3D((tilt * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * size), Vector3(point.x, ground(point.x, point.y) - size * 0.15, point.y)))
		trunks.append(point)
		placed[kind] += 1
	for key: String in placed:
		count(key, placed[key])

func log_mesh(seed_value: int, length: float, radius: float) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var wood: SurfaceTool = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for step: int in range(7):
		var t: float = float(step) / 6.0
		points.append(Vector3((t - 0.5) * length, sin(t * 2.7) * 0.06, sin(t * 3.9 + 1.0) * 0.12))
		radii.append(radius * lerpf(1.08, 0.82, t) * random.randf_range(0.93, 1.05))
	tube(wood, points, radii, 8)
	splinter(wood, points[points.size() - 1], Vector3.RIGHT, radii[radii.size() - 1], random)
	splinter(wood, points[0], Vector3.LEFT, radii[0], random)
	for stub: int in range(3):
		var at: Vector3 = sample(points, random.randf_range(0.2, 0.85))
		var out: Vector3 = Vector3(random.randf_range(-0.3, 0.3), random.randf_range(0.2, 1.0), random.randf_range(-1.0, 1.0)).normalized()
		var tip: Vector3 = at + out * random.randf_range(0.5, 1.3)
		tube(wood, PackedVector3Array([at, tip]), PackedFloat32Array([radius * 0.32, radius * 0.18]), 5)
		splinter(wood, tip, out, radius * 0.18, random)
	wood.generate_tangents()
	wood.index()
	var mesh: ArrayMesh = wood.commit()
	mesh.surface_set_material(0, bark)
	mesh.set_meta("length", length)
	mesh.set_meta("radius", radius)
	return mesh

func stump(seed_value: int, height: float, radius: float) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var wood: SurfaceTool = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = Vector3(random.randf_range(-0.05, 0.05), height, random.randf_range(-0.05, 0.05))
	tube(wood, PackedVector3Array([Vector3(0, -0.3, 0), Vector3(0, height * 0.5, 0), top]), PackedFloat32Array([radius * 1.15, radius, radius * 0.92]), 8)
	splinter(wood, top, Vector3.UP, radius * 0.92, random, 0.45)
	flare(wood, radius * 0.9, random)
	wood.generate_tangents()
	wood.index()
	var mesh: ArrayMesh = wood.commit()
	mesh.surface_set_material(0, bark)
	return mesh

func rock_mesh(seed_value: int) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var rings: int = 6
	var segments: int = 10
	var positions: Array[Vector3] = [Vector3(0.0, 0.62, 0.0)]
	for ring: int in range(1, rings):
		var phi: float = PI * float(ring) / float(rings)
		for segment: int in range(segments):
			var theta: float = TAU * float(segment) / float(segments)
			var bump: float = random.randf_range(0.82, 1.15)
			var point: Vector3 = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * bump * Vector3(1.0, 0.62, 0.85)
			if point.y < -0.2:
				point.y = -0.2 + (point.y + 0.2) * 0.3
			positions.append(point)
	positions.append(Vector3(0.0, -0.26, 0.0))
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last: int = positions.size() - 1
	for segment: int in range(segments):
		var next: int = (segment + 1) % segments
		triangle(tool, positions[0], positions[1 + segment], positions[1 + next], Vector3.UP)
		triangle(tool, positions[last], positions[1 + (rings - 2) * segments + segment], positions[1 + (rings - 2) * segments + next], Vector3.DOWN)
		for ring: int in range(rings - 2):
			var a: Vector3 = positions[1 + ring * segments + segment]
			var b: Vector3 = positions[1 + ring * segments + next]
			var c: Vector3 = positions[1 + (ring + 1) * segments + segment]
			var d: Vector3 = positions[1 + (ring + 1) * segments + next]
			triangle(tool, a, b, d, (a + b + d) / 3.0)
			triangle(tool, a, d, c, (a + d + c) / 3.0)
	tool.index()
	tool.generate_normals()
	return tool.commit()

# --- Bog pools and dry reeds ----------------------------------------------------------------

## Two boggy patches on the flattest ground beside the trail, well clear of the village ground.
func flood_bogs() -> void:
	var candidates: Array[Vector3] = []
	for step: int in range(19):
		var z: float = -48.0 - float(step) * 2.0
		for side: float in [-1.0, 1.0]:
			for offset: float in [9.5, 11.5, 13.5, 15.5]:
				var point: Vector2 = Vector2(ChurchSite.road_x(z) + side * offset, z)
				if forbidden(point, 6.5, false):
					continue
				var centre: float = ground(point.x, point.y)
				var spread: float = 0.0
				for probe: int in range(8):
					var angle: float = TAU * float(probe) / 8.0
					spread = maxf(spread, absf(ground(point.x + cos(angle) * 5.5, point.y + sin(angle) * 5.5) - centre))
				candidates.append(Vector3(point.x, point.y, spread))
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	var water: ShaderMaterial = material("bog_water")
	for candidate: Vector3 in candidates:
		if pools.size() >= 2:
			break
		var point: Vector2 = Vector2(candidate.x, candidate.y)
		if not pools.is_empty() and point.distance_to(pools[0]) < 22.0:
			continue
		pools.append(point)
		var patch: MeshInstance3D = MeshInstance3D.new()
		patch.name = "BogPool"
		patch.mesh = terrain_patch([point], Vector2(12.0, 10.0))
		var surface: ShaderMaterial = water.duplicate() as ShaderMaterial
		surface.set_shader_parameter("seed", float(pools.size()) * 13.7)
		water_materials.append(surface)
		patch.material_override = surface
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(patch)
	count("bog pools", pools.size())

## Terrain-hugging grids (one per centre, UV 0..1 each) a few centimetres above the ground.
func terrain_patch(centres: Array[Vector2], size: Vector2) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells: Vector2i = Vector2i(maxi(int(size.x / 0.5), 4), maxi(int(size.y / 0.5), 4))
	for centre: Vector2 in centres:
		for z: int in range(cells.y):
			for x: int in range(cells.x):
				for corner: Vector2i in [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]:
					var uv: Vector2 = Vector2(corner) / Vector2(cells)
					var point: Vector2 = centre + (uv - Vector2(0.5, 0.5)) * size
					tool.set_uv(uv)
					tool.add_vertex(Vector3(point.x, ground(point.x, point.y) + 0.035, point.y))
	tool.generate_normals()
	tool.index()
	return tool.commit()

func grow_reeds() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 77401
	var straw: ShaderMaterial = material("dry_grass")
	straw.set_shader_parameter("living_share", 0.12)
	var reed: ArrayMesh = grass_clump(881, 16, Vector2(0.75, 1.55), 0.3, 0.13, 0.014, straw)
	var tuft: ArrayMesh = grass_clump(882, 15, Vector2(0.22, 0.55), 0.22, 0.75, 0.012, straw)
	var reeds: int = 0
	var tufts: int = 0
	for pool: Vector2 in pools:
		for index: int in range(80):
			var angle: float = random.randf() * TAU
			var point: Vector2 = pool + Vector2(cos(angle), sin(angle)) * random.randf_range(0.5, 6.5) * Vector2(1.0, 0.85)
			if forbidden(point, GROUND_CLEAR, false) or (in_pool(point) and random.randf() < 0.75):
				continue
			batch(reed, Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.75, 1.3)), Vector3(point.x, ground(point.x, point.y) - 0.05, point.y)))
			reeds += 1
	var patches: FastNoiseLite = FastNoiseLite.new()
	patches.seed = 77417
	patches.frequency = 0.09
	for attempt: int in range(4200):
		var z: float = random.randf_range(-124.0, -31.5)
		var offset: float = lerpf(GROUND_CLEAR, 18.0, pow(random.randf(), 1.2)) * (-1.0 if random.randf() < 0.5 else 1.0)
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + offset, z)
		var clump: float = patches.get_noise_2d(point.x, point.y)
		if clump < -0.05 or forbidden(point, GROUND_CLEAR, false) or in_pool(point):
			continue
		var tall: bool = clump > 0.35 and random.randf() < 0.5
		var placement: Transform3D = Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.7, 1.35)), Vector3(point.x, ground(point.x, point.y) - 0.03, point.y))
		batch(reed if tall else tuft, placement)
		if tall:
			reeds += 1
		else:
			tufts += 1
	count("reed clumps", reeds)
	count("dead grass tufts", tufts)

func grass_clump(seed_value: int, blades: int, height: Vector2, spread: float, bend: float, width: float, straw: ShaderMaterial) -> ArrayMesh:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade: int in range(blades):
		var angle: float = float(blade) * 2.4 + random.randf_range(-0.3, 0.3)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var edge: Vector3 = Vector3(-out.z, 0.0, out.x)
		var root: Vector3 = out * random.randf_range(0.0, spread)
		var tall: float = random.randf_range(height.x, height.y)
		var lean: float = random.randf_range(0.05, 0.25) + bend * random.randf()
		var shade: float = random.randf_range(0.75, 1.15)
		for segment: int in range(3):
			var t0: float = float(segment) / 3.0
			var t1: float = float(segment + 1) / 3.0
			var p0: Vector3 = root + Vector3.UP * tall * t0 * (1.0 - lean * t0 * 0.5) + out * tall * lean * t0 * t0
			var p1: Vector3 = root + Vector3.UP * tall * t1 * (1.0 - lean * t1 * 0.5) + out * tall * lean * t1 * t1
			var w0: float = width * (1.0 - t0)
			var w1: float = width * (1.0 - t1) + 0.001
			var corners: Array[Vector3] = [p0 - edge * w0, p0 + edge * w0, p1 + edge * w1, p1 - edge * w1]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				tool.set_color(Color(shade * lerpf(0.7, 1.05, t1), shade * lerpf(0.7, 1.0, t1), shade * lerpf(0.7, 0.95, t1)))
				tool.set_uv(Vector2(float(corner == 1 or corner == 2), t1))
				tool.add_vertex(corners[corner])
	tool.generate_normals()
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, straw)
	return mesh

# --- Light shafts and ground mist -----------------------------------------------------------

func hang_light_shafts() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 66013
	var light: Vector3 = Vector3(-0.55, -0.65, 0.52)
	for node: Node in village.find_children("*", "DirectionalLight3D", true, false):
		light = -(node as DirectionalLight3D).global_transform.basis.z
		break
	# Steeper than the low storm sun, so the shafts read as canopy gaps rather than a sunset.
	var flat: Vector3 = Vector3(light.x, 0.0, light.z).normalized()
	var slant: Vector3 = (flat * cos(deg_to_rad(62.0)) + Vector3.DOWN * sin(deg_to_rad(62.0))).normalized()
	var transforms: Array[Transform3D] = []
	for z: float in [-39.0, -48.0, -57.0, -64.0, -71.0, -78.0, -84.0, -95.0]:
		var landing: Vector2 = Vector2(ChurchSite.road_x(z) + random.randf_range(-7.0, 7.0), z + random.randf_range(-2.0, 2.0))
		if churchyard(landing):
			landing.x = 17.0
		var foot: Vector3 = Vector3(landing.x, ground(landing.x, landing.y) - 0.5, landing.y)
		var axis: Vector3 = slant * random.randf_range(16.0, 20.0)
		var across: Vector3 = axis.cross(Vector3.UP).normalized() * random.randf_range(1.4, 2.8)
		transforms.append(Transform3D(Basis(across, axis, across.cross(axis).normalized()), foot - axis))
	shaft_material = material("light_shaft")
	var shafts: MultiMeshInstance3D = card_batch(transforms, shaft_material)
	shafts.name = "LightShafts"
	count("light shafts", transforms.size())

## A few smouldering ember patches beside the trail: warm accents in the grey, no lights.
func smoulder() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 19403
	var centres: Array[Vector2] = []
	for attempt: int in range(300):
		if centres.size() >= 7:
			break
		var z: float = random.randf_range(-86.0, -36.0)
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + random.randf_range(3.8, 10.0) * (-1.0 if random.randf() < 0.5 else 1.0), z)
		if forbidden(point, 3.6) or steepness(point.x, point.y) > 1.2:
			continue
		var crowded: bool = false
		for other: Vector2 in centres:
			crowded = crowded or point.distance_to(other) < 8.0
		if not crowded:
			centres.append(point)
	var patches: MeshInstance3D = MeshInstance3D.new()
	patches.name = "Embers"
	patches.mesh = terrain_patch(centres, Vector2(2.2, 2.2))
	patches.material_override = material("embers")
	patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patches.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(patches)
	count("ember patches", centres.size())

## Sparse grey ash drifting down around the camera while it is in the forest (cosmetic, per peer;
## CPU particles, so no particle shader variants).
func drift_ash() -> void:
	var flake: QuadMesh = QuadMesh.new()
	flake.size = Vector2(0.045, 0.045)
	var look: StandardMaterial3D = StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(0.52, 0.54, 0.56)
	flake.material = look
	ash.name = "AshDrift"
	ash.amount = 240
	ash.lifetime = 14.0
	ash.local_coords = false
	ash.emitting = false
	ash.mesh = flake
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ash.emission_box_extents = Vector3(16.0, 7.0, 16.0)
	ash.gravity = Vector3(0.0, -0.22, 0.0)
	ash.direction = Vector3(1.0, 0.0, 0.4)
	ash.spread = 180.0
	ash.initial_velocity_min = 0.05
	ash.initial_velocity_max = 0.3
	ash.scale_amount_min = 0.6
	ash.scale_amount_max = 1.3
	ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ash)

func spread_ground_mist() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 24691
	var mist: ShaderMaterial = material("ground_mist")
	mist_material = mist
	var transforms: Array[Transform3D] = []
	for attempt: int in range(240):
		if transforms.size() >= 80:
			break
		var z: float = random.randf_range(-124.0, -33.0)
		var crossing: bool = random.randf() < 0.35
		var offset: float = random.randf_range(-3.0, 3.0) if crossing else random.randf_range(4.0, 22.0) * (-1.0 if random.randf() < 0.5 else 1.0)
		var point: Vector2 = Vector2(ChurchSite.road_x(z) + offset, z)
		if churchyard(point):
			continue
		var size: Vector3 = Vector3(random.randf_range(7.0, 14.0), random.randf_range(1.3, 2.4), 1.0)
		transforms.append(Transform3D(Basis.from_scale(size), Vector3(point.x, ground(point.x, point.y) - 0.35, point.y)))
	var cards: MultiMeshInstance3D = card_batch(transforms, mist)
	cards.name = "GroundMist"
	count("mist cards", transforms.size())

## Camera-facing cards: a unit quad x -0.5..0.5, y 0..1, oriented by each shader.
func card_batch(transforms: Array[Transform3D], card_material: ShaderMaterial) -> MultiMeshInstance3D:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector2] = [Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0)]
	for corner: int in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(Vector2(corners[corner].x + 0.5, corners[corner].y))
		tool.set_normal(Vector3.BACK)
		tool.add_vertex(Vector3(corners[corner].x, corners[corner].y, 0.0))
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = tool.commit()
	multi.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multi.set_instance_transform(index, transforms[index])
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.multimesh = multi
	visual.material_override = card_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The shaders turn each card toward the camera, beyond the flat quad's bounds.
	visual.extra_cull_margin = 8.0
	add_child(visual)
	return visual

# --- Existing village woodland outside the palisade -----------------------------------------

## 0: leave alone; 1: strip to bare branches; 2: keep a dark, desaturated crown.
func fate(point: Vector2) -> int:
	var near_yard: float = point.distance_to(ChurchSite.YARD_CENTER)
	var offset: float = absf(trail_offset(point))
	if point.y > -29.0 or (offset > 48.0 and near_yard > 42.0):
		return 0
	var chance: float = fposmod(sin(point.x * 12.9898 + point.y * 78.233) * 43758.5453, 1.0)
	if (offset < 24.0 or near_yard < 32.0) and chance < 0.8:
		return 1
	return 2

func subdue_village_trees() -> void:
	var bark_mesh: Mesh
	var crown_mesh: Mesh
	var stripped: int = 0
	var dimmed: int = 0
	var dead_bark: Color = Color(0.42, 0.42, 0.44)
	for node: Node in village.find_children("*", "Node3D", true, false):
		if node.get_script() != WOODLAND_TREE or node.get_child_count() < 2:
			continue
		var tree: Node3D = node as Node3D
		var trunk: MeshInstance3D = tree.get_child(0) as MeshInstance3D
		var crown: MeshInstance3D = tree.get_child(1) as MeshInstance3D
		bark_mesh = trunk.mesh
		crown_mesh = crown.mesh
		var verdict: int = fate(Vector2(tree.global_position.x, tree.global_position.z))
		if verdict == 0:
			continue
		var wood: StandardMaterial3D = trunk.material_override as StandardMaterial3D
		if wood != null:
			wood.albedo_color = dead_bark
		if verdict == 1:
			crown.visible = false
			stripped += 1
		else:
			var leaves: StandardMaterial3D = crown.material_override as StandardMaterial3D
			if leaves != null:
				leaves.albedo_color = gloomy(leaves.albedo_color)
				leaves.backlight = leaves.backlight.darkened(0.6)
			dimmed += 1
	for node: Node in village.find_children("*", "MultiMeshInstance3D", true, false):
		var visual: MultiMeshInstance3D = node as MultiMeshInstance3D
		var multi: MultiMesh = visual.multimesh
		if multi == null or multi.mesh == null:
			continue
		if multi.mesh == bark_mesh or multi.mesh == crown_mesh:
			for index: int in range(multi.instance_count):
				var placement: Transform3D = multi.get_instance_transform(index)
				var verdict: int = fate(Vector2(placement.origin.x, placement.origin.z))
				if verdict == 0:
					continue
				if multi.mesh == bark_mesh:
					multi.set_instance_color(index, dead_bark)
				elif verdict == 1:
					multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), placement.origin))
					stripped += 1
				else:
					multi.set_instance_color(index, gloomy(multi.get_instance_color(index)))
					dimmed += 1
			continue
		var shader_material: ShaderMaterial = visual.material_override as ShaderMaterial
		if shader_material == null or shader_material.shader == null:
			continue
		var code: String = shader_material.shader.code
		var trail_grass: bool = "ALBEDO=vec3(0.045,0.085,0.018)" in code and (visual.global_transform * multi.get_aabb()).get_center().z < -30.0
		if not trail_grass and not "ALBEDO=vec3(0.045,0.075,0.015)" in code:
			continue
		if trail_grass:
			# The trail-shoulder grass dies back to straw beyond the palisade.
			var straw: ShaderMaterial = material("dry_grass")
			straw.set_shader_parameter("living_share", 0.35)
			straw.set_shader_parameter("brightness", 0.8)
			visual.material_override = straw
			count("grass clumps faded", multi.instance_count)
		# Grass and ferns give way to open water in the bog pools.
		for index: int in range(multi.instance_count):
			var placement: Transform3D = visual.global_transform * multi.get_instance_transform(index)
			if in_pool(Vector2(placement.origin.x, placement.origin.z)):
				multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), multi.get_instance_transform(index).origin))
				count("plants cleared from pools")
	# Distant original tree-pack meshes north of the gate go dark as well, and a village boulder
	# that spills across the walking strip before the graveyard is hidden (it has no collision).
	var dark_plants: int = 0
	for node: Node in village.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if not visual.visible or visual.mesh == null:
			continue
		var bounds: AABB = visual.global_transform * visual.get_aabb()
		var centre: Vector3 = bounds.get_center()
		var surface: StandardMaterial3D = visual.get_active_material(0) as StandardMaterial3D
		if surface == null or surface.albedo_texture == null:
			continue
		var texture: String = surface.albedo_texture.resource_path
		if "StoneGeneric" in texture and centre.z < -30.0 and centre.z > -88.0 and absf(trail_offset(Vector2(centre.x, centre.z))) - maxf(bounds.size.x, bounds.size.z) * 0.5 < GROUND_CLEAR:
			visual.visible = false
			count("road boulders hidden")
			continue
		var plant: StandardMaterial3D = visual.material_override as StandardMaterial3D
		if plant == null or plant.albedo_texture == null or not "/tree_pack/textures/" in plant.albedo_texture.resource_path:
			continue
		if fate(Vector2(centre.x, centre.z)) != 0:
			plant.albedo_color = gloomy(plant.albedo_color)
			dark_plants += 1
	count("village trees stripped bare", stripped)
	count("village crowns darkened", dimmed + dark_plants)

static func gloomy(colour: Color) -> Color:
	var grey: float = colour.r * 0.3 + colour.g * 0.59 + colour.b * 0.11
	return Color(grey, grey, grey).lerp(colour, 0.35) * Color(0.5, 0.52, 0.52)

# --- Geometry helpers -----------------------------------------------------------------------

static func sides_for(radius: float) -> int:
	if radius >= 0.15:
		return 8
	if radius >= 0.06:
		return 6
	if radius >= 0.025:
		return 4
	return 3

static func perpendicular(axis: Vector3, angle: float) -> Vector3:
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u: Vector3 = axis.cross(reference).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	return u * cos(angle) + v * sin(angle)

static func sample(points: PackedVector3Array, t: float) -> Vector3:
	var position: float = clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index: int = mini(int(position), points.size() - 2)
	return points[index].lerp(points[index + 1], position - float(index))

## Front faces are clockwise in Godot; order the corners so the face looks along `outward`.
static func triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var corners: Array[Vector3] = [a, b, c]
	if (c - a).cross(b - a).dot(outward) < 0.0:
		corners = [a, c, b]
	var face: Vector3 = (corners[2] - corners[0]).cross(corners[1] - corners[0]).normalized()
	for index: int in range(3):
		tool.set_normal(face)
		tool.set_uv(Vector2(float(index) * 0.5, float(index % 2)))
		tool.add_vertex(corners[index])

## A tapered tube along `points` with parallel-transported rings; normals point outward.
static func tube(tool: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, sides: int) -> void:
	var total: int = points.size()
	var first: Vector3 = (points[1] - points[0]).normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(first.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var normal: Vector3 = first.cross(reference).normalized()
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var along: PackedFloat32Array = PackedFloat32Array()
	var distance: float = 0.0
	for index: int in range(total):
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - points[0]
		elif index == total - 1:
			tangent = points[index] - points[index - 1]
		else:
			tangent = points[index + 1] - points[index - 1]
		tangent = tangent.normalized()
		normal = (normal - tangent * normal.dot(tangent)).normalized()
		var binormal: Vector3 = tangent.cross(normal)
		if index > 0:
			distance += points[index].distance_to(points[index - 1])
		along.append(distance)
		var ring: PackedVector3Array = PackedVector3Array()
		var ring_normals: PackedVector3Array = PackedVector3Array()
		for side: int in range(sides + 1):
			var angle: float = TAU * float(side) / float(sides)
			var direction: Vector3 = normal * cos(angle) + binormal * sin(angle)
			ring.append(points[index] + direction * radii[index])
			ring_normals.append(direction)
		rings.append(ring)
		normals.append(ring_normals)
	# Bark repeats about every 0.9 m around thick trunks and every 1.2 m along them.
	var around: float = maxf(1.0, roundf(TAU * radii[0] / 0.9))
	for index: int in range(total - 1):
		for side: int in range(sides):
			for corner: Vector2i in [Vector2i(index, side), Vector2i(index + 1, side + 1), Vector2i(index, side + 1), Vector2i(index, side), Vector2i(index + 1, side), Vector2i(index + 1, side + 1)]:
				tool.set_normal(normals[corner.x][corner.y])
				tool.set_uv(Vector2(float(corner.y) / float(sides) * around, along[corner.x] / 1.2))
				tool.add_vertex(rings[corner.x][corner.y])
