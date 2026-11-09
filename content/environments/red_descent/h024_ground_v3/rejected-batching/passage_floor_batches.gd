class_name PassageFloorBatches
extends RefCounted
## Give joined floor fragments one local light list across asset boundaries.

static func install(parent: Node3D) -> Dictionary:
	if "--original-floor-batches" in OS.get_cmdline_user_args():return {"batches":0,"triangles":0}
	var builders: Dictionary[String, SurfaceTool] = {}
	var materials: Dictionary[String, Material] = {}
	var triangles: int = 0
	var sources: Array[Node] = parent.find_children("Stone-*", "MeshInstance3D", true, false)
	for node: Node in sources:
		var visual: MeshInstance3D = node as MeshInstance3D
		var kind: String = String(visual.name).get_slice("_",0).trim_prefix("Stone-")
		if kind not in ["flag","caveflag","earth","water"] or not visual.is_visible_in_tree():continue
		var owner: Node = visual.get_parent()
		while owner != parent and not String(owner.name).begins_with("StonePassage_"):owner=owner.get_parent()
		if owner == parent:continue
		var transform: Transform3D = visual.transform
		var ancestor: Node3D = visual.get_parent() as Node3D
		while ancestor != parent:
			transform=ancestor.transform*transform
			ancestor=ancestor.get_parent() as Node3D
		var normal_basis: Basis = transform.basis.inverse().transposed()
		for surface: int in range(visual.mesh.get_surface_count()):
			var mesh: MeshDataTool = MeshDataTool.new()
			assert(mesh.create_from_surface(visual.mesh as ArrayMesh,surface) == OK)
			for face: int in range(mesh.get_face_count()):
				var centre: Vector3 = Vector3.ZERO
				for corner: int in range(3):centre += (transform*mesh.get_vertex(mesh.get_face_vertex(face,corner)))/3.0
				var row: int = floori(-centre.z/.7)
				var column: int = floori(centre.x/.9-float(posmod(row,2))*.5)
				var x: int = floori(float(column)/3.0)
				var z: int = floori(float(row+posmod(x,2))/4.0)
				var key: String = "%s_%d_%d_%d" % [kind,x,z,floori((centre.y+1)/3)]
				if not builders.has(key):
					builders[key]=SurfaceTool.new()
					builders[key].begin(Mesh.PRIMITIVE_TRIANGLES)
					materials[key]=visual.material_override
				var builder: SurfaceTool = builders[key]
				for corner: int in range(3):
					var index: int = mesh.get_face_vertex(face,corner)
					var tangent: Plane = mesh.get_vertex_tangent(index)
					builder.set_normal((normal_basis*mesh.get_vertex_normal(index)).normalized())
					builder.set_tangent(Plane((transform.basis*tangent.normal).normalized(),tangent.d))
					builder.set_color(mesh.get_vertex_color(index))
					builder.set_uv(mesh.get_vertex_uv(index))
					builder.set_uv2(mesh.get_vertex_uv2(index))
					builder.add_vertex(transform*mesh.get_vertex(index))
				triangles+=1
		visual.visible=false
		visual.queue_free()
	for key: String in builders:
		var part: MeshInstance3D = MeshInstance3D.new()
		part.name="Stone-"+key.get_slice("_",0)+"_shared_"+key.trim_prefix(key.get_slice("_",0)+"_")
		part.mesh=builders[key].commit()
		part.material_override=materials[key]
		part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(part)
	print("PASSAGE_FLOOR_BATCHES: ",builders.size()," local batches; ",triangles," unchanged triangles")
	return {"batches":builders.size(),"triangles":triangles}
