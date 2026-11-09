extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	var before: Array[String] = []
	for half: int in range(2):
		var asset: Node3D = Node3D.new()
		asset.name="StonePassage_%d" % half
		parent.add_child(asset)
		var builder: SurfaceTool = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a: Vector3 = Vector3(float(half)*.45,-19,-.1)
		var b: Vector3 = a+Vector3(.45,0,0)
		var c: Vector3 = a+Vector3(0,0,-.5)
		var d: Vector3 = b+Vector3(0,0,-.5)
		for at: Vector3 in [a,b,c,b,d,c]:
			builder.set_normal(Vector3.UP)
			builder.set_tangent(Plane(Vector3.RIGHT,1))
			builder.set_color(Color(.8,.9,.7,1))
			builder.set_uv(Vector2(at.x,-at.z))
			builder.set_uv2(Vector2(.25,.1))
			builder.add_vertex(at)
			before.append(str([at,Vector3.UP,Color(.8,.9,.7,1),Vector2(at.x,-at.z),Vector2(.25,.1)]))
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name="Stone-flag_fragment"
		visual.mesh=builder.commit()
		asset.add_child(visual)
	before.clear()
	for asset: Node in parent.get_children():
		for node: Node in asset.get_children():
			var source: MeshDataTool = MeshDataTool.new()
			assert(source.create_from_surface((node as MeshInstance3D).mesh as ArrayMesh,0)==OK)
			for face: int in range(source.get_face_count()):
				for corner: int in range(3):before.append(sample(source,source.get_face_vertex(face,corner)))
	var result: Dictionary = PassageFloorBatches.install(parent)
	assert(int(result["triangles"])==4 and int(result["batches"])==1,"Joined stone fragments still have separate light lists")
	var after: Array[String] = []
	for node: Node in parent.get_children():
		if node is MeshInstance3D:
			var mesh: MeshDataTool = MeshDataTool.new()
			assert(mesh.create_from_surface((node as MeshInstance3D).mesh as ArrayMesh,0)==OK)
			for face: int in range(mesh.get_face_count()):
				for corner: int in range(3):
					var i: int = mesh.get_face_vertex(face,corner)
					after.append(sample(mesh,i))
	before.sort();after.sort()
	if before!=after:
		push_error("Floor batching changed geometry or surface attributes: "+str([before,after]))
		quit(1)
		return
	print("PASSAGE_FLOOR_BATCHES_OK: clipped halves share one light list; all triangle attributes preserved")
	quit(0)

func sample(mesh: MeshDataTool, index: int) -> String:
	# Compare serialized mesh attributes, allowing the renderer's normal packing.
	var color: Color = mesh.get_vertex_color(index)
	var tangent: Plane = mesh.get_vertex_tangent(index)
	return str([mesh.get_vertex(index).snapped(Vector3.ONE*.0001),mesh.get_vertex_normal(index).snapped(Vector3.ONE*.0001),color.to_rgba32(),mesh.get_vertex_uv(index).snapped(Vector2.ONE*.0001),mesh.get_vertex_uv2(index).snapped(Vector2.ONE*.0001),tangent.normal.snapped(Vector3.ONE*.0001),tangent.d])
