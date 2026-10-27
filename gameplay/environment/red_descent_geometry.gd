class_name RedDescentGeometry
extends Node3D
## Fixed architecture. Batched visual blocks, one immutable concave collision mesh.

var materials: Dictionary[String, Material] = {}
var torch_posts: Array[Vector3] = []
## Wall sconces in stone rooms: {"at": wall face at sconce height, "facing": into the room}.
var sconces: Array[Dictionary] = []
var rooms: Array[Dictionary] = RedDescentLayout.rooms()
var paths: Array[Dictionary] = RedDescentLayout.routes()
var batches: Dictionary[String, Array] = {}
var batch_colors: Dictionary[String, Array] = {}
var batch_materials: Dictionary[String, String] = {}
var batch_models: Dictionary[String, String] = {}
var batch_meshes: Dictionary[String, Mesh] = {}
var structure: DungeonStructure
var module_counts: Dictionary[String, int] = {}
var surfaces: Dictionary[String, PackedVector3Array] = {}
var surface_materials: Dictionary[String, String] = {}
var collision_faces: PackedVector3Array = PackedVector3Array()
var ribbon_edges: Dictionary[String, PackedVector3Array] = {}
const STONE_ROOMS: String = "res://content/environments/procedural_architecture_v1/rooms/"
const STONE_INDEX: String = "res://content/environments/procedural_architecture_v1/index.json"
const STONE_FACE: String = "res://content/environments/procedural_stone_surface_v1/limestone/"
const ROOTS: String = "res://content/environments/procedural_roots_v1/"
const PROP_SETS: String = "res://content/environments/procedural_props_aged_v1/sets/"
const RUBBLE: String = "res://content/environments/procedural_rubble_v1/rooms/"
## Passages built stone by stone (index.json "passages"), current for this layout.
var stone_passages: Array[Dictionary] = []
## Bays and portals built in stone: centre (x, y, z) and plan radius.
var stone_nodes: Array[Vector4] = []
var cube_faces: PackedVector3Array = BoxMesh.new().get_faces()
var fort_source: Node3D

func build() -> void:
	name = "Architecture"
	integrate_materials()
	# Paving has real open joints. Its continuous mortar bed remains visible
	# below them when the old ribbon is replaced by the stone build.
	var bedding: ShaderMaterial = (materials["plaster"] as ShaderMaterial).duplicate() as ShaderMaterial
	bedding.set_shader_parameter("coat", false)
	bedding.set_shader_parameter("plaster", 0.0)
	materials["mortar_bedding"] = bedding
	structure = DungeonStructure.new(self)
	fort_source = load("res://content/environments/dungeon_geometry_v2/modular_fort_01/modular_fort_01_2k.gltf").instantiate() as Node3D
	for room: Dictionary in rooms:
		build_room(room)
	load_stone_passages()
	stone_props()
	for index: int in range(paths.size()):
		build_path(paths[index], index < RedDescentLayout.MAIN_PATHS)
	build_vault(RedDescentLayout.outline(), false)
	build_vault(RedDescentLayout.spine(), true)
	# The void's base stops physics falls; the player recovery threshold is above it.
	piece(Vector3(150, 1, 150), Vector3(0, -60, 0), "dark", Basis.IDENTITY, true)
	flush()
	fort_source.free()
	fort_source = null
	print("GENERATED_KIT_PLACED: ", JSON.stringify(module_counts))
	print("RED_DESCENT_GEOMETRY_READY: %d routes, %d rooms, %d lit landmarks, sloping crossings" % [paths.size(), rooms.size(), torch_posts.size()])

func piece(size: Vector3, at: Vector3, material: String, basis: Basis = Basis.IDENTITY, solid: bool = false, color: Color = Color.WHITE) -> void:
	if material == "collision":
		for vertex: Vector3 in cube_faces:
			collision_faces.append(at + basis * (vertex * size))
		return
	var key: String = "%s:%d:%d:%d" % [material, floori(at.x / 18.0), floori(at.y / 12.0), floori(at.z / 18.0)]
	if not batches.has(key):
		batches[key] = []
		batch_colors[key] = []
		batch_materials[key] = material
	batches[key].append(Transform3D(basis * Basis.from_scale(size), at))
	batch_colors[key].append(color)
	if solid:
		for vertex: Vector3 in cube_faces:
			collision_faces.append(at + basis * (vertex * size))

func module(id: String, at: Vector3, basis: Basis = Basis.IDENTITY, scale: Vector3 = Vector3.ONE, color: Color = Color.WHITE) -> void:
	var key: String = "@%s:%d:%d:%d" % [id, floori(at.x / 12.0), floori(at.y / 10.0), floori(at.z / 12.0)]
	if not batches.has(key):
		batches[key] = []
		batch_colors[key] = []
		batch_models[key] = id
	batches[key].append(Transform3D(basis * Basis.from_scale(scale), at))
	batch_colors[key].append(color)
	module_counts[id] = module_counts.get(id, 0) + 1
	if id in ["wall_panel", "curved_wall", "broken_wall", "window_bay", "rock_outcrop"]:
		# Baked mesh faces keep bodies unscaled and include the projecting stone relief.
		var transform: Transform3D = Transform3D(basis * Basis.from_scale(scale), at)
		for vertex: Vector3 in GeneratedDungeonKit.mesh(id, 2).get_faces():
			collision_faces.append(transform * vertex)

func fitted_module(id: String, at: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var bounds: AABB = GeneratedDungeonKit.mesh(id).get_aabb()
	module(id, at, basis, size / bounds.size)

func stacked_pier(at: Vector3, basis: Basis, size: Vector3, variant: int) -> void:
	# A continuous bonded shaft carries the wall head; bases/capitals occur only once.
	var shaft: Vector3 = Vector3(size.x * (1.3 + float(variant % 2) * 0.08), size.y, size.z)
	var key: String = "masonry_pier:%d:%d:%d" % [floori(at.x / 18.0), floori(at.y / 12.0), floori(at.z / 18.0)]
	if not batches.has(key):
		batches[key] = []
		batch_colors[key] = []
		batch_materials[key] = "stone"
		batch_meshes[key] = load("res://content/environments/dungeon_masonry_v1/pier.obj") as Mesh
	batches[key].append(Transform3D(basis * Basis.from_scale(shaft), at + Vector3.UP * size.y * 0.5))
	batch_colors[key].append(Color.WHITE)
	for end: float in [0.0, 1.0]:
		piece(Vector3(shaft.x + 0.28, 0.32, shaft.z + 0.12), at + Vector3.UP * (0.16 + end * (size.y - 0.32)), "trim", basis)

func face(a: Vector3, b: Vector3, c: Vector3, material: String, solid: bool = true) -> void:
	if material == "collision":
		collision_faces.append_array(PackedVector3Array([a, b, c]))
		return
	# Local surface bounds let Mobile select nearby practical lights for each span.
	var center: Vector3 = (a + b + c) / 3.0
	var key: String = "%s:%d:%d:%d" % [material, floori(center.x / 12.0), floori(center.y / 10.0), floori(center.z / 12.0)]
	var data: PackedVector3Array = surfaces.get(key, PackedVector3Array())
	# Godot renders clockwise front faces; callers supply an outward cross product.
	data.append_array(PackedVector3Array([a, c, b]))
	surfaces[key] = data
	surface_materials[key] = material
	if solid:
		collision_faces.append_array(PackedVector3Array([a, b, c]))

func polygon_surface(polygon: PackedVector2Array, y: float, material: String, upward: bool = true) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for index: int in range(0, indices.size(), 3):
		var a: Vector2 = polygon[indices[index]]
		var b: Vector2 = polygon[indices[index + 1]]
		var c: Vector2 = polygon[indices[index + 2]]
		var va: Vector3 = Vector3(a.x, y, a.y)
		var vb: Vector3 = Vector3(b.x, y, b.y)
		var vc: Vector3 = Vector3(c.x, y, c.y)
		if ((vb - va).cross(vc - va).y > 0.0) != upward:
			face(va, vc, vb, material)
		else:
			face(va, vb, vc, material)

func in_room(point: Vector3, tolerance: float = 0.3) -> bool:
	for room: Dictionary in rooms:
		if absf(point.y - float(room["floor"])) <= tolerance and Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), room["points"] as PackedVector2Array):
			return true
	return false

func opening(point: Vector2, floor_y: float) -> bool:
	for path: Dictionary in paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
			var length: float = Vector2(b.x - a.x, b.z - a.z).length()
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(length, 0.001)
			if near.distance_to(point) < float(path["width"]) * 0.5 + 0.6 and absf(lerpf(a.y, b.y, t) - floor_y) < 1.0:
				return true
	return false

func junction(point: Vector3, own_path: String, own_segment: int) -> bool:
	# Side walls must stop at a joining passage, including skewed T intersections.
	for path: Dictionary in paths:
		var route: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(route.size() - 1):
			if String(path["id"]) == own_path and index == own_segment:
				continue
			var a: Vector3 = route[index]
			var b: Vector3 = route[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)
			if near.distance_to(Vector2(point.x, point.z)) < float(path["width"]) * 0.5 + 0.7 and absf(lerpf(a.y, b.y, t) - point.y) < 2.5:
				return true
	return false

## Vaulted passages built with the rooms (scripts/art/build_architecture.py):
## each covers a stretch of an enclosed route between two room walls, and its
## doorway arches are the ends of its own vault.
var stone_index_cache: Dictionary = {}

## The stone build's index.json (rooms, roof tops, passage files, coverage, nodes).
func stone_index() -> Dictionary:
	if stone_index_cache.is_empty() and FileAccess.file_exists(STONE_INDEX):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STONE_INDEX))
		if parsed is Dictionary:
			stone_index_cache = parsed as Dictionary
	return stone_index_cache

func load_stone_passages() -> void:
	if "--no-stone-rooms" in OS.get_cmdline_user_args():
		return
	var index: Dictionary = stone_index()
	if index.is_empty():
		return
	var hashes: Dictionary[String, String] = {}
	for path: Dictionary in paths:
		hashes[String(path["id"])] = DungeonStructure.layout_hash(path, route_edges(path))
	var stale: Dictionary[String, bool] = {}
	for entry: Variant in (index as Dictionary).get("files", []) as Array:
		var file: Dictionary = entry as Dictionary
		var current: bool = true
		for route: Variant in (file["routes"] as Dictionary).keys():
			if hashes.get(String(route), "") != String((file["routes"] as Dictionary)[route]):
				current = false
				stale[String(route)] = true
		if not current:
			push_warning("Stale stone passage %s; rerun scripts/art/build_architecture.py" % file["file"])
			continue
		var built: Node3D = (load("res://content/environments/procedural_architecture_v1/" + String(file["file"])) as PackedScene).instantiate() as Node3D
		built.name = "StonePassage_" + String(file["file"]).get_file().get_basename()
		stone_materials(built)
		add_child(built)
	for entry: Variant in (index as Dictionary).get("passages", []) as Array:
		var passage: Dictionary = entry as Dictionary
		if not stale.has(String(passage["route"])):
			stone_passages.append(passage)
			# Roots per stretch (scripts/art/build_roots.py passage_label).
			stone_roots(ROOTS + "passages/%s_%d_%d.glb" % [passage["route"], int(passage["segment"]), floori(float(passage["t0"]) * 1000.0 + 0.5)])
	for entry: Variant in (index as Dictionary).get("nodes", []) as Array:
		var node: Dictionary = entry as Dictionary
		var at: Array = node["at"] as Array
		stone_nodes.append(Vector4(float(at[0]), float(at[1]), float(at[2]), float(node["radius"])))

## True where a stone build already encloses this point of an enclosed route:
## inside a stone passage's stretch, a bay or portal, or a stone room (at
## any level it spans) and its doorways.
func stone_enclosed(path: Dictionary, segment: int, t: float, point: Vector3) -> bool:
	for passage: Dictionary in stone_passages:
		if String(passage["route"]) == String(path["id"]) and int(passage["segment"]) == segment and t > float(passage["t0"]) - 0.02 and t < float(passage["t1"]) + 0.02:
			return true
	return stone_node_near(point, 0.0) or stone_room_near(point, 1.6)

## Inside a stone-built room above its floor: a gallery or stair the build carries.
func stone_raised(point: Vector3) -> bool:
	if "--no-stone-rooms" in OS.get_cmdline_user_args():
		return false
	for room: Dictionary in rooms:
		if point.y < float(room["floor"]) + 0.25 or point.y > float(room["floor"]) + float(room["height"]):
			continue
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), room["points"] as PackedVector2Array) and ResourceLoader.exists(STONE_ROOMS + String(room["id"]) + ".glb"):
			return true
	return false

## Under a stone passage's own paving: one of its stretches or bays.
func stone_paved(path: Dictionary, segment: int, t: float, point: Vector3) -> bool:
	for passage: Dictionary in stone_passages:
		if String(passage["route"]) == String(path["id"]) and int(passage["segment"]) == segment and t > float(passage["t0"]) and t < float(passage["t1"]):
			return true
	return stone_node_near(point, -1.0)

func stone_node_near(point: Vector3, margin: float) -> bool:
	for node: Vector4 in stone_nodes:
		if Vector2(point.x - node.x, point.z - node.z).length() < node.w + margin and absf(point.y - node.y) < 3.0:
			return true
	return false

func stone_room_near(point: Vector3, margin: float) -> bool:
	if "--no-stone-rooms" in OS.get_cmdline_user_args():
		return false
	for room: Dictionary in rooms:
		if point.y < float(room["floor"]) - 0.6 or point.y > float(room["floor"]) + float(room["height"]) or not ResourceLoader.exists(STONE_ROOMS + String(room["id"]) + ".glb"):
			continue
		var outline: PackedVector2Array = room["points"] as PackedVector2Array
		var plan: Vector2 = Vector2(point.x, point.z)
		if Geometry2D.is_point_in_polygon(plan, outline):
			return true
		for index: int in range(outline.size()):
			if Geometry2D.get_closest_point_to_segment(plan, outline[index], outline[(index + 1) % outline.size()]).distance_to(plan) < margin:
				return true
	return false

## The team's best texture sets, where the dungeon still used stand-ins
## (T-185): red_nave_v1 red lime plaster, oxidized iron and broken floor slabs;
## bridge_well_v1 mineral plaster, bridge oak and damp shaft masonry. Each keeps
## its material's shader settings (the T-181 grade: damp, tint, masks).
func integrate_materials() -> void:
	var nave: String = "res://content/environments/red_nave_v1/"
	var well: String = "res://content/environments/bridge_well_v1/"
	swap_maps("red_plaster", nave + "red_lime_plaster/", 0.4)
	swap_maps("plaster", well + "mineral_plaster/", 0.4, "normal_dx.png")
	swap_maps("iron", nave + "oxidized_iron/", 2.0)
	swap_maps("wood", well + "bridge_oak/", 0.65)
	swap_maps("floor", nave + "broken_stone_floor/", 0.333)
	swap_maps("wall", well + "damp_masonry/", 0.4)
	# The plaster sets carry their own colour; the old red tint was for grey concrete.
	if materials.has("red_plaster"):
		(materials["red_plaster"] as ShaderMaterial).set_shader_parameter("tint", Vector3(0.95, 0.92, 0.9))
	# The well's mineral plaster is fresh cream; centuries of smoke and damp grey it down.
	if materials.has("plaster"):
		(materials["plaster"] as ShaderMaterial).set_shader_parameter("tint", Vector3(0.52, 0.5, 0.46))

func swap_maps(key: String, folder: String, scale: float, normal_file: String = "normal_gl.png") -> void:
	if not materials.has(key) or not ResourceLoader.exists(folder + "albedo.png") or not materials[key] is ShaderMaterial:
		return
	var swapped: ShaderMaterial = (materials[key] as ShaderMaterial).duplicate() as ShaderMaterial
	swapped.set_shader_parameter("albedo_map", load(folder + "albedo.png"))
	swapped.set_shader_parameter("aspect", 1.0)
	swapped.set_shader_parameter("normal_map", load(folder + normal_file))
	for map: String in ["roughness", "ao", "height", "metallic"]:
		if ResourceLoader.exists(folder + map + ".png"):
			swapped.set_shader_parameter(map + "_map", load(folder + map + ".png"))
	swapped.set_shader_parameter("scale", scale)
	materials[key] = swapped

## The T-171 dressing sets, at the places the stone build chose for them
## (index.json "props": backs to a wall, clear of doors, pilasters and walks).
func stone_props() -> void:
	if "--no-stone-rooms" in OS.get_cmdline_user_args():
		return
	for entry: Variant in stone_index().get("props", []) as Array:
		var spot: Dictionary = entry as Dictionary
		var file: String = PROP_SETS + String(spot["set"]) + ".glb"
		if not ResourceLoader.exists(file) or not ResourceLoader.exists(STONE_ROOMS + String(spot["room"]) + ".glb"):
			continue
		var at: Array = spot["at"] as Array
		var facing: Array = spot["facing"] as Array
		var forward: Vector3 = Vector3(float(facing[0]), 0.0, float(facing[1])).normalized()
		var dressing: Node3D = (load(file) as PackedScene).instantiate() as Node3D
		dressing.name = "Props_%s_%s" % [spot["room"], spot["set"]]
		# The set's front (+Z, where its route strip was reserved) faces into the room.
		dressing.transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), Vector3(float(at[0]), float(at[1]), float(at[2])))
		for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = prop_material(node.name)
		add_child(dressing)

## Adds a stone room's wall sconces: the nominal wall face at sconce height
## and the direction into the room. False when the index places none.
func stone_sconces(room: String) -> bool:
	var found: bool = false
	for entry: Variant in stone_index().get("lights", []) as Array:
		var spot: Dictionary = entry as Dictionary
		if String(spot["room"]) != room:
			continue
		var at: Array = spot["at"] as Array
		var facing: Array = spot["facing"] as Array
		sconces.append({"at": Vector3(float(at[0]), float(at[1]), float(at[2])), "facing": Vector3(float(facing[0]), 0.0, float(facing[1])).normalized()})
		found = true
	return found

func prop_material(part: String) -> Material:
	var kind: String = "wood"
	if part.begins_with("07") or part.begins_with("08"):
		kind = "bone"
	elif part.begins_with("09"):
		kind = "clay"
	elif part.begins_with("10"):
		kind = "iron"
	if kind == "wood":
		kind = "prop_wood"
		if not materials.has(kind):
			materials[kind] = materials["wood"]
			swap_maps("prop_wood", "res://content/environments/red_nave_v1/aged_oak/", 0.4)
		return materials[kind]
	if kind == "iron":
		return materials["iron"]
	if not materials.has(kind):
		var plain: StandardMaterial3D = StandardMaterial3D.new()
		plain.albedo_color = Color(0.58, 0.53, 0.43) if kind == "bone" else Color(0.33, 0.19, 0.12)
		plain.roughness = 0.72 if kind == "bone" else 0.88
		materials[kind] = plain
	return materials[kind]

## Broken stone, grit and a grime bed settled at the wall bases (T-179,
## scripts/art/build_room_rubble.py): the walls' own limestone, world-projected,
## and the floor's dirt for the grime so its edge melts into the paving.
func stone_rubble(room_id: String) -> void:
	var file: String = RUBBLE + room_id + ".glb"
	if not ResourceLoader.exists(file):
		return
	if not materials.has("rubble"):
		var loose: ShaderMaterial = (materials["built_stone"] as ShaderMaterial).duplicate() as ShaderMaterial
		loose.set_shader_parameter("mapped", false)
		materials["rubble"] = loose
	var fallen: Node3D = (load(file) as PackedScene).instantiate() as Node3D
	fallen.name = "Rubble_" + room_id
	for node: Node in fallen.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		visual.material_override = FlagstoneFloor.material("dirt") if visual.name.contains("grime") else materials["rubble"]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if visual.name.contains("grime") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(fallen)

## Roots grown over a stone build in Blender (T-178, scripts/art/build_roots.py):
## dark wet red, darkened by their baked contact occlusion; no collision.
func stone_roots(file: String) -> void:
	if not ResourceLoader.exists(file):
		return
	if not materials.has("roots"):
		var roots: StandardMaterial3D = StandardMaterial3D.new()
		roots.albedo_color = Color8(80, 11, 16)
		roots.vertex_color_use_as_albedo = true
		roots.roughness = 0.35
		roots.specular = 0.45
		materials["roots"] = roots
	var grown: Node3D = (load(file) as PackedScene).instantiate() as Node3D
	grown.name = "Roots_" + file.get_file().get_basename()
	for node: Node in grown.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = materials["roots"]
	add_child(grown)

## Face materials by stone kind: dressed ashlar, lacing slabs, quoins, rough
## crypt walling, floor flags and arch stones each get their own T-183 face
## (with its anti-tiling sampler); walling stone keeps the T-180 limestone.
const KIND_FACES: Dictionary[String, String] = {
	"ashlar": "01-chisel-limestone", "slab": "02-split-bedded-stone", "quoin": "03-drafted-quoin-stone",
	"galleted": "08-salt-weathered-limestone", "flag": "07-worn-floor-limestone", "arch": "09-fine-tooled-sandstone",
}
func stone_face(kind: String) -> Material:
	var key: String = "built_" + kind
	if materials.has(key):
		return materials[key]
	var preset: String = "res://content/environments/stone_brick_materials_v1/materials/%s/surface.tres" % KIND_FACES.get(kind, "")
	if not KIND_FACES.has(kind) or not ResourceLoader.exists(preset):
		materials[key] = materials["built_stone"]
		return materials[key]
	var face: ShaderMaterial = (load(preset) as ShaderMaterial).duplicate() as ShaderMaterial
	var rock: ShaderMaterial = materials["rock"] as ShaderMaterial
	# The dungeon's own grade: damp, peel and algae masks and the stone tint.
	for parameter: String in ["wetness", "tint", "algae", "peel_map", "algae_map", "wet_map", "dry_roughness_min", "wet_roughness"]:
		var value: Variant = rock.get_shader_parameter(parameter)
		if value != null:
			face.set_shader_parameter(parameter, value)
	face.set_shader_parameter("mapped", true)
	materials[key] = face
	return face

## The render over plastered stone rooms: the room's plaster, holed where it peels.
func stone_coat(family: String) -> Material:
	if not materials.has(family + "_coat"):
		var skin: ShaderMaterial = (materials[family] as ShaderMaterial).duplicate() as ShaderMaterial
		skin.set_shader_parameter("plaster", 1.0)
		skin.set_shader_parameter("coat", true)
		materials[family + "_coat"] = skin
	return materials[family + "_coat"]

func stone_materials(built: Node3D) -> void:
	if not materials.has("built_stone"):
		# Dressed limestone faces (T-180, no joints or veins of its own), read
		# through each stone's baked coordinates; damp, peel and algae stay the rock's.
		var mapped: ShaderMaterial = (materials["rock"] as ShaderMaterial).duplicate() as ShaderMaterial
		var albedo: Texture2D = load(STONE_FACE + "albedo.png") as Texture2D
		mapped.set_shader_parameter("albedo_map", albedo)
		mapped.set_shader_parameter("aspect", float(albedo.get_width()) / float(albedo.get_height()))
		for key: String in ["normal", "roughness", "ao", "height"]:
			mapped.set_shader_parameter(key + "_map", load(STONE_FACE + ("normal_gl" if key == "normal" else key) + ".png"))
		mapped.set_shader_parameter("scale", 0.555)
		mapped.set_shader_parameter("normal_strength", 0.75)
		mapped.set_shader_parameter("mapped", true)
		materials["built_stone"] = mapped
	for node: Node in built.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.name.begins_with("Stone"):
			# "Stone-<kind>_...": each stone kind wears its own face (T-182 shapes, T-183 faces).
			var kind: String = visual.name.get_slice("_", 0).trim_prefix("Stone-") if visual.name.begins_with("Stone-") else "stone"
			visual.material_override = stone_face(kind)
		elif visual.name.begins_with("Plaster"):
			visual.material_override = stone_coat("red_plaster" if visual.name.begins_with("Plaster_nave") else "plaster")
		else:
			visual.material_override = materials["plaster"]

## A room built stone by stone in Blender (scripts/art/build_architecture.py):
## its walls, honest openings and collision replace the boxes, niches,
## pilasters and arches build_room would otherwise make for it.
func stone_room(room: Dictionary) -> bool:
	var file: String = STONE_ROOMS + String(room["id"]) + ".glb"
	if not ResourceLoader.exists(file) or "--no-stone-rooms" in OS.get_cmdline_user_args():
		return false
	var built: Node3D = (load(file) as PackedScene).instantiate() as Node3D
	built.name = "StoneRoom_" + String(room["id"])
	stone_materials(built)
	add_child(built)
	stone_roots(ROOTS + String(room["id"]) + ".glb")
	stone_rubble(String(room["id"]))
	return true

func build_room(room: Dictionary) -> void:
	var polygon: PackedVector2Array = room["points"] as PackedVector2Array
	var y: float = float(room["floor"])
	var height: float = float(room["height"])
	var wall_material: String = "red_plaster" if String(room["id"]) == "nave" else "plaster"
	polygon_surface(polygon, y, "collision")
	var floor: Node3D = Node3D.new()
	floor.name = "Floor_" + String(room["id"])
	add_child(floor)
	floor.add_to_group("flagstone_room_floors")
	var family: String = "laid" if String(room["id"]) in ["entry", "ossuary", "bones", "window"] else "coursed"
	floor.set_meta("room_id", String(room["id"]))
	floor.set_meta("floor_y", y)
	floor.set_meta("family", family)
	floor.set_meta("module_count", FlagstoneFloor.cover(floor, polygon, y, family, 165))
	# Joint occlusion is baked; centimetre-high stones need not cast into every torch shadow map.
	for node: Node in floor.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	polygon_surface(polygon, y - 0.5, "stone", false)
	var stone_built: bool = stone_room(room)
	# A stone room's roof sits over its vault.
	var top: float = float((stone_index().get("tops", {}) as Dictionary).get(String(room["id"]), y + height)) if stone_built else y + height
	polygon_surface(polygon, top, "collision" if String(room["id"]) == "nave" else "stone", false)
	for index: int in range(polygon.size()):
		if stone_built:
			continue
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var delta: Vector2 = b - a
		var count: int = ceili(delta.length() / 1.5)
		var basis: Basis = Basis(Vector3.UP, -atan2(delta.y, delta.x))
		var recesses: Array[Vector2] = []
		var cuts: Array[float] = []
		for step: int in range(count + 1):
			cuts.append(delta.length() * float(step) / float(count))
		if delta.length() > 5.0:
			var positions: Array[float] = [0.5]
			if delta.length() > 8.0:
				positions.assign([0.35, 0.65])
			for t: float in positions:
				var center: Vector2 = a.lerp(b, t)
				var width: float = 1.1 if index % 3 == 0 else 1.65
				if not portal_levels(center, width * 0.5 + 0.3).is_empty():
					continue
				var interval: Vector2 = Vector2(delta.length() * t - width * 0.5, delta.length() * t + width * 0.5)
				recesses.append(interval)
				cuts.append(interval.x)
				cuts.append(interval.y)
		cuts.sort()
		var door_start: int = -1
		for step: int in range(cuts.size() - 1):
			var width: float = cuts[step + 1] - cuts[step]
			if width < 0.001:
				continue
			var distance: float = (cuts[step] + cuts[step + 1]) * 0.5
			var mid: Vector2 = a + delta.normalized() * distance
			var door_height: float = 6.4 if String(room["id"]) == "nave" and mid.x > 3.0 and mid.y < 29.0 else 4.2
			var door: bool = opening(mid, y)
			var spans: Array[Vector2] = [Vector2(y, y + height)]
			var voids: Array[Vector2] = []
			# Keep portal decisions on the original wall grid, independent of recess cuts.
			var grid_mid: Vector2 = a.lerp(b, (floorf(distance / delta.length() * float(count)) + 0.5) / float(count))
			for level: float in portal_levels(grid_mid, 0.1):
				voids.append(Vector2(level - 0.2, level + door_height))
			for recess: Vector2 in recesses:
				if distance > recess.x and distance < recess.y:
					voids.append(Vector2(y + 0.7, y + 3.8))
			for gap: Vector2 in voids:
				var next: Array[Vector2] = []
				for span: Vector2 in spans:
					if gap.y <= span.x or gap.x >= span.y:
						next.append(span)
					else:
						if gap.x > span.x:
							next.append(Vector2(span.x, gap.x))
						if gap.y < span.y:
							next.append(Vector2(gap.y, span.y))
				spans = next
			for span: Vector2 in spans:
				piece(Vector3(width + 0.002, span.y - span.x, 0.9), Vector3(mid.x, (span.x + span.y) * 0.5, mid.y), wall_material, basis, true)
			if door and door_start < 0:
				door_start = step
			if door_start >= 0 and (not door or step == cuts.size() - 2):
				var end: int = step if not door else step + 1
				var center: Vector2 = a + delta.normalized() * (cuts[door_start] + cuts[end]) * 0.5
				if String(room["id"]) == "nave" and center.x > 3.0 and center.y < 29.0:
					fort_gate(Vector3(center.x, y, center.y), delta.normalized())
				else:
					arch(Vector3(center.x, y, center.y), delta.normalized(), (cuts[end] - cuts[door_start]) * 0.5)
				door_start = -1
		# Tall worn pilasters give the side halls scale without a flat wall of tiny bricks.
		if delta.length() > 5.0:
			for t: float in [0.18, 0.82]:
				var at: Vector2 = a.lerp(b, t)
				if not opening(at, y):
					stacked_pier(Vector3(at.x, y, at.y) + basis.z * 0.55, basis, Vector3(0.95, height, 1.25), index + int(t * 10.0))
		for recess: Vector2 in recesses:
			var center: Vector2 = a + delta.normalized() * (recess.x + recess.y) * 0.5
			var niche: Vector3 = Vector3(center.x, y, center.y)
			var width: float = recess.y - recess.x
			# The back lies behind the 0.9 m wall face; jambs and sill expose its depth.
			piece(Vector3(width, 3.1, 0.08), niche - basis.z * 0.41 + Vector3.UP * 2.25, "dark", basis, true)
			piece(Vector3(width + 0.4, 0.18, 0.98), niche + Vector3.UP * 0.7, "stone", basis)
			for side: float in [-1.0, 1.0]:
				piece(Vector3(0.2, 1.95, 0.98), niche + basis.x * side * (width * 0.5 + 0.1) + Vector3.UP * 1.675, "stone", basis)
			arch_spandrel(niche, basis, width * 0.5, wall_material, 2.65, 3.8, 0.9)
	var centroid: Vector2 = Vector2.ZERO
	for point: Vector2 in polygon:
		centroid += point
	centroid /= float(polygon.size())
	# A stone room is lit by wall sconces (index.json lights) instead of posts.
	if not (stone_built and stone_sconces(String(room["id"]))):
		for index: int in [0, polygon.size() / 2]:
			var at: Vector2 = centroid.lerp(polygon[index], 0.78)
			torch_posts.append(Vector3(at.x, y, at.y))
	# A stone room has its own rubble (T-179) and a vault instead of a timber roof.
	if stone_built:
		if String(room["id"]) == "nave":
			structure.roof(room, true)
		return
	# Fallen chips remain beside the wall and clear of all route centers.
	for index: int in range(polygon.size()):
		var at: Vector2 = polygon[index].lerp(centroid, 0.12)
		if not opening(at, y):
			var rubble_basis: Basis = Basis(Vector3.UP, float(index) * 1.73)
			module("rubble", Vector3(at.x, y - 0.15, at.y), rubble_basis, Vector3.ONE * (0.55 + float(index % 3) * 0.15))
	if String(room["id"]) == "nave":
		structure.roof(room)

## Mitered half-width per node. Joined routes share the miter at their common
## node, so neighbouring ribbons meet on one line.
func route_edges(path: Dictionary) -> PackedVector3Array:
	var id: String = String(path["id"])
	if ribbon_edges.has(id):
		return ribbon_edges[id]
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var edges: PackedVector3Array = PackedVector3Array()
	for node: int in range(points.size()):
		var before: Vector3 = points[node] - points[maxi(0, node - 1)]
		var after: Vector3 = points[mini(points.size() - 1, node + 1)] - points[node]
		for neighbor: Dictionary in paths:
			if String(neighbor["id"]) == id:
				continue
			var other: PackedVector3Array = neighbor["points"] as PackedVector3Array
			if node == 0 and points[node].distance_to(other[-1]) < 0.02:
				before = other[-1] - other[-2]
			if node == points.size() - 1 and points[node].distance_to(other[0]) < 0.02:
				after = other[1] - other[0]
		before.y = 0.0
		after.y = 0.0
		if before.is_zero_approx():
			before = after
		if after.is_zero_approx():
			after = before
		var incoming: Vector3 = before.normalized()
		var outgoing: Vector3 = after.normalized()
		var tangent: Vector3 = (incoming + outgoing).normalized()
		var side: Vector3 = Vector3(-tangent.z, 0, tangent.x)
		edges.append(side * width * 0.5 / maxf(0.65, tangent.dot(incoming)))
	ribbon_edges[id] = edges
	return edges

func build_path(path: Dictionary, light_route: bool) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var material: String = "wood" if bool(path["wood"]) else "floor"
	var enclosed: bool = bool(path["enclosed"])
	var lining: String = "rock" if String(path["id"]) in ["root_tunnel", "cave_bypass"] else "stone"
	var edges: PackedVector3Array = route_edges(path)
	if not enclosed:
		structure.route(path, edges)
		open_guards(path, edges)
	var since_light: float = 15.0
	for index: int in range(points.size() - 1):
		var from: Vector3 = points[index]
		var to: Vector3 = points[index + 1]
		var direction: Vector3 = (to - from).normalized()
		var basis: Basis = Basis.looking_at(direction, Vector3.UP)
		var side: Vector3 = basis.x
		var sculpted_deck: bool = bool(path["wood"]) and not enclosed
		var steps: int = maxi(1, ceili(from.distance_to(to) / 1.4))
		for step: int in range(steps):
			var a: Vector3 = from.lerp(to, float(step) / float(steps))
			var b: Vector3 = from.lerp(to, float(step + 1) / float(steps))
			var at: Vector3 = (a + b) * 0.5
			var length: float = a.distance_to(b)
			var room_floor: bool = in_room(a) and in_room(b)
			# Raised walks inside stone rooms stand on baked masonry with stone treads:
			# keep only their walking collision.
			var stone_walk: bool = stone_raised(at) or (enclosed and stone_paved(path, index, (float(step) + 0.5) / float(steps), at))
			if not room_floor:
				# One shared ribbon across each turn: no horizontal landing lips on ramps.
				var edge_a: Vector3 = edges[index].lerp(edges[index + 1], float(step) / float(steps))
				var edge_b: Vector3 = edges[index].lerp(edges[index + 1], float(step + 1) / float(steps))
				ribbon_top(a - edge_a, a + edge_a, b - edge_b, "collision" if sculpted_deck or stone_walk else material)
				ribbon_top(a + edge_a, b + edge_b, b - edge_b, "collision" if sculpted_deck or stone_walk else material)
				if stone_walk:
					paving_bed(a - edge_a, a + edge_a, b - edge_b)
					paving_bed(a + edge_a, b + edge_b, b - edge_b)
				if not sculpted_deck and not stone_walk:
					face(a - edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, a + edge_a - Vector3.UP * 0.32, "stone")
					face(a + edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, b + edge_b - Vector3.UP * 0.32, "stone")
				# Close the walking ribbon's open sides; slopes and corners need real fascia.
				if not sculpted_deck and not stone_walk:
					quad(a - edge_a, a - edge_a - Vector3.UP * 0.32, b - edge_b - Vector3.UP * 0.32, b - edge_b, -side, "stone")
					quad(a + edge_a, b + edge_b, b + edge_b - Vector3.UP * 0.32, a + edge_a - Vector3.UP * 0.32, side, "stone")
				var segment_t: float = (float(step) + 0.5) / float(steps)
				if enclosed and not stone_enclosed(path, index, segment_t, at):
					var roof: float = 3.7 if String(path["id"]) in ["root_tunnel", "cave_bypass"] else 4.2
					for sign_value: float in [-1.0, 1.0]:
						var edge: Vector3 = at + side * sign_value * (width * 0.5 + 0.3)
						if not junction(edge, String(path["id"]), index):
							piece(Vector3(0.65, roof + absf(a.y - b.y), length + 0.12), edge + Vector3.UP * roof * 0.5, lining, Basis(Vector3.UP, atan2(-direction.x, -direction.z)), true)
					piece(Vector3(width + 1.0, 0.55, length + 0.1), at + Vector3.UP * (roof + 0.25), lining, basis, true)
					if lining == "rock" and step % 3 == 0:
						var wall_side: float = -1.0 if (step + index) % 2 == 0 else 1.0
						var rock_at: Vector3 = at + side * wall_side * (width * 0.5 + 0.65)
						if not junction(rock_at, String(path["id"]), index):
							fitted_module("rock_outcrop", rock_at - Vector3.UP * 0.2, Vector3(1.4, 3.9, 3.6), basis)
				since_light += length
				if light_route and since_light >= 13.0:
					# Clear of the parapet a stone walk carries along its edge.
					torch_posts.append(at + side * (width * 0.5 - (0.65 if stone_walk else 0.35)))
					since_light = 0.0

## Recessed mortar across the same mitred ribbon as the real paving. Visual
## only: the smooth walking collision above it remains authoritative.
func paving_bed(a: Vector3, b: Vector3, c: Vector3) -> void:
	var recess: Vector3 = Vector3.DOWN * 0.04
	if (b - a).cross(c - a).y < 0.0:
		face(a + recess, c + recess, b + recess, "mortar_bedding", false)
	else:
		face(a + recess, b + recess, c + recess, "mortar_bedding", false)

## Keep the original walking triangles; only trim flat route visuals at room thresholds.
func ribbon_top(a: Vector3, b: Vector3, c: Vector3, material: String) -> void:
	face(a, b, c, "collision")
	if material == "collision":
		return
	if not is_equal_approx(a.y, b.y) or not is_equal_approx(a.y, c.y):
		face(a, b, c, material, false)
		return
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])]
	for room: Dictionary in rooms:
		if not is_equal_approx(a.y, float(room["floor"])):
			continue
		var remaining: Array[PackedVector2Array] = []
		for polygon: PackedVector2Array in polygons:
			remaining.append_array(Geometry2D.clip_polygons(polygon, room["points"] as PackedVector2Array))
		polygons = remaining
	for polygon: PackedVector2Array in polygons:
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
		for index: int in range(0, indices.size(), 3):
			var va: Vector3 = Vector3(polygon[indices[index]].x, a.y, polygon[indices[index]].y)
			var vb: Vector3 = Vector3(polygon[indices[index + 1]].x, a.y, polygon[indices[index + 1]].y)
			var vc: Vector3 = Vector3(polygon[indices[index + 2]].x, a.y, polygon[indices[index + 2]].y)
			if (vb - va).cross(vc - va).y < 0.0:
				face(va, vc, vb, material, false)
			else:
				face(va, vb, vc, material, false)

## Invisible rail on an open crossing, from `from` to `to` along the guard line.
## It stays wherever stepping outward would leave every floor for the void.
func open_guard(from: Vector3, to: Vector3, outward: Vector3, own_path: String) -> void:
	# Rails inside the solid spine stay too: its windows open onto the void.
	var center: Vector3 = (from + to) * 0.5
	if from.distance_to(to) < 0.02 or in_room(center) or walkable_beyond(center + outward * 0.5, own_path):
		return
	var up: Vector3 = Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD
	piece(Vector3(0.12, 0.86, from.distance_to(to) + 0.12), center + Vector3.UP * 0.55, "collision", Basis.looking_at(to - from, up), true)

## Flat distance from `node` along the segment before (t) and after (u) it to
## where the two guard lines on this side cross. Negative t means the inner
## side of a bend; positive t means the outer side.
func guard_crossing(points: PackedVector3Array, node: int, sign_value: float, inset: float) -> Vector2:
	if node <= 0 or node >= points.size() - 1:
		return Vector2.ZERO
	var before: Vector2 = Vector2(points[node].x - points[node - 1].x, points[node].z - points[node - 1].z).normalized()
	var after: Vector2 = Vector2(points[node + 1].x - points[node].x, points[node + 1].z - points[node].z).normalized()
	var turn: float = before.cross(after)
	if absf(turn) < 0.0001:
		return Vector2.ZERO
	var offset: Vector2 = (Vector2(-after.y, after.x) - Vector2(-before.y, before.x)) * sign_value * inset
	return Vector2(clampf(offset.cross(after) / turn, -2.0, 2.0), clampf(offset.cross(before) / turn, -2.0, 2.0))

## Invisible rails along both sides of an open crossing. Each side runs as one
## line per segment, trimmed or extended to meet its neighbour exactly at a
## bend; ends get a cap where a wider joining passage narrows to the deck.
func open_guards(path: Dictionary, edges: PackedVector3Array) -> void:
	var points: PackedVector3Array = path["points"] as PackedVector3Array
	var width: float = float(path["width"])
	var id: String = String(path["id"])
	var inset: float = width * 0.5 - 0.08
	for index: int in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var along: Vector3 = (b - a).normalized()
		var flat_length: float = Vector2(along.x, along.z).length()
		var side: Vector3 = Basis.looking_at(along, Vector3.UP).x
		for sign_value: float in [-1.0, 1.0]:
			var start: float = guard_crossing(points, index, sign_value, inset).y
			var end: float = guard_crossing(points, index + 1, sign_value, inset).x
			var from: Vector3 = a + side * sign_value * inset + along * start / flat_length
			var to: Vector3 = b + side * sign_value * inset + along * end / flat_length
			var parts: int = maxi(1, ceili(from.distance_to(to) / 0.7))
			for part: int in range(parts):
				open_guard(from.lerp(to, float(part) / float(parts)), from.lerp(to, float(part + 1) / float(parts)), side * sign_value, id)
	for node: int in [0, points.size() - 1]:
		if in_room(points[node]):
			continue
		var joining: Dictionary = {}
		for other: Dictionary in paths:
			var route: PackedVector3Array = other["points"] as PackedVector3Array
			if String(other["id"]) != id and (route[0].distance_to(points[node]) < 0.02 or route[-1].distance_to(points[node]) < 0.02):
				joining = other
		if joining.is_empty():
			continue
		var joining_width: float = float(joining["width"])
		var joining_points: PackedVector3Array = joining["points"] as PackedVector3Array
		var last: bool = joining_points[-1].distance_to(points[node]) < 0.02
		var joining_node: int = joining_points.size() - 1 if last else 0
		var into: Vector3 = (joining_points[-1] - joining_points[-2]) if last else (joining_points[0] - joining_points[1])
		var reach: float = minf(3.0, into.length())
		into = into.normalized()
		var lateral: Vector3 = Vector3(-into.z, 0, into.x).normalized()
		var joining_edge: Vector3 = route_edges(joining)[joining_node]
		for sign_value: float in [-1.0, 1.0]:
			# Joining passages drop their own side walls near this node, so the
			# rail continues back along their floor edge from the shared miter.
			var start: Vector3 = points[node] + joining_edge * sign_value * (joining_width * 0.5 - 0.08) / (joining_width * 0.5)
			var outward: Vector3 = lateral * signf(lateral.dot(joining_edge * sign_value))
			for part: int in range(4):
				open_guard(start - into * reach * float(part) / 4.0, start - into * reach * float(part + 1) / 4.0, outward, String(joining["id"]))
		if joining_width <= width:
			continue
		# Both passages share this miter line; cap the stretch only the wider one covers.
		var miter: Vector3 = edges[node].normalized()
		var scale: float = edges[node].length() / (width * 0.5)
		var away: Vector3 = (points[1] - points[0]) if node == 0 else (points[node - 1] - points[node])
		away = Vector3(away.x, 0, away.z).normalized()
		for sign_value: float in [-1.0, 1.0]:
			var from: Vector3 = points[node] + miter * sign_value * (edges[node].length() - 0.08)
			var to: Vector3 = points[node] + miter * sign_value * (joining_width * 0.5 * scale + 0.3)
			open_guard(from, to, away, id)

## True when a point lies on another route's mitered walking ribbon or a room
## floor at about the same height, so a guard there would block a real junction.
func walkable_beyond(point: Vector3, own_path: String) -> bool:
	if in_room(point, 1.0):
		return true
	var at: Vector2 = Vector2(point.x, point.z)
	for path: Dictionary in paths:
		if String(path["id"]) == own_path:
			continue
		var route: PackedVector3Array = path["points"] as PackedVector3Array
		var edges: PackedVector3Array = route_edges(path)
		for index: int in range(route.size() - 1):
			var a: Vector3 = route[index]
			var b: Vector3 = route[index + 1]
			var strip: PackedVector2Array = PackedVector2Array()
			for corner: Vector3 in [a - edges[index], a + edges[index], b + edges[index + 1], b - edges[index + 1]]:
				strip.append(Vector2(corner.x, corner.z))
			if not Geometry2D.is_point_in_polygon(at, strip):
				continue
			var ab: Vector2 = Vector2(b.x - a.x, b.z - a.z)
			var t: float = clampf((at - Vector2(a.x, a.z)).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if absf(lerpf(a.y, b.y, t) - point.y) < 1.0:
				return true
	return false

func beam(from: Vector3, to: Vector3, width: float, material: String) -> void:
	if material == "wood":
		structure.timber(from, to, width, width)
		return
	var up: Vector3 = Vector3.FORWARD if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	if material == "iron" and is_equal_approx(width, 0.035):
		var count: int = maxi(1, roundi(from.distance_to(to) / 0.13))
		var basis: Basis = Basis.looking_at(to - from, up)
		for link: int in range(count):
			piece(Vector3(1, 1, 1.5), from.lerp(to, (float(link) + 0.5) / float(count)), "chain", basis * Basis(Vector3.BACK, float(link % 2) * PI * 0.5))
		return
	piece(Vector3(width, width, from.distance_to(to)), (from + to) * 0.5, material, Basis.looking_at(to - from, up))

func fort_gate(at: Vector3, tangent: Vector2) -> void:
	var source: MeshInstance3D = fort_source.find_child("*thin_gate_01*", true, false) as MeshInstance3D
	var gate: MeshInstance3D = source.duplicate() as MeshInstance3D
	var basis: Basis = Basis(Vector3(tangent.y, 0, -tangent.x), Vector3.UP, Vector3(tangent.x, 0, tangent.y))
	# Native mesh units are metres. Recenter the module around its clear opening.
	gate.transform = Transform3D(basis, at - basis * Vector3(1.2, 0.35, 3.7046))
	add_child(gate)
	for vertex: Vector3 in gate.mesh.get_faces():
		collision_faces.append(gate.transform * vertex)

func arch(at: Vector3, tangent: Vector2, radius: float) -> void:
	var basis: Basis = Basis(Vector3.UP, -atan2(tangent.y, tangent.x))
	# Jambs share the wall thickness. The inner edges retain the passage's full width.
	for side: float in [-1.0, 1.0]:
		piece(Vector3(0.34, 2.9, 1.04), at + basis.x * side * (radius + 0.17) + Vector3.UP * 1.45, "stone", basis)
	arch_spandrel(at, basis, radius, "stone", 2.9, 4.8)

func portal_levels(point: Vector2, radius: float) -> Array[float]:
	var result: Array[float] = []
	for path: Dictionary in paths:
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		for index: int in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
			if near.distance_to(point) > radius + float(path["width"]) * 0.5 + 0.35:
				continue
			var t: float = near.distance_to(Vector2(a.x, a.z)) / maxf(0.001, Vector2(b.x - a.x, b.z - a.z).length())
			var y: float = lerpf(a.y, b.y, t)
			var unique: bool = true
			for existing: float in result:
				if absf(existing - y) < 2.0:
					unique = false
			if unique:
				result.append(y)
	return result

func build_vault(polygon: PackedVector2Array, central: bool) -> void:
	for index: int in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var delta: Vector2 = b - a
		var tangent: Vector2 = delta.normalized()
		var normal: Vector2 = Vector2(tangent.y, -tangent.x) * (-1.0 if central else 1.0)
		var basis: Basis = Basis(Vector3.UP, -atan2(tangent.y, tangent.x))
		# Collision stays at the actual wall outline; blind reveals occupy the facing.
		var count: int = maxi(1, roundi(delta.length() / 4.8))
		var rooms_in_wall: Array[Dictionary] = room_cuts(a, b)
		for column: int in range(count):
			var center: Vector2 = a.lerp(b, (float(column) + 0.5) / float(count))
			var width: float = delta.length() / float(count)
			# Rooms standing in the outline: their own walls bound the shaft
			# there, so this wall stops at them over the room's height.
			var bands: Array[Vector2] = []
			var beside: Array[Array] = []
			var c0: float = float(column) / float(count)
			var c1: float = float(column + 1) / float(count)
			for cut: Dictionary in rooms_in_wall:
				if float(cut["t1"]) <= c0 or float(cut["t0"]) >= c1:
					continue
				bands.append(cut["band"] as Vector2)
				for part: Vector2 in [Vector2(c0, maxf(c0, float(cut["t0"]))), Vector2(minf(c1, float(cut["t1"])), c1)]:
					if (part.y - part.x) * delta.length() > 0.05:
						beside.append([part, cut["band"]])
			var doors: Array[float] = []
			if not central:
				for level: float in portal_levels(center, width * 0.5):
					if not bands.any(func(band: Vector2) -> bool: return level > band.x and level < band.y):
						doors.append(level)
			var gaps: Array[Vector2] = bands.duplicate()
			for floor_y: float in doors:
				gaps.append(Vector2(floor_y - 0.25, floor_y + 4.8))
			var spans: Array[Vector2] = cut_spans([Vector2(-48, 14)], gaps)
			var backing: float = 1.3 if central else 0.45
			for span: Vector2 in spans:
				piece(Vector3(width + 0.05, span.y - span.x, 0.8), Vector3(center.x + normal.x * backing, (span.x + span.y) * 0.5, center.y + normal.y * backing), "core_stone" if central else "dark", basis, true)
			for part: Array in beside:
				var range_t: Vector2 = part[0] as Vector2
				var band: Vector2 = part[1] as Vector2
				var middle: Vector2 = a.lerp(b, (range_t.x + range_t.y) * 0.5)
				var part_width: float = (range_t.y - range_t.x) * delta.length()
				# A route may still pass through the wall beside the room.
				var part_gaps: Array[Vector2] = []
				for level: float in ([] as Array[float]) if central else portal_levels(middle, part_width * 0.5):
					if level > band.x and level < band.y:
						part_gaps.append(Vector2(level - 0.25, level + 4.8))
						arch(Vector3(middle.x, level, middle.y), tangent, part_width * 0.48)
				for span: Vector2 in cut_spans([band], part_gaps):
					piece(Vector3(part_width, span.y - span.x, 0.8), Vector3(middle.x + normal.x * backing, (span.x + span.y) * 0.5, middle.y + normal.y * backing), "core_stone" if central else "dark", basis, true)
					piece(Vector3(part_width, span.y - span.x, 1.0), Vector3(middle.x + normal.x * (0.5 if central else 0.0), (span.x + span.y) * 0.5, middle.y + normal.y * (0.5 if central else 0.0)), "plaster" if central else "wall", basis)
			for door_y: float in doors:
				if not stone_node_near(Vector3(center.x, door_y, center.y), width * 0.5):
					arch(Vector3(center.x, door_y, center.y), tangent, width * 0.48)
			for row: int in range(10):
				var y: float = -46.0 + float(row) * 6.0
				var at: Vector3 = Vector3(center.x, y, center.y) + Vector3(normal.x, 0, normal.y) * (0.5 if central else 0.0)
				var doorway: bool = false
				for gap: Vector2 in gaps:
					if y < gap.y and y + 6.0 > gap.x:
						doorway = true
				var wall_material: String = "plaster" if central else "wall"
				if doorway:
					# A portal or a room removes only its own height, never the entire six-metre row.
					for span: Vector2 in cut_spans([Vector2(y, y + 6.0)], gaps):
						piece(Vector3(width + 0.04, span.y - span.x, 1.0), Vector3(at.x, (span.x + span.y) * 0.5, at.z), wall_material, basis)
					continue
				# Continuous wall mass. No blind arcades: an opening with nothing behind
				# it has no reason to exist.
				piece(Vector3(width + 0.004, 6.0, 1.0), at + Vector3.UP * 3.0, wall_material, basis)
				if not central and row in [3, 6] and posmod(index * 3 + column, 4) == 0 and posmod(index * 17 + column * 11 + row * 7, 23) <= 4:
					torch_posts.append(at - Vector3(normal.x, 0, normal.y) * 1.1 + Vector3.UP * 0.8)
	polygon_surface(polygon, 14, "stone", central)
	if central:
		polygon_surface(polygon, -48, "dark", false)

## Spans minus gaps (both as Vector2(from, to)).
static func cut_spans(spans: Array[Vector2], gaps: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = spans.duplicate()
	for gap: Vector2 in gaps:
		var next: Array[Vector2] = []
		for span: Vector2 in result:
			if gap.y <= span.x or gap.x >= span.y:
				next.append(span)
			else:
				if gap.x > span.x:
					next.append(Vector2(span.x, gap.x))
				if gap.y < span.y:
					next.append(Vector2(gap.y, span.y))
		result = next
	return result

## Rooms an outline wall a->b runs into: {t0, t1} along it and the room's
## height band. Rooms are cut into the rock at the shaft's edge; where one
## stands in the outline, its own walls are the shaft wall.
func room_cuts(a: Vector2, b: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var length: float = a.distance_to(b)
	for room: Dictionary in rooms:
		var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(room["points"] as PackedVector2Array, 0.45, Geometry2D.JOIN_MITER)
		if grown.is_empty():
			continue
		for inside: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), grown[0]):
			var t0: float = inside[0].distance_to(a) / length
			var t1: float = inside[inside.size() - 1].distance_to(a) / length
			result.append({"t0": minf(t0, t1), "t1": maxf(t0, t1), "band": Vector2(float(room["floor"]) - 0.6, float(room["floor"]) + float(room["height"]) + 0.6)})
	return result

func arch_spandrel(at: Vector3, basis: Basis, radius: float, material: String, spring: float = 2.9, top: float = 6.0, depth: float = 1.0) -> void:
	# The curved reveal and masonry above it form one wall, including the soffit.
	var rise: float = minf(radius * 0.65, top - spring - 0.28)
	for segment: int in range(12):
		var angle_a: float = PI * float(segment) / 12.0
		var angle_b: float = PI * float(segment + 1) / 12.0
		var a: Vector3 = Vector3(cos(angle_a) * radius, spring + sin(angle_a) * rise, 0)
		var b: Vector3 = Vector3(cos(angle_b) * radius, spring + sin(angle_b) * rise, 0)
		for side: float in [-1.0, 1.0]:
			var near_a: Vector3 = at + basis * (a + Vector3.BACK * depth * 0.5 * side)
			var near_b: Vector3 = at + basis * (b + Vector3.BACK * depth * 0.5 * side)
			var top_a: Vector3 = at + basis * Vector3(a.x, top, depth * 0.5 * side)
			var top_b: Vector3 = at + basis * Vector3(b.x, top, depth * 0.5 * side)
			quad(near_a, near_b, top_b, top_a, basis.z * side, material)
		quad(at + basis * (a + Vector3.FORWARD * depth * 0.5), at + basis * (b + Vector3.FORWARD * depth * 0.5), at + basis * (b + Vector3.BACK * depth * 0.5), at + basis * (a + Vector3.BACK * depth * 0.5), -basis.y, "stone")
		# Bonded voussoirs have real projecting faces, chamfers and narrow mortar joints.
		# Their triangles join the existing stone surface batches, not per-stone nodes.
		var edge: PackedVector3Array = PackedVector3Array()
		var inset: PackedVector3Array = PackedVector3Array()
		var gap: float = 0.012 / maxf(radius, 0.5)
		for corner: Vector2 in [Vector2(angle_a + gap, 0.0), Vector2(angle_b - gap, 0.0), Vector2(angle_b - gap, 0.28), Vector2(angle_a + gap, 0.28)]:
			edge.append(Vector3(cos(corner.x) * (radius + corner.y), spring + sin(corner.x) * (rise + corner.y), depth * 0.5 + 0.025))
			var angle: float = corner.x + (0.018 / maxf(radius, 0.5)) * (1.0 if corner.x < (angle_a + angle_b) * 0.5 else -1.0)
			var offset: float = 0.025 if corner.y < 0.1 else 0.255
			inset.append(Vector3(cos(angle) * (radius + offset), spring + sin(angle) * (rise + offset), depth * 0.5 + 0.09 + float(segment % 3) * 0.008))
		quad(at + basis * inset[0], at + basis * inset[1], at + basis * inset[2], at + basis * inset[3], basis.z, "stone")
		for corner: int in range(4):
			var next: int = (corner + 1) % 4
			var outward: Vector3 = ((edge[next] - edge[corner]).cross(Vector3.FORWARD)).normalized()
			quad(at + basis * edge[corner], at + basis * edge[next], at + basis * inset[next], at + basis * inset[corner], basis * (outward + Vector3.BACK).normalized(), "stone")
			quad(at + basis * (edge[corner] - Vector3.BACK * 0.05), at + basis * (edge[next] - Vector3.BACK * 0.05), at + basis * edge[next], at + basis * edge[corner], basis * outward, "stone")

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, material: String) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		face(a, b, c, material, false)
		face(a, c, d, material, false)
	else:
		face(a, c, b, material, false)
		face(a, d, c, material, false)

func flush() -> void:
	var worn_block: ArrayMesh = bevelled_block()
	var chain: TorusMesh = TorusMesh.new()
	chain.inner_radius = 0.045
	chain.outer_radius = 0.06
	chain.rings = 8
	chain.ring_segments = 4
	for key: String in batches:
		var generated: bool = batch_models.has(key)
		for level: int in range(3 if generated else 1):
			var multi: MultiMesh = MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = GeneratedDungeonKit.mesh(batch_models[key], level) if generated else (batch_meshes[key] if batch_meshes.has(key) else (chain if batch_materials[key] == "chain" else (worn_block if batch_materials[key] in ["trim", "wood"] else BoxMesh.new())))
			multi.instance_count = batches[key].size()
			for index: int in range(multi.instance_count):
				multi.set_instance_transform(index, batches[key][index] as Transform3D)
				multi.set_instance_color(index, batch_colors[key][index] as Color)
			var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
			visual.name = key.validate_node_name() + "_lod%d" % level
			visual.multimesh = multi
			visual.material_override = GeneratedDungeonKit.material(batch_models[key]) if generated else materials["iron" if batch_materials[key] == "chain" else batch_materials[key]]
			if generated:
				visual.visibility_range_begin = [0.0, 20.0, 50.0][level]
				visual.visibility_range_end = [20.0, 50.0, 140.0][level]
			add_child(visual)
	for key: String in surfaces:
		var material: String = surface_materials[key]
		var vertices: PackedVector3Array = surfaces[key]
		var normals: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		for index: int in range(0, vertices.size(), 3):
			var normal: Vector3 = -(vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).normalized()
			for corner: int in range(3):
				normals.append(normal)
				colors.append(Color.WHITE)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = materials[material]
		add_child(visual)
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(collision_faces)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

	batches.clear()
	batch_colors.clear()
	batch_materials.clear()
	batch_models.clear()
	batch_meshes.clear()
	surfaces.clear()
	surface_materials.clear()
	collision_faces.clear()

func bevelled_block() -> ArrayMesh:
	# Shared chamfered cube: a small silhouette break on masonry, boards and old posts.
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for axis: int in range(3):
		for sign_value: float in [-1.0, 1.0]:
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = sign_value
			var quad: PackedVector3Array = PackedVector3Array()
			for pair: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point: Vector3 = normal * 0.5
				point[(axis + 1) % 3] = pair.x * 0.48
				point[(axis + 2) % 3] = pair.y * 0.48
				quad.append(point)
			bevel_face(quad, normal, vertices, normals)
	for axis: int in range(3):
		for s: float in [-1.0, 1.0]:
			for t: float in [-1.0, 1.0]:
				var quad: PackedVector3Array = PackedVector3Array()
				for pair: Vector2 in [Vector2(0.5, -0.48), Vector2(0.48, -0.48), Vector2(0.48, 0.48), Vector2(0.5, 0.48)]:
					var point: Vector3 = Vector3.ZERO
					point[axis] = pair.x * s
					point[(axis + 1) % 3] = (0.98 - pair.x) * t
					point[(axis + 2) % 3] = pair.y
					quad.append(point)
				var normal: Vector3 = Vector3.ZERO
				normal[axis] = s
				normal[(axis + 1) % 3] = t
				bevel_face(quad, normal.normalized(), vertices, normals)
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				bevel_face(PackedVector3Array([Vector3(x * 0.5, y * 0.48, z * 0.48), Vector3(x * 0.48, y * 0.5, z * 0.48), Vector3(x * 0.48, y * 0.48, z * 0.5)]), Vector3(x, y, z).normalized(), vertices, normals)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func bevel_face(polygon: PackedVector3Array, normal: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	for index: int in range(1, polygon.size() - 1):
		var a: Vector3 = polygon[0]
		var b: Vector3 = polygon[index]
		var c: Vector3 = polygon[index + 1]
		vertices.append_array(PackedVector3Array([a, b, c] if (b - a).cross(c - a).dot(normal) < 0 else [a, c, b]))
		normals.append_array(PackedVector3Array([normal, normal, normal]))
