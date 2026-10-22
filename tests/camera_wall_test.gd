extends SceneTree
## Runs the actual player and spring arm beside side/back walls in both camera modes.

var failed: bool = false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		printerr("CAMERA_WALL_FAIL: " + message)

func run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var walls: Array[Vector4] = [Vector4(0.75, 2, 0, 0), Vector4(0, 2, 0.75, 1)]
	for point: Vector4 in walls:
		var body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.6, 6, 8) if point.w == 0 else Vector3(8, 6, 0.6)
		collision.shape = shape
		body.position = Vector3(point.x, point.y, point.z)
		body.add_child(collision)
		stage.add_child(body)
	var player: CharacterBody3D = load("res://gameplay/player/player_character.tscn").instantiate() as CharacterBody3D
	player.position = Vector3(0, 0.95, 0)
	stage.add_child(player)
	player.set_physics_process(false)
	var camera: Camera3D = player.get("camera") as Camera3D
	var pivot: Node3D = player.get("pivot") as Node3D
	var arm: SpringArm3D = player.get("arm") as SpringArm3D
	for third: bool in [true, false]:
		player.call("set_camera_mode", third)
		for yaw: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
			for pitch: float in [-0.55, 0.0, 0.55]:
				player.rotation.y = yaw
				pivot.rotation.x = pitch
				for frame: int in range(8):
					await physics_frame
				var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
				var sphere: SphereShape3D = SphereShape3D.new()
				sphere.radius = 0.12
				query.shape = sphere
				query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
				query.exclude = [player.get_rid()]
				check(stage.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Camera overlaps a wall: third=%s yaw=%.2f pitch=%.2f at %s" % [third, yaw, pitch, camera.global_position])
				if third and is_zero_approx(yaw):
					check(arm.position.x < 0.3, "Shoulder cast must pull its origin away from the side wall")
	stage.queue_free()
	await process_frame
	if not failed:
		print("CAMERA_WALL_OK: shoulder offset, rear cast, corners, pitches and first-person clearance")
	quit(1 if failed else 0)
