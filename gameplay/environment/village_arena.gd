extends Node3D
## Original procedural village; cosmetic scenery never owns gameplay state.

var wood: StandardMaterial3D
var straw: StandardMaterial3D
var stone: StandardMaterial3D
var earth: StandardMaterial3D
var beam: StandardMaterial3D
var red: StandardMaterial3D
var teal: StandardMaterial3D
var cream: StandardMaterial3D
var gold: StandardMaterial3D
var landscape_noise: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
	name = "WoodlandVillage"
	wood = surface("b0a08a", "oak", 0.5)
	straw = surface("d5c491", "thatch", 0.5)
	stone = surface("88918f")
	earth = surface("c1b9a6", "ground", 0.3)
	beam = surface("493d32")
	red = surface("aa6355", "oak", 0.5)
	teal = surface("5a9695", "oak", 0.5)
	cream = surface("d5ccb2")
	gold = surface("b59a51")
	lighting()
	terrain()
	landscape()
	green_borders()
	# Connected clearings bounded by angled palisades, rather than a square enclosure.
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(-28,-10), Vector2(-24,-23), Vector2(-9,-28), Vector2(8,-25),
		Vector2(22,-28), Vector2(28,-16), Vector2(25,0), Vector2(28,15),
		Vector2(17,27), Vector2(2,28), Vector2(-12,25), Vector2(-28,28)])
	for index: int in range(outline.size()):
		var start: Vector2 = outline[index]
		var finish: Vector2 = outline[(index + 1) % outline.size()]
		var midpoint: Vector2 = (start + finish) * 0.5
		var delta: Vector2 = finish - start
		var fence: MeshInstance3D = block(Vector3(delta.length(), 2.2, 0.35), Vector3(midpoint.x, ground_height(midpoint.x, midpoint.y) + 1.1, midpoint.y), wood, true)
		fence.rotation.y = -atan2(delta.y, delta.x)
		var count: int = ceili(delta.length() / 0.65)
		for post: int in range(count + 1):
			var point: Vector2 = start.lerp(finish, float(post) / float(count))
			log_post(Vector3(point.x, ground_height(point.x, point.y) + 1.25, point.y), 2.5 + sin(float(post) * 2.1) * 0.18, 0.14)
	# Keep the spawn and combat-test axis x=0 unobstructed.
	for location: Vector3 in [Vector3(-5, 0.6, -4), Vector3(5, 0.6, 4), Vector3(-5, 0.6, 4), Vector3(5, 0.6, -4)]:
		var cover: MeshInstance3D = block(Vector3(3, 1.2, 2), location, wood, true)
		cover.visible = false
		for offset: float in [-0.65, 0.65]:
			kit_prop("crate", Vector3(location.x + offset, 0, location.z), 1.2, 0.03 * offset, false)
	kit_prop("cottage_a", Vector3(-15, 0, -17), 8.0, 0.18)
	kit_prop("cottage_f", Vector3(-4, 0, -21), 8.0, -0.12)
	kit_prop("cottage_h", Vector3(13, 0, -19), 8.5, -0.3)
	kit_prop("cottage_f", Vector3(19, 0, 17), 8.0, PI + 0.3)
	kit_prop("cottage_a", Vector3(-7, 0, 20), 8.5, PI - 0.2)
	kit_prop("wagon", Vector3(16, 0, 3), 3.5, 0.4)
	kit_prop("dummy", Vector3(20, 0, 8), 1.3, -0.7)
	kit_prop("shield", Vector3(18, 0, 10), 0.8, -0.5, false)
	for index: int in range(18):
		var angle: float = TAU * float(index) / 18.0
		kit_prop("rock_a" if index % 2 == 0 else "rock_b", Vector3(cos(angle) * 30.0, 0, sin(angle) * 30.0), 2.0 + float(index % 3), angle, false)
	for side: int in [-1, 1]:
		stall(Vector3(side * 15, 0, -8), red if side < 0 else teal)
		stall(Vector3(side * 15, 0, 9), gold if side < 0 else cream)
		for index: int in range(3):
			barrel(Vector3(side * 20, 0, -5 + index * 4))
	kit_prop("well", Vector3(-12, 0, 0), 3.0, 0.0)
	watchtower(Vector3(-23, 0, 2))
	var trees: Node3D = preload("res://gameplay/environment/tree_pack.tscn").instantiate() as Node3D
	add_child(trees)
	# The asset preview's flat ground cuts through this level's sculpted terrain.
	for child: Node in trees.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh:
			trees.remove_child(child)
			child.queue_free()
	# Additional vegetation belongs to the surrounding land, not a single circular tree row.
	var forest_random: RandomNumberGenerator = RandomNumberGenerator.new()
	forest_random.seed = 41271
	for index: int in range(112):
		var angle: float = forest_random.randf_range(0.0, TAU)
		var radius: float = forest_random.randf_range(38.0, 175.0)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		(trees as TreePack).add_plant("tree%02d" % (1 + index % 36), Vector3(x, landscape_surface_height(x, z) - 0.05, z), forest_random.randf_range(7.0, 14.0))

func landscape_height(x: float, z: float) -> float:
	var distance: float = maxf(absf(x), absf(z))
	var broad: float = landscape_noise.get_noise_2d(x, z)
	var foothills: float = smoothstep(34.0, 100.0, distance) * (2.0 + broad * 2.0)
	var mountains: float = smoothstep(90.0, 260.0, distance)
	var ridge: float = pow(clampf(0.5 + broad, 0.0, 1.0), 2.0) * 75.0
	var detail: float = landscape_noise.get_noise_2d(x * 2.1 + 91.0, z * 2.1) * 4.0
	return -0.7 + foothills + mountains * (ridge + detail + 6.0)

func landscape_surface_height(x: float, z: float) -> float:
	# Match the actual six-metre mesh triangles, not an unsampled noise peak.
	var cell: Vector2 = (Vector2(x,z) + Vector2.ONE * 288.0) / 6.0
	var base: Vector2 = cell.floor() * 6.0 - Vector2.ONE * 288.0
	var offset: Vector2 = cell - cell.floor()
	var near_height: float = landscape_height(base.x, base.y)
	var right_height: float = landscape_height(base.x + 6.0, base.y)
	var far_height: float = landscape_height(base.x, base.y + 6.0)
	if offset.x + offset.y <= 1.0:
		return near_height + (right_height-near_height)*offset.x + (far_height-near_height)*offset.y
	var diagonal: float = landscape_height(base.x + 6.0, base.y + 6.0)
	return diagonal + (far_height-diagonal)*(1.0-offset.x) + (right_height-diagonal)*(1.0-offset.y)

func landscape() -> void:
	landscape_noise.seed = 41271
	landscape_noise.frequency = 0.006
	landscape_noise.fractal_octaves = 3
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: int in range(96):
		for x: int in range(96):
			var corners: Array[Vector2] = [Vector2(x,z), Vector2(x+1,z), Vector2(x,z+1), Vector2(x+1,z), Vector2(x+1,z+1), Vector2(x,z+1)]
			for corner: Vector2 in corners:
				var point: Vector2 = corner * 6.0 - Vector2.ONE * 288.0
				var height: float = landscape_height(point.x, point.y)
				var rocky: float = smoothstep(12.0, 42.0, height)
				tool.set_color(Color("637457").lerp(Color("858780"), rocky))
				tool.add_vertex(Vector3(point.x, height, point.y))
	tool.generate_normals()
	tool.index()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = tool.commit()
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying float slope;
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; slope=NORMAL.y; }
void fragment() {
 float exposed=max(1.0-smoothstep(0.55,0.85,slope),smoothstep(18.0,42.0,world_pos.y));
 vec3 earth=texture(soil,world_pos.xz*0.18).rgb*vec3(0.72,1.05,0.68);
 ALBEDO=mix(earth,texture(rock,world_pos.xz*0.13).rgb*0.8,exposed);
 ROUGHNESS=0.95;
}
"""
	material.shader = shader
	material.set_shader_parameter("soil", load("res://content/environments/valhalla/textures/KB3D_VHL_GrassGround_basecolor.png"))
	material.set_shader_parameter("rock", load("res://content/environments/valhalla/textures/KB3D_VHL_StoneFloor_basecolor.png"))
	visual.material_override = material
	add_child(visual)

func surface(color: String, texture: String = "", tiling: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not texture.is_empty():
		material.albedo_texture = load("res://content/environments/village_generated/%s.png" % texture) as Texture2D
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE * tiling
	return material

func block(size: Vector3, location: Vector3, material: Material, collision: bool = false, parent: Node3D = self) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = location
	parent.add_child(visual)
	if collision:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		visual.add_child(body)
	return visual

func roof(location: Vector3, width: float, depth: float, parent: Node3D) -> void:
	# Two pitched surfaces leave the gable open; straw is never painted onto a solid triangular end.
	var slope: float = atan(2.8 / (width * 0.5))
	var length: float = sqrt(pow(width * 0.5, 2) + 2.8 * 2.8)
	for side: int in [-1, 1]:
		var panel: MeshInstance3D = block(Vector3(length, 0.18, depth), location + Vector3(side * width * 0.25, 0, 0), straw, false, parent)
		panel.rotation.z = -side * slope
		for row: int in range(5):
			var t: float = float(row) / 5.0
			var course: MeshInstance3D = block(Vector3(length * 0.21, 0.13, depth + 0.08), location + Vector3(side * (width * 0.5 * t + width * 0.05), 1.4 - 2.8 * (t + 0.1), 0), straw, false, parent)
			course.rotation.z = -side * slope
	block(Vector3(0.18, 0.24, depth + 0.25), location + Vector3(0, 1.48, 0), beam, false, parent)

func house(location: Vector3, yaw: float, paint: StandardMaterial3D) -> void:
	var root: Node3D = Node3D.new()
	root.position = location + Vector3(0, ground_height(location.x, location.z), 0)
	root.rotation.y = yaw
	add_child(root)
	block(Vector3(7, 3.8, 6), Vector3(0, 1.9, 0), wood, true, root)
	for index: int in range(18):
		var x: float = -3.3 + index * 0.39
		block(Vector3(0.36, 3.6 - float(index % 3) * 0.025, 0.12), Vector3(x, 1.9, 3.08), paint, false, root)
	for side: int in [-1, 1]:
		for index: int in range(15):
			block(Vector3(0.12, 3.6, 0.37), Vector3(side * 3.55, 1.9, -2.8 + index * 0.4), paint, false, root)
	var gable_mesh: PrismMesh = PrismMesh.new()
	gable_mesh.size = Vector3(7, 2.8, 6)
	var gable: MeshInstance3D = MeshInstance3D.new()
	gable.mesh = gable_mesh
	gable.position.y = 5.2
	gable.material_override = wood
	root.add_child(gable)
	roof(Vector3(0, 5.2, 0), 8.0, 7.0, root)
	# Exposed frame, planks and shutters carry color without an overall brown grade.
	for x: float in [-3.4, 0.0, 3.4]:
		block(Vector3(0.25, 3.9, 0.25), Vector3(x, 1.95, 3.08), beam, false, root)
	for y: float in [0.3, 1.4, 3.65]:
		block(Vector3(7.2, 0.15, 0.18), Vector3(0, y, 3.12), wood, false, root)
	block(Vector3(1.3, 2.4, 0.15), Vector3(-1.5, 1.2, 3.15), wood, false, root)
	block(Vector3(1.5, 1.2, 0.16), Vector3(1.8, 2.1, 3.15), beam, false, root)
	block(Vector3(0.09, 1.2, 0.2), Vector3(1.8, 2.1, 3.25), cream, false, root)
	block(Vector3(1.5, 0.09, 0.2), Vector3(1.8, 2.1, 3.25), cream, false, root)
	block(Vector3(1.0, 2.6, 0.9), Vector3(2.3, 4.8, -1.8), stone, false, root)
	for side: int in [-1, 1]:
		var rafter: MeshInstance3D = block(Vector3(0.19, 4.9, 0.2), Vector3(side * 1.8, 4.8, 3.55), beam, false, root)
		rafter.rotation.z = side * 0.95

func stall(location: Vector3, cloth: StandardMaterial3D) -> void:
	# Collision remains a simple counter footprint; the visible table has open legs.
	var table: PrototypeProp = kit_prop("table", location + Vector3.LEFT * 0.95, 1.9, 0.0)
	kit_prop("table", location + Vector3.RIGHT * 0.95, 1.9, PI)
	var tabletop: float = table.bounds.size.y * table.scale.y
	for x: float in [-1.9, 1.9]:
		for z: float in [-1.1, 1.1]:
			log_post(location + Vector3(x, ground_height(location.x, location.z) + 1.62, z), 3.24, 0.07)
	cloth_canopy(location + Vector3.UP * ground_height(location.x, location.z), cloth.albedo_color)
	kit_prop("basket", location + Vector3(-0.8, tabletop, 0), 0.5, 0.1, false)
	kit_prop("basket", location + Vector3(0.6, tabletop, 0.2), 0.45, 1.3, false)
	kit_prop("crate", location + Vector3(2.0, 0, 0.6), 0.9, 0.15)

func cloth_canopy(location: Vector3, dye: Color) -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: int in range(8):
		for x: int in range(12):
			var corners: Array[Vector2] = [Vector2(x,z), Vector2(x+1,z), Vector2(x,z+1), Vector2(x+1,z), Vector2(x+1,z+1), Vector2(x,z+1)]
			for corner: Vector2 in corners:
				var uv: Vector2 = corner / Vector2(12.0, 8.0)
				var edge: float = absf(uv.x * 2.0 - 1.0)
				var sag: float = (1.0 - edge * edge) * 0.32
				var height: float = 3.2 - sag + sin(uv.y * PI * 4.0) * 0.035
				tool.set_uv(uv * Vector2(3.6, 2.4))
				tool.add_vertex(Vector3((uv.x - 0.5) * 4.5, height, (uv.y - 0.5) * 3.0))
	tool.generate_normals()
	tool.index()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = tool.commit()
	visual.position = location
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D weave : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dye;
void fragment() {
 float variation=texture(weave,UV).r;
 ALBEDO=dye*(0.65+variation*0.8);
 ROUGHNESS=0.95;
 BACKLIGHT=ALBEDO*0.12;
}
"""
	material.shader = shader
	material.set_shader_parameter("weave", load("res://content/environments/village_generated/flax_weave.png"))
	var linear_dye: Color = dye.srgb_to_linear()
	material.set_shader_parameter("dye", Vector3(linear_dye.r, linear_dye.g, linear_dye.b))
	visual.material_override = material
	add_child(visual)

func kit_prop(asset: String, location: Vector3, width: float, yaw: float, collision: bool = true) -> PrototypeProp:
	var prop: PrototypeProp = PrototypeProp.new()
	prop.model_scene = load("res://content/environments/valhalla/%s.gltf" % asset) as PackedScene
	prop.collision_enabled = collision
	prop.position = location + Vector3(0, ground_height(location.x, location.z), 0)
	prop.rotation.y = yaw
	add_child(prop)
	# Uniform scaling also preserves the imported collision shape proportions.
	prop.scale = Vector3.ONE * (width / maxf(prop.bounds.size.x, 0.01))
	return prop

func barrel(location: Vector3) -> void:
	kit_prop("barrel", location, 0.9, location.z * 0.3)

func well(location: Vector3) -> void:
	for index: int in range(12):
		var angle: float = TAU * index / 12.0
		var piece: MeshInstance3D = block(Vector3(0.7, 1.0, 0.45), location + Vector3(sin(angle) * 1.2, 0.5, cos(angle) * 1.2), stone, true)
		piece.rotation.y = angle
	for side: int in [-1, 1]:
		log_post(location + Vector3(side * 1.25, 1.6, 0), 3.2, 0.12)
	roof(location + Vector3(0, 3.5, 0), 3.4, 2.6, self)

func watchtower(location: Vector3) -> void:
	for x: float in [-1.5, 1.5]:
		for z: float in [-1.5, 1.5]:
			log_post(location + Vector3(x, 3.35, z), 6.7, 0.18, true)
	block(Vector3(3.5, 0.3, 3.5), location + Vector3(0, 4.2, 0), wood, true)
	# Long rafters lean inward at the top and meet the ridge, not outward.
	for z: float in [-1.65, 1.65]:
		for side: int in [-1, 1]:
			var rafter: MeshInstance3D = block(Vector3(0.18, 3.5, 0.18), location + Vector3(side * 1.05, 7.0, z), beam)
			rafter.rotation.z = float(side) * atan(2.1 / 2.8)
	roof(location + Vector3(0, 7.1, 0), 4.2, 4.2, self)
	for side: int in [-1, 1]:
		block(Vector3(0.2, 1.0, 3.4), location + Vector3(side * 1.6, 4.8, 0), teal)
	block(Vector3(3.4, 1.0, 0.2), location + Vector3(0, 4.8, -1.6), teal)
	# One broad approach gives the lookout an actual playable connection.
	var ramp: MeshInstance3D = block(Vector3(3.0, 0.25, 9.5), location + Vector3(0, 2.1, 6.0), wood, true)
	ramp.rotation.x = atan(4.2 / 8.5)

func lighting() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -50, 0)
	light.light_color = Color("fff1d8")
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 100.0
	add_child(light)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: ShaderMaterial = ShaderMaterial.new()
	var sky_shader: Shader = Shader.new()
	sky_shader.code = """shader_type sky;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
 return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
void sky() {
 float altitude = max(EYEDIR.y, 0.0);
 vec3 base = mix(vec3(0.47, 0.65, 0.76), vec3(0.13, 0.36, 0.60), pow(altitude, 0.4));
 vec2 p = EYEDIR.xz / max(0.15, altitude) * 3.0;
 float n = noise(p) * 0.53 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.13 + noise(p * 8.7) * 0.06;
 float clouds = smoothstep(0.44, 0.64, n) * smoothstep(0.02, 0.16, altitude);
 COLOR = mix(base, mix(vec3(0.62, 0.69, 0.75),vec3(1.0, 0.98, 0.93), smoothstep(0.48,0.67,n)), clouds);
}
"""
	sky_material.shader = sky_shader
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_light_color = Color("91b2c6")
	environment.fog_density = 0.0012
	world.environment = environment
	add_child(world)

func ground_height(x: float, z: float) -> float:
	var edge: float = smoothstep(5.0, 18.0, maxf(absf(x), absf(z)))
	return sin(x * 1.2) * cos(z * 1.4) * 0.025 + edge * (sin(x * 0.31) * cos(z * 0.23) * 0.55 + sin(z * 0.65 + x * 0.18) * 0.17)

func terrain() -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: int in range(112):
		for x: int in range(112):
			var corners: Array[Vector2] = [Vector2(x, z), Vector2(x + 1, z), Vector2(x, z + 1), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]
			for corner: Vector2 in corners:
				var location: Vector2 = corner * 0.5 - Vector2.ONE * 28
				tool.set_uv(location * 0.25)
				tool.add_vertex(Vector3(location.x, ground_height(location.x, location.y), location.y))
	tool.generate_normals()
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D dirt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stones : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 pos;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex() { pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=pos.xz;
 float footprint = length(fwidth(p));
 float fine = mix(noise(p*2.4),0.5,smoothstep(0.03,0.2,footprint));
 float n=noise(p*0.6)*0.7+fine*0.3;
 float main_path=1.0-smoothstep(2.6,4.8,abs(p.x-sin(p.y*0.16)*2.2));
 float cross_path=1.0-smoothstep(2.0,4.0,abs(p.y-sin(p.x*0.14)*1.5));
 float court=1.0-smoothstep(7.0,14.0,length(p));
 float path=max(court,max(main_path,cross_path));
 float vegetation=(1.0-path)*smoothstep(0.2,0.7,n);
 vec3 dirt=texture(dirt_color,p*0.65).rgb * mix(0.8,1.05,n);
 vec3 grass=texture(grass_color,p*0.22).rgb * mix(0.72,1.05,n);
 vec3 rock=texture(stones,p*0.22).rgb;
 float rock_mask=smoothstep(0.4,0.68,noise(p*0.23))*path;
 ALBEDO=mix(mix(dirt,rock,rock_mask*0.38),grass,vegetation);
 ROUGHNESS=mix(texture(stone_roughness,p*0.22).r,texture(grass_roughness,p*0.22).r,vegetation);
 NORMAL_MAP=mix(texture(stone_normal,p*0.22).rgb,texture(grass_normal,p*0.22).rgb,vegetation);
 NORMAL_MAP_DEPTH=0.45;
 // Screen-space color derivatives are not a physical normal map and shimmer during motion.
}
"""
	material.shader = shader
	material.set_shader_parameter("dirt_color", load("res://content/environments/village_generated/compacted_path.png"))
	for binding: String in ["stones", "grass_color", "stone_normal", "grass_normal", "stone_roughness", "grass_roughness"]:
		var family: String = "GrassGround" if binding.begins_with("grass") else "StoneFloor"
		var channel: String = "normal" if binding.ends_with("normal") else ("roughness" if binding.ends_with("roughness") else "basecolor")
		material.set_shader_parameter(binding, load("res://content/environments/valhalla/textures/KB3D_VHL_%s_%s.png" % [family, channel]))
	visual.material_override = material
	add_child(visual)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)

func log_post(location: Vector3, height: float, radius: float, collision: bool = false) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius * 0.9
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 9
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = location
	visual.material_override = wood
	add_child(visual)
	if collision:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var cylinder: CylinderShape3D = CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		body.add_child(shape)
		visual.add_child(body)

func green_borders() -> void:
	var blades: SurfaceTool = SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 32017
	for index: int in range(7):
		var angle: float = index * 2.4
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 0.12
		var edge: Vector3 = Vector3(cos(angle + 0.7), 0, sin(angle + 0.7)) * 0.028
		var top: Vector3 = offset + Vector3(0.06, random.randf_range(0.17, 0.34), 0.02)
		blades.add_vertex(offset - edge)
		blades.add_vertex(offset + edge)
		blades.add_vertex(top)
	blades.generate_normals()
	var blade_material: ShaderMaterial = ShaderMaterial.new()
	var grass_shader: Shader = Shader.new()
	grass_shader.code = """shader_type spatial;
render_mode cull_disabled;
void vertex() { NORMAL=normalize(mix(NORMAL,vec3(0.0,1.0,0.0),0.75)); }
void fragment() { ALBEDO=vec3(0.12,0.23,0.055)*COLOR.rgb; ROUGHNESS=0.95; BACKLIGHT=ALBEDO*0.3; }
"""
	blade_material.shader = grass_shader
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = blades.commit()
	var locations: Array[Vector3] = []
	for attempt: int in range(10000):
		var x: float = random.randf_range(-27.0, 27.0)
		var z: float = random.randf_range(-26.0, 26.0)
		if Vector2(x,z).length() < 10.0 or absf(x - sin(z * 0.16) * 2.2) < 3.6 or absf(z - sin(x * 0.14) * 1.5) < 2.8:
			continue
		if sin(x * 0.65) * cos(z * 0.55) < -0.25:
			continue
		locations.append(Vector3(x, ground_height(x, z) + 0.01, z))
	multi.instance_count = locations.size()
	for index: int in range(locations.size()):
		var basis: Basis = Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.7, 1.5))
		multi.set_instance_transform(index, Transform3D(basis, locations[index]))
		multi.set_instance_color(index, Color(random.randf_range(0.65, 1.0), random.randf_range(0.75, 1.0), 0.65))
	instance.multimesh = multi
	instance.material_override = blade_material
	add_child(instance)
