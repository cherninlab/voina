class_name CarProp
extends StaticBody3D
## A parked GGBot PSX car used as arena cover. The source models are built about 1.5x real size,
## so only the visual is uniformly scaled; the collision hull is built from scaled points
## instead of scaling the body.

const VISUAL_SCALE: float = 0.65
const ROOT: String = "res://content/vehicles/ggbot_psx_cars/"

@export var mesh: Mesh
@export var texture: Texture2D

static func create(model: String, skin: String) -> CarProp:
	var car: CarProp = CarProp.new()
	car.mesh = load(ROOT + model) as Mesh
	car.texture = load(ROOT + skin) as Texture2D
	return car

func _ready() -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3.ONE * VISUAL_SCALE
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	# 128 px PSX textures read best unfiltered.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 0.85
	visual.material_override = material
	add_child(visual)
	var hull: ConvexPolygonShape3D = mesh.create_convex_shape(true, true)
	var points: PackedVector3Array = hull.points
	for index: int in range(points.size()):
		points[index] *= VISUAL_SCALE
	hull.points = points
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = hull
	add_child(collision)

func size() -> Vector3:
	return mesh.get_aabb().size * VISUAL_SCALE
