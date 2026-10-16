extends SceneTree

const MODELS: Dictionary[String, String] = {
	"Car 01/Car.obj": "Car 01/car_red.png", "Car 02/Car2.obj": "Car 02/car2.png", "Car 03/Car3.obj": "Car 03/car3.png",
	"Car 04/Car4.obj": "Car 04/car4.png", "Car 05/Car5.obj": "Car 05/car5.png", "Car 05/Car5_Police.obj": "Car 05/car5_police.png",
	"Car 05/Car5_Taxi.obj": "Car 05/car5_taxi.png", "Car 06/Car6.obj": "Car 06/car6.png", "Car 07/Car7.obj": "Car 07/car7.png",
	"Car 08/Car8.obj": "Car 08/Car8.png",
}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("CAR_FAIL: " + message)
		quit(1)

func run() -> void:
	# Exact-case texture names: macOS hides MTL case mismatches that break Linux CI.
	for model: String in MODELS:
		var folder: String = CarProp.ROOT + model.get_base_dir()
		var files: PackedStringArray = DirAccess.get_files_at(folder)
		for line: String in FileAccess.get_file_as_string(CarProp.ROOT + model.get_basename() + ".mtl").split("\n"):
			if line.strip_edges().begins_with("map_K"):
				var texture: String = line.strip_edges().get_slice(" ", 1)
				check(files.has(texture), "%s references %s with exact case" % [model, texture])
	var cover: CarProp = null
	for model: String in MODELS:
		var car: CarProp = CarProp.create(model, MODELS[model])
		check(car.mesh != null and car.texture != null, model + " imports with its texture")
		var size: Vector3 = car.size()
		check(size.z > 3.4 and size.z < 5.2 and size.y > 1.0 and size.y < 2.2, "%s is car-sized next to a 1.8 m player: %s" % [model, size])
		if cover == null:
			cover = car
		else:
			car.free()
	cover.position = Vector3(0, 0, -5)
	cover.rotation_degrees.y = 90
	root.add_child(cover)
	check(cover.get_child_count() == 2 and cover.get_child(1) is CollisionShape3D, "Car builds a visual and a collision hull")
	await physics_frame
	await physics_frame
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(0, 0.65, 0), Vector3(0, 0.65, -10))
	var result: Dictionary = cover.get_world_3d().direct_space_state.intersect_ray(query)
	check(result.get("collider") == cover, "A chest-height beam is stopped by a parked car")
	query = PhysicsRayQueryParameters3D.create(Vector3(0, 2.5, 0), Vector3(0, 2.5, -10))
	check(cover.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Shots above the roof pass")
	print("CAR_OK: %d models, textures, scale, collision hull, cover" % MODELS.size())
	quit()
