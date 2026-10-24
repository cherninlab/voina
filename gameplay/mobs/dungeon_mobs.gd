extends MobSystem
## Five finite guards, using the existing host-owned combat and replicated spawn protocol.
## Separate height-bounded room grids keep stacked halls from sampling one another's floor.

class RoomNavigation:
	extends MobNavigation
	var floor_y: float

	func _init(level: float) -> void:
		floor_y = level

	func lowest_ground(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, point: Vector2) -> float:
		ray.from = Vector3(point.x, floor_y + 0.55, point.y)
		ray.to = Vector3(point.x, floor_y - 1.0, point.y)
		var hit: Dictionary = space.intersect_ray(ray)
		return (hit["position"] as Vector3).y if not hit.is_empty() else NAN

	func covers(location: Vector3) -> bool:
		return absf(location.y - floor_y) < 4.0 and super.covers(location)

# The choir's return stair climbs its walls on masonry; its guards hold the open floor.
const POSTS: Array[Vector3] = [Vector3(80, -4, 36), Vector3(88, -4, 34), Vector3(82, -28, 46), Vector3(84, -28, 52), Vector3(90, -28, 50)]
var remaining: int = POSTS.size()

func _ready() -> void:
	super._ready()
	villagers = false
	forest_raiders = false
	raider_grids[Zone.VILLAGE] = RoomNavigation.new(-4.0)
	raider_grids[Zone.FOREST] = RoomNavigation.new(-28.0)
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
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	raider_grids[Zone.VILLAGE].build(space, actor_rids(), Vector2(34, -12))
	raider_grids[Zone.FOREST].build(space, actor_rids(), Vector2(36, -2))
	for index: int in range(POSTS.size()):
		var zone: int = Zone.VILLAGE if index < 2 else Zone.FOREST
		var point: Vector3 = raider_grids[zone].stand_point(RedDescentLayout.at(POSTS[index])) + Vector3.UP * 0.05
		var toward: Vector3 = RedDescentLayout.at(Vector3(74, POSTS[index].y, 42 if index < 2 else 56)) - point
		raider_spawner.spawn([next_raider_id, point, atan2(-toward.x, -toward.z), zone])
		next_raider_id += 1
	print("DUNGEON_ENCOUNTER_READY: five guards across two vertically separated halls, no replacements")

func _process(_delta: float) -> void:
	if multiplayer.is_server() and started and next_raider_id > RAIDER_ID + POSTS.size():
		remaining = living_count(raiders)

func clear() -> void:
	super.clear()
	remaining = POSTS.size()
