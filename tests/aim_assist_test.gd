extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var eye: Vector3 = Vector3(0, 1.6, 0)
	var ahead: Vector3 = Vector3(0, 0, -1)
	assert(AimAssist.hit_distance(eye, ahead, Vector3(0, 0.95, -10)) > 9.0, "A body straight ahead is under the crosshair")
	assert(AimAssist.hit_distance(eye, ahead, Vector3(0.7, 0.95, -10)) > 0.0, "The old 0.35 m sweep still grazes a capsule 0.7 m off the ray")
	assert(AimAssist.hit_distance(eye, ahead, Vector3(0.8, 0.95, -10)) < 0.0, "A capsule beyond sweep plus body radius is missed")
	assert(AimAssist.hit_distance(eye, ahead, Vector3(0, 0.95, 10)) < 0.0, "Bodies behind the camera are ignored")
	assert(AimAssist.hit_distance(eye, ahead, Vector3(0, 0.95, -AimAssist.RANGE - 2.0)) < 0.0, "Bodies past 40 m are ignored")
	var near_body: Node3D = Node3D.new()
	var far_body: Node3D = Node3D.new()
	var me: Node3D = Node3D.new()
	root.add_child(near_body)
	root.add_child(far_body)
	root.add_child(me)
	near_body.position = Vector3(0, 0.95, -5)
	far_body.position = Vector3(0, 0.95, -20)
	me.position = Vector3(0, 0.95, -1)
	var candidates: Array[Node3D] = [far_body, me, near_body]
	assert(AimAssist.nearest(eye, ahead, candidates, me) == near_body, "The nearest body wins and the owner is skipped")
	print("AIM_ASSIST_OK: crosshair targeting matches the old sweep envelope")
	quit()
