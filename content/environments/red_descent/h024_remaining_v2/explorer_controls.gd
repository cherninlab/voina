extends "res://tests/dungeon_explorer.gd"
## Run the crawler's unchanged detector controls without repeating its survey.

func run() -> void:
	rng.seed = 186
	report = {"capabilities":{}}
	world = load("res://gameplay/match_world.tscn").instantiate() as Node3D
	add_child(world)
	await frames(20)
	dungeon = world.get_node("CinderCrypt") as RedDescentDungeon
	mobs = world.get("mobs") as MobSystem
	for mob: Node in mobs.raiders.get_children():mob.set_physics_process(false)
	var players: Node3D = world.get("players") as Node3D
	for actor: Node in players.get_children():
		actor.set_physics_process(false)
		actor.set_process(false)
	space = get_world_3d().direct_space_state
	exclude = mobs.actor_rids()
	await enemy_scenarios()
	inventory()
	await visual_controls()
	print("EXPLORER_UNCHANGED_CONTROLS: ",JSON.stringify(checks))
	if detector_failures > 0 or checks.size() != 22:
		push_error("Crawler detector controls failed")
		get_tree().quit(1)
		return
	print("EXPLORER_UNCHANGED_CONTROLS_OK: 22/22; no new survey claimed")
	NetworkManager.stop("controls finished")
	world.queue_free()
	await frames(15)
	get_tree().quit(0)
