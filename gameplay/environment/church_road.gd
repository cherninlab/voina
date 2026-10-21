extends Node3D
## Small burning stakes along the north trail from the village gate to the church (ChurchSite).
## Cosmetic only: no collision, gameplay or network state.
##
## The Mobile renderer applies at most eight omni lights to one mesh instance: those with the lowest
## distance-from-the-mesh's-centre / (range * energy). The landscape is one 576 m mesh centred under
## the village, so every lantern, church or forest light in the level competes for its eight slots
## and torch pools on the bare landscape come and go with what else is built. The pools therefore
## land on a thin wet-mud overlay laid over the trail in eight-metre chunks; each chunk is its own
## mesh and pairs only with the two or three torches beside it.

const SHADERS: String = "res://content/environments/church_road/"
const SEED: int = 86086
const LAST_TORCH_Z: float = -84.0 # the church gate pillars carry their own torches at the road end
const TORCH_SPACING: Vector2 = Vector2(7.0, 9.0)
const TORCH_OFFSET: Vector2 = Vector2(2.3, 2.7)
const STRIP_HALF_WIDTH: float = 1.9
const STRIP_LIFT: float = 0.03 # above the exact landscape triangles; covers chord sag at creases
const STRIP_STEP: float = 0.5
const STRIP_COLUMNS: int = 10
const CHUNK_STATIONS: int = 16 # eight metres per chunk
const LIGHT_ENERGY: float = 3.1
const LIGHT_RANGE: float = 7.0
const LIGHT_FALLOFF: float = 1.6 # steeper than the default so each torch makes its own pool
const FLAME_SIZE: Vector2 = Vector2(0.46, 0.78)
const HALO_SIZE: float = 2.2
enum State { LIT, SMOULDERING, DEAD }

## One burning head: its light (lit torches only) and the glowing meshes that share its flicker.
class Fire:
	var light: OmniLight3D
	var base_heat: float = 1.0
	var phase: float = 0.0
	var glowing: Array[GeometryInstance3D] = []

var village: Node3D
var fires: Array[Fire] = []
var torches: Array[Node3D] = []
var chunks: Array[MeshInstance3D] = []
var flicker: FastNoiseLite = FastNoiseLite.new()
var elapsed: float = 0.0
var fog_wait: float = 0.0
var fog_materials: Array[ShaderMaterial] = []
var stake_material: StandardMaterial3D = StandardMaterial3D.new()
var head_material: ShaderMaterial = ShaderMaterial.new()
var flame_material: ShaderMaterial = ShaderMaterial.new()
var halo_material: ShaderMaterial = ShaderMaterial.new()
var spark_material: ShaderMaterial = ShaderMaterial.new()
var smoke_material: ShaderMaterial = ShaderMaterial.new()
var mud_material: ShaderMaterial = ShaderMaterial.new()

func _ready() -> void:
	name = "ChurchRoad"
	set_process(false)
	# The village samples its landscape only after its own _ready.
	build.call_deferred()

func build() -> void:
	village = get_parent().get_node_or_null("WoodlandVillage") as Node3D
	if village == null:
		push_warning("ChurchRoad needs the WoodlandVillage sibling for terrain heights")
		return
	flicker.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	flicker.frequency = 1.0
	flicker.seed = SEED
	make_materials()
	road_strip()
	place_torches()
	update_fog()
	set_process(true)
	print("CHURCH_ROAD_OK: ", torches.size(), " torch stakes, ", lit_count(), " lit, ", chunks.size(), " mud chunks, ", lit_count(), " omni lights")

func lit_count() -> int:
	var count: int = 0
	for fire: Fire in fires:
		if fire.light != null:
			count += 1
	return count

# Visible ground: the exact landscape triangles, or the village's blended apron where that sits higher.
func surface_height(x: float, z: float) -> float:
	var height: float = float(village.call("landscape_surface_height", x, z))
	if x >= -3.5 and x <= 2.5 and z >= -37.0 and z <= -27.0:
		height = maxf(height, apron_height(x, z))
	return height

# The apron mesh from WoodlandVillage.open_north_approach: 0.5 m cells split along the same diagonal.
func apron_height(x: float, z: float) -> float:
	var cell: Vector2 = (Vector2(x, z) - Vector2(-3.5, -37.0)) / 0.5
	var base: Vector2 = cell.floor()
	var offset: Vector2 = cell - base
	var origin: Vector2 = base * 0.5 + Vector2(-3.5, -37.0)
	var near_height: float = apron_vertex(origin.x, origin.y)
	var right_height: float = apron_vertex(origin.x + 0.5, origin.y)
	var far_height: float = apron_vertex(origin.x, origin.y + 0.5)
	if offset.x + offset.y <= 1.0:
		return near_height + (right_height - near_height) * offset.x + (far_height - near_height) * offset.y
	var diagonal: float = apron_vertex(origin.x + 0.5, origin.y + 0.5)
	return diagonal + (far_height - diagonal) * (1.0 - offset.x) + (right_height - diagonal) * (1.0 - offset.y)

func apron_vertex(x: float, z: float) -> float:
	var blend: float = smoothstep(27.0, 34.0, -z)
	return lerpf(float(village.call("ground_height", x, z)), float(village.call("landscape_surface_height", x, z)), blend) + 0.015

static func road_point(z: float) -> Vector2:
	return Vector2(ChurchSite.road_x(z), z)

# Unit vector across the road toward +x at depth z.
static func road_across(z: float) -> Vector2:
	var along: Vector2 = Vector2(ChurchSite.road_x(z - 0.25) - ChurchSite.road_x(z + 0.25), -0.5).normalized()
	return Vector2(-along.y, along.x)

func make_materials() -> void:
	stake_material.albedo_texture = load("res://content/environments/village_generated/aged_timber.png") as Texture2D
	stake_material.albedo_color = Color(0.78, 0.7, 0.6)
	stake_material.vertex_color_use_as_albedo = true
	stake_material.roughness = 0.92
	stake_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	head_material.shader = load(SHADERS + "torch_head.gdshader") as Shader
	flame_material.shader = load(SHADERS + "torch_flame.gdshader") as Shader
	halo_material.shader = load(SHADERS + "torch_halo.gdshader") as Shader
	spark_material.shader = load(SHADERS + "torch_spark.gdshader") as Shader
	smoke_material.shader = load(SHADERS + "torch_smoke.gdshader") as Shader
	mud_material.shader = load(SHADERS + "road_mud.gdshader") as Shader
	mud_material.set_shader_parameter("trail", load("res://content/environments/village_generated/mineral_earth.png"))
	mud_material.set_shader_parameter("gravel", load("res://content/environments/village_generated/soil_gravel.png"))
	# Transparent, so sorted per 8 m chunk against blood marks and mist: drawn first, under both.
	mud_material.render_priority = -1
	fog_materials = [flame_material, halo_material, spark_material]

func road_strip() -> void:
	var stations: Array[float] = []
	var z: float = ChurchSite.ROAD_START_Z
	while z > ChurchSite.ROAD_END_Z - 0.01:
		stations.append(z)
		z -= STRIP_STEP
	var along: Array[float] = [0.0]
	for index: int in range(1, stations.size()):
		along.append(along[index - 1] + road_point(stations[index]).distance_to(road_point(stations[index - 1])))
	mud_material.set_shader_parameter("road_length", along[along.size() - 1])
	var start: int = 0
	while start < stations.size() - 1:
		var finish: int = mini(start + CHUNK_STATIONS, stations.size() - 1)
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row: int in range(start, finish):
			for column: int in range(STRIP_COLUMNS):
				# Clockwise from above, matching the landscape's front faces.
				for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var station: int = row + corner.y
					var across: float = -1.0 + 2.0 * float(column + corner.x) / float(STRIP_COLUMNS)
					var point: Vector2 = road_point(stations[station]) + road_across(stations[station]) * (across * STRIP_HALF_WIDTH)
					tool.set_uv(Vector2(across, along[station]))
					tool.add_vertex(Vector3(point.x, surface_height(point.x, point.y) + STRIP_LIFT, point.y))
		tool.generate_normals()
		tool.index()
		var chunk: MeshInstance3D = MeshInstance3D.new()
		chunk.name = "MudChunk%d" % chunks.size()
		chunk.mesh = tool.commit()
		chunk.material_override = mud_material
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(chunk)
		chunks.append(chunk)
		start = finish

func place_torches() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = SEED
	var spots: Array[Vector2] = [] # (z, side)
	var z: float = ChurchSite.ROAD_START_Z - 1.4
	var side: float = 1.0
	while z >= LAST_TORCH_Z - 0.5:
		spots.append(Vector2(z, side))
		z -= random.randf_range(TORCH_SPACING.x, TORCH_SPACING.y)
		side = -side
	for index: int in range(spots.size()):
		var state: State = State.LIT
		if index == spots.size() - 1:
			state = State.SMOULDERING # the last stake before the church gate has guttered out
		elif index == spots.size() - 3:
			state = State.DEAD # cold, knocked askew
		var depth: float = spots[index].x
		var outward: Vector2 = road_across(depth) * spots[index].y
		var ground: Vector2 = road_point(depth) + outward * random.randf_range(TORCH_OFFSET.x, TORCH_OFFSET.y)
		torch(Vector3(ground.x, surface_height(ground.x, ground.y), ground.y), Vector3(outward.x, 0.0, outward.y), state, random)

func torch(base: Vector3, outward: Vector3, state: State, random: RandomNumberGenerator) -> void:
	var root: Node3D = Node3D.new()
	root.name = "TorchStake%d" % torches.size()
	add_child(root)
	root.position = base
	torches.append(root)
	# A slightly crooked stake with a modest lean; the dead one has been knocked well over.
	var lean_axis: Vector3 = Vector3.UP.cross(outward.rotated(Vector3.UP, random.randf_range(-1.2, 1.2))).normalized()
	var lean: float = deg_to_rad(random.randf_range(1.5, 7.0))
	if state == State.DEAD:
		lean_axis = Vector3.UP.cross(outward.rotated(Vector3.UP, 0.5)).normalized()
		lean = deg_to_rad(21.0)
	var axis: Vector3 = Vector3.UP.rotated(lean_axis, lean)
	var height: float = random.randf_range(1.18, 1.4)
	var bow: Vector3 = axis.cross(Vector3(random.randf_range(-1.0, 1.0), 0.0, random.randf_range(-1.0, 1.0))).normalized()
	var spine: PackedVector3Array = PackedVector3Array()
	for step: int in range(6):
		var t: float = float(step) / 5.0
		var kink: Vector3 = Vector3(random.randf_range(-1.0, 1.0), 0.0, random.randf_range(-1.0, 1.0)) * 0.02
		if step == 0 or step == 5:
			kink = Vector3.ZERO
		spine.append(axis * lerpf(-0.24, height, t) + bow * sin(t * PI) * random.randf_range(0.03, 0.06) + kink)
	var stake: MeshInstance3D = MeshInstance3D.new()
	stake.name = "Stake"
	stake.mesh = stake_mesh(spine, height, random)
	stake.material_override = stake_material
	root.add_child(stake)
	var crown: Vector3 = spine[5]
	var head_length: float = 0.25 if state == State.LIT else 0.16
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "PitchHead"
	head.mesh = head_mesh(crown - axis * 0.07, axis, head_length, random)
	head.material_override = head_material
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	var fire: Fire = Fire.new()
	fire.phase = random.randf_range(0.0, 500.0)
	fire.base_heat = 1.0 if state == State.LIT else (0.32 if state == State.SMOULDERING else 0.0)
	var seed_value: float = random.randf_range(0.0, 50.0)
	head.set_instance_shader_parameter(&"seed", seed_value)
	head.set_instance_shader_parameter(&"heat", fire.base_heat)
	var rim: Vector3 = crown - axis * 0.07 + axis * head_length
	if state == State.LIT:
		var flame: MeshInstance3D = billboard("Flame", FLAME_SIZE, flame_material, rim - Vector3.UP * 0.07, root)
		(flame.mesh as QuadMesh).center_offset = Vector3(0.0, FLAME_SIZE.y * 0.5, 0.0)
		flame.set_instance_shader_parameter(&"seed", seed_value)
		var halo: MeshInstance3D = billboard("Glow", Vector2.ONE * HALO_SIZE, halo_material, rim + Vector3.UP * 0.2, root)
		fire.glowing = [flame, halo, head]
		fire.light = OmniLight3D.new()
		fire.light.name = "TorchLight"
		fire.light.light_color = Color(1.0, 0.52, 0.2)
		fire.light.light_energy = LIGHT_ENERGY
		fire.light.light_specular = 0.9
		fire.light.omni_range = LIGHT_RANGE
		fire.light.omni_attenuation = LIGHT_FALLOFF
		fire.light.shadow_enabled = false
		fire.light.light_bake_mode = Light3D.BAKE_DISABLED
		fire.light.position = rim + Vector3.UP * 0.3
		root.add_child(fire.light)
		root.add_child(embers(rim, 12, 1.5))
		root.add_child(smoke(rim + Vector3.UP * 0.35, 5, 0.12))
	elif state == State.SMOULDERING:
		fire.glowing = [head]
		root.add_child(embers(rim, 3, 0.8))
		root.add_child(smoke(rim, 6, 0.2))
	fires.append(fire)

func stake_mesh(spine: PackedVector3Array, height: float, random: RandomNumberGenerator) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 7
	var rings: Array[PackedVector3Array] = []
	var ring_colors: Array[Color] = []
	var ring_v: Array[float] = []
	var length: float = 0.0
	for step: int in range(spine.size()):
		var t: float = float(step) / float(spine.size() - 1)
		if step > 0:
			length += spine[step].distance_to(spine[step - 1])
		var direction: Vector3 = (spine[mini(step + 1, spine.size() - 1)] - spine[maxi(step - 1, 0)]).normalized()
		var tangent: Vector3 = direction.cross(Vector3.FORWARD).normalized()
		var binormal: Vector3 = direction.cross(tangent)
		var radius: float = lerpf(0.04, 0.028, t) * random.randf_range(0.9, 1.1)
		if step == 0:
			radius = 0.012 # sharpened point, buried
		var ring: PackedVector3Array = PackedVector3Array()
		for corner: int in range(sides + 1):
			var angle: float = TAU * float(corner % sides) / float(sides)
			var bark: float = 1.0 + 0.07 * sin(angle * 3.0 + float(step) * 1.7)
			ring.append(spine[step] + (tangent * cos(angle) + binormal * sin(angle)) * radius * bark)
		rings.append(ring)
		# Soot creeps down from the head; mud splashes the foot.
		var soot: float = 1.0 - smoothstep(0.62, 1.0, spine[step].y / height) * 0.82
		var mud: float = lerpf(0.55, 1.0, smoothstep(-0.05, 0.3, spine[step].y))
		ring_colors.append(Color(soot * mud, soot * mud * 0.97, soot * mud * 0.94))
		ring_v.append(length * 0.7)
	# Clockwise seen from outside: Godot's front faces.
	for step: int in range(rings.size() - 1):
		for corner: int in range(sides):
			for vertex: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var ring_index: int = step + vertex.y
				tool.set_color(ring_colors[ring_index])
				tool.set_uv(Vector2(float(corner + vertex.x) / float(sides) * 0.3, ring_v[ring_index]))
				tool.add_vertex(rings[ring_index][corner + vertex.x])
	tool.generate_normals()
	return tool.commit()

func head_mesh(bottom: Vector3, axis: Vector3, length: float, random: RandomNumberGenerator) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 12
	var ring_count: int = 9
	var tangent: Vector3 = axis.cross(Vector3.FORWARD).normalized()
	var binormal: Vector3 = axis.cross(tangent)
	var lumps: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(sides * (ring_count + 1)):
		lumps.append(random.randf_range(-0.09, 0.09))
	var rings: Array[PackedVector3Array] = []
	for step: int in range(ring_count + 1):
		var t: float = float(step) / float(ring_count)
		# A bundle that swells over the stake and closes in at the burnt rim.
		var radius: float = 0.036 + 0.036 * sin(PI * minf(t * 1.2, 1.0)) - 0.01 * smoothstep(0.85, 1.0, t)
		var ring: PackedVector3Array = PackedVector3Array()
		for corner: int in range(sides + 1):
			var angle: float = TAU * float(corner % sides) / float(sides)
			var wrap: float = 1.0 + 0.075 * sin(TAU * (t * 4.5 + float(corner) / float(sides)))
			var bump: float = 1.0 + lumps[step * sides + corner % sides]
			ring.append(bottom + axis * (t * length) + (tangent * cos(angle) + binormal * sin(angle)) * radius * wrap * bump)
		rings.append(ring)
	for step: int in range(ring_count):
		for corner: int in range(sides):
			for vertex: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				tool.set_uv(Vector2(float(corner + vertex.x) / float(sides), float(step + vertex.y) / float(ring_count)))
				tool.add_vertex(rings[step + vertex.y][corner + vertex.x])
	# A slightly sunken, charred cap.
	var cap: Vector3 = bottom + axis * (length - 0.008)
	for corner: int in range(sides):
		tool.set_uv(Vector2(0.5, 1.15))
		tool.add_vertex(cap)
		tool.set_uv(Vector2(float(corner + 1) / float(sides), 1.0))
		tool.add_vertex(rings[ring_count][corner + 1])
		tool.set_uv(Vector2(float(corner) / float(sides), 1.0))
		tool.add_vertex(rings[ring_count][corner])
	tool.generate_normals()
	return tool.commit()

func billboard(label: String, size: Vector2, material: ShaderMaterial, point: Vector3, parent: Node3D) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = label
	visual.mesh = quad
	visual.material_override = material
	visual.position = point
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visual.extra_cull_margin = maxf(size.x, size.y)
	parent.add_child(visual)
	return visual

# CPU particles: a few dozen sparks in all, and no per-emitter process shader to compile or free.
func embers(point: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var emitter: CPUParticles3D = particles("Embers", point, amount, lifetime, spark_material)
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 0.05
	emitter.direction = Vector3.UP
	emitter.spread = 28.0
	emitter.initial_velocity_min = 0.25
	emitter.initial_velocity_max = 0.75
	emitter.gravity = Vector3(0.12, 0.45, 0.05)
	emitter.damping_min = 0.2
	emitter.damping_max = 0.5
	emitter.tangential_accel_min = -0.5 # a sideways wander as they rise
	emitter.tangential_accel_max = 0.5
	emitter.scale_amount_min = 0.012
	emitter.scale_amount_max = 0.028
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.32, 1.0))
	ramp.set_color(1, Color(0.7, 0.06, 0.0, 0.0))
	ramp.add_point(0.45, Color(1.0, 0.32, 0.04, 0.9))
	emitter.color_ramp = ramp
	return emitter

func smoke(point: Vector3, amount: int, opacity: float) -> CPUParticles3D:
	var emitter: CPUParticles3D = particles("SmokeWisp", point, amount, 3.4, smoke_material)
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 0.04
	emitter.direction = Vector3.UP
	emitter.spread = 10.0
	emitter.initial_velocity_min = 0.25
	emitter.initial_velocity_max = 0.4
	emitter.gravity = Vector3(0.08, 0.12, 0.03)
	emitter.damping_min = 0.05
	emitter.damping_max = 0.1
	emitter.scale_amount_min = 0.12
	emitter.scale_amount_max = 0.2
	var growth: Curve = Curve.new()
	growth.max_value = 4.0
	growth.add_point(Vector2(0.0, 0.6))
	growth.add_point(Vector2(1.0, 3.2))
	emitter.scale_amount_curve = growth
	emitter.angle_min = -180.0
	emitter.angle_max = 180.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.18, Color(1.0, 1.0, 1.0, opacity))
	emitter.color_ramp = ramp
	return emitter

func particles(label: String, point: Vector3, amount: int, lifetime: float, material: ShaderMaterial) -> CPUParticles3D:
	var emitter: CPUParticles3D = CPUParticles3D.new()
	emitter.name = label
	emitter.position = point
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.preprocess = lifetime
	emitter.randomness = 0.6
	emitter.fixed_fps = 30
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.extra_cull_margin = 1.5
	var quad: QuadMesh = QuadMesh.new()
	quad.material = material
	emitter.mesh = quad
	return emitter

func update_fog() -> void:
	# Additive glows skip engine fog (it would brighten them); fade them by the same exponential haze.
	var environment: Environment = get_world_3d().environment if get_world_3d() != null else null
	if environment == null:
		for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			environment = (node as WorldEnvironment).environment
	var density: float = 0.0
	if environment != null and environment.fog_enabled:
		density = 3.0 / maxf(environment.fog_depth_end, 1.0) if environment.fog_mode == Environment.FOG_MODE_DEPTH else environment.fog_density
	for material: ShaderMaterial in fog_materials:
		material.set_shader_parameter(&"fog_density", density)

func _process(delta: float) -> void:
	elapsed += delta
	fog_wait -= delta
	if fog_wait <= 0.0:
		fog_wait = 0.5
		update_fog()
	for fire: Fire in fires:
		if fire.glowing.is_empty():
			continue
		# Smooth noise in time: lively, never strobing between frames.
		var slow: float = flicker.get_noise_2d(elapsed * 3.2, fire.phase)
		var quick: float = flicker.get_noise_2d(elapsed * 9.5, fire.phase + 71.0)
		var heat: float = fire.base_heat * (1.0 + slow * 0.2 + quick * 0.07)
		# Energy only: moving a light re-pairs every mesh it touches, and the per-mesh light choice
		# (distance over range times energy) could then flip between frames on the landscape.
		if fire.light != null:
			fire.light.light_energy = LIGHT_ENERGY * heat
		for visual: GeometryInstance3D in fire.glowing:
			visual.set_instance_shader_parameter(&"heat", heat)
