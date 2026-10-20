extends Node3D

# Raiders (RaiderMob) on flat ground from the village past the church road: forest posts, ignoring
# the village, pursuit and one 12-damage jab per attack, giving up and walking home, replacement;
# then each lobby switch on its own: village raiders without villagers or forest raiders.
const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const CULTIST: String = "res://content/mobs/hooded_cultist/hooded_cultist.glb" # the village raiders' body, T-107
var players: Node3D = Node3D.new()
var mobs: MobSystem = MobSystem.new()
var failed: bool = false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("RAIDER_FAIL: " + message)
		get_tree().quit(1)

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func road(z: float, off: float = 0.0) -> Vector3:
	return Vector3(ChurchSite.road_x(z) + off, MobNavigation.STAND, z)

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func place(player: CharacterBody3D, location: Vector3) -> void:
	player.position = location
	player.set("sync_position", location)
	player.set("accepted_position", location)
	(player.get("history") as HitResolver.PositionHistory).clear()

func raider_list() -> Array[RaiderMob]:
	var result: Array[RaiderMob] = []
	for node: Node in mobs.raiders.get_children():
		result.append(node as RaiderMob)
	return result

func run() -> void:
	players.name = "Players"
	add_child(players)
	mobs.name = "Mobs"
	mobs.players = players
	mobs.forest_raiders = true
	add_child(mobs)
	# Flat ground from the village gate past the church yard.
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cube: BoxShape3D = BoxShape3D.new()
	cube.size = Vector3(90, 2, 170)
	shape.shape = cube
	body.position = Vector3(0, -1, -65)
	body.add_child(shape)
	add_child(body)
	# Like the real village: an older landscape buried 1.5 m under the walkable floor.
	var buried: StaticBody3D = StaticBody3D.new()
	var buried_shape: CollisionShape3D = CollisionShape3D.new()
	var slab: BoxShape3D = BoxShape3D.new()
	slab.size = Vector3(40, 1, 40)
	buried_shape.shape = slab
	buried.position = Vector3(0, -2.0, 0)
	buried.add_child(buried_shape)
	add_child(buried)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = "1"
	players.add_child(player)
	player.set_physics_process(false)
	var village: Vector3 = Vector3(0, MobNavigation.STAND, -10)
	place(player, village)
	await frames(2)
	mobs.start()
	await frames(4)
	var raiders: Array[RaiderMob] = raider_list()
	check(raiders.size() == MobSystem.RAIDER_COUNT and mobs.raider_points[MobSystem.Zone.FOREST].size() == MobSystem.FOREST_POSTS.size() and mobs.raider_points[MobSystem.Zone.VILLAGE].is_empty(), "The forest posts are found and three raiders spawn, none in the village (%d)" % raiders.size())
	check(mobs.bodies.get_child_count() == MobSystem.COUNT, "The church yard keeps its villagers")
	for raider: RaiderMob in raiders:
		check(absf(raider.global_position.y - (MobNavigation.STAND + 0.05)) < 0.1 and raider.mob_id > MobSystem.RAIDER_ID and raider.zone == MobSystem.Zone.FOREST, "Raider %d stands on the forest ground with a raider id" % raider.mob_id)
		check(not raider.visual.get("possession").active, "Raider %d has the plain body" % raider.mob_id)
		var to_road: Vector3 = road(raider.global_position.z) - raider.global_position
		check(Vector3.FORWARD.rotated(Vector3.UP, raider.yaw).dot(to_road.normalized()) > 0.9, "Raider %d waits facing the road" % raider.mob_id)
	# A player in the village is ignored.
	await frames(60)
	for raider: RaiderMob in raiders:
		check(raider.target == null and flat_distance(raider.global_position, raider.home) < 0.3, "A player in the village is not hunted")
	# On the road beside the first post: it runs them down and jabs, 12 damage per committed attack.
	var guard: CombatController = player.get("combat") as CombatController
	var first: RaiderMob = raiders[0]
	place(player, road(first.home.z))
	var hit_frame: int = -1
	for frame: int in range(360):
		await get_tree().physics_frame
		if guard.health < 100:
			hit_frame = frame
			break
	check(hit_frame >= 0, "A raider runs down a player on the road and jabs")
	check((100 - guard.health) % RaiderMob.RAIDER_DAMAGE == 0, "Each jab deals %d (health %d)" % [RaiderMob.RAIDER_DAMAGE, guard.health])
	var striker: RaiderMob
	for raider: RaiderMob in raiders:
		if raider.state == HostileMob.State.ACT and raider.did_strike:
			striker = raider
	check(striker != null, "The jab came from a committed attack")
	var after_first: int = guard.health
	await frames(int(RaiderMob.RAIDER_RECOVERY * 60.0) - 4)
	check(after_first - guard.health < RaiderMob.RAIDER_DAMAGE or striker.state == HostileMob.State.ACT, "One hit per attack")
	# Back to the village: they give up after their memory runs out and walk home.
	guard.health = 100
	place(player, village)
	await frames(1200)
	for raider: RaiderMob in raider_list():
		check(raider.target == null and raider.state == HostileMob.State.IDLE and flat_distance(raider.global_position, raider.home) < 0.8, "Raider %d returns to its post (%.1f m away)" % [raider.mob_id, flat_distance(raider.global_position, raider.home)])
	# A dead raider is replaced at the post farthest from the players.
	var forest_points: Array[Vector3] = []
	forest_points.assign(mobs.raider_points[MobSystem.Zone.FOREST])
	var expected: Vector3 = MobSystem.farthest_spawn(forest_points, [player.global_position])
	first.receive_hit(999, Vector3.FORWARD)
	var replacement: RaiderMob
	for frame: int in range(600):
		await get_tree().physics_frame
		replacement = mobs.raiders.get_node_or_null("Raider%d" % (MobSystem.RAIDER_COUNT + 1)) as RaiderMob
		if replacement != null:
			break
	check(replacement != null and flat_distance(replacement.global_position, expected) < 0.1 and mobs.raiders.get_child_count() == MobSystem.RAIDER_COUNT, "A replacement raider arrives at the farthest post")
	mobs.clear()
	await frames(2)
	check(mobs.raiders.get_child_count() == 0, "Clearing the encounter removes the raiders")
	# Only the village switch: raiders around the square, no villagers, nobody in the woods.
	mobs.villagers = false
	mobs.forest_raiders = false
	mobs.village_raiders = true
	place(player, road(-60.0))
	mobs.start()
	await frames(4)
	var village_raiders: Array[RaiderMob] = raider_list()
	check(village_raiders.size() == MobSystem.RAIDER_COUNT and mobs.bodies.get_child_count() == 0 and mobs.zone_raiders(MobSystem.Zone.FOREST).is_empty(), "The village switch alone spawns three village raiders (%d raiders, %d villagers)" % [village_raiders.size(), mobs.bodies.get_child_count()])
	for raider: RaiderMob in village_raiders:
		check(raider.zone == MobSystem.Zone.VILLAGE and flat_distance(raider.global_position, Vector3.ZERO) < 16.0, "Raider %d waits in the village" % raider.mob_id)
		check(absf(raider.home.y - (MobNavigation.STAND + 0.05)) < 0.1, "Raider %d stands on the village floor, not the buried ground (%.2f)" % [raider.mob_id, raider.home.y])
		var dressed: bool = (raider.visual.get("body_scene") as PackedScene).resource_path == CULTIST
		check(dressed == ResourceLoader.exists(CULTIST), "Raider %d wears the cultist robe when the asset exists" % raider.mob_id)
	await frames(30)
	check(village_raiders[0].target == null, "A player in the woods is beyond the village raiders")
	place(player, Vector3(0, MobNavigation.STAND, 3))
	await frames(30)
	check(village_raiders[0].target == player, "A village raider spots a player on the square")
	mobs.clear()
	await frames(2)
	if not failed:
		print("RAIDER_OK: forest posts, facing the road, village ignored, pursuit, 12-damage jab, one hit per attack, return to post, replacement, clear, village switch alone")
		get_tree().quit()
