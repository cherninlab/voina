class_name MobSystem
extends Node3D

const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var bodies: Node3D = Node3D.new()
var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
var players: Node3D
var navigation: MobNavigation = MobNavigation.new()
var started: bool = false
var generation: int = 0

func _ready() -> void:
	bodies.name = "Bodies"
	add_child(bodies)
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Bodies")
	spawner.spawn_limit = 3
	spawner.spawn_function = create_mob
	add_child(spawner)

func create_mob(data: Variant) -> Node:
	var info: Array = data as Array
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = int(info[0])
	mob.name = "Mob%d" % mob.mob_id
	mob.position = info[1] as Vector3
	mob.sync_position = mob.position
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
	var locations: Array[Vector3] = [Vector3(-3, 0.95, 0), Vector3(3, 0.95, 0), Vector3(0, 0.95, -5)]
	for index: int in range(locations.size()):
		spawner.spawn([index + 1, locations[index]])

func clear() -> void:
	started = false
	generation += 1
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
