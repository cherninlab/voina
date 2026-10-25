class_name RedDescentDressing
extends Node3D
## Integrates settled assets at their baked scale, using real framing as sockets.

const RUBBLE: String = "res://content/environments/procedural_rubble_v1/"
const HANGING: String = "res://content/environments/procedural_hanging_v1/"
var piles: Array[Node3D] = []
var hangings: Array[Node3D] = []
var placements: Array[Dictionary] = []
var practical_mounts: Array[Dictionary] = []
var hanging_assets: Dictionary[String, Dictionary] = {}
var rubble_assets: Dictionary[String, Dictionary] = {}
var level: RedDescentDungeon

func build(dungeon: RedDescentDungeon) -> void:
	level = dungeon
	name = "GeneratedDressing"
	var rubble_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RUBBLE + "rubble.json")) as Dictionary
	for entry: Dictionary in rubble_report["piles"] as Array:
		rubble_assets[String(entry["id"])] = entry
	var hanging_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HANGING + "bake.json")) as Dictionary
	for entry: Dictionary in hanging_report["assets"] as Array:
		hanging_assets["%s_%d" % [String(entry["type"]), int(entry["variant"])]] = entry
	var stone: ShaderMaterial = level.surface(RedDescentDungeon.PBR + "Rocks025/", 0.526, 0.8, 0.3)
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_texture = load(RedDescentDungeon.PBR + "Wood035/albedo.png") as Texture2D
	wood.normal_enabled = true
	wood.normal_texture = load(RedDescentDungeon.PBR + "Wood035/normal_gl.png") as Texture2D
	wood.roughness_texture = load(RedDescentDungeon.PBR + "Wood035/roughness.png") as Texture2D
	wood.vertex_color_use_as_albedo = true
	wood.albedo_color = Color(0.62, 0.6, 0.58)
	wood.uv1_scale = Vector3(0.6, 0.6, 1.0)
	# Wall piles meet the inner masonry face, including the bake's back-plane offset.
	for spot: Array in [
		["wall_spill_s2", Vector3(3, -10, -41.8765), 0.0],
		["wall_spill_s1", Vector3(0, -18, 47.9524), PI],
		["wall_spill_s3", Vector3(-40.9771, -10, -34), PI * 0.5],
		["floor_scatter_s2", Vector3(-43, 0, -29), 0.0],
		["floor_scatter_s3", Vector3(-24, 0, -28), 0.0],
		["floor_scatter_s1", Vector3(29.5, -4, -15), 0.0],
		["bridge_debris_s2", Vector3(40, -18, 33), 0.0],
		["bridge_debris_s3", Vector3(30, -28, -8), 0.0],
	]:
		place_rubble("rubble_" + String(spot[0]), spot[1] as Vector3, float(spot[2]), stone, wood)
	var ties: Array[Dictionary] = []
	var king_posts: int = 0
	var bell: Dictionary = {}
	var restraint: Dictionary = {}
	for member: Dictionary in level.architecture.structure.members:
		match String(member["role"]):
			"roof tie": ties.append(member)
			"king post": king_posts += 1
			"bell beam": bell = member
			"restraint beam": restraint = member
	assert(ties.size() == 3 and not bell.is_empty() and not restraint.is_empty(), "Dressing requires actual landmark framing")
	var tie: Dictionary = ties[1]
	var a: Vector3 = tie["from"] as Vector3
	var b: Vector3 = tie["to"] as Vector3
	var along: Vector3 = (b - a).normalized()
	var basis: Basis = Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var half_depth: float = float(tie["depth"]) * 0.5
	mount("nave_banner", "banner_1", a.lerp(b, 0.22) - Vector3.UP * half_depth, basis, "cloth_crimson", "underside")
	mount("nave_drape", "drape_1", a.lerp(b, 0.36), basis, "cloth_ash", "top")
	mount("nave_tapestry", "tapestry_1", a.lerp(b, 0.66) - Vector3.UP * half_depth, basis, "cloth_crimson", "underside")
	mount("nave_pennant", "banner_0", a.lerp(b, 0.80) - Vector3.UP * half_depth, basis, "cloth_ochre", "underside")
	# A right-angle web fits the tie top and the king post's near face; a
	# vaulted nave keeps only its tie beams.
	if king_posts > 0:
		mount("nave_web", "web_corner_2", (a + b) * 0.5 - along * 0.13 + Vector3.UP * half_depth, basis * Basis(Vector3.BACK, PI), "cobweb_corner", "web")
	var bell_a: Vector3 = bell["from"] as Vector3
	var bell_b: Vector3 = bell["to"] as Vector3
	mount("bell_banner", "banner_1", bell_a.lerp(bell_b, 0.28) - Vector3.UP * 0.2, Basis.IDENTITY, "cloth_ochre", "underside")
	mount("bell_tapestry", "tapestry_2", bell_a.lerp(bell_b, 0.715) - Vector3.UP * 0.2, Basis.IDENTITY, "cloth_crimson", "underside")
	var frame: Vector3 = ((restraint["from"] as Vector3) + (restraint["to"] as Vector3)) * 0.5
	mount("restraint_banner", "banner_2", frame + Vector3(-0.55, -0.18, 0), Basis.IDENTITY, "cloth_ash", "underside")
	mount("restraint_rope", "rope_2", frame + Vector3(-0.7, 0, 0.2), Basis.IDENTITY, "rope_hemp", "front")
	mount("restraint_web", "web_corner_2", frame + Vector3(-0.93, -0.18, 0.14), Basis.IDENTITY, "cobweb_corner", "web")
	# Permanent practicals, with two iron brackets back into the masonry.
	for end: Vector3 in [a, b]:
		var inward: Vector3 = along if end == a else -along
		# Move the practical off the cloth plane: coplanar lights cannot illuminate
		# its faces, even when their distance/range appears sufficient.
		var wall: Vector3 = end - basis.z * 2.0
		var base: Vector3 = wall + inward - Vector3.UP * 4.0
		practical_mounts.append({"wall": wall, "pole": base, "inward": inward})
		for rise: float in [0.3, 1.15]:
			level.architecture.beam(wall + Vector3.UP * (rise - 4.0), base + Vector3.UP * rise, 0.07, "iron")
		level.torch(base)
		var light: OmniLight3D = level.fires[-1]
		light.omni_range = 22.0
		light.light_energy = 5.8

func place_rubble(id: String, at: Vector3, yaw: float, stone: Material, wood: Material) -> void:
	var pile: Node3D = (load(RUBBLE + id + ".glb") as PackedScene).instantiate() as Node3D
	pile.name = id
	pile.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(pile)
	pile.add_to_group("dungeon_rubble")
	piles.append(pile)
	# The settled convex hulls are retained only on LOD0. Other levels are visual.
	for lod: int in range(3):
		var visual: Node3D = pile
		if lod > 0:
			visual = (load(RUBBLE + "lod/%s_lod%d.glb" % [id, lod]) as PackedScene).instantiate() as Node3D
			for body: Node in visual.find_children("*", "StaticBody3D", true, false):
				body.get_parent().remove_child(body)
				body.free()
			pile.add_child(visual)
		for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			mesh.material_override = wood if mesh.name.begins_with("Wood") else stone
			mesh.visibility_range_begin = [0.0, 14.0, 32.0][lod]
			mesh.visibility_range_end = [14.0, 32.0, 80.0][lod]
	placements.append({"id": id, "kind": "rubble", "node": pile, "asset": rubble_assets[id]})

func mount(id: String, asset: String, at: Vector3, basis: Basis, material: String, face: String) -> void:
	var hanging: Node3D = (load(HANGING + asset + ".glb") as PackedScene).instantiate() as Node3D
	hanging.name = id
	hanging.transform = Transform3D(basis, at)
	for node: Node in hanging.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.material_override = load(HANGING + material + ".tres") as Material
		mesh.visibility_range_end = 65.0
	add_child(hanging)
	hanging.add_to_group("dungeon_hangings")
	hangings.append(hanging)
	var sockets: Dictionary = hanging_assets[asset]["sockets_godot"] as Dictionary
	for key: String in sockets:
		var socket: Vector3 = hanging.global_transform * vector(sockets[key] as Array)
		var into: Vector3 = basis.y if face == "underside" else (-basis.y if face == "top" else -basis.z)
		if face != "web":
			level.architecture.beam(socket - into * 0.015, socket + into * 0.09, 0.045, "iron")
	placements.append({"id": id, "kind": "hanging", "node": hanging, "asset": hanging_assets[asset], "material": material})

static func vector(array: Array) -> Vector3:
	return Vector3(float(array[0]), float(array[1]), float(array[2]))
