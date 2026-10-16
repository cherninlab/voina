class_name TreePack
extends Node3D

const ASSET_ROOT: String = "res://content/environments/tree_pack/"
var plants: Array[Node3D] = []

func _ready() -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	ground.position.y = -0.03
	var soil: StandardMaterial3D = StandardMaterial3D.new()
	soil.albedo_color = Color("283b30")
	soil.roughness = 1.0
	ground.material_override = soil
	add_child(ground)
	# Cosmetic scenery sits beyond the arena's +/-12 m walls; no random or replicated state.
	for index: int in range(24):
		var angle: float = TAU * index / 24.0
		var radius: float = 17.0 + (index % 3) * 2.0
		add_plant("tree%02d" % (1 + (index * 5) % 36), Vector3(cos(angle) * radius, 0, sin(angle) * radius), 5.0 + index % 4)
	for index: int in range(12):
		var angle: float = TAU * (index + 0.4) / 12.0
		add_plant("bush%02d" % (1 + index % 8), Vector3(cos(angle) * 18.0, 0, sin(angle) * 18.0), 1.2)

func add_plant(id: String, location: Vector3, height: float) -> Node3D:
	var scene: PackedScene = load(ASSET_ROOT + "models/" + id + ".fbx") as PackedScene
	var texture: Texture2D = load(ASSET_ROOT + "textures/" + id + ".png") as Texture2D
	var plant: Node3D = Node3D.new()
	plant.name = id + "_" + str(plants.size())
	add_child(plant)
	var model: Node3D = scene.instantiate() as Node3D
	plant.add_child(model)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 1.0
	var bounds: AABB
	var first: bool = true
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.material_override = material
		var relative: Transform3D = plant.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds: AABB = relative * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	assert(not first and bounds.size.y > 0.0, "Plant must contain a usable mesh")
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	plant.scale = Vector3.ONE * height / bounds.size.y
	plant.position = location
	plants.append(plant)
	return plant
