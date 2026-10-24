class_name FlagstoneFloor
extends RefCounted
## Seamless flagstone floor modules baked by scripts/art/build_flagstones.py (T-165).
## A module spans +X and +Z from its corner (4 x 4 m; border strips 4 x 0.5 m) with the
## walking plane at y = 0. Every vertex stays within 2.1 cm of it, so flat collision stays.
## Variants of one family share every stone that crosses a border, so any variant tiles
## with any other: pick one per cell to hide repetition. Visual only, no collision.

const ROOT: String = "res://content/environments/procedural_flagstone_v1/"
const PBR: String = "res://content/environments/dungeon_pbr_v2/"
const SIZE: float = 4.0
const BORDER_WIDTH: float = 0.5
const FAMILIES: Dictionary[String, Array] = {
	"laid": ["laid_a", "laid_b", "laid_c"],
	"coursed": ["coursed_a", "coursed_b", "coursed_c"],
	"border": ["border_a", "border_b"],
}
const PARTS: PackedStringArray = ["stones", "dirt"]
## Visibility range (begin, end) in metres for LOD 0, 1 and 2.
const LOD_RANGES: Array[Vector2] = [Vector2(0.0, 14.0), Vector2(14.0, 32.0), Vector2(32.0, 90.0)]
static var meshes: Dictionary[String, Mesh] = {}
static var surfaces: Dictionary[String, ShaderMaterial] = {}

static func mesh(id: String, part: String, level: int = 0) -> Mesh:
	var key: String = "%s_%s_lod%d" % [id, part, level]
	if not meshes.has(key):
		var scene: Node3D = (load(ROOT + "flagstone_%s.glb" % id) as PackedScene).instantiate() as Node3D
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			meshes[String(node.name)] = (node as MeshInstance3D).mesh
		scene.free()
	return meshes[key]

static func material(part: String) -> ShaderMaterial:
	if surfaces.has(part):
		return surfaces[part]
	var folder: String = PBR + ("Rocks025/" if part == "dirt" else "Concrete012/")
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = preload("res://content/environments/procedural_flagstone_v1/flagstone.gdshader")
	result.set_shader_parameter("albedo_map", load(folder + "albedo.png"))
	result.set_shader_parameter("normal_map", load(folder + "normal_gl.png"))
	result.set_shader_parameter("roughness_map", load(folder + "roughness.png"))
	result.set_shader_parameter("dirt", part == "dirt")
	surfaces[part] = result
	return result

## One module with both parts and all LODs switched by visibility range.
static func module(id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = id
	for part: String in PARTS:
		for level: int in range(LOD_RANGES.size()):
			var visual: MeshInstance3D = MeshInstance3D.new()
			visual.name = "%s_lod%d" % [part, level]
			visual.mesh = mesh(id, part, level)
			visual.material_override = material(part)
			visual.visibility_range_begin = LOD_RANGES[level].x
			visual.visibility_range_end = LOD_RANGES[level].y
			if part == "dirt":
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(visual)
	return root

## Deterministic variant for a grid cell.
static func pick(family: String, cell: Vector2i, seed: int = 0) -> String:
	var ids: Array = FAMILIES[family]
	return String(ids[posmod(hash([cell.x, cell.y, seed]), ids.size())])

## Lays `cells` modules of one family from `origin` (a module corner) along +X and +Z.
static func tile(parent: Node3D, family: String, origin: Vector3, cells: Vector2i, seed: int = 0) -> void:
	var depth: float = BORDER_WIDTH if family == "border" else SIZE
	for x: int in range(cells.x):
		for z: int in range(cells.y):
			var piece: Node3D = module(pick(family, Vector2i(x, z), seed))
			piece.position = origin + Vector3(x * SIZE, 0.0, z * depth)
			parent.add_child(piece)
