extends Node3D
## Original trunk/branch mesh and clustered foliage using the paired generated atlas.

static var bark_mesh: ArrayMesh
static var foliage_mesh: ArrayMesh

func configure(atlas: Texture2D, source_material: StandardMaterial3D, height: float) -> void:
	if bark_mesh == null:
		build_meshes()
	scale = Vector3.ONE * height / 10.0
	var bark: StandardMaterial3D = StandardMaterial3D.new()
	bark.albedo_texture = atlas
	bark.roughness = 0.95
	bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var foliage: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
	foliage.albedo_texture = atlas
	foliage.albedo_color = Color("d5d9c6")
	foliage.backlight_enabled = true
	foliage.backlight = Color("455624")
	for part: int in range(2):
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = bark_mesh if part == 0 else foliage_mesh
		visual.material_override = bark if part == 0 else foliage
		visual.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		add_child(visual)

static func build_meshes() -> void:
	var bark: SurfaceTool = SurfaceTool.new()
	var leaves: SurfaceTool = SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 64192
	var trunk: Array[Vector3] = [Vector3(0,-0.08,0), Vector3(0.12,2.5,-0.08), Vector3(-0.18,4.8,0.16), Vector3(0.3,6.8,0.1), Vector3(0.12,8.2,-0.18)]
	for segment: int in range(trunk.size() - 1):
		branch(bark, trunk[segment], trunk[segment + 1], 0.28 - segment * 0.06, 0.22 - segment * 0.06)
	for index: int in range(12):
		var angle: float = index * 2.4 + random.randf_range(-0.2, 0.2)
		var height: float = 3.5 + index * 0.26
		var reach: float = random.randf_range(3.0, 4.0) - absf(height - 5.0) * 0.25
		var radial: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var lateral: Vector3 = Vector3(-sin(angle), 0.0, cos(angle))
		var start: Vector3 = trunk[trunk.size() - 1]
		for segment: int in range(trunk.size() - 1):
			if height <= trunk[segment + 1].y:
				var weight: float = inverse_lerp(trunk[segment].y, trunk[segment + 1].y, height)
				start = trunk[segment].lerp(trunk[segment + 1], weight)
				break
		var middle: Vector3 = start + radial * reach * 0.5 + Vector3.UP * 0.7
		var finish: Vector3 = start + radial * reach + Vector3.UP * random.randf_range(1.4, 2.1)
		branch(bark, start, middle, 0.11, 0.065)
		branch(bark, middle, finish, 0.065, 0.025)
		for fork: int in range(2):
			var side: float = -1.0 if fork == 0 else 1.0
			var tip: Vector3 = finish + lateral * side * random.randf_range(0.5, 1.0) + Vector3.UP * random.randf_range(0.1, 0.6)
			branch(bark, middle.lerp(finish, 0.65), tip, 0.035, 0.008)
			for card: int in range(3):
				var orientation: Basis = Basis(Vector3.UP, angle + card * PI / 3.0) * Basis(Vector3.RIGHT, random.randf_range(-0.7, 0.7)) * Basis(Vector3.FORWARD, random.randf_range(-0.6, 0.6))
				leaf_card(leaves, tip, orientation, random.randf_range(2.0, 2.8), random.randf_range(1.5, 2.1))
		for card: int in range(2):
			var center: Vector3 = start.lerp(finish, 0.6) + Vector3.UP * 0.7
			var orientation: Basis = Basis(Vector3.UP, angle + card * PI * 0.5) * Basis(Vector3.FORWARD, random.randf_range(-0.6, 0.6))
			leaf_card(leaves, center, orientation, 2.4, 1.9)
	for crown: int in range(3):
		var angle: float = crown * 2.4
		var tip: Vector3 = trunk[4] + Vector3(cos(angle) * 0.8, 0.35, sin(angle) * 0.8)
		branch(bark, trunk[3], tip, 0.07, 0.015)
		for card: int in range(3):
			leaf_card(leaves, tip, Basis(Vector3.UP, angle + card * PI / 3.0), 2.4, 2.0)
	bark.generate_normals()
	bark.index()
	leaves.index()
	bark_mesh = bark.commit()
	foliage_mesh = leaves.commit()

static func branch(tool: SurfaceTool, start: Vector3, finish: Vector3, base_radius: float, tip_radius: float) -> void:
	var rotation: Quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	for side: int in range(8):
		var corners: Array[Vector2] = [Vector2(side,0),Vector2(side+1,0),Vector2(side,1),Vector2(side+1,0),Vector2(side+1,1),Vector2(side,1)]
		for corner: Vector2 in corners:
			var angle: float = corner.x * TAU / 8.0
			var radius: float = lerpf(base_radius, tip_radius, corner.y)
			var radial: Vector3 = Vector3(cos(angle),0,sin(angle)) * radius
			tool.set_uv(Vector2(0.08 + corner.x / 8.0 * 0.1, 0.9 - corner.y * 0.84))
			tool.add_vertex(start.lerp(finish, corner.y) + rotation * radial)

static func leaf_card(tool: SurfaceTool, center: Vector3, orientation: Basis, width: float, height: float) -> void:
	for y: int in range(3):
		for x: int in range(3):
			var corners: Array[Vector2] = [Vector2(x,y),Vector2(x+1,y),Vector2(x,y+1),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]
			for corner: Vector2 in corners:
				var uv: Vector2 = corner / 3.0
				var curve: float = sin(uv.x * PI) * sin(uv.y * PI) * 0.2
				tool.set_uv(Vector2(0.31 + uv.x * 0.68, 0.99 - uv.y * 0.98))
				var position: Vector3 = center + orientation * Vector3((uv.x - 0.5) * width, (uv.y - 0.5) * height, curve)
				# Artist-shaped crown normals keep intersecting foliage cards from shading as flat sheets.
				tool.set_normal(((position - Vector3(0.0, 6.5, 0.0)) * Vector3(1.0, 0.8, 1.0)).normalized())
				tool.add_vertex(position)
