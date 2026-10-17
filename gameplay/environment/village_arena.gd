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
	# Visual terrain extends beyond the fenced playfield; collisions stay inside 56 m.
	block(Vector3(240, 0.2, 240), Vector3(0, -0.75, 0), surface("54684b"))
	green_borders()
	for side: int in [-1, 1]:
		block(Vector3(0.4, 2.5, 56), Vector3(side * 28, 1.25, 0), wood, true)
		block(Vector3(56, 2.5, 0.4), Vector3(0, 1.25, side * 28), wood, true)
		for index: int in range(19):
			block(Vector3(0.22, 3.0, 0.22), Vector3(side * 27.7, 1.5, -27 + index * 3), beam)
			block(Vector3(0.22, 3.0, 0.22), Vector3(-27 + index * 3, 1.5, side * 27.7), beam)
	# Keep the spawn and combat-test axis x=0 unobstructed.
	for location: Vector3 in [Vector3(-5, 0.6, -4), Vector3(5, 0.6, 4), Vector3(-5, 0.6, 4), Vector3(5, 0.6, -4)]:
		block(Vector3(3, 1.2, 2), location, wood, true)
		for offset: float in [-1.25, 1.25]:
			block(Vector3(0.12, 1.25, 2.04), location + Vector3(offset, 0, 0), beam)
	for index: int in range(4):
		var x: float = -20.0 + index * 13.0
		house(Vector3(x, 0, -22), 0.0, red if index % 2 == 0 else teal)
		house(Vector3(x, 0, 22), PI, teal if index % 2 == 0 else wood)
	for side: int in [-1, 1]:
		stall(Vector3(side * 15, 0, -8), red if side < 0 else teal)
		stall(Vector3(side * 15, 0, 9), gold if side < 0 else cream)
		for index: int in range(3):
			barrel(Vector3(side * 20, 0, -5 + index * 4))
	well(Vector3(-12, ground_height(-12, 0), 0))
	watchtower(Vector3(-23, 0, 2))
	var trees: Node3D = preload("res://gameplay/environment/tree_pack.tscn").instantiate() as Node3D
	add_child(trees)
	for index: int in range(14):
		var angle: float = TAU * index / 14.0
		var hill: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 16.0 + float(index % 4) * 5.0
		mesh.height = mesh.radius * 1.3
		mesh.radial_segments = 12
		mesh.rings = 6
		hill.mesh = mesh
		hill.position = Vector3(cos(angle) * 100, -7, sin(angle) * 100)
		hill.material_override = surface("5d7068" if index % 2 == 0 else "70808b")
		add_child(hill)

func surface(color: String, texture: String = "", tiling: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
		rafter.rotation.z = side * -0.95

func stall(location: Vector3, cloth: StandardMaterial3D) -> void:
	block(Vector3(4, 1.1, 2.4), location + Vector3(0, 0.55, 0), wood, true)
	for x: float in [-1.9, 1.9]:
		for z: float in [-1.1, 1.1]:
			block(Vector3(0.14, 3.2, 0.14), location + Vector3(x, 1.6, z), beam)
	var canopy: MeshInstance3D = block(Vector3(4.5, 0.12, 3.0), location + Vector3(0, 3.15, 0), cloth)
	canopy.rotation.x = 0.12
	block(Vector3(4.5, 0.5, 0.08), location + Vector3(0, 2.95, 1.45), cloth)
	for x: float in [-1.2, 0.0, 1.2]:
		block(Vector3(0.7, 0.5, 0.7), location + Vector3(x, 1.35, 0), cream if x == 0 else gold)

func barrel(location: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = location + Vector3(0, 0.65, 0)
	add_child(body)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.3
	mesh.radial_segments = 12
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = wood
	body.add_child(visual)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 0.5
	cylinder.height = 1.3
	shape.shape = cylinder
	body.add_child(shape)

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
			log_post(location + Vector3(x, 3, z), 6.0, 0.18, true)
	block(Vector3(3.5, 0.3, 3.5), location + Vector3(0, 4.2, 0), wood, true)
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
 float n = noise(p) * 0.65 + noise(p * 2.7) * 0.25 + noise(p * 7.0) * 0.1;
 float clouds = smoothstep(0.56, 0.73, n) * smoothstep(0.03, 0.22, altitude);
 COLOR = mix(base, vec3(0.87, 0.90, 0.91), clouds * 0.8);
}
"""
	sky_material.shader = sky_shader
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_light_color = Color("91b2c6")
	environment.fog_density = 0.0012
	world.environment = environment
	add_child(world)

func ground_height(x: float, z: float) -> float:
	var edge: float = smoothstep(5.0, 18.0, maxf(absf(x), absf(z)))
	return edge * (sin(x * 0.31) * cos(z * 0.23) * 0.32 + sin(z * 0.65 + x * 0.18) * 0.12)

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
uniform sampler2D stones : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 pos;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex() { pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=pos.xz;
 float n=noise(p*0.6)*0.6+noise(p*2.4)*0.3+noise(p*13.0)*0.1;
 float main_path=1.0-smoothstep(2.6,4.8,abs(p.x-sin(p.y*0.16)*2.2));
 float cross_path=1.0-smoothstep(2.0,4.0,abs(p.y-sin(p.x*0.14)*1.5));
 float court=1.0-smoothstep(7.0,14.0,length(p));
 float path=max(court,max(main_path,cross_path));
 float vegetation=(1.0-path)*smoothstep(0.2,0.7,n);
 vec3 dirt=mix(vec3(0.13,0.095,0.065),vec3(0.29,0.23,0.16),n);
 vec3 grass=mix(vec3(0.075,0.12,0.045),vec3(0.21,0.27,0.11),n);
 vec3 rock=texture(stones,p*0.18).rgb*0.65;
 float rock_mask=smoothstep(0.4,0.68,noise(p*0.23))*path;
 ALBEDO=mix(mix(dirt,rock,rock_mask*0.72),grass,vegetation);
 ROUGHNESS=mix(0.74,0.97,n);
 float h=dot(texture(stones,p*0.18).rgb,vec3(0.333));
 NORMAL_MAP=normalize(vec3(-dFdx(h)*14.0,-dFdy(h)*14.0,1.0))*0.5+0.5;
}
"""
	material.shader = shader
	material.set_shader_parameter("stones", load("res://content/environments/village_generated/ground.png"))
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
	var blade_material: StandardMaterial3D = surface("506037")
	blade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade_material.vertex_color_use_as_albedo = true
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = blades.commit()
	multi.instance_count = 3200
	for index: int in range(multi.instance_count):
		var x: float = random.randf_range(-27.0, 27.0)
		var z: float = random.randf_range(-26.0, 26.0)
		# Keep central dueling space and the two main routes clear; cluster growth off the tracks.
		if Vector2(x,z).length() < 11.0 or absf(x - sin(z * 0.16) * 2.2) < 4.0 or absf(z - sin(x * 0.14) * 1.5) < 3.0:
			x = (-1.0 if x < 0 else 1.0) * random.randf_range(24.0, 27.0)
		var location: Vector3 = Vector3(x, ground_height(x, z) + 0.01, z)
		var basis: Basis = Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.7, 1.5))
		multi.set_instance_transform(index, Transform3D(basis, location))
		multi.set_instance_color(index, Color(random.randf_range(0.65, 1.0), random.randf_range(0.75, 1.0), 0.65))
	instance.multimesh = multi
	instance.material_override = blade_material
	add_child(instance)
