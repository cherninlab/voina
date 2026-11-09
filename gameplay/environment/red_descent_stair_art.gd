class_name RedDescentStairArt
extends RefCounted
## Sparse wall-attached ritual art and local surface treatment; no collision or lights.

const ROOT: String = "res://content/environments/red_descent/stair_art_v1/"

static func install(architecture: RedDescentGeometry) -> void:
	if architecture.has_node("StairRitualArt"):
		return
	if not ResourceLoader.exists(ROOT + "ritual_wall_art.glb"):
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "build.json")) as Dictionary
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		var room: Node3D = architecture.get_node_or_null("StoneRoom_" + id) as Node3D
		if room == null or not room.get_meta("fitted_stairs", false):
			return
		if FileAccess.get_sha256(RedDescentGeometry.MASONRY_REPAIRS + "stairs/" + id + ".glb") != String((manifest["stairs_sha256"] as Dictionary)[id]):
			push_warning("Stair art source changed: " + id)
			return
	var lights: Array = (JSON.parse_string(FileAccess.get_file_as_string(RedDescentGeometry.STONE_INDEX)) as Dictionary)["lights"] as Array
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		var room: Node3D = architecture.get_node("StoneRoom_" + id) as Node3D
		var soot: PackedVector3Array = PackedVector3Array()
		for spot: Dictionary in lights:
			if String(spot["room"]) == id:
				var at: Array = spot["at"] as Array
				soot.append(Vector3(float(at[0]), float(at[1]), float(at[2])))
		var cache: Dictionary[String, ShaderMaterial] = {}
		for node: Node in room.find_children("Stone*", "MeshInstance3D", true, false):
			var visual: MeshInstance3D = node as MeshInstance3D
			var source: ShaderMaterial = visual.material_override as ShaderMaterial
			if source == null:
				continue
			var role: int = 2 if room.get_node("FittedStairMasonry").is_ancestor_of(visual) else 1
			var key: String = str(source.get_instance_id()) + ":" + str(role)
			if not cache.has(key):
				var surface: ShaderMaterial = source.duplicate() as ShaderMaterial
				surface.set_shader_parameter("stair_art_role", role)
				surface.set_shader_parameter("stair_soot_count", soot.size())
				var band: Dictionary = (manifest["seal_bands"] as Dictionary)[id] as Dictionary
				var anchor: Array = band["at"] as Array
				var facing: Array = band["normal"] as Array
				surface.set_shader_parameter("stair_seal_anchor", Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2])))
				surface.set_shader_parameter("stair_seal_normal", Vector3(float(facing[0]), float(facing[1]), float(facing[2])))
				surface.set_shader_parameter("stair_seal_length", float(band["length_m"]))
				var spots: PackedVector3Array = soot.duplicate()
				spots.resize(4)
				surface.set_shader_parameter("stair_soot", spots)
				surface.set_shader_parameter("wetness", 0.12)
				cache[key] = surface
			visual.material_override = cache[key]
		var floor: Node3D = architecture.get_node("Floor_" + id) as Node3D
		cache.clear()
		for node: Node in floor.find_children("*", "MeshInstance3D", true, false):
			var visual: MeshInstance3D = node as MeshInstance3D
			if not visual.name.begins_with("stones"):
				continue
			var source: ShaderMaterial = visual.material_override as ShaderMaterial
			var border: bool = visual.mesh.resource_path.contains("/flagstone_border_")
			var key: String = str(source.get_instance_id()) + ":" + str(border)
			if not cache.has(key):
				var surface: ShaderMaterial = source.duplicate() as ShaderMaterial
				for map: String in ["albedo", "normal", "roughness"]:
					surface.set_shader_parameter(map + "_map", load(RedDescentGeometry.STONE_FACE + ("normal_gl" if map == "normal" else map) + ".png"))
				var tint: Vector3 = Vector3(0.39, 0.44, 0.46) if border else Vector3(0.80, 0.84, 0.86)
				if id == "second_stair_hall":
					tint *= Vector3(0.92, 0.97, 1.0)
				surface.set_shader_parameter("tint", tint)
				surface.set_shader_parameter("normal_strength", 0.22)
				surface.set_shader_parameter("roughness_min", 0.88)
				surface.set_shader_parameter("wear_light", 0.18)
				cache[key] = surface
			visual.material_override = cache[key]
	var art: Node3D = (load(ROOT + "ritual_wall_art.glb") as PackedScene).instantiate() as Node3D
	art.name = "StairRitualArt"
	var stone: ShaderMaterial = (architecture.stone_face("arch") as ShaderMaterial).duplicate() as ShaderMaterial
	stone.set_shader_parameter("mapped", false)
	stone.set_shader_parameter("tint", Vector3(1.12, 1.10, 1.0))
	stone.set_shader_parameter("normal_strength", 0.16)
	stone.set_shader_parameter("wetness", 0.0)
	var pale: ShaderMaterial = stone.duplicate() as ShaderMaterial
	pale.set_shader_parameter("tint", Vector3(1.6, 1.6, 1.45))
	var iron: StandardMaterial3D = StandardMaterial3D.new()
	iron.albedo_color = Color(0.85, 0.90, 0.94)
	iron.albedo_texture = load("res://content/environments/red_nave_v1/oxidized_iron/albedo.png") as Texture2D
	iron.roughness = 0.78
	iron.metallic = 0.65
	iron.vertex_color_use_as_albedo = true
	var bronze: StandardMaterial3D = iron.duplicate() as StandardMaterial3D
	bronze.albedo_texture = null
	bronze.albedo_color = Color(0.35, 0.28, 0.18)
	bronze.metallic = 0.58
	var tissue: StandardMaterial3D = StandardMaterial3D.new()
	tissue.albedo_color = Color(0.58, 0.024, 0.045)
	tissue.albedo_texture = load(RedDescentGeometry.KREA_MATERIALS + "roots/albedo.png") as Texture2D
	tissue.normal_enabled = true
	tissue.normal_texture = load(RedDescentGeometry.KREA_MATERIALS + "roots/normal_gl.png") as Texture2D
	tissue.normal_scale = 0.18
	tissue.roughness = 0.58
	tissue.metallic_specular = 0.22
	for node: Node in art.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		visual.material_override = pale if visual.name.begins_with("StoneRim") else stone if visual.name.begins_with("Stone") else bronze if visual.name.begins_with("Bronze") else tissue if visual.name.begins_with("Tissue") else iron
	architecture.add_child(art)
	if ResourceLoader.exists(ROOT + "parapet_coping.glb") and FileAccess.file_exists(ROOT + "coping.json"):
		var coping_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "coping.json")) as Dictionary
		var sources: Dictionary = coping_report["source_stairs_sha256"] as Dictionary
		var current: bool = true
		for hall: String in ["first_stair_hall", "second_stair_hall"]:
			current = current and FileAccess.get_sha256(RedDescentGeometry.MASONRY_REPAIRS + "stairs/" + hall + ".glb") == String(sources[hall])
		if current:
			var coping: Node3D = (load(ROOT + "parapet_coping.glb") as PackedScene).instantiate() as Node3D
			coping.name = "StairParapetCoping"
			for node: Node in coping.find_children("*", "MeshInstance3D", true, false):
				(node as MeshInstance3D).material_override = architecture.stone_face("ashlar")
			architecture.add_child(coping)
