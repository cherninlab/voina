extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dungeon: RedDescentDungeon = RedDescentDungeon.new()
	root.add_child(dungeon)
	dungeon.set_process(false)
	var camera: Camera3D = Camera3D.new()
	dungeon.add_child(camera)
	for frame: int in range(4):await physics_frame
	var previous: Dictionary[int,float] = {}
	var maximum_change: float = 0.0
	for step: int in range(81):
		camera.position=Vector3(-11.52932+float(step)*.05,-16.78233,25.85301)
		dungeon.update_fire_lights(camera)
		var active: int = 0
		for light: OmniLight3D in dungeon.fires:
			if light.visible:active+=1
			if previous.has(light.get_instance_id()):maximum_change=maxf(maximum_change,absf(light.light_energy-previous[light.get_instance_id()]))
			previous[light.get_instance_id()]=light.light_energy
		assert(active>0 and active<=6,"Practical light budget exceeds renderer allowance")
	assert(maximum_change<.65,"Torch budget exchanges cause an abrupt energy jump")
	camera.position=Vector3(500,500,500)
	dungeon.update_fire_lights(camera)
	assert(dungeon.fires.all(func(light: OmniLight3D) -> bool: return not light.visible and is_zero_approx(light.light_energy)),"Distant practicals still enter the mesh light list")
	print("DUNGEON_LIGHT_BUDGET_OK: <=6 practicals, 81 camera positions, largest 5cm energy change ",maximum_change)
	quit(0)
