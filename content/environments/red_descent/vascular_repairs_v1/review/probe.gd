extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,900)
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await process_frame
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var views: Array[Array] = [
		[Vector3(-28.7,-16.9,34.2),Vector3(-28.7,-16.9,38.05),60.0,[Vector2(480,225),Vector2(1250,225)]],
		[Vector3(36.4,-3.65,-37.5),Vector3(36.4,-3.65,-41.55),55.0,[Vector2(115,520),Vector2(405,775)]]
	]
	for view: Array in views:
		camera.position = view[0]
		camera.look_at(view[1])
		camera.fov = view[2]
		camera.make_current()
		await process_frame
		for pixel: Vector2 in view[3]:
			var origin: Vector3 = camera.project_ray_origin(pixel)
			var direction: Vector3 = camera.project_ray_normal(pixel)
			var distance: float = INF
			var result: Dictionary = {}
			for node: Node in world.find_children("*", "MeshInstance3D", true, false):
				var mesh: MeshInstance3D = node as MeshInstance3D
				if not "/Roots_" in String(mesh.get_path()): continue
				var inverse: Transform3D = mesh.global_transform.affine_inverse()
				var local_origin: Vector3 = inverse * origin
				var local_direction: Vector3 = inverse.basis * direction
				if mesh.get_aabb().intersects_ray(local_origin,local_direction) == null: continue
				var faces: PackedVector3Array = mesh.mesh.get_faces()
				for i: int in range(0,faces.size(),3):
					var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
					if hit == null: continue
					var position: Vector3 = mesh.global_transform * (hit as Vector3)
					var span: float = origin.distance_to(position)
					if span < distance:
						distance = span
						result = {"mesh":str(mesh.get_path()),"position":str(position),"triangle":i/3}
			print("VASCULAR_PIXEL ",pixel," ",result)
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5): await process_frame
	quit()
