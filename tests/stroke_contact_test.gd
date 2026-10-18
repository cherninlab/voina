extends Node3D

# A level heavy cut is still flying after the 0.52 s swing window. The host keeps its blade
# damaging until its own reconstruction of the stroke lands, capped, and only for an approved swing.
const PLAYER: PackedScene = preload("res://gameplay/player/player_character.tscn")
const MOB: PackedScene = preload("res://gameplay/mobs/hostile_mob.tscn")
const HZ: int = 60
const ORIGIN: Vector3 = Vector3(0, 0.9, 0)
var failures: int = 0
var player: CharacterBody3D
var combat: CombatController
var next_mob: int = 1
var spot: Vector3 = Vector3.INF

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("STROKE_CONTACT_FAIL: " + message)

func spawn_mob(location: Vector3) -> HostileMob:
	var mob: HostileMob = MOB.instantiate() as HostileMob
	mob.mob_id = next_mob
	next_mob += 1
	mob.position = location
	add_child(mob)
	mob.set_physics_process(false)
	mob.combat.set_physics_process(false)
	return mob

func step_motion(motion: HeavySwordMotion, time: float) -> void:
	# No held drag: the cut flies on the torque the approved swing gave it. The blade is never
	# braced here, so the cancellation cases test the combat gate rather than the guard pose.
	motion.step(1.0 / HZ, 0.0, 0.0, false, time < 0.52, false, ORIGIN, 0.0)

# Where a raider stands so the tip end of the blade reaches it about 170 degrees into the cut.
func raider_spot() -> Vector3:
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	motion.reset(0.0, ORIGIN, 0.0)
	motion.strike(Vector2.LEFT)
	var previous: float = motion.blade_yaw()
	var swept: float = 0.0
	for frame: int in range(HZ * 2):
		step_motion(motion, float(frame + 1) / HZ)
		swept += angle_difference(previous, motion.blade_yaw())
		previous = motion.blade_yaw()
		if swept >= deg_to_rad(170.0):
			var outward: Vector3 = motion.tip - motion.hilt
			outward.y = 0.0
			return motion.tip + outward.normalized() * 0.38
	return Vector3.INF

# Runs one cut past a fresh raider. gate decides damage each tick; act runs once at 0.57 s,
# after the swing's phases and before the blade reaches the raider.
func cut(approved: bool, gate: Callable, act: Callable = Callable()) -> Dictionary:
	var mob: HostileMob = spawn_mob(spot)
	var health: int = mob.combat.health
	var contact: BladeContact = BladeContact.new()
	combat.respawn()
	combat.clock += 5.0
	if approved:
		check(combat.begin_attack(false), "The swing is approved")
	var motion: HeavySwordMotion = HeavySwordMotion.new()
	motion.reset(0.0, ORIGIN, 0.0)
	motion.strike(Vector2.LEFT)
	var previous: float = motion.blade_yaw()
	var swept: float = 0.0
	var result: Dictionary = {"touched": -1.0, "swept": 0.0, "phase": -1, "landed": -1.0, "live_after_landing": false}
	for frame: int in range(HZ * 2):
		var time: float = float(frame + 1) / HZ
		combat.step(1.0 / HZ)
		if act.is_valid() and is_equal_approx(time, 34.0 / HZ):
			check(combat.phase == CombatController.Phase.IDLE and bool(act.call()), "The cancelling action is accepted after recovery")
		step_motion(motion, time)
		swept += angle_difference(previous, motion.blade_yaw())
		previous = motion.blade_yaw()
		contact.sweep(player, motion, gate.call(motion), time)
		if contact.last_hit.has(mob.mob_id) and float(result["touched"]) < 0.0:
			result["touched"] = time
			result["swept"] = rad_to_deg(swept)
			result["phase"] = combat.phase
		if float(result["landed"]) < 0.0 and not motion.stroke_live:
			result["landed"] = time
		elif float(result["landed"]) >= 0.0:
			result["live_after_landing"] = bool(result["live_after_landing"]) or combat.cuts(motion.stroke_live)
	result["damage"] = health - mob.combat.health
	mob.queue_free()
	await get_tree().process_frame
	return result

func run() -> void:
	player = PLAYER.instantiate() as CharacterBody3D
	player.position = ORIGIN
	add_child(player)
	player.set_physics_process(false)
	combat = player.get("combat") as CombatController
	combat.set_physics_process(false)
	await get_tree().physics_frame
	var host_gate: Callable = func(motion: HeavySwordMotion) -> bool: return combat.cuts(motion.stroke_live)
	var window_gate: Callable = func(_motion: HeavySwordMotion) -> bool: return combat.phase in [CombatController.Phase.WINDUP, CombatController.Phase.ACTIVE, CombatController.Phase.RECOVERY]
	spot = raider_spot()
	check(spot.is_finite(), "A level cut reaches 170 degrees")
	var braced: HeavySwordMotion = HeavySwordMotion.new()
	braced.reset(0.0, ORIGIN, 0.0)
	braced.strike(Vector2.LEFT)
	check(braced.stroke_live, "An approved cut's stroke is live")
	braced.step(1.0 / HZ, 0.0, 0.0, false, true, true, ORIGIN, 0.0)
	check(not braced.stroke_live, "Bracing the blade ends the stroke")
	var hit: Dictionary = await cut(true, host_gate)
	check(float(hit["touched"]) > 0.52 and int(hit["phase"]) == CombatController.Phase.IDLE, "The raider is reached after the 0.52 s swing window (%.2f s)" % float(hit["touched"]))
	check(float(hit["swept"]) > 155.0 and float(hit["swept"]) < 185.0, "The raider is reached about 170 degrees into the cut (%.0f deg)" % float(hit["swept"]))
	check(int(hit["damage"]) >= BladeContact.DAMAGE, "A raider 170 degrees into a level cut takes damage (%d)" % int(hit["damage"]))
	check(float(hit["landed"]) > float(hit["touched"]) and float(hit["landed"]) < CombatController.CUT_FOLLOW_THROUGH_CAP, "The stroke lands after the hit and inside the cap (%.2f s)" % float(hit["landed"]))
	check(not bool(hit["live_after_landing"]), "Once the stroke lands the blade only shoves")
	var old: Dictionary = await cut(true, window_gate)
	check(float(old["touched"]) > 0.0 and int(old["damage"]) == 0, "The 0.52 s window alone would only have shoved it")
	var unapproved: Dictionary = await cut(false, host_gate)
	check(float(unapproved["touched"]) > 0.0 and int(unapproved["damage"]) == 0, "A flying stroke without an approved swing only shoves")
	var blocked: Dictionary = await cut(true, host_gate, func() -> bool: return combat.set_block(true))
	check(float(blocked["touched"]) > 0.0 and int(blocked["damage"]) == 0, "Raising guard after recovery ends the cut's damage")
	var staggered: Dictionary = await cut(true, host_gate, func() -> bool:
		combat.stagger()
		return true)
	check(float(staggered["touched"]) > 0.0 and int(staggered["damage"]) == 0, "A stagger after recovery ends the cut's damage")
	if failures == 0:
		print("STROKE_CONTACT_OK: 170-degree raider hit after the window, landing ends damage, cap, old-window shove, no approval no damage, block and stagger cancel")
	get_tree().quit(0 if failures == 0 else 1)
