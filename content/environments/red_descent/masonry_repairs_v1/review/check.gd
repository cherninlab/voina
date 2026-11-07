extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var world: Node3D = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	var architecture: RedDescentGeometry = world.get_node("CinderCrypt/Architecture") as RedDescentGeometry
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var count: int = 0
	var matches: int = 0
	for id: String in ["first_stair_hall", "second_stair_hall"]:
		var room: Node3D = architecture.get_node("StoneRoom_" + id) as Node3D
		assert(room.get_meta("closed_backing",false),"Repaired backing did not load")
		var visual: MeshInstance3D = room.get_node("Mortar_" + id + "_4") as MeshInstance3D
		var bodies: Array[Node] = room.find_children("Collision_" + id + "_4*", "StaticBody3D", true, false)
		assert(bodies.size()==1,"Old vault collision duplicated")
		var shape: CollisionShape3D = bodies[0].get_child(0) as CollisionShape3D
		assert((shape.shape as ConcavePolygonShape3D).get_faces().size()==visual.mesh.get_faces().size())
		var faces: PackedVector3Array = visual.mesh.get_faces()
		for index: int in range(0,faces.size(),39):
			var a: Vector3 = visual.global_transform * faces[index]
			var b: Vector3 = visual.global_transform * faces[index+1]
			var c: Vector3 = visual.global_transform * faces[index+2]
			var centre: Vector3 = (a+b+c)/3.0
			var normal: Vector3 = (c-a).cross(b-a).normalized()
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(centre+normal*.025,centre-normal*.025,1))
			count += 1
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(centre)<.006:
				matches += 1
		var source: String = RedDescentGeometry.STONE_ROOMS + id + ".glb"
		var stale: Node3D = (load(source) as PackedScene).instantiate() as Node3D
		var data: Dictionary = architecture.rooms.filter(func(entry: Dictionary)->bool:return entry["id"]==id)[0].duplicate(true)
		data["height"] = float(data["height"])+.1
		architecture.repair_room_backing(stale,data,source)
		assert(not stale.has_meta("closed_backing"),"Stale room accepted")
		stale.free()
	for node: Node in architecture.find_children("Mortar*","MeshInstance3D",true,false):
		var material: StandardMaterial3D = (node as MeshInstance3D).material_override as StandardMaterial3D
		assert(material != null and material.resource_name == "SolidMortar" and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,"Wet/transparent material used for cement core")
	assert(count>150 and matches>count*.95,"Vault collision does not match shell")
	print("MASONRY_CHECK_OK: %d/%d new shell render/collision rays; single replacement bodies, opaque mortar, stale-room rejection"%[matches,count])
	world.queue_free()
	root.get_node("Audio").set_process(false)
	for frame: int in range(5):await process_frame
	quit()
