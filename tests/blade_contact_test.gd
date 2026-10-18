extends Node3D

const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
var failures: int = 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("BLADE_CONTACT_FAIL: " + message)

func spawn_mob(id: int, location: Vector3) -> HostileMob:
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = id
	mob.position = location
	add_child(mob)
	mob.set_physics_process(false)
	mob.combat.set_physics_process(false)
	return mob

func run() -> void:
	var closest: Array[Vector3] = BladeContact.closest_points(Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(0, 0, 0), Vector3(0, 2, 0))
	check(closest[0].distance_to(closest[1]) < 0.001 and absf(closest[2].x - 0.5) < 0.001, "Crossing segments meet at their midpoints")
	closest = BladeContact.closest_points(Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(0, 0, 0), Vector3(0, 2, 0))
	check(absf(closest[0].distance_to(closest[1]) - 1.0) < 0.001, "Offset segments report their gap")
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.position = Vector3(-1.5, 0.95, 0)
	add_child(player)
	player.set_physics_process(false)
	var player_combat: CombatController = player.get("combat") as CombatController
	player_combat.set_physics_process(false)
	await get_tree().physics_frame
	var contact: BladeContact = BladeContact.new()
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	motion.reset(0.0, player.position, 0.0)
	motion.hilt = Vector3(-1.2, 1.0, 0)
	motion.tip = Vector3(0.3, 1.0, 0)
	# A slow blade through a raider shoves it a little but never hurts.
	var mob: HostileMob = spawn_mob(1, Vector3(0, 0.95, 0))
	motion.tip_velocity = Vector3(0, 0, 0.5)
	player_combat.respawn()
	player_combat.begin_attack(false)
	contact.sweep(player, motion, true, -1.0)
	check(mob.combat.health == 60 and mob.kick_velocity.is_zero_approx(), "A barely moving blade does nothing")
	motion.tip_velocity = Vector3(0, 0, 2.0)
	contact.sweep(player, motion, false, 0.0)
	check(mob.combat.health == 60 and mob.kick_velocity.length() > 0.3, "A slow blade shoves without hurting, even outside a swing")
	mob.kick_velocity = Vector3.ZERO
	# A medium swing shoves and deals the cone's damage once per swing.
	motion.tip_velocity = Vector3(0, 0, 6.0)
	contact.sweep(player, motion, true, 1.0)
	check(mob.combat.health == 35, "A medium contact deals swing damage (health %d)" % mob.combat.health)
	check(mob.kick_velocity.length() > 1.0 and mob.hop > 0.0, "A medium contact shoves the raider")
	check(float(mob.visual.get("react_left")) > 0.0, "The raider visibly reacts")
	check((mob.visual.get("wounds") as Array).size() == 1, "A damaging contact leaves a wound line on the raider")
	contact.sweep(player, motion, true, 1.1)
	check(mob.combat.health == 35, "Re-hit cooldown blocks an immediate second contact")
	contact.sweep(player, motion, true, 2.0)
	check(mob.combat.health == 35, "One damaging contact per swing")
	# Not swinging: a fast blade still shoves but neither hurts nor cuts.
	motion.tip_velocity = Vector3(0, 0, 15.0)
	mob.kick_velocity = Vector3.ZERO
	contact.sweep(player, motion, false, 3.0)
	check(mob.combat.health == 35 and mob.state != HostileMob.State.DEAD and mob.kick_velocity.length() > 3.0, "Contact outside an approved swing shoves without damage or cut")
	var far: Vector3 = MobSystem.farthest_spawn(MobSystem.SPAWN_POINTS, [Vector3(-8, 1, 0), Vector3(8, 1, 0)])
	check(far == Vector3(0, 0.95, -13), "Respawns pick the spawn point farthest from players")
	# A fast approved swing bisects in one shot.
	player_combat.respawn()
	player_combat.clock += 5.0
	player_combat.begin_attack(false)
	var before: int = get_tree().current_scene.get_child_count()
	contact.sweep(player, motion, true, 4.0)
	await get_tree().process_frame
	check(mob.combat.health <= 0 and mob.state == HostileMob.State.DEAD, "A fast contact kills in one shot")
	check(not mob.visual.visible, "The raider visual is replaced by halves")
	var halves: int = 0
	for node: Node in get_tree().current_scene.get_children():
		if node is RigidBody3D:
			halves += 1
	check(halves == 2, "Two tumbling halves exist (%d)" % halves)
	check(get_tree().current_scene.get_child_count() == before + 2, "Halves are the only new scene children")
	# A cone-approved swing goes through the blade path: it wounds, and a lethal blow bisects.
	var coned: HostileMob = spawn_mob(2, Vector3(0, 0.95, 3))
	motion.hilt = Vector3(-1.2, 1.0, 3)
	motion.tip = Vector3(0.3, 1.0, 3)
	motion.tip_velocity = Vector3(0, 0, 3.0)
	contact.strike_mob(player, motion, coned, Vector3.RIGHT, 10.0)
	check(coned.combat.health == 35 and (coned.visual.get("wounds") as Array).size() == 1, "A slow cone hit damages and wounds without cutting")
	coned.combat.health = 20
	contact.strike_mob(player, motion, coned, Vector3.RIGHT, 11.0)
	await get_tree().process_frame
	check(coned.state == HostileMob.State.DEAD and not coned.visual.visible, "A lethal cone hit bisects even when slow")
	if failures == 0:
		print("BLADE_CONTACT_OK: segment geometry, gentle shove, shove and damage, wound, cooldown, one hit per swing, swing gate, farthest respawn, one-shot bisect, cone hit wounds, lethal bisect")
	get_tree().quit(0 if failures == 0 else 1)
