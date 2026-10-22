class_name CampMobs
extends MobSystem
## Long Grass encounters: each campfire clearing (LongGrass.fires) wakes its hooded cultists the
## first time a player comes within wake_distance. One camp is live at a time: its raider grid is
## centred on the clearing, and cultists still standing at a camp the players walked away from give
## up and vanish when the next one wakes. Camps never respawn. active, alive and cleared replicate
## for the HUD.

const LIMIT: int = 16 # spawned cultists alive or still falling, across the live and the last camp
var woken: Array[bool] = [] # host only, by camp
var done: Array[bool] = [] # host only, by camp
var camp_raiders: Array[RaiderMob] = [] # host only: the live camp's cultists
var active: int = -1
var alive: int = 0
var cleared: int = 0

func _ready() -> void:
	super._ready()
	villagers = false
	village_raiders = false
	forest_raiders = false
	raider_spawner.spawn_limit = LIMIT
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "CampSync"
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [^".:active", ^".:alive", ^".:cleared"]:
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)

func road() -> LongGrass:
	return get_parent().get_node_or_null(^"LongGrass") as LongGrass

func start() -> void:
	if not multiplayer.is_server() or started or road() == null:
		return
	started = true
	generation += 1
	var count: int = road().fires.size()
	woken.clear()
	woken.resize(count)
	woken.fill(false)
	done.clear()
	done.resize(count)
	done.fill(false)
	active = -1
	cleared = 0
	print("CAMP_ENCOUNTERS_READY: %d camps along the road" % count)

# Waking queries physics (the raider grid), so it runs in the physics step.
func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or not started:
		return
	var field: LongGrass = road()
	if field == null:
		return
	var positions: Array[Vector3] = player_positions()
	for index: int in range(field.fires.size()):
		if woken[index]:
			continue
		for at: Vector3 in positions:
			if Vector2(at.x - field.fires[index].x, at.z - field.fires[index].z).length() < field.settings.wake_distance:
				wake(index)
				return

func wake(index: int) -> void:
	var field: LongGrass = road()
	woken[index] = true
	for raider: RaiderMob in camp_raiders:
		if is_instance_valid(raider) and raider.combat.health > 0:
			raider.queue_free()
	camp_raiders.clear()
	active = index
	var centre: Vector3 = field.camps[index]
	var fire: Vector3 = field.fires[index]
	var grid: MobNavigation = raider_grids[Zone.VILLAGE]
	grid.build(get_world_3d().direct_space_state, actor_rids(), Vector2(centre.x, centre.z))
	var count: int = field.camp_cultists[index]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = field.settings.road_seed * 31 + index
	for slot: int in range(count):
		var angle: float = TAU * float(slot) / float(count) + rng.randf_range(-0.3, 0.3)
		var radius: float = rng.randf_range(2.2, field.settings.camp_radius - 1.5)
		var post: Vector3 = grid.stand_point(fire + Vector3(cos(angle), 0.0, sin(angle)) * radius) + Vector3.UP * 0.05
		var toward: Vector2 = Vector2(fire.x - post.x, fire.z - post.z)
		camp_raiders.append(raider_spawner.spawn([next_raider_id, post, atan2(-toward.x, -toward.y), Zone.VILLAGE]) as RaiderMob)
		next_raider_id += 1
	alive = count
	print("CAMP_WOKE: camp %d, %d cultists" % [index, count])

func _process(_delta: float) -> void:
	if not multiplayer.is_server() or not started or active < 0:
		return
	var standing: int = 0
	for raider: RaiderMob in camp_raiders:
		if is_instance_valid(raider) and raider.combat.health > 0:
			standing += 1
	alive = standing
	if standing == 0 and not done[active]:
		done[active] = true
		cleared += 1
		print("CAMP_CLEARED: camp %d (%d / %d)" % [active, cleared, done.size()])

func clear() -> void:
	super.clear()
	camp_raiders.clear()
	woken.clear()
	done.clear()
	active = -1
	alive = 0
	cleared = 0
