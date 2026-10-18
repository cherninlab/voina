extends Node3D
## Original procedural village; cosmetic scenery never owns gameplay state.

var timber_material: ShaderMaterial
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
	# The source builder remains available to regenerate the static lightmap snapshot.
	var baked_path: String = "res://content/environments/village_generated/village_lit.scn"
	if not bool(get_meta("prepare_lightmap", false)) and ResourceLoader.exists(baked_path):
		var baked: PackedScene = load(baked_path) as PackedScene
		var snapshot: Node3D = baked.instantiate() as Node3D
		var lightmap: LightmapGI = snapshot.get_node("VillageLightmap") as LightmapGI
		if lightmap.light_data != null and lightmap.light_data.get_user_count() > 0:
			add_child(snapshot)
			for node: Node in snapshot.find_children("*", "WorldEnvironment", true, false):
				apply_atmosphere((node as WorldEnvironment).environment)
			refresh_landscape(snapshot)
			refresh_ground(snapshot)
			clover_edges()
			refresh_foliage(snapshot)
			woodland_edges()
			ridge_outcrops()
			return
		snapshot.free()
	wood = surface("b0a08a", "oak", 0.5)
	make_timber_material()
	straw = surface("bfb9aa", "reed_thatch")
	straw.uv1_triplanar = false
	straw.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	ground_stones()
	if not bool(get_meta("prepare_lightmap", false)):
		clover_edges()
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
	# Rock shelves follow the slopes instead of forming a decorative ring.
	var rock_random: RandomNumberGenerator = RandomNumberGenerator.new()
	rock_random.seed = 52191
	for index: int in range(72):
		var angle: float = rock_random.randf_range(0.0, TAU)
		var radius: float = rock_random.randf_range(34.0, 155.0)
		var location: Vector3 = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var width: float = rock_random.randf_range(2.5, 7.5)
		location.y = landscape_surface_height(location.x, location.z) - width * 0.12
		kit_prop("rock_a" if index % 2 == 0 else "rock_b", location, width, angle, false)
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
	for plant: Node3D in (trees as TreePack).plants:
		plant.position.y = landscape_surface_height(plant.position.x, plant.position.z) - 0.05
	# Additional vegetation belongs to the surrounding land, not a single circular tree row.
	var forest_random: RandomNumberGenerator = RandomNumberGenerator.new()
	forest_random.seed = 41271
	for index: int in range(320):
		var angle: float = forest_random.randf_range(0.0, TAU)
		var radius: float = forest_random.randf_range(38.0, 175.0)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		(trees as TreePack).add_plant("tree%02d" % (1 + index % 36), Vector3(x, landscape_surface_height(x, z) - 0.05, z), forest_random.randf_range(7.0, 14.0))
	if not bool(get_meta("prepare_lightmap", false)):
		refresh_foliage(trees)
		woodland_edges()
		ridge_outcrops()

func landscape_height(x: float, z: float) -> float:
	var distance: float = maxf(absf(x), absf(z))
	var broad: float = landscape_noise.get_noise_2d(x, z)
	var foothills: float = smoothstep(34.0, 100.0, distance) * (2.0 + broad * 2.0)
	var mountains: float = smoothstep(90.0, 260.0, distance)
	# Warped ridges and softened strata interrupt the former smooth dome outline.
	var warp: float = landscape_noise.get_noise_2d(x * 2.4 + 143.0, z * 2.4 - 71.0) * 28.0
	var ridge_noise: float = landscape_noise.get_noise_2d((x + warp) * 1.7, (z - warp) * 1.7)
	var crags: float = pow(1.0 - absf(ridge_noise), 2.0)
	var ridge: float = pow(clampf(0.5 + broad, 0.0, 1.0), 2.0) * 65.0
	var detail: float = landscape_noise.get_noise_2d(x * 5.0 + 91.0, z * 5.0) * 2.0
	var raw_height: float = ridge + crags * 10.0 + detail + 3.0
	var layer: float = raw_height / 5.5
	var shelves: float = (floorf(layer) + smoothstep(0.1, 0.9, fposmod(layer, 1.0))) * 5.5
	return -0.7 + foothills + mountains * lerpf(raw_height, shelves, 0.65)

func landscape_surface_height(x: float, z: float) -> float:
	# Match the actual three-metre mesh triangles, not an unsampled noise peak.
	var cell: Vector2 = (Vector2(x,z) + Vector2.ONE * 288.0) / 3.0
	var base: Vector2 = cell.floor() * 3.0 - Vector2.ONE * 288.0
	var offset: Vector2 = cell - cell.floor()
	var near_height: float = landscape_height(base.x, base.y)
	var right_height: float = landscape_height(base.x + 3.0, base.y)
	var far_height: float = landscape_height(base.x, base.y + 3.0)
	if offset.x + offset.y <= 1.0:
		return near_height + (right_height-near_height)*offset.x + (far_height-near_height)*offset.y
	var diagonal: float = landscape_height(base.x + 3.0, base.y + 3.0)
	return diagonal + (far_height-diagonal)*(1.0-offset.x) + (right_height-diagonal)*(1.0-offset.y)

func landscape() -> void:
	landscape_noise.seed = 41271
	landscape_noise.frequency = 0.006
	landscape_noise.fractal_octaves = 3
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: int in range(192):
		for x: int in range(192):
			var corners: Array[Vector2] = [Vector2(x,z), Vector2(x+1,z), Vector2(x,z+1), Vector2(x+1,z), Vector2(x+1,z+1), Vector2(x,z+1)]
			for corner: Vector2 in corners:
				var point: Vector2 = corner * 3.0 - Vector2.ONE * 288.0
				var height: float = landscape_height(point.x, point.y)
				var rocky: float = smoothstep(12.0, 42.0, height)
				tool.set_color(Color("637457").lerp(Color("858780"), rocky))
				tool.add_vertex(Vector3(point.x, height, point.y))
	tool.generate_normals()
	tool.index()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = tool.commit()
	var material: ShaderMaterial = make_landscape_material()
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

func timber(start: Vector3, finish: Vector3, radius: float, parent: Node3D = self) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.height = start.distance_to(finish)
	mesh.top_radius = radius * 0.9
	mesh.bottom_radius = radius
	mesh.radial_segments = 10
	visual.mesh = mesh
	visual.material_override = timber_material
	visual.position = (start + finish) * 0.5
	visual.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	parent.add_child(visual)

func roof(location: Vector3, width: float, depth: float, parent: Node3D) -> void:
	var rise: float = 2.8
	var length: float = sqrt(pow(width * 0.5, 2) + rise * rise)
	for side: int in [-1, 1]:
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row: int in range(10):
			for column: int in range(28):
				var corners: Array[Vector2] = [Vector2(row,column),Vector2(row+1,column),Vector2(row,column+1),Vector2(row+1,column),Vector2(row+1,column+1),Vector2(row,column+1)]
				if side < 0:
					corners.reverse()
				for corner: Vector2 in corners:
					var down: float = corner.x / 10.0
					var along: float = corner.y / 28.0
					var fringe: float = pow(down, 8.0) * sin(along * 83.0) * 0.065
					var point: Vector3 = Vector3(side * (width * 0.5 * down + fringe), rise * (0.5 - down) - absf(fringe), (along-0.5)*depth)
					tool.set_uv(Vector2(along * depth * 0.65, down * length * 0.65))
					tool.set_normal(Vector3(side * rise, width * 0.5, 0).normalized())
					tool.add_vertex(location + point)
		for row: int in range(10):
			for column: int in range(28):
				var corners: Array[Vector2] = [Vector2(row,column),Vector2(row+1,column),Vector2(row,column+1),Vector2(row+1,column),Vector2(row+1,column+1),Vector2(row,column+1)]
				if side > 0:
					corners.reverse()
				for corner: Vector2 in corners:
					var down: float = corner.x / 10.0
					var along: float = corner.y / 28.0
					var thickness: float = 0.2 + 0.035 * sin(along * 83.0) * down
					tool.set_uv(Vector2(along * depth * 0.65, down * length * 0.65))
					tool.set_normal(-Vector3(side * rise, width * 0.5, 0).normalized())
					tool.add_vertex(roof_surface_point(location, width, depth, side, down, along) - Vector3.UP * thickness)
		# A closed, irregular edge gives thatch actual thickness at eaves and gables.
		for edge: int in range(3):
			var segments: int = 28 if edge == 0 else 10
			for segment: int in range(segments):
				var t0: float = float(segment) / segments
				var t1: float = float(segment + 1) / segments
				var down0: float = 1.0 if edge == 0 else t0
				var down1: float = 1.0 if edge == 0 else t1
				var along0: float = t0 if edge == 0 else float(edge - 1)
				var along1: float = t1 if edge == 0 else float(edge - 1)
				var start: Vector3 = roof_surface_point(location, width, depth, side, down0, along0)
				var finish: Vector3 = roof_surface_point(location, width, depth, side, down1, along1)
				var low_start: Vector3 = start - Vector3.UP * (0.2 + 0.035 * sin(along0 * 83.0) * down0)
				var low_finish: Vector3 = finish - Vector3.UP * (0.2 + 0.035 * sin(along1 * 83.0) * down1)
				var normal: Vector3 = Vector3(side, 0, 0) if edge == 0 else Vector3(0, 0, -1 if edge == 1 else 1)
				var edge_points: Array[Vector3] = [start, finish, low_start, finish, low_finish, low_start]
				for point: Vector3 in edge_points:
					tool.set_normal(normal)
					tool.set_uv(Vector2(point.z + point.x, point.y) * 0.65)
					tool.add_vertex(point)
		tool.index()
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = tool.commit()
		visual.material_override = straw
		parent.add_child(visual)
		for z: float in [-depth*0.42, 0.0, depth*0.42]:
			timber(location + Vector3(side*width*0.5, -rise*0.5-0.29, z), location + Vector3(0, rise*0.5-0.29, z), 0.085, parent)
	timber(location + Vector3(0, rise*0.5+0.04, -depth*0.53), location + Vector3(0, rise*0.5+0.04, depth*0.53), 0.11, parent)

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

func watchtower(location: Vector3) -> void:
	for x: float in [-1.5, 1.5]:
		for z: float in [-1.5, 1.5]:
			log_post(location + Vector3(x, 3.175, z), 6.35, 0.18, true)
			timber(location + Vector3(x, 2.9, z), location + Vector3(x*0.4, 4.05, z), 0.1)
			timber(location + Vector3(x, 2.9, z), location + Vector3(x, 4.05, z*0.4), 0.1)
	block(Vector3(3.5, 0.3, 3.5), location + Vector3(0, 4.2, 0), wood, true)
	# Tie beams, king posts and inward rafters give the roof a supported load path.
	for z: float in [-1.5, 1.5]:
		timber(location + Vector3(-1.5, 6.3, z), location + Vector3(1.5, 6.3, z), 0.1)
		timber(location + Vector3(0, 6.3, z), location + Vector3(0, 8.36, z), 0.085)
	roof(location + Vector3(0, 7.1, 0), 4.2, 4.2, self)
	for index: int in range(18):
		var offset: float = -1.53 + float(index) * 0.18
		var height: float = 0.86 + sin(float(index) * 2.3) * 0.04
		for side: int in [-1, 1]:
			block(Vector3(0.1, height, 0.16), location + Vector3(side*1.62, 4.78, offset), wood)
		block(Vector3(0.16, height, 0.1), location + Vector3(offset, 4.78, -1.62), wood)
	for side: int in [-1, 1]:
		timber(location + Vector3(side*1.62, 5.25, -1.65), location + Vector3(side*1.62, 5.25, 1.65), 0.065)
	timber(location + Vector3(-1.65, 5.25, -1.62), location + Vector3(1.65, 5.25, -1.62), 0.065)
	# Retain the single smooth collision ramp; decorative decking must not add step jitter.
	var ramp: MeshInstance3D = block(Vector3(3.0, 0.25, 9.5), location + Vector3(0, 2.1, 6.0), wood, true)
	ramp.rotation.x = atan(4.2 / 8.5)
	ramp.visible = false
	for index: int in range(34):
		var z: float = -4.62 + float(index) * 0.28
		var plank: MeshInstance3D = block(Vector3(3.0, 0.07, 0.265), ramp.transform * Vector3(0, 0.135, z), wood)
		plank.rotation.x = ramp.rotation.x
	for side: int in [-1, 1]:
		for z: float in [-4.5, -1.5, 1.5, 4.5]:
			var base: Vector3 = ramp.transform * Vector3(side*1.45, 0.15, z)
			timber(base, base + Vector3.UP * 0.9, 0.055)
		var near_end: Vector3 = ramp.transform * Vector3(side*1.45, 0.15, -4.5)
		var far_end: Vector3 = ramp.transform * Vector3(side*1.45, 0.15, 4.5)
		timber(near_end + Vector3.UP*0.9, far_end + Vector3.UP*0.9, 0.055)

func lighting() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -50, 0)
	light.light_color = Color("fff1d8")
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.8
	light.directional_shadow_max_distance = 100.0
	add_child(light)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: ShaderMaterial = ShaderMaterial.new()
	var sky_shader: Shader = Shader.new()
	sky_shader.code = """shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
void sky() {
 vec2 uv=SKY_COORDS;
 // The generated panorama's horizon is at 57%; keep both poles fixed.
 uv.y+=0.07*(1.0-abs(uv.y*2.0-1.0));
 vec3 base=texture(panorama,uv).rgb;
 vec3 opposite=texture(panorama,vec2(1.0-uv.x,uv.y)).rgb;
 float seam=smoothstep(0.0,0.035,min(uv.x,1.0-uv.x));
 vec3 wrapped=mix((base+opposite)*0.5,base,seam);
 COLOR=mix(vec3(0.025,0.08,0.22),wrapped,smoothstep(0.0,0.04,uv.y));
}
"""
	sky_material.shader = sky_shader
	sky_material.set_shader_parameter("panorama", load("res://content/environments/village_generated/daylight_sky.png"))
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	apply_atmosphere(environment)
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
	tool.generate_tangents()
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	var material: ShaderMaterial = make_ground_material()
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
	visual.material_override = timber_material
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
	# Solid tapered strips follow the generated shape study, avoiding alpha fringes.
	for index: int in range(11):
		var angle: float = index * 2.4
		var direction: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var offset: Vector3 = direction * random.randf_range(0.02, 0.16)
		var edge: Vector3 = Vector3(-direction.z, 0, direction.x)
		var height: float = random.randf_range(0.14, 0.36)
		var width: float = random.randf_range(0.009, 0.018)
		for segment: int in range(3):
			var t0: float = float(segment) / 3.0
			var t1: float = float(segment + 1) / 3.0
			var base: Vector3 = offset + Vector3.UP * height * t0 + direction * height * t0 * t0 * 0.65
			var tip: Vector3 = offset + Vector3.UP * height * t1 + direction * height * t1 * t1 * 0.65
			var left: Vector3 = base - edge * width * (1.0 - t0)
			var right: Vector3 = base + edge * width * (1.0 - t0)
			var upper_left: Vector3 = tip - edge * width * (1.0 - t1)
			var upper_right: Vector3 = tip + edge * width * (1.0 - t1)
			for point: Vector3 in [left, right, upper_left, right, upper_right, upper_left]:
				blades.set_color(Color(0.65 + t1 * 0.35, 0.75 + t1 * 0.25, 0.65))
				blades.add_vertex(point)
	blades.generate_normals()
	var blade_material: ShaderMaterial = ShaderMaterial.new()
	var grass_shader: Shader = Shader.new()
	grass_shader.code = """shader_type spatial;
render_mode cull_disabled;
void vertex() { NORMAL=normalize(mix(NORMAL,vec3(0.0,1.0,0.0),0.75)); }
void fragment() { ALBEDO=vec3(0.045,0.085,0.018)*COLOR.rgb; ROUGHNESS=0.95; BACKLIGHT=ALBEDO*0.3; }
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

func ground_stones() -> void:
	# Small original geometry paired with the schist-valley target and rock albedo.
	# Visual-only stones remain below ankle height and cannot snag a moving player.
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 7
	mesh.rings = 3
	var material: StandardMaterial3D = surface("d8d4cb", "schist_rock", 2.0)
	material.vertex_color_use_as_albedo = true
	var scatter: MultiMesh = MultiMesh.new()
	scatter.transform_format = MultiMesh.TRANSFORM_3D
	scatter.use_colors = true
	scatter.mesh = mesh
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 68192
	var locations: Array[Vector3] = []
	for attempt: int in range(2100):
		var x: float = random.randf_range(-26.0, 26.0)
		var z: float = random.randf_range(-26.0, 26.0)
		# Leave the test axis and central duelling space visually readable.
		if absf(x) < 2.0 or Vector2(x, z).length() < 8.0:
			continue
		var path_edge: float = absf(z - sin(x * 0.14) * 1.5)
		if path_edge < 1.1 or sin(x * 0.43 + z * 0.19) * cos(z * 0.36) < -0.2:
			continue
		locations.append(Vector3(x, ground_height(x, z) + 0.025, z))
	scatter.instance_count = locations.size()
	for index: int in range(locations.size()):
		var size: float = random.randf_range(0.5, 1.5)
		var shape: Vector3 = Vector3(size, random.randf_range(0.3, 0.6), size * random.randf_range(0.65, 1.3))
		scatter.set_instance_transform(index, Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(shape), locations[index]))
		var tint: float = random.randf_range(0.65, 1.0)
		scatter.set_instance_color(index, Color(tint, tint * 0.98, tint * 0.91))
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.name = "GroundStoneScatter"
	visual.multimesh = scatter
	visual.material_override = material
	add_child(visual)

func clover_edges() -> void:
	# Original opaque leaf geometry follows the paired groundcover shape study.
	# Keep this small live foliage layer outside the static lighting snapshot.
	var leaves: SurfaceTool = SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plant: int in range(3):
		var origin: Vector3 = Vector3(cos(plant * 2.4) * 0.055, 0.045 + plant * 0.025, sin(plant * 2.4) * 0.055)
		for petal: int in range(3):
			var direction: float = petal * TAU / 3.0 + plant
			var center: Vector3 = origin + Vector3(cos(direction), 0, sin(direction)) * 0.026
			for side: int in range(8):
				leaves.set_color(Color(0.95, 1.0, 0.85))
				leaves.add_vertex(center + Vector3.UP * 0.005)
				for corner: int in [side + 1, side]:
					var angle: float = corner * TAU / 8.0
					var radius: float = 0.027 * (0.88 + 0.12 * cos(angle * 2.0))
					leaves.set_color(Color(0.72, 0.88, 0.65))
					leaves.add_vertex(center + Vector3(cos(angle) * radius, sin(angle + direction) * 0.003, sin(angle) * radius))
	leaves.generate_normals()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() { ALBEDO=vec3(0.08,0.14,0.025)*COLOR.rgb; ROUGHNESS=0.9; BACKLIGHT=ALBEDO*0.35; }
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 91271
	var locations: Array[Vector3] = []
	for attempt: int in range(14000):
		var x: float = random.randf_range(-26.0, 26.0)
		var z: float = random.randf_range(-26.0, 26.0)
		if Vector2(x, z).length() < 8.0 or absf(x - sin(z * 0.16) * 2.2) < 3.6 or absf(z - sin(x * 0.14) * 1.5) < 2.7:
			continue
		if sin(x * 0.8 + sin(z * 0.3)) * cos(z * 0.7) < 0.05:
			continue
		locations.append(Vector3(x, ground_height(x, z), z))
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = leaves.commit()
	multi.instance_count = locations.size()
	for index: int in range(locations.size()):
		var size: float = random.randf_range(0.8, 1.7)
		multi.set_instance_transform(index, Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * size), locations[index]))
		multi.set_instance_color(index, Color(random.randf_range(0.65, 1.0), random.randf_range(0.8, 1.0), 0.8))
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.name = "CloverEdges"
	visual.multimesh = multi
	visual.material_override = material
	visual.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

func make_timber_material() -> void:
	# Grain follows each beam's local length rather than projecting board joints onto logs.
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_pos;
void vertex() { local_pos=VERTEX; }
void fragment() {
 vec2 uv=vec2(UV.x*0.6,local_pos.y*0.5);
 vec3 base=texture(grain,uv).rgb;
 ALBEDO=base*vec3(0.82,0.78,0.70);
 ROUGHNESS=0.88;
}
"""
	timber_material = ShaderMaterial.new()
	timber_material.shader = shader
	timber_material.set_shader_parameter("grain", load("res://content/environments/village_generated/aged_timber.png"))

func roof_surface_point(location: Vector3, width: float, depth: float, side: int, down: float, along: float) -> Vector3:
	var fringe: float = pow(down, 8.0) * sin(along * 83.0) * 0.065
	return location + Vector3(side * (width * 0.5 * down + fringe), 2.8 * (0.5 - down) - absf(fringe), (along - 0.5) * depth)

func refresh_foliage(root_node: Node3D) -> void:
	# Upgrade nearby broadleaf species; preserve conifers and distant low-detail meshes.
	var replacement: StandardMaterial3D
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var material: Material = visual.material_override
		if not material is StandardMaterial3D:
			continue
		var original: StandardMaterial3D = material as StandardMaterial3D
		if original.albedo_texture == null:
			continue
		var species: String = original.albedo_texture.resource_path.get_file().get_basename()
		var broadleaf: Array[String] = ["tree01", "tree02", "tree03", "tree04", "tree08", "tree09"]
		if not species in broadleaf:
			continue
		var bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		if Vector2(bounds.get_center().x, bounds.get_center().z).length() < 80.0:
			var tree: Node3D = preload("res://gameplay/environment/woodland_tree.gd").new() as Node3D
			root_node.add_child(tree)
			var base: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
			tree.global_position = base
			tree.rotation.y = fposmod(base.x * 0.71 + base.z * 0.37, TAU)
			tree.call("configure", load("res://content/environments/village_generated/tree01_atlas.png"), original, bounds.size.y)
			var crown_width: float = clampf(bounds.size.x / bounds.size.y / 0.58, 0.8, 1.35)
			tree.scale.x *= crown_width
			tree.scale.z *= crown_width
			var leaf_tones: Array[Color] = [Color("d5d9c6"), Color("b9c7a6"), Color("9fae91"), Color("d0ce9e"), Color("c3c59b"), Color("b2c3aa")]
			var crown: MeshInstance3D = tree.get_child(1) as MeshInstance3D
			(crown.material_override as StandardMaterial3D).albedo_color = leaf_tones[broadleaf.find(species)]
			visual.visible = false
			continue
		if species != "tree01":
			continue
		if replacement == null:
			replacement = original.duplicate() as StandardMaterial3D
			replacement.albedo_texture = load("res://content/environments/village_generated/tree01_atlas.png") as Texture2D
		visual.material_override = replacement

func ridge_outcrops() -> void:
	# Terrain-conforming fractured rock shoulders interrupt selected distant crests.
	var candidates: Array[Vector3] = []
	for z: int in range(-240, 241, 12):
		for x: int in range(-240, 241, 12):
			if Vector2(x,z).length() < 145.0:
				continue
			var height: float = landscape_surface_height(x,z)
			if height < 20.0:
				continue
			if height < landscape_surface_height(x-12,z) or height < landscape_surface_height(x+12,z) or height < landscape_surface_height(x,z-12) or height < landscape_surface_height(x,z+12):
				continue
			candidates.append(Vector3(x,height,z))
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var peaks: Array[Vector3] = []
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 82519
	for candidate: Vector3 in candidates:
		var spaced: bool = true
		for peak: Vector3 in peaks:
			if peak.distance_to(candidate) < 48.0:
				spaced = false
		if not spaced:
			continue
		peaks.append(candidate)
		var direction: float = random.randf_range(0.0, TAU)
		var width: float = random.randf_range(32.0, 52.0)
		var depth: float = random.randf_range(12.0, 22.0)
		var rise: float = random.randf_range(12.0, 22.0)
		var rotation: Basis = Basis(Vector3.UP, direction)
		for z: int in range(8):
			for x: int in range(20):
				var corners: Array[Vector2] = [Vector2(x,z),Vector2(x+1,z),Vector2(x,z+1),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]
				for corner: Vector2 in corners:
					var uv: Vector2 = corner / Vector2(20.0,8.0)
					var point: Vector3 = candidate + rotation * Vector3((uv.x-0.5)*width,0,(uv.y-0.5)*depth)
					var envelope: float = pow(maxf(sin(uv.x*PI),0.0),0.65) * pow(maxf(sin(uv.y*PI),0.0),0.5)
					var shoulder: float = lerpf(1.15,0.55,uv.x)
					var fracture: float = sin(corner.x*2.3+corner.y*1.7)*0.8
					var raw: float = envelope*rise*shoulder + fracture*envelope
					var stepped: float = floorf(raw/2.4)*2.4
					point.y = landscape_surface_height(point.x,point.z) - 0.25 + lerpf(raw,stepped,0.6)
					tool.add_vertex(point)
		if peaks.size() == 10:
			break
	assert(not peaks.is_empty(), "Distant terrain must provide ridge outcrop sites")
	tool.generate_normals()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = tool.commit()
	visual.material_override = make_landscape_material()
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(visual)
	print("VILLAGE_RIDGES_OK: ", peaks.size(), " spaced crest formations")

func woodland_edges() -> void:
	# Cosmetic grouped saplings share two instanced meshes, with no gameplay collision.
	landscape_noise.seed = 41271
	landscape_noise.frequency = 0.006
	landscape_noise.fractal_octaves = 3
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 74219
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for group: int in range(52):
		var angle: float = random.randf_range(0.0, TAU)
		var radius: float = random.randf_range(43.0, 126.0)
		var center: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		for plant: int in range(7):
			var point: Vector2 = center + Vector2(random.randf_range(-8.0,8.0), random.randf_range(-8.0,8.0))
			if maxf(absf(point.x), absf(point.y)) < 34.0 or absf(point.x) < 6.0:
				continue
			var height: float = landscape_surface_height(point.x, point.y)
			var slope: float = absf(landscape_surface_height(point.x + 2.0, point.y) - height) + absf(landscape_surface_height(point.x, point.y + 2.0) - height)
			if slope > 2.0:
				continue
			var size: float = random.randf_range(2.5, 6.5) / 10.0
			var basis: Basis = Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(size * 1.25, size, size * 1.25))
			transforms.append(Transform3D(basis, Vector3(point.x, height - 0.06, point.y)))
			colors.append(Color("b4c29c").lerp(Color("e2e6c5"), random.randf()))
	assert(transforms.size() > 200, "Woodland groups must contain usable grounded saplings")
	var source: StandardMaterial3D = StandardMaterial3D.new()
	source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	source.alpha_scissor_threshold = 0.5
	source.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	var prototype: Node3D = preload("res://gameplay/environment/woodland_tree.gd").new() as Node3D
	prototype.call("configure", load("res://content/environments/village_generated/tree01_atlas.png"), source, 10.0)
	for part: int in range(2):
		var template: MeshInstance3D = prototype.get_child(part) as MeshInstance3D
		var instances: MultiMesh = MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = template.mesh
		instances.instance_count = transforms.size()
		for index: int in range(transforms.size()):
			instances.set_instance_transform(index, transforms[index])
			instances.set_instance_color(index, colors[index] if part == 1 else Color.WHITE)
		var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
		visual.multimesh = instances
		var material: StandardMaterial3D = template.material_override as StandardMaterial3D
		material.vertex_color_use_as_albedo = true
		visual.material_override = material
		visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(visual)
	prototype.free()
	print("VILLAGE_WOODLAND_OK: ", transforms.size(), " grounded saplings in two instanced meshes")

func apply_atmosphere(environment: Environment) -> void:
	environment.fog_enabled = true
	environment.fog_light_color = Color("bdcbd2")
	environment.fog_density = 0.0015
	environment.fog_height = 2.0
	environment.fog_height_density = 0.015
	environment.fog_aerial_perspective = 0.25
	environment.fog_sun_scatter = 0.18
	environment.fog_sky_affect = 0.08

func make_ground_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D dirt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mineral_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
 vec2 warped=p+vec2(noise(p*0.17),noise(p*0.17+31.0))*0.8;
 float mineral_mask=smoothstep(0.28,0.72,noise(warped*0.16));
 vec3 dirt=mix(texture(dirt_color,warped*0.4).rgb,texture(mineral_color,warped*0.23).rgb,mineral_mask*0.75);
 dirt*=mix(vec3(0.72,0.68,0.60),vec3(1.04,1.0,0.91),noise(p*0.09))*mix(0.9,1.04,n);
 vec3 grass=texture(grass_color,p*0.22).rgb * mix(0.72,1.05,n);
 vec3 rock=texture(stones,p*0.65).rgb;
 float rock_mask=smoothstep(0.55,0.8,noise(p*0.23))*path*0.25;
 ALBEDO=mix(mix(dirt,rock,rock_mask),grass,vegetation);
 ROUGHNESS=mix(mix(0.94,texture(stone_roughness,p*0.65).r,rock_mask),texture(grass_roughness,p*0.22).r,vegetation);
 NORMAL_MAP=mix(mix(vec3(0.5,0.5,1.0),texture(stone_normal,p*0.65).rgb,rock_mask),texture(grass_normal,p*0.22).rgb,vegetation);
 NORMAL_MAP_DEPTH=0.45;
 // Screen-space color derivatives are not a physical normal map and shimmer during motion.
}
"""
	material.shader = shader
	material.set_shader_parameter("dirt_color", load("res://content/environments/village_generated/soil_gravel.png"))
	material.set_shader_parameter("mineral_color", load("res://content/environments/village_generated/mineral_earth.png"))
	for binding: String in ["stones", "grass_color", "stone_normal", "grass_normal", "stone_roughness", "grass_roughness"]:
		var family: String = "GrassGround" if binding.begins_with("grass") else "StoneFloor"
		var channel: String = "normal" if binding.ends_with("normal") else ("roughness" if binding.ends_with("roughness") else "basecolor")
		material.set_shader_parameter(binding, load("res://content/environments/valhalla/textures/KB3D_VHL_%s_%s.png" % [family, channel]))
	return material

func refresh_ground(root_node: Node3D) -> void:
	# Replace only the terrain material; baked UV2, lightmap and collision stay intact.
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var material: ShaderMaterial = visual.material_override as ShaderMaterial
		if material != null and material.get_shader_parameter("dirt_color") != null:
			visual.material_override = make_ground_material()

func make_landscape_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
vec3 bedrock(vec3 p,vec3 n) {
 vec3 weights=pow(abs(n),vec3(4.0));
 weights/=max(weights.x+weights.y+weights.z,0.001);
 return texture(rock,p.yz*0.12).rgb*weights.x+texture(rock,p.xz*0.12).rgb*weights.y+texture(rock,p.xy*0.12).rgb*weights.z;
}
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void fragment() {
 float slope=normalize(world_normal).y;
 vec2 p=world_pos.xz;
 vec2 warped=p+vec2(noise(p*0.035),noise(p*0.035+47.0))*18.0;
 float patch=noise(warped*0.065);
 float elevation=smoothstep(7.0,26.0,world_pos.y+patch*9.0);
 float cliff=1.0-smoothstep(0.67,0.94,slope);
 float exposed=clamp(max(cliff,elevation*0.8)+(patch-0.5)*0.35,0.0,1.0);
 vec3 earth=texture(soil,p*0.18).rgb*mix(vec3(0.60,0.78,0.47),vec3(0.9,0.98,0.68),noise(warped*0.027));
 vec3 stone=bedrock(world_pos,normalize(world_normal));
 float strata=0.93+0.07*sin(world_pos.y*1.6+noise(p*0.12)*2.0);
 stone*=mix(vec3(0.76,0.79,0.77),vec3(1.03,0.96,0.84),patch)*strata;
 ALBEDO=mix(earth,stone,exposed)*(0.87+0.13*noise(warped*0.018));
 ROUGHNESS=0.95;
}
"""
	material.shader = shader
	material.set_shader_parameter("soil", load("res://content/environments/valhalla/textures/KB3D_VHL_GrassGround_basecolor.png"))
	material.set_shader_parameter("rock", load("res://content/environments/village_generated/schist_rock.png"))
	return material

func refresh_landscape(root_node: Node3D) -> void:
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		var material: ShaderMaterial = visual.material_override as ShaderMaterial
		if material != null and material.get_shader_parameter("soil") != null and material.get_shader_parameter("rock") != null:
			visual.material_override = make_landscape_material()
