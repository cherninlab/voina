class_name CampMobs
extends MobSystem
## Long Grass encounters, in road order (LongGrass.site_*): each campfire clearing wakes its hooded
## cultists the first time a player comes within wake_distance of the fire, and each ambush midway
## between two fires raises its cultists from the grass around a small trampled space when a player
## reaches ambush_wake of its middle. One site is live at a time: its raider grid is centred on it,
## and cultists still standing at a site the players walked away from give up and vanish when the
## next one wakes. Sites never respawn. active (a site index), alive and cleared replicate for the
## HUD.

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
	var count: int = road().site_stations.size()
	woken.clear()
	woken.resize(count)
	woken.fill(false)
	done.clear()
	done.resize(count)
	done.fill(false)
	active = -1
	cleared = 0
	print("CAMP_ENCOUNTERS_READY: %d camps and %d ambushes along the road" % [road().camps.size(), road().ambush_stations.size()])

# Waking queries physics (the raider grid), so it runs in the physics step.
func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or not started:
		return
	var field: LongGrass = road()
	if field == null:
		return
	var positions: Array[Vector3] = player_positions()
	for index: int in range(field.site_stations.size()):
		if woken[index]:
			continue
		var anchor: Vector3 = field.site_anchors[index]
		var reach: float = field.settings.wake_distance if field.site_camp[index] else field.settings.ambush_wake
		for at: Vector3 in positions:
			if Vector2(at.x - anchor.x, at.z - anchor.z).length() < reach:
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
	var station: float = field.site_stations[index]
	var centre: Vector3 = field.point_at(station)
	var anchor: Vector3 = field.site_anchors[index]
	var camp: bool = field.site_camp[index]
	var grid: MobNavigation = raider_grids[Zone.VILLAGE]
	grid.build(get_world_3d().direct_space_state, actor_rids(), Vector2(centre.x, centre.z))
	var count: int = field.site_cultists[index]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = field.settings.road_seed * 31 + index
	for slot: int in range(count):
		var angle: float = TAU * float(slot) / float(count) + rng.randf_range(-0.3, 0.3)
		# Around the fire inside a camp; just inside the grass around an ambush's space.
		var radius: float = rng.randf_range(2.2, field.settings.camp_radius - 1.5) if camp else field.settings.ambush_radius + rng.randf_range(0.8, 2.5)
		var post: Vector3 = grid.stand_point(anchor + Vector3(cos(angle), 0.0, sin(angle)) * radius) + Vector3.UP * 0.05
		var toward: Vector2 = Vector2(anchor.x - post.x, anchor.z - post.z)
		camp_raiders.append(raider_spawner.spawn([next_raider_id, post, atan2(-toward.x, -toward.y), Zone.VILLAGE]) as RaiderMob)
		next_raider_id += 1
	alive = count
	print("CAMP_WOKE: %s %d, %d cultists" % ["camp" if camp else "ambush", index, count])

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
		print("CAMP_CLEARED: site %d (%d / %d)" % [active, cleared, done.size()])

func clear() -> void:
	super.clear()
	camp_raiders.clear()
	woken.clear()
	done.clear()
	active = -1
	alive = 0
	cleared = 0
