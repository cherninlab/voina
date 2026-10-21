extends MobSystem
## A finite encounter, using existing host-owned raiders, combat and spawn replication.

const POSTS: Array[Vector3] = [Vector3(-8, 0, 2), Vector3(8, 0, -2), Vector3(-5, 0, -5), Vector3(-4, 0, -16), Vector3(4, 0, -17)]
var remaining: int = POSTS.size()

func _ready() -> void:
	super._ready()
	villagers = false
	forest_raiders = false
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "DungeonSync"
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	config.add_property(^".:remaining")
	config.property_set_replication_mode(^".:remaining", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)

func start() -> void:
	if not multiplayer.is_server() or started:
		return
	started = true
	generation += 1
	remaining = POSTS.size()
	var token: int = generation
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not started or token != generation or not multiplayer.is_server():
		return
	var grid: MobNavigation = raider_grids[Zone.VILLAGE]
	grid.build(get_world_3d().direct_space_state, actor_rids(), Vector2.ZERO)
	for post: Vector3 in POSTS:
		spawn_raider(Zone.VILLAGE, grid.stand_point(post) + Vector3.UP * 0.05)
	print("DUNGEON_ENCOUNTER_READY: five cultists, no replacements")

func _process(_delta: float) -> void:
	if multiplayer.is_server() and started and next_raider_id > RAIDER_ID + POSTS.size():
		remaining = living_count(raiders)

func clear() -> void:
	super.clear()
	remaining = POSTS.size()
