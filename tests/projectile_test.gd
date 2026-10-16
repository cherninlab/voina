extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const CHEST: Vector3 = Vector3.UP * HitResolver.CHEST_HEIGHT

var players: Node3D = Node3D.new()
var failed: bool = false

# Run as a scene so the Projectiles, NetworkManager and InputSettings autoloads exist.
# Offline peer: this process is peer 1, the host for every request below.
func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("PROJECTILE_FAIL: " + message)
		get_tree().quit(1)

func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func add_player(peer: int, location: Vector3, facing: float) -> CharacterBody3D:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = location
	player.set("sync_position", location)
	player.set("yaw", facing)
	players.add_child(player)
	return player

func place(player: CharacterBody3D, location: Vector3) -> void:
	player.position = location
	player.set("sync_position", location)
	player.set("accepted_position", location)

func add_wall(size: Vector3, location: Vector3) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = location
	add_child(wall)

func combat(player: CharacterBody3D) -> CombatController:
	return player.get("combat") as CombatController

func chest(player: CharacterBody3D) -> Vector3:
	return (player.get("sync_position") as Vector3) + CHEST

func fire(shooter: CharacterBody3D, target: Vector3) -> bool:
	return Projectiles.handle_fire(shooter.get_multiplayer_authority(), 0, chest(shooter), (target - chest(shooter)).normalized())

func run() -> void:
	players.name = "Players"
	add_child(players)
	add_wall(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	add_wall(Vector3(0.2, 3, 3), Vector3(3, 1.5, 0))
	var shooter: CharacterBody3D = add_player(1, Vector3(0, 0.9, 0), 0.0)
	var target: CharacterBody3D = add_player(2, Vector3(0, 0.95, -6), PI)
	var covered: CharacterBody3D = add_player(3, Vector3(6, 0.95, 0), 0.0)
	await frames(5)

	check(fire(shooter, chest(target)), "A valid bolt is accepted")
	check(not fire(shooter, chest(target)), "Bolts share the attack cooldown")
	check(Projectiles.bolts.size() == 1, "Exactly one bolt flies")
	await frames(20)
	check(combat(target).health == 80, "A bolt hits its target once")
	check(Projectiles.bolts.is_empty(), "A hit ends the bolt")

	await frames(40)
	check(fire(shooter, chest(covered)), "A bolt toward cover is accepted")
	await frames(30)
	check(combat(covered).health == 100 and Projectiles.bolts.is_empty(), "Cover stops a bolt")

	await frames(40)
	var stamina: float = combat(shooter).stamina
	var origin: Vector3 = chest(shooter)
	check(not Projectiles.handle_fire(9, 0, origin, Vector3.FORWARD), "A peer without a player cannot fire")
	check(not Projectiles.handle_fire(2, 0, origin, Vector3.BACK), "A client cannot fire from another player's position")
	check(not Projectiles.handle_fire(1, 0, Vector3(NAN, 0, 0), Vector3.FORWARD), "A non-finite origin is refused")
	check(not Projectiles.handle_fire(1, 0, origin, Vector3.ZERO), "A zero direction is refused")
	check(not Projectiles.handle_fire(1, 0, origin, Vector3.FORWARD * 10.0), "An unnormalized direction is refused")
	check(combat(shooter).stamina >= stamina and Projectiles.bolts.is_empty(), "Refused bolts cost nothing")
	# A muzzle claimed on the far side of the wall fires from the shooter's chest instead.
	place(shooter, Vector3(2.2, 0.9, 0))
	await frames(2)
	check(Projectiles.handle_fire(1, 0, Vector3(3.5, chest(shooter).y, 0), Vector3.RIGHT), "A bolt from beside the wall is accepted")
	await frames(30)
	check(combat(covered).health == 100, "A claimed muzzle cannot pass through a wall")
	place(shooter, Vector3(0, 0.9, 0))

	for shot: int in range(3):
		await frames(37)
		check(fire(shooter, chest(shooter) + Vector3.UP * 10.0), "Bolts are accepted until three fly")
	await frames(37)
	check(not fire(shooter, chest(shooter) + Vector3.UP * 10.0), "At most three bolts per player fly at once")
	await frames(130)
	check(Projectiles.bolts.is_empty(), "Bolts expire after their lifetime")

	place(target, Vector3(0, 0.95, -2))
	await frames(2)
	var before: int = combat(target).health
	check(combat(target).begin_dash() and fire(shooter, chest(target)), "A bolt at a dashing target is accepted")
	await frames(30)
	check(combat(target).health == before, "Dash immunity lets a bolt pass through")

	await frames(100)
	check(combat(target).set_block(true), "The target raises its guard")
	await frames(20)
	check(fire(shooter, chest(target)), "A bolt at a blocking target is accepted")
	await frames(15)
	check(combat(target).health == before - 4 and Projectiles.bolts.is_empty(), "A front block takes 20% of a bolt")
	combat(target).set_block(false)

	place(target, Vector3(0, 0.95, -6))
	await frames(40)
	var shooter_health: int = combat(shooter).health
	check(fire(shooter, chest(target)), "A bolt to be parried is accepted")
	await frames(9)
	check(combat(target).set_block(true), "The target parries just before impact")
	await frames(40)
	check(combat(target).health == before - 4, "A parried bolt deals no damage")
	check(combat(shooter).health == shooter_health - 20, "The reflected bolt hits its original shooter")
	combat(target).set_block(false)

	await frames(40)
	check(fire(shooter, chest(shooter) + Vector3.UP * 10.0), "A bolt for disconnect cleanup is accepted")
	Projectiles.drop_owner(1)
	check(Projectiles.bolts.is_empty(), "A disconnecting owner's bolts end")
	if failed:
		return
	print("PROJECTILE_OK: hit, cover, validation, wall-muzzle clamp, cooldown, in-flight cap, lifetime, dash pass-through, block, parry reflect, disconnect")
	get_tree().quit()
