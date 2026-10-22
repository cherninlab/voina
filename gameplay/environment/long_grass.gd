class_name LongGrass
extends Node3D
## A long night walk: a trodden road winds through a field of tall grass, opening now and then
## into a campfire clearing whose cultists wake as players approach, and midway between two fires
## into a small trampled space where more rise from the grass (CampMobs). Camps and ambushes are
## the road's encounter sites, in road order (site_*). Everything comes
## from long_grass.tres (LongGrassSettings) and its seed, so every peer generates the same road.
## Flat ground at y = 0; the grass is cosmetic (no collision) and an invisible fence keeps players
## within field_half_width of the road. The road ends in a last clearing around its final fire.
## Dirt textures are the village's (content/environments/village_generated); pine sprites line the
## horizon (content/environments/long_grass). See docs/long-grass.md.

const SETTINGS: LongGrassSettings = preload("res://gameplay/environment/long_grass.tres")
const CHUNK: float = 30.0 # road metres per grass multimesh, so far chunks are culled whole
const BLADES: int = 11
const GROUND: String = "res://content/environments/village_generated/"
var settings: LongGrassSettings = SETTINGS
var points: PackedVector3Array = PackedVector3Array() # road centre line, one per settings.step
var camp_stations: PackedFloat32Array = PackedFloat32Array() # road distance of each clearing
var camps: PackedVector3Array = PackedVector3Array() # clearing centres, on the road
var fires: PackedVector3Array = PackedVector3Array() # each camp's fire, beside the road
var camp_cultists: PackedInt32Array = PackedInt32Array()
var ambush_stations: PackedFloat32Array = PackedFloat32Array() # midway between two camps
# Every encounter in road order: its road distance, where its cultists gather (a camp's fire, an
# ambush's centre), how many, and whether it is a camp (else an ambush).
var site_stations: PackedFloat32Array = PackedFloat32Array()
var site_anchors: PackedVector3Array = PackedVector3Array()
var site_cultists: PackedInt32Array = PackedInt32Array()
var site_camp: Array[bool] = []
var grass_clumps: int = 0
var tree_count: int = 0
var objective: Label = Label.new()

func _ready() -> void:
	name = "LongGrass"
	generate()
	night()
	ground()
	road()
	fence()
	treeline()
	var flame: ShaderMaterial = ShaderMaterial.new()
	flame.shader = preload("res://content/environments/church_road/torch_flame.gdshader")
	for index: int in range(camps.size()):
		camp(index, flame)
	for station: float in ambush_stations:
		ambush_space(station)
	# Grass is presentation only; headless tests and servers skip the field.
	if DisplayServer.get_name() != "headless":
		grass()
	hud()
	print("LONG_GRASS_READY: %d m road, %d camps (%s cultists), %d ambushes, %d grass clumps, %d trees, seed %d" % [roundi(settings.length), camps.size(), ",".join(PackedStringArray(Array(camp_cultists).map(func(count: int) -> String: return str(count)))), ambush_stations.size(), grass_clumps, tree_count, settings.road_seed])

## The road, then the clearings along it. Only the seed and settings decide them.
func generate() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = settings.road_seed
	var heading: float = 0.0
	var at: Vector3 = Vector3.ZERO
	points.clear()
	points.append(at)
	for index: int in range(ceili(settings.length / settings.step)):
		heading += deg_to_rad(rng.randf_range(-settings.turn, settings.turn))
		heading -= heading * settings.straighten
		heading = clampf(heading, -deg_to_rad(settings.max_heading), deg_to_rad(settings.max_heading))
		at += Vector3(sin(heading), 0.0, -cos(heading)) * settings.step
		points.append(at)
	var station: float = settings.first_camp
	var last: float = road_length()
	while station < last - settings.camp_spacing * 0.5:
		camp_stations.append(station)
		station += settings.camp_spacing + rng.randf_range(-settings.camp_jitter, settings.camp_jitter)
	camp_stations.append(last) # the road ends in a clearing around the last fire
	for index: int in range(camp_stations.size()):
		var centre: Vector3 = point_at(camp_stations[index])
		camps.append(centre)
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var aside: float = 0.0 if index == camp_stations.size() - 1 else 3.2
		fires.append(centre + normal_at(camp_stations[index]) * side * aside)
		var count: int = mini(settings.cultists_max, settings.cultists_first + floori(float(index) * settings.camp_growth))
		camp_cultists.append(settings.cultists_max if index == camp_stations.size() - 1 else count)
	for index: int in range(camp_stations.size()):
		site_stations.append(camp_stations[index])
		site_anchors.append(fires[index])
		site_cultists.append(camp_cultists[index])
		site_camp.append(true)
		if settings.ambushes and index + 1 < camp_stations.size():
			var middle: float = (camp_stations[index] + camp_stations[index + 1]) * 0.5
			ambush_stations.append(middle)
			site_stations.append(middle)
			site_anchors.append(point_at(middle))
			site_cultists.append(settings.ambush_cultists)
			site_camp.append(false)

func road_length() -> float:
	return float(points.size() - 1) * settings.step

# Past either end it continues straight on, for the field and fence around the road's ends.
func point_at(station: float) -> Vector3:
	if station < 0.0:
		return points[0] + tangent_at(0.0) * station
	if station > road_length():
		return points[points.size() - 1] + tangent_at(road_length()) * (station - road_length())
	var at: float = station / settings.step
	var index: int = mini(floori(at), points.size() - 2)
	return points[index].lerp(points[index + 1], at - float(index))

## Where the field and fence stop: a little behind the start, and around the final clearing.
func field_start() -> float:
	return -8.0

func field_end() -> float:
	return road_length() + settings.camp_radius + 6.0

func tangent_at(station: float) -> Vector3:
	var index: int = clampi(floori(station / settings.step), 0, points.size() - 2)
	return (points[index + 1] - points[index]).normalized()

# Left of the direction of travel.
func normal_at(station: float) -> Vector3:
	var tangent: Vector3 = tangent_at(station)
	return Vector3(tangent.z, 0.0, -tangent.x)

## Nearest road distance to a point, searched around a station guess (the road never doubles back).
func station_of(at: Vector3, near: float = -1.0, window: int = 8) -> float:
	var first: int = 0
	var last: int = points.size() - 2
	if near >= 0.0:
		first = maxi(0, floori(near / settings.step) - window)
		last = mini(points.size() - 2, floori(near / settings.step) + window)
	var best: float = INF
	var best_station: float = 0.0
	for index: int in range(first, last + 1):
		var a: Vector3 = points[index]
		var segment: Vector3 = points[index + 1] - a
		var along: float = clampf((at - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var distance: float = (a + segment * along).distance_squared_to(at)
		if distance < best:
			best = distance
			best_station = (float(index) + along) * settings.step
	return best_station

func distance_to_road(at: Vector3, near: float) -> float:
	return point_at(station_of(at, near, ceili(grass_half_width() / settings.step))).distance_to(at)

# The fence stands at field_half_width; the grass carries on past it.
func grass_half_width() -> float:
	return settings.field_half_width + settings.grass_beyond_fence

func player_spawn(slot: int) -> Vector3:
	var station: float = 4.0 + float(slot / 2) * 2.0
	return point_at(station) + normal_at(station) * (0.95 if slot % 2 == 0 else -0.95) + Vector3.UP * 0.95

func night() -> void:
	var yaw: float = deg_to_rad(settings.moon_yaw)
	var height: float = deg_to_rad(settings.moon_height)
	var toward_moon: Vector3 = Vector3(sin(yaw) * cos(height), sin(height), -cos(yaw) * cos(height))
	var sky_material: ShaderMaterial = ShaderMaterial.new()
	sky_material.shader = preload("res://gameplay/environment/moon_sky.gdshader")
	sky_material.set_shader_parameter("panorama", load("res://content/environments/grim/storm_sky.png"))
	sky_material.set_shader_parameter("moon_dir", toward_moon)
	sky_material.set_shader_parameter("moon_radius", deg_to_rad(settings.moon_size))
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.2, 0.25, 0.36)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.035, 0.045, 0.065)
	environment.fog_density = settings.fog_density
	environment.fog_sky_affect = 0.15
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.62, 0.7, 0.92)
	moon.light_energy = settings.moonlight
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)
	moon.basis = Basis.looking_at(-toward_moon, Vector3.UP)

func ground() -> void:
	var low: Vector3 = Vector3(INF, 0, INF)
	var high: Vector3 = Vector3(-INF, 0, -INF)
	for point: Vector3 in points:
		low = Vector3(minf(low.x, point.x), 0, minf(low.z, point.z))
		high = Vector3(maxf(high.x, point.x), 0, maxf(high.z, point.z))
	var margin: float = settings.trees_far + 20.0
	var size: Vector3 = Vector3(high.x - low.x + margin * 2.0, 1.0, high.z - low.z + margin * 2.0)
	var centre: Vector3 = (low + high) * 0.5
	var soil: StandardMaterial3D = dirt("mineral_earth.png", 2.5, Color(0.32, 0.36, 0.3))
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = plane
	visual.material_override = soil
	visual.position = centre
	add_child(visual)
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = centre - Vector3.UP * 0.5
	body.add_child(collision)
	add_child(body)

# One flat ribbon along the centre line, a hair above the soil.
func road() -> void:
	var path: StandardMaterial3D = dirt("compacted_path.png", 1.5, Color(0.5, 0.48, 0.45))
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	var half: float = settings.path_width * 0.5
	for index: int in range(points.size() - 1):
		var a: float = float(index) * settings.step
		var b: float = a + settings.step
		var a_left: Vector3 = points[index] + normal_at(a) * half + Vector3.UP * 0.012
		var a_right: Vector3 = points[index] - normal_at(a) * half + Vector3.UP * 0.012
		var b_left: Vector3 = points[index + 1] + normal_at(minf(b, road_length() - 0.01)) * half + Vector3.UP * 0.012
		var b_right: Vector3 = points[index + 1] - normal_at(minf(b, road_length() - 0.01)) * half + Vector3.UP * 0.012
		for vertex: Vector3 in [a_left, b_left, a_right, a_right, b_left, b_right]:
			surface.add_vertex(vertex)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = surface.commit()
	visual.material_override = path
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

# Invisible walls field_half_width either side of the road, in chords of four road points, and
# across both ends.
func fence() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Fence"
	add_child(body)
	var stride: float = settings.step * 4.0
	var station: float = field_start()
	while station < field_end():
		var next: float = minf(station + stride, field_end())
		for side: float in [-1.0, 1.0]:
			wall(body, point_at(station) + normal_at(station) * side * settings.field_half_width, point_at(next) + normal_at(next) * side * settings.field_half_width)
		station = next
	for end: float in [field_start(), field_end()]:
		var across: Vector3 = normal_at(end) * settings.field_half_width
		wall(body, point_at(end) - across, point_at(end) + across)

func dirt(file: String, metres: float, tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(GROUND + file) as Texture2D
	material.albedo_color = tint
	material.roughness = 1.0
	# Projected from above in world metres: no UVs to build, and every piece tiles seamlessly.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / metres
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

## Pines in stands either side of the road and beyond both ends, past the fence, three per side
## every tree_spacing metres where a stand stands. Each is three crossed sprites of one of three
## pines; fog would swallow them at this range, so they ignore it (horizon_pines.gdshader).
func treeline() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = settings.road_seed + 2
	var placements: Array[Transform3D] = []
	var variants: Array[float] = []
	var near: float = maxf(settings.trees_near, grass_half_width() + 8.0)
	var far: float = maxf(settings.trees_far, near + 10.0)
	var stand: float = 0.0
	var station: float = -far
	while station < road_length() + far:
		# Stands come and go along the road; tree_gaps of it is left open.
		if absf(fmod(station, 60.0)) < settings.tree_spacing:
			stand = rng.randf()
		if stand >= settings.tree_gaps:
			for side: float in [-1.0, 1.0, -1.0, 1.0, -1.0, 1.0]:
				var at: Vector3 = point_at(station + rng.randf_range(-0.5, 0.5) * settings.tree_spacing) + normal_at(clampf(station, 0.0, road_length())) * side * rng.randf_range(near, far)
				if distance_to_road(at, clampf(station, 0.0, road_length())) < near * 0.8 or end_distance(at) < near * 0.8:
					continue
				var height: float = rng.randf_range(settings.tree_height_min, settings.tree_height_max)
				var width: float = height * rng.randf_range(0.85, 1.15)
				placements.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width)), at))
				variants.append(float(rng.randi_range(0, 2)))
		station += settings.tree_spacing
	if placements.is_empty():
		return
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = pine_mesh()
	multi.instance_count = placements.size()
	for index: int in range(placements.size()):
		multi.set_instance_transform(index, placements[index])
		multi.set_instance_custom_data(index, Color(variants[index], 0.0, 0.0, 0.0))
	var dark: ShaderMaterial = ShaderMaterial.new()
	dark.shader = preload("res://gameplay/environment/horizon_pines.gdshader")
	dark.set_shader_parameter("atlas", load("res://content/environments/long_grass/horizon_pines.png"))
	dark.set_shader_parameter("tint", settings.tree_tint)
	var wood: MultiMeshInstance3D = MultiMeshInstance3D.new()
	wood.name = "Treeline"
	wood.multimesh = multi
	wood.material_override = dark
	wood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wood)
	tree_count = placements.size()

# Distance to the road's start or end point, which station_of() clamps to.
func end_distance(at: Vector3) -> float:
	return minf(points[0].distance_to(at), points[points.size() - 1].distance_to(at))

# Three quads crossed at 60 degrees, 1 m tall and as wide as an atlas cell (512 x 768) allows, the
# trunk foot at the origin.
func pine_mesh() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = 512.0 / 768.0 * 0.5
	for quad: int in range(3):
		var angle: float = PI * float(quad) / 3.0
		var across: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * half
		surface.set_normal(Vector3(-sin(angle), 0.0, cos(angle)))
		var corners: Array[Vector3] = [-across, across, across + Vector3.UP, -across + Vector3.UP]
		var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for corner: int in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(uvs[corner])
			surface.add_vertex(corners[corner])
	return surface.commit()

func wall(body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(a.distance_to(b) + 1.0, 4.0, 0.5)
	collision.shape = shape
	collision.position = (a + b) * 0.5 + Vector3.UP * 2.0
	collision.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	body.add_child(collision)

func camp(index: int, flame: ShaderMaterial) -> void:
	var trodden: StandardMaterial3D = dirt("soil_gravel.png", 2.5, Color(0.5, 0.48, 0.45))
	var clearing: CylinderMesh = CylinderMesh.new()
	clearing.top_radius = settings.camp_radius
	clearing.bottom_radius = settings.camp_radius
	clearing.height = 0.02
	clearing.radial_segments = 32
	add_mesh(clearing, camps[index] + Vector3.UP * 0.006, trodden)
	var fire: Vector3 = fires[index]
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.21, 0.2)
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.1, 0.06)
	var ember: StandardMaterial3D = StandardMaterial3D.new()
	ember.albedo_color = Color(0.2, 0.05, 0.02)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.35, 0.08)
	ember.emission_energy_multiplier = 2.0
	for ring: int in range(9):
		var angle: float = TAU * float(ring) / 9.0
		var rock: BoxMesh = BoxMesh.new()
		rock.size = Vector3(0.32, 0.2, 0.26)
		add_mesh(rock, fire + Vector3(cos(angle) * 0.75, 0.1, sin(angle) * 0.75), stone).rotation.y = angle
	for log_index: int in range(3):
		var log_mesh: CylinderMesh = CylinderMesh.new()
		log_mesh.top_radius = 0.07
		log_mesh.bottom_radius = 0.09
		log_mesh.height = 1.0
		var piece: MeshInstance3D = add_mesh(log_mesh, fire + Vector3.UP * 0.14, ember if log_index == 0 else wood)
		piece.rotation = Vector3(PI * 0.5, float(log_index) * TAU / 3.0, 0.0)
	# Two seats for the camp, facing the fire.
	for seat: int in range(2):
		var angle: float = float(index) * 1.7 + float(seat) * PI
		var bench: CylinderMesh = CylinderMesh.new()
		bench.top_radius = 0.2
		bench.bottom_radius = 0.22
		bench.height = 1.8
		var piece: MeshInstance3D = add_mesh(bench, fire + Vector3(cos(angle) * 2.3, 0.2, sin(angle) * 2.3), wood)
		piece.rotation = Vector3(PI * 0.5, -angle, 0.0)
	var blaze: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.9, 1.3)
	blaze.mesh = quad
	blaze.material_override = flame
	blaze.position = fire + Vector3.UP * 0.75
	blaze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blaze.set_instance_shader_parameter("seed", float(index) * 0.137)
	add_child(blaze)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = fire + Vector3.UP * 1.1
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = 2.6
	light.omni_range = 13.0
	light.omni_attenuation = 1.3
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	add_child(light)

func add_mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)
	return visual

## Tall grass in road chunks: clumps on a jittered grid in road coordinates, kept off the path and
## out of the clearings.
func grass() -> void:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://gameplay/environment/tall_grass.gdshader")
	material.set_shader_parameter("root_color", settings.grass_root)
	material.set_shader_parameter("tip_color", settings.grass_tip)
	material.set_shader_parameter("wind", settings.wind)
	var clump: ArrayMesh = clump_mesh()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = settings.road_seed + 1
	var cell: float = 1.0 / sqrt(settings.grass_density)
	var clear_path: float = settings.path_width * 0.5 + 0.15
	var chunk_start: float = field_start()
	while chunk_start < field_end():
		var origin: Vector3 = point_at(chunk_start + CHUNK * 0.5)
		var placements: Array[Transform3D] = []
		var shades: Array[Color] = []
		var station: float = chunk_start
		while station < minf(chunk_start + CHUNK, field_end()):
			var normal: Vector3 = normal_at(station)
			var lateral: float = clear_path
			while lateral < grass_half_width():
				for side: float in [-1.0, 1.0]:
					var along: float = station + rng.randf_range(-0.5, 0.5) * cell
					var across: float = (lateral + rng.randf_range(0.0, 1.0) * cell) * side
					var at: Vector3 = point_at(along) + normal * across
					if absf(across) > grass_half_width() or in_clearing(at, along) or distance_to_road(at, along) < clear_path:
						continue
					var height: float = rng.randf_range(settings.grass_height_min, settings.grass_height_max)
					var width: float = rng.randf_range(0.8, 1.3)
					placements.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width)), at - origin))
					var shade: float = rng.randf_range(0.75, 1.15)
					shades.append(Color(shade, shade * rng.randf_range(0.95, 1.05), shade))
				lateral += cell
			station += cell
		if not placements.is_empty():
			var multi: MultiMesh = MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = clump
			multi.instance_count = placements.size()
			for index: int in range(placements.size()):
				multi.set_instance_transform(index, placements[index])
				multi.set_instance_color(index, shades[index])
			var field: MultiMeshInstance3D = MultiMeshInstance3D.new()
			field.multimesh = multi
			field.material_override = material
			field.position = origin
			field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			field.visibility_range_end = settings.grass_view_distance + CHUNK * 0.5
			field.visibility_range_end_margin = 10.0
			field.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(field)
			grass_clumps += placements.size()
		chunk_start += CHUNK

func in_clearing(at: Vector3, station: float) -> bool:
	for index: int in range(camps.size()):
		if absf(camp_stations[index] - station) < settings.camp_radius * 2.0 and camps[index].distance_to(at) < settings.camp_radius:
			return true
	for middle: float in ambush_stations:
		if absf(middle - station) < settings.ambush_radius * 2.0 and point_at(middle).distance_to(at) < settings.ambush_radius:
			return true
	return false

# A small trampled patch with no fire: the grass parts, and what waits in it does not show.
func ambush_space(station: float) -> void:
	var trampled: CylinderMesh = CylinderMesh.new()
	trampled.top_radius = settings.ambush_radius
	trampled.bottom_radius = settings.ambush_radius
	trampled.height = 0.02
	trampled.radial_segments = 24
	add_mesh(trampled, point_at(station) + Vector3.UP * 0.006, dirt("soil_gravel.png", 2.5, Color(0.42, 0.42, 0.4)))

# BLADES thin triangles around a 0.3 m clump, 1 m tall before each instance's height scale.
func clump_mesh() -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	for blade: int in range(BLADES):
		var base: Vector3 = Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var facing: float = rng.randf() * TAU
		var side: Vector3 = Vector3(cos(facing), 0.0, sin(facing)) * rng.randf_range(0.018, 0.035)
		var lean: Vector3 = Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))
		var tall: float = rng.randf_range(0.7, 1.0)
		surface.set_uv(Vector2(0.0, 0.0))
		surface.add_vertex(base - side)
		surface.set_uv(Vector2(1.0, 0.0))
		surface.add_vertex(base + side)
		surface.set_uv(Vector2(0.5, tall))
		surface.add_vertex(base + lean + Vector3.UP * tall)
	return surface.commit()

func hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_left = 300
	objective.offset_right = -24
	objective.offset_top = 24
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.86, 0.84, 0.74))
	objective.add_theme_color_override("font_outline_color", Color.BLACK)
	objective.add_theme_constant_override("outline_size", 5)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(objective)

func _process(_delta: float) -> void:
	var world: Node3D = get_parent() as Node3D
	var players: Node3D = world.get("players") as Node3D
	var local: Node3D = players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	objective.visible = local != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if local == null or not objective.visible:
		return
	var mobs: Node = world.get("mobs") as Node
	var cleared: int = int(mobs.get("cleared"))
	var active: int = int(mobs.get("active"))
	var left: int = roundi(road_length() - station_of(local.position))
	var line: String = "%d m to the last fire" % left
	if active >= 0 and active < site_camp.size() and int(mobs.get("alive")) > 0:
		line = "%d cultists %s" % [int(mobs.get("alive")), "at the fire" if site_camp[active] else "in the grass"]
	elif local.position.distance_to(fires[fires.size() - 1]) < settings.camp_radius:
		line = "The road ends here."
	objective.text = "LONG GRASS  ·  %d / %d fights won\n%s" % [cleared, site_stations.size(), line]
