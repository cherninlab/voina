extends SceneTree
## Freeze the deterministic village and prepare UV2 for Godot's editor lightmapper.
## Run with --script (real renderer, no --headless or --editor).
## Open village_lit.scn and use Bake Lightmaps in the editor.

const OUTPUT: String = "res://content/environments/village_generated/village_lit.scn"
const DATA: String = "res://content/environments/village_generated/village_indirect.lmbake"

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint():
		printerr("Bake preparation requires the real renderer without --headless/--editor; dummy rendering loses MultiMesh data.")
		quit(1)
		return
	prepare.call_deferred()

func prepare() -> void:
	var village: Node3D = load("res://gameplay/environment/village_arena.gd").new() as Node3D
	root.add_child(village)
	var trees: Node = village.get_node("TreePack")
	var cache: Dictionary[Mesh, ArrayMesh] = {}
	var count: int = 0
	for node: Node in village.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not node is MeshInstance3D or trees.is_ancestor_of(node) or not geometry.is_visible_in_tree():
			continue
		var visual: MeshInstance3D = node as MeshInstance3D
		var bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		if bounds.size.x > 60.0 or bounds.size.z > 60.0 or absf(bounds.get_center().x) > 34.0 or absf(bounds.get_center().z) > 34.0:
			continue
		var original: Mesh = visual.mesh
		if not cache.has(original):
			var unwrapped: ArrayMesh = ArrayMesh.new()
			for surface: int in range(original.get_surface_count()):
				unwrapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original.surface_get_arrays(surface))
				unwrapped.surface_set_material(surface, original.surface_get_material(surface))
			var result: Error = unwrapped.lightmap_unwrap(visual.global_transform, 0.3)
			assert(result == OK, "UV2 unwrap failed: " + str(visual.get_path()))
			cache[original] = unwrapped
		visual.mesh = cache[original]
		geometry.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		count += 1
	for node: Node in village.find_children("*", "Light3D", true, false):
		(node as Light3D).light_bake_mode = Light3D.BAKE_DYNAMIC
	var lightmap: LightmapGI = LightmapGI.new()
	lightmap.name = "VillageLightmap"
	lightmap.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lightmap.bounces = 3
	lightmap.directional = true
	lightmap.max_texture_size = 2048
	lightmap.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	lightmap.light_data = LightmapGIData.new()
	assert(ResourceSaver.save(lightmap.light_data, DATA) == OK, "Cannot save lightmap data")
	village.add_child(lightmap)
	# Explicit samples make missing automatic probes diagnosable in the next bake.
	for x: float in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		for z: float in [-24.0, -12.0, 0.0, 12.0, 24.0]:
			for height: float in [1.2, 4.0]:
				var probe: LightmapProbe = LightmapProbe.new()
				probe.position = Vector3(x, height, z)
				village.add_child(probe)
	var nodes: Array[Node] = village.find_children("*", "", true, false)
	for index: int in range(nodes.size()):
		var node: Node = nodes[index]
		node.owner = village
		if node != lightmap:
			node.name = "Part_%04d" % index
		node.scene_file_path = ""
		node.set_script(null)
	village.set_script(null)
	var scene: PackedScene = PackedScene.new()
	assert(scene.pack(village) == OK, "Cannot pack prepared village")
	assert(ResourceSaver.save(scene, OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK, "Cannot save prepared village")
	print("VILLAGE_BAKE_PREPARED: ", count, " meshes, ", cache.size(), " unique meshes; ", OUTPUT)
	quit()
