extends SceneTree

func _initialize() -> void:
	# Every event layer must resolve to catalog clips; a renamed family would otherwise go silent.
	for event: StringName in GameAudio.EVENTS:
		for layer: Dictionary in GameAudio.EVENTS[event]:
			for family: StringName in layer["families"] as Array:
				assert(not GameAudio.CATALOG.variants(family).is_empty(), "%s: missing family %s" % [event, family])
			for id: StringName in layer.get("clips", []) as Array:
				assert(GameAudio.CATALOG.find_clip(id) != null, "%s: missing clip %s" % [event, id])
	for id: StringName in GameAudio.AMBIENCE:
		assert(GameAudio.CATALOG.find_clip(id) != null)

	# Headless keeps the autoload disabled, so gameplay calls are silent no-ops.
	var autoload: GameAudio = root.get_node_or_null(^"Audio") as GameAudio
	assert(autoload == null or not autoload.enabled)
	assert(GameAudio.instance() == null)
	GameAudio.play(&"swing", Vector3.ZERO)

	await process_frame
	var audio: GameAudio = GameAudio.new()
	audio.name = "TestAudio"
	root.add_child(audio)
	audio.setup()
	assert(audio.pool.size() == GameAudio.POOL_SIZE)
	assert(audio.play_event(&"hit", Vector3(1, 1, 1)) == 1)
	assert(audio.play_event(&"parry", Vector3.ZERO) == 2)
	assert(audio.play_event(&"mob_bisect", Vector3.ZERO) == 3)
	var footstep_bus: StringName = audio.lowpass_bus(1600.0)
	assert(audio.lowpass_bus(1600.0) == footstep_bus and AudioServer.get_bus_index(footstep_bus) >= 0)
	assert(AudioServer.get_bus_effect(AudioServer.get_bus_index(footstep_bus), 0) is AudioEffectLowPassFilter)
	assert(audio.play_event(&"unknown", Vector3.ZERO) == 0)
	assert(audio.play_event(&"swing", Vector3(INF, 0, 0)) == 0)

	# No immediate repeats inside a family pool.
	var previous: StringName = &""
	for index: int in range(40):
		var clip: GameSoundClip = audio.pick([&"heavy_swing_thud"])
		assert(clip.id != previous)
		previous = clip.id
	# Cloth layer draws from both families.
	var families: Dictionary[StringName, bool] = {}
	for index: int in range(60):
		families[audio.pick([&"cloth_24", &"cloth_29"]).family] = true
	assert(families.size() == 2)

	# Footsteps only use the two click-free takes; punches start at their first impact.
	var footstep: Dictionary = (GameAudio.EVENTS[&"footstep"] as Array)[0]
	for index: int in range(20):
		var step: GameSoundClip = audio.pick(footstep["families"] as Array, footstep["clips"] as Array)
		assert(step.id in [&"footstep_grass_flipflop_06", &"footstep_grass_flipflop_07"])
	for punch: GameSoundClip in GameAudio.CATALOG.variants(&"body_punch"):
		var offset: float = audio.start_offset(punch, "impact")
		assert(offset > 0.05 and offset < punch.energy_peak_seconds())

	# A full pool reuses voices instead of growing.
	for index: int in range(GameAudio.POOL_SIZE * 2):
		audio.play_event(&"footstep", Vector3.ZERO)
	assert(audio.get_children().filter(func(node: Node) -> bool: return node is AudioStreamPlayer3D).size() == GameAudio.POOL_SIZE)
	print("GAME_AUDIO_OK: %d events resolve to catalog clips, pool of %d voices, %d ambience beds" % [GameAudio.EVENTS.size(), GameAudio.POOL_SIZE, GameAudio.AMBIENCE.size()])
	for node: Node in audio.get_children():
		node.call("stop")
	audio.queue_free()
	await process_frame
	await process_frame
	quit()
