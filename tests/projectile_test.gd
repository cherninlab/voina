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

func sweep_regressions(shooter: CharacterBody3D, target: CharacterBody3D, covered: CharacterBody3D) -> void:
	Projectiles.set_physics_process(false)
	var second_evader: CharacterBody3D = add_player(4, Vector3(80, 1, 0), 0.0)
	for body: CharacterBody3D in [shooter, target, covered, second_evader]:
		body.set_physics_process(false)
		combat(body).set_physics_process(false)
		combat(body).health = 100
		combat(body).blocking = false
		combat(body).invulnerable_until = 0.0
	place(shooter, Vector3(30, 1, 0))
	place(target, Vector3(30, 1, -1))
	place(covered, Vector3(30, 1, -3.4))
	add_wall(Vector3(3, 3, 0.1), Vector3(30, 1, -1.7))
	combat(target).invulnerable_until = combat(target).clock + 100.0
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	var bolt: Projectiles.Bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 0.1)
	check(bolt.passed.size() == 1 and Projectiles.bolts.is_empty(), "A 0.1s catch-up sweeps cover after an evade")
	for step: int in range(20):
		Projectiles.fly(bolt, 1.0 / 60.0)
	check(combat(covered).health == 100, "The player behind evade-plus-cover stays protected")
	Projectiles.clear()

	place(shooter, Vector3(40, 1, 0))
	place(target, Vector3(40, 1, -0.8))
	place(second_evader, Vector3(40, 1, -1.7))
	place(covered, Vector3(40, 1, -3.1))
	combat(second_evader).invulnerable_until = combat(second_evader).clock + 100.0
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 0.1)
	check(bolt.passed.size() == 2 and is_equal_approx(bolt.age, 0.1), "One catch-up passes multiple evaders without losing flight time")
	check(Projectiles.flight_position(bolt, bolt.age).is_equal_approx(chest(shooter) + Vector3(0, -0.02, -2.4)), "Evades preserve the normal ballistic endpoint")
	Projectiles.fly(bolt, 0.1)
	check(combat(target).health == 100 and combat(second_evader).health == 100, "Both evaders remain unharmed")
	check(combat(covered).health == 80 and Projectiles.bolts.is_empty(), "The remaining flight hits the first vulnerable player once")
	Projectiles.fly(bolt, 0.1)
	check(combat(covered).health == 80, "An already ended bolt cannot deal duplicate damage")
	Projectiles.clear()

	place(shooter, Vector3(50, 1, 0))
	place(target, Vector3(50, 1, -0.8))
	place(covered, Vector3(50, 1, -1.6))
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	bolt.age = Projectiles.LIFETIME - 0.04
	bolt.velocity = Vector3.FORWARD * Projectiles.SPEED - Projectiles.GRAVITY * bolt.age
	bolt.origin = chest(shooter) - bolt.velocity * bolt.age - Projectiles.GRAVITY * (0.5 * bolt.age * bolt.age)
	var before_expiry: int = combat(covered).health
	Projectiles.fly(bolt, 0.1)
	check(bolt.passed.size() == 1 and is_equal_approx(bolt.age, Projectiles.LIFETIME) and Projectiles.bolts.is_empty(), "An evaded bolt expires within the catch-up interval")
	check(combat(covered).health == before_expiry, "Expiry prevents a hit in the unused part of the interval")
	Projectiles.fly(bolt, 0.0)
	check(Projectiles.bolts.is_empty(), "Zero-time updates cannot revive an expired bolt")

	place(shooter, Vector3(60, 1, 0))
	place(target, Vector3(60, 1, -0.85))
	combat(target).invulnerable_until = 0.0
	combat(target).phase = CombatController.Phase.IDLE
	combat(target).next_block = 0.0
	target.set("yaw", PI)
	shooter.set("yaw", 0.0)
	check(combat(target).set_block(true), "The close defender can parry")
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 1.0 / 60.0)
	check(combat(shooter).health == 80 and combat(target).health == 100 and Projectiles.bolts.is_empty(), "A close reflection hits the shooter overlapping its new origin")
	Projectiles.fly(bolt, 0.1)
	check(combat(shooter).health == 80, "A reflected overlap deals damage only once")
	Projectiles.clear()

	combat(shooter).health = 100
	combat(shooter).phase = CombatController.Phase.IDLE
	combat(shooter).next_block = 0.0
	check(combat(shooter).set_block(true), "The close shooter can also parry")
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 0.1)
	check(Projectiles.bolts.is_empty() and combat(shooter).health == 100 and combat(target).health == 100, "Mutual overlapping parries terminate without recursion or damage")
	Projectiles.clear()

	# A distant reflection must also use the rest of its catch-up interval, not just overlaps.
	place(shooter, Vector3(70, 1, 0))
	place(target, Vector3(70, 1, -1.5))
	combat(shooter).blocking = false
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 0.1)
	check(combat(shooter).health == 80 and Projectiles.bolts.is_empty(), "A reflection sweeps its remaining catch-up time back to the shooter")
	Projectiles.clear()

	place(shooter, Vector3(80, 1, 0))
	place(target, Vector3(80, 1, -0.2))
	place(second_evader, Vector3(80, 1, -0.3))
	place(covered, Vector3(80, 1, -1.5))
	combat(target).blocking = false
	combat(target).invulnerable_until = combat(target).clock + 100.0
	combat(covered).health = 100
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	check(bolt.passed.size() == 2 and is_zero_approx(bolt.age), "Spawn resolves multiple immune starting overlaps without consuming flight time")
	Projectiles.fly(bolt, 0.1)
	check(combat(covered).health == 80 and Projectiles.bolts.is_empty(), "Starting overlaps do not skip the vulnerable player ahead")
	Projectiles.clear()

	place(target, Vector3(90, 1, -0.2))
	place(second_evader, Vector3(90, 1, -0.3))
	place(shooter, Vector3(90, 1, 0))
	add_wall(Vector3(0.1, 3, 3), Vector3(90.1, 1, 0))
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	check(Projectiles.bolts.is_empty(), "Static cover overlapping an immune spawn still ends the bolt")

	place(shooter, Vector3(100, 1, 0))
	place(target, Vector3(100, 1, -1.5))
	combat(target).invulnerable_until = 0.0
	combat(target).next_block = 0.0
	target.set("yaw", PI - 0.6)
	check(combat(target).set_block(true), "A defender beside cover can parry")
	add_wall(Vector3(0.2, 3, 0.4), Vector3(99.5, 1, -1.0))
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	var before_reflection: int = combat(shooter).health
	Projectiles.fly(bolt, 0.1)
	check(bolt.owner_peer == 2 and Projectiles.bolts.is_empty() and combat(shooter).health == before_reflection, "Cover overlapping a reflected origin stops its remaining flight")

	place(shooter, Vector3(110, 5, 0))
	await frames(2)
	Projectiles.spawn(1, 0, chest(shooter), Vector3.FORWARD * Projectiles.SPEED)
	bolt = Projectiles.bolts.values()[0]
	Projectiles.fly(bolt, 0.1)
	check(is_equal_approx(bolt.age, 0.1) and Projectiles.flight_position(bolt, bolt.age).is_equal_approx(chest(shooter) + Vector3(0, -0.02, -2.4)), "An unobstructed bolt preserves its ordinary flight endpoint")
	check(Projectiles.flight_velocity(bolt, bolt.age).is_equal_approx(Vector3(0, -0.4, -24)), "An unobstructed bolt preserves gravity")
	Projectiles.clear()
	print("PROJECTILE_SWEEP_OK: catch-up cover, multiple evades, ballistic time, single damage, expiry, close reflection, bounded parries, starting overlaps")

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
	# The lower crypt is playable below the old village kill plane.
	await frames(40)
	shooter.set_physics_process(false)
	target.set_physics_process(false)
	place(shooter, Vector3(0, -25, 0))
	place(target, Vector3(0, -25, -6))
	combat(target).health = 100
	check(fire(shooter, chest(target)), "A lower-dungeon bolt is accepted")
	await frames(2)
	check(not Projectiles.bolts.is_empty(), "A lower-dungeon bolt survives its first flight ticks")
	await frames(20)
	check(combat(target).health == 80 and Projectiles.bolts.is_empty(), "A lower-dungeon bolt reaches and damages its target once")
	await frames(40)
	check(fire(shooter, chest(shooter) + Vector3.RIGHT * 10), "A lower-dungeon miss is accepted")
	await frames(130)
	check(Projectiles.bolts.is_empty(), "A lower-dungeon miss still expires after its lifetime")
	await sweep_regressions(shooter, target, covered)
	if failed:
		return
	print("PROJECTILE_OK: hit, cover, validation, wall-muzzle clamp, cooldown, in-flight cap, lifetime, dash pass-through, block, parry reflect, disconnect")
	get_tree().quit()
