class_name MobSystem
extends Node3D
## The possessed villagers of the church yard (ChurchSite): host-owned spawning, navigation and
## replacements. Each villager keeps to the yard on its own; see HostileMob.

const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var bodies: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var players: Node3D
var navigation: MobNavigation = MobNavigation.new()
var started: bool = false
var generation: int = 0
const COUNT: int = 4
const RESPAWN_DELAY: float = 5.0
# Graves around the yard, relative to its centre: the first COUNT are the opening places. The
# church door is 9 m north of the centre and the road arrives from the south.
const SPAWN_SPOTS: Array[Vector2] = [Vector2(-8, -6), Vector2(8, -5), Vector2(-11, 3), Vector2(10, 4), Vector2(-3, 7), Vector2(3, -2)]
var spawn_points: Array[Vector3] = [] # host only: the spots on the sampled ground
var next_id: int = COUNT + 1
var respawn_left: float = RESPAWN_DELAY

func _ready() -> void:
	bodies.name = "Bodies"
	add_child(bodies)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Bodies")
	spawner.spawn_limit = COUNT
	spawner.spawn_function = create_mob
	add_child(spawner)

func create_mob(data: Variant) -> Node:
	var info: Array = data as Array
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = int(info[0])
	mob.name = "Mob%d" % mob.mob_id
	mob.position = info[1] as Vector3
	mob.sync_position = mob.position
	mob.home = mob.position
	mob.system = self
	return mob

func start() -> void:
	if not multiplayer.is_server() or started:
		return
	started = true
	generation += 1
	var token: int = generation
	# CSG and imported prop collisions must exist before the occupancy query.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not started or token != generation or not multiplayer.is_server():
		return
	navigation.build(get_world_3d().direct_space_state, actor_rids())
	spawn_points.clear()
	for spot: Vector2 in SPAWN_SPOTS:
		var flat: Vector2 = ChurchSite.YARD_CENTER + spot
		spawn_points.append(navigation.stand_point(Vector3(flat.x, 0.0, flat.y)) + Vector3.UP * 0.05)
	for index: int in range(COUNT):
		spawner.spawn([index + 1, spawn_points[index]])

func _process(delta: float) -> void:
	# Replacements keep the yard haunted: once a corpse is gone, a new villager rises after a delay.
	if not multiplayer.is_server() or not started or spawn_points.is_empty():
		return
	if bodies.get_child_count() >= COUNT:
		respawn_left = RESPAWN_DELAY
		return
	respawn_left -= delta
	if respawn_left > 0.0:
		return
	respawn_left = RESPAWN_DELAY
	var occupied: Array[Vector3] = []
	for node: Node in players.get_children():
		if node is Node3D:
			occupied.append((node as Node3D).global_position)
	spawner.spawn([next_id, farthest_spawn(spawn_points, occupied)])
	next_id += 1

static func farthest_spawn(points: Array[Vector3], from: Array[Vector3]) -> Vector3:
	var best: Vector3 = points[0]
	var best_distance: float = -1.0
	for point: Vector3 in points:
		var nearest: float = INF
		for other: Vector3 in from:
			nearest = minf(nearest, Vector2(point.x - other.x, point.z - other.z).length())
		if from.is_empty():
			nearest = 0.0
		if nearest > best_distance:
			best_distance = nearest
			best = point
	return best

func clear() -> void:
	started = false
	generation += 1
	next_id = COUNT + 1
	respawn_left = RESPAWN_DELAY
	for mob: Node in bodies.get_children():
		mob.queue_free()

func actor_rids() -> Array[RID]:
	var result: Array[RID] = []
	for root: Node3D in [players, bodies]:
		for node: Node in root.get_children():
			if node is CollisionObject3D:
				result.append((node as CollisionObject3D).get_rid())
	return result

func living_count() -> int:
	var count: int = 0
	for node: Node in bodies.get_children():
		if (node as HostileMob).combat.health > 0:
			count += 1
	return count
