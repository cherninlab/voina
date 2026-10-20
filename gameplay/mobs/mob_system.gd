class_name MobSystem
extends Node3D
## Host-owned spawning, navigation and replacements for every hostile encounter, each switched on
## by the host before hosting: the possessed villagers of the church yard (ChurchSite), each keeping
## to the yard on its own (HostileMob), and raiders in the village or in the forest along the church
## road, each hunting players through its own zone and returning to its post (RaiderMob).

enum Zone { VILLAGE, FOREST }
const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var bodies: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var raiders: Node3D = Node3D.new()
var raider_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var players: Node3D
var navigation: MobNavigation = MobNavigation.new()
var started: bool = false
var generation: int = 0
# Which encounters start(), chosen by MatchWorld from the lobby switches.
var villagers: bool = true
var village_raiders: bool = false
var forest_raiders: bool = false
const COUNT: int = 4
const RESPAWN_DELAY: float = 5.0
# Graves around the yard, relative to its centre: the first COUNT are the opening places. The
# church door is 9 m north of the centre and the road arrives from the south.
const SPAWN_SPOTS: Array[Vector2] = [Vector2(-8, -6), Vector2(8, -5), Vector2(-11, 3), Vector2(10, 4), Vector2(-3, 7), Vector2(3, -2)]
var spawn_points: Array[Vector3] = [] # host only: the spots on the sampled ground
var next_id: int = COUNT + 1
var respawn_left: float = RESPAWN_DELAY
const RAIDER_COUNTS: PackedInt32Array = [5, 3] # by Zone: five cultists in the village, three in the woods
const RAIDER_ID: int = 1000 # raider ids start above this, apart from the villagers' (swing hit ids)
# Each zone's grid centre: the village square, and the road at z -62, whose 44 m cover the woods
# from z -84 to -40.
const FOREST_Z: float = -62.0
# Raider posts; the first RAIDER_COUNTS[zone] of each zone are the opening places. In the village, the
# old arena spawns first, around the square (x, z). In the forest, among the trees: (metres off the
# road's centre line, z); the road runs from the gate (z -30) to the church yard (z -90).
const VILLAGE_POSTS: Array[Vector2] = [Vector2(-8, 0), Vector2(8, 0), Vector2(0, -13), Vector2(-12, 10), Vector2(12, 10), Vector2(-14, -8), Vector2(14, -8)]
const FOREST_POSTS: Array[Vector2] = [Vector2(-8, -48), Vector2(8, -60), Vector2(-7, -73), Vector2(9, -80), Vector2(7, -44)]
var raider_grids: Array[MobNavigation] = [MobNavigation.new(), MobNavigation.new()] # by Zone
var raider_points: Array[Array] = [[], []] # host only, by Zone: the posts on the sampled ground
var raider_respawn_left: PackedFloat32Array = PackedFloat32Array([RESPAWN_DELAY, RESPAWN_DELAY])
var next_raider_id: int = RAIDER_ID + 1

func _ready() -> void:
	bodies.name = "Bodies"
	add_child(bodies)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Bodies")
	spawner.spawn_limit = COUNT
	spawner.spawn_function = create_mob
	add_child(spawner)
	raiders.name = "Raiders"
	add_child(raiders)
	raider_spawner.name = "RaiderSpawner"
	raider_spawner.spawn_path = NodePath("../Raiders")
	raider_spawner.spawn_limit = RAIDER_COUNTS[Zone.VILLAGE] + RAIDER_COUNTS[Zone.FOREST]
	raider_spawner.spawn_function = create_raider
	add_child(raider_spawner)

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

# [id, post, yaw, zone]
func create_raider(data: Variant) -> Node:
	var info: Array = data as Array
	var mob: RaiderMob = RaiderMob.new()
	mob.mob_id = int(info[0])
	mob.name = "Raider%d" % (mob.mob_id - RAIDER_ID)
	mob.position = info[1] as Vector3
	mob.sync_position = mob.position
	mob.home = mob.position
	mob.yaw = float(info[2])
	mob.zone = int(info[3])
	mob.system = self
	return mob

static func zone_center(zone: int) -> Vector2:
	return Vector2(ChurchSite.road_x(FOREST_Z), FOREST_Z) if zone == Zone.FOREST else Vector2.ZERO

static func post_flat(zone: int, post: Vector2) -> Vector3:
	if zone == Zone.FOREST:
		return Vector3(ChurchSite.road_x(post.y) + post.x, 0.0, post.y)
	return Vector3(post.x, 0.0, post.y)

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
	if villagers:
		navigation.build(get_world_3d().direct_space_state, actor_rids())
		spawn_points.clear()
		for spot: Vector2 in SPAWN_SPOTS:
			var flat: Vector2 = ChurchSite.YARD_CENTER + spot
			spawn_points.append(navigation.stand_point(Vector3(flat.x, 0.0, flat.y)) + Vector3.UP * 0.05)
		for index: int in range(COUNT):
			spawner.spawn([index + 1, spawn_points[index]])
	if village_raiders:
		start_raiders(Zone.VILLAGE)
	if forest_raiders:
		start_raiders(Zone.FOREST)

# Posts only count where the zone's grid found open ground.
func start_raiders(zone: int) -> void:
	var grid: MobNavigation = raider_grids[zone]
	grid.build(get_world_3d().direct_space_state, actor_rids(), zone_center(zone))
	var points: Array = raider_points[zone]
	points.clear()
	for post: Vector2 in (FOREST_POSTS if zone == Zone.FOREST else VILLAGE_POSTS):
		var cell: Vector2i = grid.nearest(post_flat(zone, post))
		if grid.grid.is_point_solid(cell) or grid.height(cell) < -999.0:
			continue
		points.append(grid.point_of(cell) + Vector3.UP * 0.05)
	for index: int in range(mini(RAIDER_COUNTS[zone], points.size())):
		spawn_raider(zone, points[index] as Vector3)

func spawn_raider(zone: int, point: Vector3) -> void:
	raider_spawner.spawn([next_raider_id, point, facing_post(zone, point), zone])
	next_raider_id += 1

# A forest raider waits facing the road, so it sees whoever walks it; a village raider faces the
# square.
static func facing_post(zone: int, point: Vector3) -> float:
	var toward: Vector2 = Vector2(ChurchSite.road_x(point.z) - point.x, 0.0) if zone == Zone.FOREST else -Vector2(point.x, point.z)
	return atan2(-toward.x, -toward.y) if toward.length_squared() > 0.0001 else 0.0

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not started:
		return
	for zone: int in range(Zone.size()):
		respawn_raiders(zone, delta)
	# Replacements keep the yard haunted: once a corpse is gone, a new villager rises after a delay.
	if spawn_points.is_empty():
		return
	if bodies.get_child_count() >= COUNT:
		respawn_left = RESPAWN_DELAY
		return
	respawn_left -= delta
	if respawn_left > 0.0:
		return
	respawn_left = RESPAWN_DELAY
	spawner.spawn([next_id, farthest_spawn(spawn_points, player_positions())])
	next_id += 1

# A fallen raider is replaced after a delay at its zone's post farthest from the players.
func respawn_raiders(zone: int, delta: float) -> void:
	var points: Array[Vector3] = []
	points.assign(raider_points[zone])
	if points.is_empty() or zone_raiders(zone).size() >= mini(RAIDER_COUNTS[zone], points.size()):
		raider_respawn_left[zone] = RESPAWN_DELAY
		return
	raider_respawn_left[zone] -= delta
	if raider_respawn_left[zone] > 0.0:
		return
	raider_respawn_left[zone] = RESPAWN_DELAY
	spawn_raider(zone, farthest_spawn(points, player_positions()))

func zone_raiders(zone: int) -> Array[RaiderMob]:
	var result: Array[RaiderMob] = []
	for node: Node in raiders.get_children():
		if (node as RaiderMob).zone == zone:
			result.append(node as RaiderMob)
	return result

func player_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node: Node in players.get_children():
		if node is Node3D:
			result.append((node as Node3D).global_position)
	return result

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
	spawn_points.clear()
	next_raider_id = RAIDER_ID + 1
	raider_respawn_left = PackedFloat32Array([RESPAWN_DELAY, RESPAWN_DELAY])
	raider_points = [[], []]
	for mob: Node in bodies.get_children() + raiders.get_children():
		mob.queue_free()

func actor_rids() -> Array[RID]:
	var result: Array[RID] = []
	for root: Node3D in [players, bodies, raiders]:
		for node: Node in root.get_children():
			if node is CollisionObject3D:
				result.append((node as CollisionObject3D).get_rid())
	return result

func living_count(root: Node3D = bodies) -> int:
	var count: int = 0
	for node: Node in root.get_children():
		if (node as HostileMob).combat.health > 0:
			count += 1
	return count
