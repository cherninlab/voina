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
	var trunk: Array[Vector3] = [Vector3(0,-0.08,0), Vector3(0.08,2.5,-0.05), Vector3(-0.12,5.0,0.12), Vector3(0.22,7.2,0.05), Vector3(0.12,8.8,-0.12)]
	for segment: int in range(trunk.size() - 1):
		branch(bark, trunk[segment], trunk[segment + 1], 0.24 - segment * 0.045, 0.195 - segment * 0.045)
	for index: int in range(14):
		var angle: float = index * 2.4
		var height: float = 3.4 + index * 0.34
		var reach: float = 2.1 - absf(height - 5.8) * 0.28
		var start: Vector3 = trunk[trunk.size() - 1]
		for segment: int in range(trunk.size() - 1):
			if height <= trunk[segment + 1].y:
				var weight: float = inverse_lerp(trunk[segment].y, trunk[segment + 1].y, height)
				start = trunk[segment].lerp(trunk[segment + 1], weight)
				break
		var middle: Vector3 = start + Vector3(cos(angle), 0.5, sin(angle)) * reach * 0.55
		var finish: Vector3 = start + Vector3(cos(angle) * reach, 1.2 + random.randf() * 0.5, sin(angle) * reach)
		branch(bark, start, middle, 0.085, 0.05)
		branch(bark, middle, finish, 0.05, 0.015)
		for card: int in range(3):
			var orientation: Basis = Basis(Vector3.UP, angle + card * PI / 3.0) * Basis(Vector3.RIGHT, random.randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, random.randf_range(-0.45, 0.45))
			var center: Vector3 = finish + Vector3(random.randf_range(-0.25,0.25), 0.15, random.randf_range(-0.25,0.25))
			leaf_card(leaves, center, orientation, random.randf_range(1.6,2.2), random.randf_range(1.8,2.4))
		for card: int in range(2):
			var center: Vector3 = start.lerp(finish, 0.65) + Vector3.UP * 0.6
			var orientation: Basis = Basis(Vector3.UP, angle + card * PI * 0.5) * Basis(Vector3.FORWARD, random.randf_range(-0.5, 0.5))
			leaf_card(leaves, center, orientation, 2.0, 2.2)
	for card: int in range(3):
		leaf_card(leaves, Vector3(0.12,8.9,-0.12), Basis(Vector3.UP, card * PI / 3.0), 1.8, 2.0)
	bark.generate_normals()
	bark.index()
	leaves.generate_normals()
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
				tool.add_vertex(center + orientation * Vector3((uv.x - 0.5) * width, (uv.y - 0.5) * height, curve))
