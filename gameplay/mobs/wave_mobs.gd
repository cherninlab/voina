class_name WaveMobs
extends MobSystem
## The white room's endless encounter: classic (unhooded) raiders keep arriving from the far corners,
## up to MAX_ALIVE at once, one every SPAWN_INTERVAL. They hold the middle of the room, from where
## every corner is in sight. Host-owned like every raider; alive and felled replicate for the HUD.

const GATES: Array[Vector3] = [Vector3(-8, 0, -12), Vector3(8, 0, -12), Vector3(-8.5, 0, 0), Vector3(8.5, 0, 0)]
const OPENING: int = 3
const MAX_ALIVE: int = 6
const SPAWN_INTERVAL: float = 4.0
var gates: Array[Vector3] = [] # host only: the gates on the sampled floor
var spawn_left: float = SPAWN_INTERVAL
var alive: int = 0
var felled: int = 0

func _ready() -> void:
	super._ready()
	villagers = false
	village_raiders = false
	forest_raiders = false
	raider_spawner.spawn_limit = MAX_ALIVE
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "WaveSync"
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [^".:alive", ^".:felled"]:
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)

# The forest zone gives the classic raider look; its grid is centred on the room instead.
func create_raider(data: Variant) -> Node:
	var mob: RaiderMob = super.create_raider(data) as RaiderMob
	mob.home = Vector3(0, mob.position.y, 0)
	return mob

func start() -> void:
	if not multiplayer.is_server() or started:
		return
	started = true
	generation += 1
	var token: int = generation
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not started or token != generation or not multiplayer.is_server():
		return
	var grid: MobNavigation = raider_grids[Zone.FOREST]
	grid.build(get_world_3d().direct_space_state, actor_rids(), Vector2.ZERO)
	gates.clear()
	for gate: Vector3 in GATES:
		gates.append(grid.stand_point(gate) + Vector3.UP * 0.05)
	spawn_left = SPAWN_INTERVAL
	for index: int in range(OPENING):
		spawn_at(gates[index])
	print("WAVE_ENCOUNTER_READY: raiders keep coming, up to %d at once" % MAX_ALIVE)

func spawn_at(point: Vector3) -> void:
	raider_spawner.spawn([next_raider_id, point, atan2(point.x, point.z), Zone.FOREST])
	next_raider_id += 1

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not started or gates.is_empty():
		return
	alive = living_count(raiders)
	felled = next_raider_id - RAIDER_ID - 1 - alive
	# Corpses still count against the spawner's limit until they are freed.
	if raiders.get_child_count() >= MAX_ALIVE:
		spawn_left = SPAWN_INTERVAL
		return
	spawn_left -= delta
	if spawn_left > 0.0:
		return
	spawn_left = SPAWN_INTERVAL
	spawn_at(farthest_spawn(gates, player_positions()))

func clear() -> void:
	super.clear()
	gates.clear()
	alive = 0
	felled = 0
